using System.ComponentModel;
using System.Runtime.InteropServices;

namespace JustACBridgeM5;

internal sealed class M5Hook : IDisposable
{
    private const uint WmCancelHeldForProtection = 0x8000 + 77; // WM_APP + 77
    private readonly NativeMethods.LowLevelMouseProc _callback;
    private Thread? _thread;
    private nint _hook;
    private uint _threadId;
    private HookAction _current = new(null, false);
    private HotkeyBinding? _held;
    private bool _blockedHeld;
    private volatile bool _enabled = true;
    private readonly ManualResetEventSlim _ready = new(false);

    internal M5Hook() => _callback = HookCallback;
    internal bool Enabled { get => _enabled; set => _enabled = value; }
    internal void SetAction(HotkeyBinding? binding, bool suppressWithoutBinding)
    {
        Volatile.Write(ref _current, new HookAction(binding, suppressWithoutBinding));
        if (suppressWithoutBinding && _threadId != 0)
            NativeMethods.PostThreadMessage(_threadId, WmCancelHeldForProtection, 0, 0);
    }

    internal void Start()
    {
        _thread = new Thread(HookThread) { IsBackground = true, Name = "JAC M5 hook", Priority = ThreadPriority.Highest };
        _thread.Start();
        if (!_ready.Wait(2000) || _hook == 0) throw new Win32Exception("无法安装 M5 低级鼠标钩子");
    }

    private void HookThread()
    {
        _threadId = NativeMethods.GetCurrentThreadId();
        _hook = NativeMethods.SetWindowsHookEx(NativeMethods.WH_MOUSE_LL, _callback, NativeMethods.GetModuleHandle(null), 0);
        _ready.Set();
        if (_hook == 0) return;
        while (NativeMethods.GetMessage(out var message, 0, 0, 0) > 0)
        {
            if (message.message == WmCancelHeldForProtection && _held is not null)
            {
                _held.Release();
                _held = null;
                _blockedHeld = true; // 物理 M5 仍处于按下状态；其后续 UP 也必须吞掉。
            }
        }
        NativeMethods.UnhookWindowsHookEx(_hook);
        _hook = 0;
    }

    private nint HookCallback(int code, nint wParam, nint lParam)
    {
        if (code >= 0)
        {
            var data = Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);
            uint xbutton = data.mouseData >> 16;
            if ((data.flags & NativeMethods.LLMHF_INJECTED) == 0 && xbutton == NativeMethods.XBUTTON2)
            {
                if ((int)wParam == NativeMethods.WM_XBUTTONDOWN && _enabled)
                {
                    HookAction action = Volatile.Read(ref _current);
                    if (action.Binding is not null)
                    {
                        _held = action.Binding;
                        action.Binding.Press();
                        return 1;
                    }
                    if (action.SuppressWithoutBinding)
                    {
                        _blockedHeld = true;
                        return 1;
                    }
                }
                else if ((int)wParam == NativeMethods.WM_XBUTTONUP && _held is not null)
                {
                    _held.Release();
                    _held = null;
                    return 1;
                }
                else if ((int)wParam == NativeMethods.WM_XBUTTONUP && _blockedHeld)
                {
                    _blockedHeld = false;
                    return 1;
                }
            }
        }
        return NativeMethods.CallNextHookEx(_hook, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (_held is not null) { _held.Release(); _held = null; }
        if (_threadId != 0) NativeMethods.PostThreadMessage(_threadId, NativeMethods.WM_QUIT, 0, 0);
        _thread?.Join(1000);
        _thread = null;
        _ready.Dispose();
    }

    private sealed record HookAction(HotkeyBinding? Binding, bool SuppressWithoutBinding);
}
