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
    // WoW can take more than one capture frame to report the GCD/channel that
    // was started by an injected key. Repeating the same key during that
    // acknowledgement gap can pre-queue a second Arcane Missiles and clip the
    // first channel as soon as the GCD permits it. Only de-duplicate the same
    // binding; a genuinely different recommendation may still fire at once.
    private const int SameBindingAcknowledgementMs = 250;
    private const int ProtectedChannelStartTimeoutMs = 2000;
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
    private ActionMap _actions = new(null, null, false, false, false, false, 0, 0, false, false);
    private TriggerMap _triggers = new(TriggerBinding.M5, TriggerBinding.M4);
    private TriggerMap _pendingTriggers = new(TriggerBinding.M5, TriggerBinding.M4);
    private CaptureRequest? _captureRequest;
    private HeldAction? _losslessHeld;
    private HeldAction? _preserveHeld;
    private readonly HashSet<TriggerBinding> _blockedUps = [];
    private volatile bool _enabled = true;
    private readonly ManualResetEventSlim _ready = new(false);
    private string _lastPulseState = "";
    private string _lastActionTrace = "";
    private long _lastPulseLogTick;
    private readonly RepeatSendGate _repeatSendGate = new(SameBindingAcknowledgementMs);
    private readonly ProtectedChannelSendLatch _protectedChannelSendLatch = new(ProtectedChannelStartTimeoutMs);

    internal M5Hook()
    {
        _mouseCallback = MouseHookCallback;
        _keyboardCallback = KeyboardHookCallback;
    }

    internal event Action<ActionSlot, TriggerBinding>? TriggerCaptured;
    internal event Action<ActionSlot>? RightClickWhileHolding;

    internal bool Enabled
    {
        get => _enabled;
        set
        {
            _enabled = value;
            if (!value) _protectedChannelSendLatch.Cancel();
            if (!value && _threadId != 0)
                NativeMethods.PostThreadMessage(_threadId, WmCancelHeld, 0, 0);
        }
    }

    internal void ConfigureTriggers(TriggerBinding lossless, TriggerBinding preserveBurst)
    {
        DiagnosticLog.Write($"HOOK configure-triggers lossless={lossless.Display} preserve={preserveBurst.Display}");
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

    internal void SetActions(HotkeyBinding? lossless, HotkeyBinding? preserveBurst,
        bool suppressWithoutBinding, bool canPulse,
        bool suppressLosslessWithoutBinding = false,
        bool suppressPreserveWithoutBinding = false,
        int losslessStabilityKey = 0,
        int losslessStabilityDelayMs = 0,
        bool losslessStartsProtectedChannel = false,
        bool preserveStartsProtectedChannel = false,
        bool? observedBusy = null)
    {
        if (observedBusy.HasValue)
            _protectedChannelSendLatch.ObserveBusy(observedBusy.Value);
        var next = new ActionMap(
            lossless, preserveBurst, suppressWithoutBinding, canPulse,
            suppressLosslessWithoutBinding, suppressPreserveWithoutBinding,
            losslessStabilityKey, Math.Max(0, losslessStabilityDelayMs),
            losslessStartsProtectedChannel, preserveStartsProtectedChannel);
        Volatile.Write(ref _actions, next);
        if (DiagnosticLog.Enabled)
        {
            string trace = $"lossless={BindingName(lossless)} preserve={BindingName(preserveBurst)} suppress={suppressWithoutBinding} canPulse={canPulse} suppressLossless={suppressLosslessWithoutBinding} suppressPreserve={suppressPreserveWithoutBinding} losslessStability={losslessStabilityKey}/{Math.Max(0, losslessStabilityDelayMs)}ms protectedStart={losslessStartsProtectedChannel}/{preserveStartsProtectedChannel} latch={_protectedChannelSendLatch.State}";
            if (trace != _lastActionTrace)
            {
                _lastActionTrace = trace;
                DiagnosticLog.Write("HOOK actions " + trace);
            }
        }
        else _lastActionTrace = "";
        if (_threadId != 0)
            NativeMethods.PostThreadMessage(_threadId, WmActionsChanged, 0, 0);
    }

    internal void Start()
    {
        DiagnosticLog.Write("HOOK start-request");
        _thread = new Thread(HookThread)
        {
            IsBackground = true,
            Name = "JAC input hook",
            Priority = ThreadPriority.Highest
        };
        _thread.Start();
        if (!_ready.Wait(2000) || _mouseHook == 0 || _keyboardHook == 0)
            throw new Win32Exception("无法安装全局键鼠钩子");
        DiagnosticLog.Write($"HOOK started thread={_threadId} mouse=0x{_mouseHook:X} keyboard=0x{_keyboardHook:X}");
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
            if ((data.flags & NativeMethods.LLMHF_INJECTED) == 0 &&
                (int)wParam == NativeMethods.WM_RBUTTONDOWN)
            {
                ActionMap actions = Volatile.Read(ref _actions);
                if (actions.CanPulse && actions.Lossless is not null && _losslessHeld is not null)
                    RightClickWhileHolding?.Invoke(ActionSlot.Lossless);
                else if (actions.CanPulse && actions.PreserveBurst is not null && _preserveHeld is not null)
                    RightClickWhileHolding?.Invoke(ActionSlot.PreserveBurst);
            }

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
        if (!_enabled)
        {
            DiagnosticLog.Write($"INPUT down trigger={trigger.Display} result=passthrough reason=disabled");
            return false;
        }
        TriggerMap triggers = Volatile.Read(ref _triggers);
        ActionMap actions = Volatile.Read(ref _actions);

        if (trigger == triggers.Lossless)
        {
            bool suppress = actions.SuppressWithoutBinding || actions.SuppressLosslessWithoutBinding;
            DiagnosticLog.Write($"INPUT down trigger={trigger.Display} slot=lossless binding={BindingName(actions.Lossless)} suppress={suppress} canPulse={actions.CanPulse}");
            if (actions.Lossless is not null || suppress)
                CancelHeldAction(ref _preserveHeld, blockFollowingUp: true);
            return PressSlot(trigger, actions.Lossless, suppress, actions.CanPulse,
                actions.LosslessStabilityKey, actions.LosslessStabilityDelayMs,
                actions.LosslessStartsProtectedChannel, ref _losslessHeld);
        }
        if (trigger == triggers.PreserveBurst)
        {
            bool suppress = actions.SuppressWithoutBinding || actions.SuppressPreserveWithoutBinding;
            DiagnosticLog.Write($"INPUT down trigger={trigger.Display} slot=preserve binding={BindingName(actions.PreserveBurst)} suppress={suppress} canPulse={actions.CanPulse}");
            if (actions.PreserveBurst is not null || suppress)
                CancelHeldAction(ref _losslessHeld, blockFollowingUp: true);
            return PressSlot(trigger, actions.PreserveBurst, suppress, actions.CanPulse,
                0, 0, actions.PreserveStartsProtectedChannel, ref _preserveHeld);
        }
        return false;
    }

    private bool HandleUp(TriggerBinding trigger)
    {
        bool handled = ReleaseHeldAction(trigger, ref _losslessHeld);
        handled = ReleaseHeldAction(trigger, ref _preserveHeld) || handled;
        bool blocked = _blockedUps.Remove(trigger);
        if (handled || blocked) DiagnosticLog.Write($"INPUT up trigger={trigger.Display} handled={handled} blockedUp={blocked}");
        return blocked || handled;
    }

    private bool PressSlot(TriggerBinding trigger, HotkeyBinding? binding, bool suppressWithoutBinding,
        bool canPulse, int stabilityKey, int stabilityDelayMs,
        bool startsProtectedChannel, ref HeldAction? held)
    {
        if (held?.Trigger == trigger || _blockedUps.Contains(trigger))
        {
            DiagnosticLog.Write($"INPUT down-repeat trigger={trigger.Display} consumed=true");
            return true; // Ignore keyboard auto-repeat and consumed downs.
        }
        CancelHeldAction(ref held, blockFollowingUp: true);
        if (binding is not null)
        {
            held = new HeldAction(trigger);
            long now = Environment.TickCount64;
            bool stabilityReady = held.StabilityDelay.Observe(stabilityKey, stabilityDelayMs, now);
            if (canPulse && stabilityReady)
                Pulse(binding, startsProtectedChannel);
            else if (canPulse)
                DiagnosticLog.Write($"HOLD armed trigger={trigger.Display} binding={binding.Canonical} initialPulse=false reason=stability-delay remainingMs={held.StabilityDelay.RemainingMs(now)}");
            else
                DiagnosticLog.Write($"HOLD armed trigger={trigger.Display} binding={binding.Canonical} initialPulse=false reason=queue-gate");
            return true;
        }
        if (!suppressWithoutBinding)
        {
            DiagnosticLog.Write($"INPUT trigger={trigger.Display} result=passthrough reason=no-binding");
            return false;
        }
        held = new HeldAction(trigger);
        DiagnosticLog.Write($"HOLD armed trigger={trigger.Display} binding=null result=suppressed");
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
        ActionMap actions = Volatile.Read(ref _actions);
        long now = Environment.TickCount64;
        bool losslessStabilityReady = _losslessHeld?.StabilityDelay.Observe(
            actions.LosslessStabilityKey,
            actions.LosslessStabilityDelayMs,
            now) ?? true;

        if (!_enabled) { TracePulseState("disabled"); return; }
        if (_protectedChannelSendLatch.Blocks(now))
        {
            TracePulseState("blocked-protected-channel-latch:" + _protectedChannelSendLatch.State);
            return;
        }
        if (actions.SuppressWithoutBinding) { TracePulseState("blocked-busy"); return; }
        if (!actions.CanPulse) { TracePulseState("blocked-queue-gate"); return; }

        if (_losslessHeld is not null && actions.Lossless is not null)
        {
            if (!losslessStabilityReady)
            {
                TracePulseState("blocked-lossless-stability-delay");
                return;
            }
            TracePulseState("pulsing-lossless:" + actions.Lossless.Canonical);
            Pulse(actions.Lossless, actions.LosslessStartsProtectedChannel);
            return;
        }
        if (_preserveHeld is not null && actions.PreserveBurst is not null)
        {
            TracePulseState("pulsing-preserve:" + actions.PreserveBurst.Canonical);
            Pulse(actions.PreserveBurst, actions.PreserveStartsProtectedChannel);
            return;
        }
        TracePulseState((_losslessHeld is not null || _preserveHeld is not null) ? "held-no-binding" : "idle-no-held-key");
    }

    private void Pulse(HotkeyBinding binding, bool startsProtectedChannel)
    {
        long now = Environment.TickCount64;
        if (!_repeatSendGate.TryCommit(binding.Canonical, now))
        {
            TracePulseState($"blocked-send-ack:{binding.Canonical}:{_repeatSendGate.RemainingMs(binding.Canonical, now)}ms");
            return;
        }
        if (!DiagnosticLog.Enabled)
        {
            binding.Pulse();
            if (startsProtectedChannel) _protectedChannelSendLatch.Arm(now);
            return;
        }
        bool ok = binding.Pulse(out string result);
        if (ok && startsProtectedChannel) _protectedChannelSendLatch.Arm(now);
        if (!ok || now - _lastPulseLogTick >= 500)
        {
            _lastPulseLogTick = now;
            DiagnosticLog.Write($"SEND binding={binding.Canonical} ok={ok} {result}");
        }
    }

    private void TracePulseState(string state)
    {
        if (!DiagnosticLog.Enabled)
        {
            _lastPulseState = "";
            return;
        }
        if (state == _lastPulseState) return;
        _lastPulseState = state;
        DiagnosticLog.Write("HOLD state=" + state);
    }

    private static string BindingName(HotkeyBinding? binding) => binding?.Canonical ?? "null";

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

    private sealed record ActionMap(HotkeyBinding? Lossless, HotkeyBinding? PreserveBurst,
        bool SuppressWithoutBinding, bool CanPulse,
        bool SuppressLosslessWithoutBinding, bool SuppressPreserveWithoutBinding,
        int LosslessStabilityKey, int LosslessStabilityDelayMs,
        bool LosslessStartsProtectedChannel, bool PreserveStartsProtectedChannel);
    private sealed record TriggerMap(TriggerBinding Lossless, TriggerBinding PreserveBurst);
    private sealed record CaptureRequest(ActionSlot Slot);
    private sealed record HeldAction(TriggerBinding Trigger)
    {
        internal StableRecommendationDelay StabilityDelay { get; } = new();
    }
}

