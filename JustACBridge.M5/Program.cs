using System.Diagnostics;
using System.Runtime.InteropServices;

namespace JustACBridgeM5;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
            return SelfTest.Run();
        if (args.Contains("--probe", StringComparer.OrdinalIgnoreCase))
        {
            NativeMethods.SetProcessDpiAwarenessContext(new nint(-4));
            NativeMethods.timeBeginPeriod(1);
            try { return SelfTest.Probe(); }
            finally { NativeMethods.timeEndPeriod(1); }
        }

        NativeMethods.SetProcessDpiAwarenessContext(new nint(-4)); // Per-Monitor V2
        NativeMethods.timeBeginPeriod(1);
        try
        {
            try { Process.GetCurrentProcess().PriorityClass = ProcessPriorityClass.High; }
            catch { /* Normal priority is still safe if policy rejects this. */ }

            ApplicationConfiguration.Initialize();
            Application.Run(new MainForm());
            return 0;
        }
        finally
        {
            NativeMethods.timeEndPeriod(1);
        }
    }
}
