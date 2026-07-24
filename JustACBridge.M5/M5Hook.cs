using System.ComponentModel;
using System.Runtime.InteropServices;

namespace JustACBridgeM5;

internal enum ActionSlot
{
    Lossless,
    PreserveBurst
}

internal enum TriggerKind
{
    Keyboard,
    XButton
}

internal readonly record struct TriggerBinding(TriggerKind Kind, uint Code)
{
    internal static TriggerBinding M4 => new(TriggerKind.XButton, NativeMethods.XBUTTON1);
    internal static TriggerBinding M5 => new(TriggerKind.XButton, NativeMethods.XBUTTON2);

    internal string Display => Kind switch
    {
        TriggerKind.XButton when Code == NativeMethods.XBUTTON1 => "M4",
        TriggerKind.XButton when Code == NativeMethods.XBUTTON2 => "M5",
        TriggerKind.Keyboard => FormatKeyboard(Code),
        _ => $"Key {Code}"
    };

    private static string FormatKeyboard(uint virtualKey)
    {
        Keys key = (Keys)virtualKey;
        if (key is >= Keys.A and <= Keys.Z) return key.ToString();
        if (key is >= Keys.D0 and <= Keys.D9) return ((char)('0' + virtualKey - (uint)Keys.D0)).ToString();
        if (key is >= Keys.F1 and <= Keys.F24) return key.ToString();
        return key switch
        {
            Keys.Space => "Space",
            Keys.Tab => "Tab",
            Keys.Enter => "Enter",
            Keys.Escape => "Esc",
            Keys.Back => "Backspace",
            Keys.Insert => "Insert",
            Keys.Delete => "Delete",
            Keys.Home => "Home",
            Keys.End => "End",
            Keys.PageUp => "PageUp",
            Keys.PageDown => "PageDown",
            Keys.Up => "↑",
            Keys.Down => "↓",
            Keys.Left => "←",
            Keys.Right => "→",
            _ => key.ToString()
        };
    }
}

internal sealed class M5Hook : IDisposable
{
    private const int RepeatIntervalMs = 20;
    private const uint WmCancelHeld = 0x8000 + 77; // WM_APP + 77
    private const uint WmConfigureTriggers = 0x8000 + 78;
    private const uint WmActionsChanged = 0x8000 + 79;
    private const uint WmRepeat = 0x8000 + 80;
    private readonly NativeMethods.LowLevelHookProc _mouseCallback;
    private readonly NativeMethods.LowLevelHookProc _keyboardCallback;
    private Thread? _thread;
    private System.Threading.Timer? _repeatTimer;
    private nint _mouseHook;
    private nint _keyboardHook;
    private uint _threadId;
    private ActionMap _actions = new(null, null, false);
    private TriggerMap _triggers = new(TriggerBinding.M5, TriggerBinding.M4);
    private TriggerMap _pendingTriggers = new(TriggerBinding.M5, TriggerBinding.M4);
    private CaptureRequest? _captureRequest;
    private HeldAction? _losslessHeld;
    private HeldAction? _preserveHeld;
    private readonly HashSet<TriggerBinding> _blockedUps = [];
    private volatile bool _enabled = true;
    private readonly ManualResetEventSlim _ready = new(false);

    internal M5Hook()
    {
        _mouseCallback = MouseHookCallback;
        _keyboardCallback = KeyboardHookCallback;
    }

    internal event Action<ActionSlot, TriggerBinding>? TriggerCaptured;

    internal bool Enabled
    {
        get => _enabled;
        set
        {
            _enabled = value;
            if (!value && _threadId != 0)
                NativeMethods.PostThreadMessage(_threadId, WmCancelHeld, 0, 0);
        }
    }

    internal void ConfigureTriggers(TriggerBinding lossless, TriggerBinding preserveBurst)
    {
        var map = new TriggerMap(lossless, preserveBurst);
        Volatile.Write(ref _pendingTriggers, map);
        if (_threadId != 0)
            NativeMethods.PostThreadMessage(_threadId, WmConfigureTriggers, 0, 0);
        else
            Volatile.Write(ref _triggers, map);
    }

    internal void BeginCapture(ActionSlot slot) =>
        Volatile.Write(ref _captureRequest, new CaptureRequest(slot));

    internal void CancelCapture() => Volatile.Write(ref _captureRequest, null);