internal sealed class RepeatSendGate(int acknowledgementMs)
{
    private readonly int _acknowledgementMs = Math.Max(0, acknowledgementMs);
    private string? _lastBinding;
    private long _lastSentAt = long.MinValue;

    internal bool TryCommit(string binding, long now)
    {
        if (_lastBinding == binding && now - _lastSentAt < _acknowledgementMs)
            return false;
        _lastBinding = binding;
        _lastSentAt = now;
        return true;
    }

    internal int RemainingMs(string binding, long now)
    {
        if (_lastBinding != binding) return 0;
        return Math.Max(0, _acknowledgementMs - (int)Math.Min(int.MaxValue, now - _lastSentAt));
    }
}

internal sealed class ProtectedChannelSendLatch(int startTimeoutMs)
{
    private readonly object _gate = new();
    private readonly int _startTimeoutMs = Math.Max(1, startTimeoutMs);
    private LatchState _state;
    private long _pendingUntil;

    internal string State
    {
        get { lock (_gate) return _state.ToString().ToLowerInvariant(); }
    }

    internal void Arm(long now)
    {
        lock (_gate)
        {
            _state = LatchState.PendingStart;
            _pendingUntil = now + _startTimeoutMs;
        }
    }

    internal void ObserveBusy(bool busy)
    {
        lock (_gate)
        {
            if (busy && _state == LatchState.PendingStart)
                _state = LatchState.ConfirmedChannel;
            else if (!busy && _state == LatchState.ConfirmedChannel)
                _state = LatchState.Idle;
        }
    }

    internal bool Blocks(long now)
    {
        lock (_gate)
        {
            if (_state == LatchState.PendingStart && now >= _pendingUntil)
                _state = LatchState.Idle;
            return _state != LatchState.Idle;
        }
    }

    internal void Cancel()
    {
        lock (_gate) _state = LatchState.Idle;
    }

    private enum LatchState
    {
        Idle,
        PendingStart,
        ConfirmedChannel
    }
}
