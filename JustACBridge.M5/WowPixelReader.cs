using System.ComponentModel;
using System.Diagnostics;

namespace JustACBridgeM5;

internal sealed record ReaderUpdate(string State, string Window, Packet? Packet, PixelProtocol.Geometry? Geometry, double CaptureMs);

internal sealed unsafe class WowPixelReader : IDisposable
{
    private Thread? _thread;
    private volatile bool _running;
    private volatile int _pollMs;
    private GdiCapture? _capture;
    internal event Action<ReaderUpdate>? Updated;
    internal bool Running => _running;

    internal void Start(int pollMs = 0)
    {
        if (_running) return;
        _pollMs = pollMs;
        _running = true;
        _thread = new Thread(Run) { IsBackground = true, Name = "JAC pixel reader", Priority = ThreadPriority.Highest };
        _thread.Start();
    }

    internal void SetPollMs(int value) => _pollMs = Math.Clamp(value, 0, 20);

    internal void Stop()
    {
        _running = false;
        _thread?.Join(1500);
        _thread = null;
    }

    private void Run()
    {
        _capture = new GdiCapture();
        nint hwnd = 0;
        string windowName = "";
        PixelProtocol.Geometry? geometry = null;
        ushort? lastSequence = null;
        bool wasValid = false;
        long nextWindowSearch = 0;
        long lastStateReport = 0;
        Span<byte> payload = stackalloc byte[72];

        try
        {
            while (_running)
            {
                long loopStart = Stopwatch.GetTimestamp();
                if (hwnd == 0 || !NativeMethods.IsWindowVisible(hwnd) || NativeMethods.IsIconic(hwnd))
                {
                    long now = Environment.TickCount64;
                    if (now >= nextWindowSearch)
                    {
                        hwnd = FindWowWindow(out windowName);
                        nextWindowSearch = now + 250;
                        geometry = null;
                        if (hwnd != 0) Updated?.Invoke(new("正在同步像素矩阵…", windowName, null, null, 0));
                    }
                    if (hwnd == 0)
                    {
                        if (wasValid || now - lastStateReport >= 1000)
                        {
                            Updated?.Invoke(new("等待 WoW 窗口", "未找到 Wow*.exe 可见窗口", null, null, 0));
                            lastStateReport = now;
                        }
                        wasValid = false;
                        Thread.Sleep(100);
                        continue;
                    }
                }

                try
                {
                    if (!_capture.Capture(hwnd))
                    {
                        hwnd = 0;
                        continue;
                    }

                    bool valid;
                    if (geometry is { } known)
                    {
                        PixelProtocol.DecodePixels(_capture.Bits, known, payload);
                        valid = PixelProtocol.Validate(payload);
                        if (!valid) geometry = null;
                    }
                    else
                    {
                        valid = PixelProtocol.TryFind(_capture.Bits, out var found, payload);
                        if (valid) geometry = found;
                    }

                    double elapsedMs = Stopwatch.GetElapsedTime(loopStart).TotalMilliseconds;
                    ushort sequence = valid ? (ushort)(payload[4] | payload[5] << 8) : (ushort)0;
                    if (valid && (!wasValid || lastSequence is null || sequence != lastSequence))
                    {
                        Packet packet = PixelProtocol.DecodeValidated(payload);
                        wasValid = true;
                        lastSequence = packet.Sequence;
                        Updated?.Invoke(new("实时映射已启用", windowName, packet, geometry, elapsedMs));
                    }
                    else if (!valid)
                    {
                        bool reportNow = wasValid || Environment.TickCount64 - lastStateReport >= 1000;
                        wasValid = false;
                        if (reportNow)
                        {
                            Updated?.Invoke(new("等待有效像素包", windowName, null, null, elapsedMs));
                            lastStateReport = Environment.TickCount64;
                        }
                    }
                }
                catch
                {
                    hwnd = 0;
                    geometry = null;
                    wasValid = false;
                }

                int wait = _pollMs;
                if (wait > 0)
                {
                    double used = Stopwatch.GetElapsedTime(loopStart).TotalMilliseconds;
                    int remaining = wait - (int)used;
                    if (remaining > 0) Thread.Sleep(remaining);
                    else Thread.Yield();
                }
                else
                {
                    Thread.Yield();
                }
            }
        }
        finally
        {
            _capture.Dispose();
            _capture = null;
        }
    }