    internal void SetActions(HotkeyBinding? lossless, HotkeyBinding? preserveBurst, bool suppressWithoutBinding)
    {
        Volatile.Write(ref _actions, new ActionMap(lossless, preserveBurst, suppressWithoutBinding));
        if (_threadId != 0)
            NativeMethods.PostThreadMessage(_threadId, WmActionsChanged, 0, 0);
    }

    internal void Start()
    {
        _thread = new Thread(HookThread)
        {
            IsBackground = true,
            Name = "JAC input hook",
            Priority = ThreadPriority.Highest
        };
        _thread.Start();
        if (!_ready.Wait(2000) || _mouseHook == 0 || _keyboardHook == 0)
            throw new Win32Exception("无法安装全局键鼠钩子");
        _repeatTimer = new System.Threading.Timer(
            _ =>
            {
                uint threadId = Volatile.Read(ref _threadId);
                if (threadId != 0)
                    NativeMethods.PostThreadMessage(threadId, WmRepeat, 0, 0);
            },
            null,
            RepeatIntervalMs,
            RepeatIntervalMs);
    }

    private void HookThread()
    {
        _threadId = NativeMethods.GetCurrentThreadId();
        nint module = NativeMethods.GetModuleHandle(null);
        _mouseHook = NativeMethods.SetWindowsHookEx(NativeMethods.WH_MOUSE_LL, _mouseCallback, module, 0);
        _keyboardHook = NativeMethods.SetWindowsHookEx(NativeMethods.WH_KEYBOARD_LL, _keyboardCallback, module, 0);
        _ready.Set();
        if (_mouseHook == 0 || _keyboardHook == 0)
        {
            if (_mouseHook != 0) NativeMethods.UnhookWindowsHookEx(_mouseHook);
            if (_keyboardHook != 0) NativeMethods.UnhookWindowsHookEx(_keyboardHook);
            _mouseHook = _keyboardHook = 0;
            _threadId = 0;
            return;
        }

        try
        {
            while (NativeMethods.GetMessage(out var message, 0, 0, 0) > 0)
            {
                if (message.message == WmCancelHeld)
                    CancelHeldActions(blockFollowingUp: true);
                else if (message.message == WmConfigureTriggers)
                {
                    CancelHeldActions(blockFollowingUp: true);
                    Volatile.Write(ref _triggers, Volatile.Read(ref _pendingTriggers));
                }
                else if (message.message is WmActionsChanged or WmRepeat)
                {
                    PulseHeldAction();
                }
            }
        }
        finally
        {
            CancelHeldActions(blockFollowingUp: false);
            NativeMethods.UnhookWindowsHookEx(_keyboardHook);
            NativeMethods.UnhookWindowsHookEx(_mouseHook);
            _keyboardHook = _mouseHook = 0;
            _threadId = 0;
        }
    }

