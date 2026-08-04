using System.Text;

namespace JustACBridgeM5;

internal static class DiagnosticLog
{
    private const int MaxLines = 6000;
    private static readonly object Gate = new();
    private static readonly Queue<string> Lines = new();
    private static StreamWriter? _writer;
    private static bool _enabled;
    internal static string FilePath { get; private set; } = "未启用";

    internal static bool Enabled
    {
        get { lock (Gate) return _enabled; }
        set
        {
            lock (Gate)
            {
                if (_enabled == value) return;
                if (!value)
                {
                    WriteLocked("STOP diagnostics-disabled");
                    _enabled = false;
                    try { _writer?.Dispose(); } catch { }
                    _writer = null;
                    return;
                }

                Lines.Clear();
                string directory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "JustACBridge.M5", "diagnostics");
                Directory.CreateDirectory(directory);
                FilePath = Path.Combine(directory, $"debug-{DateTime.Now:yyyyMMdd-HHmmss}.log");
                try
                {
                    _writer = new StreamWriter(FilePath, append: false, new UTF8Encoding(false)) { AutoFlush = true };
                }
                catch { _writer = null; }
                _enabled = true;
                WriteLocked($"START version={Application.ProductVersion} os={Environment.OSVersion} pid={Environment.ProcessId} elevated={IsElevated()}");
            }
        }
    }

    internal static void Write(string message)
    {
        lock (Gate)
        {
            if (!_enabled) return;
            WriteLocked(message);
        }
    }

    private static void WriteLocked(string message)
    {
        string line = $"[{DateTime.Now:HH:mm:ss.fff} tick={Environment.TickCount64}] {message.Replace('\r', ' ').Replace('\n', ' ')}";
        Lines.Enqueue(line);
        while (Lines.Count > MaxLines) Lines.Dequeue();
        try { _writer?.WriteLine(line); } catch { }
    }

    internal static string Snapshot()
    {
        lock (Gate)
        {
            if (!_enabled) return "JustACBridge Windows diagnostic log\r\n诊断未开启。";
            return $"JustACBridge Windows diagnostic log\r\nfile={FilePath}\r\n" +
                   string.Join("\r\n", Lines);
        }
    }

    private static bool IsElevated()
    {
        try
        {
            using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
            return new System.Security.Principal.WindowsPrincipal(identity)
                .IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }
        catch { return false; }
    }
}