    private static nint FindWowWindow(out string description)
    {
        var candidates = new List<(nint Hwnd, string Name, int Area, bool Foreground)>();
        nint foreground = NativeMethods.GetForegroundWindow();
        NativeMethods.EnumWindows((hwnd, _) =>
        {
            if (!NativeMethods.IsWindowVisible(hwnd) || NativeMethods.IsIconic(hwnd)) return true;
            NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
            try
            {
                using var process = Process.GetProcessById((int)pid);
                string name = process.ProcessName;
                if (!name.StartsWith("Wow", StringComparison.OrdinalIgnoreCase)) return true;
                if (!NativeMethods.GetClientRect(hwnd, out var rect)) return true;
                int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
                if (width < PixelProtocol.Width + PixelProtocol.CaptureOffsetX ||
                    height < PixelProtocol.Height + PixelProtocol.CaptureOffsetY) return true;
                candidates.Add((hwnd, name + ".exe", width * height, hwnd == foreground));
            }
            catch { }
            return true;
        }, 0);
        var best = candidates.OrderByDescending(x => x.Foreground).ThenByDescending(x => x.Area).FirstOrDefault();
        description = best.Hwnd == 0 ? "" : $"{best.Name} (0x{best.Hwnd:X})";
        return best.Hwnd;
    }

    public void Dispose() => Stop();

    private sealed class GdiCapture : IDisposable
    {
        private readonly nint _screenDc;
        private readonly nint _memoryDc;
        private readonly nint _bitmap;
        private readonly nint _oldObject;
        internal byte* Bits { get; }

        internal GdiCapture()
        {
            _screenDc = NativeMethods.GetDC(0);
            _memoryDc = NativeMethods.CreateCompatibleDC(_screenDc);
            var info = new NativeMethods.BITMAPINFO
            {
                bmiHeader = new NativeMethods.BITMAPINFOHEADER
                {
                    biSize = (uint)sizeof(NativeMethods.BITMAPINFOHEADER),
                    biWidth = PixelProtocol.Width,
                    biHeight = -PixelProtocol.Height,
                    biPlanes = 1,
                    biBitCount = 32,
                    biCompression = NativeMethods.BI_RGB,
                    biSizeImage = PixelProtocol.Width * PixelProtocol.Height * 4
                }
            };
            _bitmap = NativeMethods.CreateDIBSection(_screenDc, ref info, NativeMethods.DIB_RGB_COLORS, out nint bits, 0, 0);
            if (_screenDc == 0 || _memoryDc == 0 || _bitmap == 0 || bits == 0)
                throw new Win32Exception();
            Bits = (byte*)bits;
            _oldObject = NativeMethods.SelectObject(_memoryDc, _bitmap);
        }

        internal bool Capture(nint hwnd)
        {
            if (!NativeMethods.GetClientRect(hwnd, out var rect) ||
                rect.Right < PixelProtocol.Width + PixelProtocol.CaptureOffsetX ||
                rect.Bottom < PixelProtocol.Height + PixelProtocol.CaptureOffsetY)
                return false;
            var point = new NativeMethods.POINT { X = 0, Y = 0 };
            if (!NativeMethods.ClientToScreen(hwnd, ref point)) return false;
            return NativeMethods.BitBlt(_memoryDc, 0, 0, PixelProtocol.Width, PixelProtocol.Height,
                _screenDc,
                point.X + PixelProtocol.CaptureOffsetX,
                point.Y + PixelProtocol.CaptureOffsetY,
                NativeMethods.SRCCOPY | NativeMethods.CAPTUREBLT);
        }

        public void Dispose()
        {
            if (_memoryDc != 0 && _oldObject != 0) NativeMethods.SelectObject(_memoryDc, _oldObject);
            if (_bitmap != 0) NativeMethods.DeleteObject(_bitmap);
            if (_memoryDc != 0) NativeMethods.DeleteDC(_memoryDc);
            if (_screenDc != 0) NativeMethods.ReleaseDC(0, _screenDc);
        }
    }
}