    private nint MouseHookCallback(int code, nint wParam, nint lParam)
    {
        if (code >= 0)
        {
            var data = Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);
            uint xbutton = data.mouseData >> 16;
            if ((data.flags & NativeMethods.LLMHF_INJECTED) == 0 &&
                xbutton is NativeMethods.XBUTTON1 or NativeMethods.XBUTTON2)
            {
                var trigger = new TriggerBinding(TriggerKind.XButton, xbutton);
                if ((int)wParam == NativeMethods.WM_XBUTTONDOWN)
                {
                    if (TryCapture(trigger)) return 1;
                    if (HandleDown(trigger)) return 1;
                }
                else if ((int)wParam == NativeMethods.WM_XBUTTONUP)
                {
                    if (HandleUp(trigger)) return 1;
                }
            }
        }
        return NativeMethods.CallNextHookEx(_mouseHook, code, wParam, lParam);
    }

    private nint KeyboardHookCallback(int code, nint wParam, nint lParam)
    {
        if (code >= 0)
        {
            var data = Marshal.PtrToStructure<NativeMethods.KBDLLHOOKSTRUCT>(lParam);
            if ((data.flags & NativeMethods.LLKHF_INJECTED) == 0)
            {
                var trigger = new TriggerBinding(TriggerKind.Keyboard, data.vkCode);
                int message = (int)wParam;
                if (message is NativeMethods.WM_KEYDOWN or NativeMethods.WM_SYSKEYDOWN)
                {
                    if (IsModifierKey(data.vkCode))
                        return NativeMethods.CallNextHookEx(_keyboardHook, code, wParam, lParam);
                    if (TryCapture(trigger)) return 1;
                    if (HandleDown(trigger)) return 1;
                }
                else if (message is NativeMethods.WM_KEYUP or NativeMethods.WM_SYSKEYUP)
                {
                    if (HandleUp(trigger)) return 1;
                }
            }
        }
        return NativeMethods.CallNextHookEx(_keyboardHook, code, wParam, lParam);
    }

    private bool TryCapture(TriggerBinding trigger)
    {
        CaptureRequest? request = Volatile.Read(ref _captureRequest);
        if (request is null) return false;

        Volatile.Write(ref _captureRequest, null);
        _blockedUps.Add(trigger);
        TriggerCaptured?.Invoke(request.Slot, trigger);
        return true;
    }

    private bool HandleDown(TriggerBinding trigger)
    {
        if (!_enabled) return false;
        TriggerMap triggers = Volatile.Read(ref _triggers);
        ActionMap actions = Volatile.Read(ref _actions);

        if (trigger == triggers.Lossless)
        {
            if (actions.Lossless is not null || actions.SuppressWithoutBinding)
                CancelHeldAction(ref _preserveHeld, blockFollowingUp: true);
            return PressSlot(trigger, actions.Lossless, actions.SuppressWithoutBinding, ref _losslessHeld);
        }
        if (trigger == triggers.PreserveBurst)
        {
            if (actions.PreserveBurst is not null || actions.SuppressWithoutBinding)
                CancelHeldAction(ref _losslessHeld, blockFollowingUp: true);
            return PressSlot(trigger, actions.PreserveBurst, actions.SuppressWithoutBinding, ref _preserveHeld);
        }
        return false;
    }

    private bool HandleUp(TriggerBinding trigger)
    {
        bool handled = ReleaseHeldAction(trigger, ref _losslessHeld);
        handled = ReleaseHeldAction(trigger, ref _preserveHeld) || handled;
        return _blockedUps.Remove(trigger) || handled;
    }

    private bool PressSlot(TriggerBinding trigger, HotkeyBinding? binding, bool suppressWithoutBinding,
        ref HeldAction? held)
    {
        if (held?.Trigger == trigger || _blockedUps.Contains(trigger))
            return true; // Ignore keyboard auto-repeat and consumed downs.
        CancelHeldAction(ref held, blockFollowingUp: true);
        if (binding is not null)
        {
            held = new HeldAction(trigger);
            Pulse(binding);
            return true;
        }
        if (!suppressWithoutBinding)
            return false;
        held = new HeldAction(trigger);
        return true;
    }

    private static bool ReleaseHeldAction(TriggerBinding trigger, ref HeldAction? held)
    {
        if (held?.Trigger != trigger) return false;
        held = null;
        return true;
    }

    private void CancelHeldAction(ref HeldAction? held, bool blockFollowingUp)
    {
        if (held is null) return;
        if (blockFollowingUp) _blockedUps.Add(held.Trigger);
        held = null;
    }

    private void CancelHeldActions(bool blockFollowingUp)
    {
        CancelHeldAction(ref _losslessHeld, blockFollowingUp);
        CancelHeldAction(ref _preserveHeld, blockFollowingUp);
        if (!blockFollowingUp) _blockedUps.Clear();
    }

    private void PulseHeldAction()
    {
        if (!_enabled) return;
        ActionMap actions = Volatile.Read(ref _actions);
        if (actions.SuppressWithoutBinding) return;

        if (_losslessHeld is not null && actions.Lossless is not null)
        {
            Pulse(actions.Lossless);
            return;
        }
        if (_preserveHeld is not null && actions.PreserveBurst is not null)
            Pulse(actions.PreserveBurst);
    }

    private static void Pulse(HotkeyBinding binding)
    {
        binding.Press();
        binding.Release();
    }

    private static bool IsModifierKey(uint vk) => vk is
        0x10 or 0x11 or 0x12 or // Shift, Ctrl, Alt
        0x5B or 0x5C or        // Windows
        0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5;

    public void Dispose()
    {
        _repeatTimer?.Dispose();
        _repeatTimer = null;
        if (_threadId != 0) NativeMethods.PostThreadMessage(_threadId, NativeMethods.WM_QUIT, 0, 0);
        _thread?.Join(1000);
        _thread = null;
        _ready.Dispose();
    }

    private sealed record ActionMap(HotkeyBinding? Lossless, HotkeyBinding? PreserveBurst, bool SuppressWithoutBinding);
    private sealed record TriggerMap(TriggerBinding Lossless, TriggerBinding PreserveBurst);
    private sealed record CaptureRequest(ActionSlot Slot);
    private sealed record HeldAction(TriggerBinding Trigger);
}
