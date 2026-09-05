// Compiles the actual hook state machine with a fake clock and side-effect sinks.
// NEVER calls Start/HookThread or HotkeyBinding's native production sender.
using System.Reflection;
namespace JustACBridgeM5;

internal static class Program
{
    static void Require(bool value, string message)
    {
        if (!value) throw new Exception(message);
    }

    static void Invoke(M5Hook hook, string method, params object[] args) =>
        typeof(M5Hook).GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(hook, args);

    static void Main()
    {
        // Deterministic fault-injection model: game SQW=80, no transport delay.
        // It proves local scheduling only, not server acceptance or DPS.
        static int FirstAccepted(int commitWindow, int gameWindow)
        {
            var gate = new RepeatSendGate(250);
            for (int time = -commitWindow; time <= 500; time += 20)
                if (gate.TryCommit("1", 1000 + time) && time >= -gameWindow) return time;
            throw new Exception("no accepted attempt in model");
        }
        Require(FirstAccepted(120, 80) == 140, "legacy early send reproducer");
        Require(FirstAccepted(80, 80) == -80, "matched window removes early send");
        Require(FirstAccepted(120, 400) == -120, "normal window remains unchanged");
        Require(FirstAccepted(0, 0) == 0, "disabled prequeue waits for GCD end");

        using var hook = new M5Hook();
        var one = new HotkeyBinding("1");
        var two = new HotkeyBinding("2");
        var three = new HotkeyBinding("3");
        hook.SetActions(one, null, false, false, false);
        Invoke(hook, "HandleDown", TriggerBinding.M5);
        Require(HotkeyBinding.Attempts == 0, "closed queue must not send");
        hook.SetActions(one, null, false, true, false);
        Invoke(hook, "PulseHeldAction");
        Require(HotkeyBinding.Attempts == 1, "opening queue sends immediately");
        Invoke(hook, "PulseHeldAction"); // first acknowledgement-block transition
        int logCount = DiagnosticLog.Lines.Count;
        for (int i = 0; i < 10; i++) Invoke(hook, "PulseHeldAction");
        Require(HotkeyBinding.Attempts == 1, "same binding still has 250ms gate");
        Require(DiagnosticLog.Lines.Count == logCount, "blocked repeats must not flood logs");
        hook.SetActions(two, null, false, true, false);
        Invoke(hook, "PulseHeldAction");
        hook.SetActions(three, null, false, true, false);
        Invoke(hook, "PulseHeldAction");
        Require(HotkeyBinding.Attempts == 3, "different binding still follows latest queue");
        Require(DiagnosticLog.Lines.Count(s => s.StartsWith("SEND ")) == 3,
            "every attempt logged, including rapid recommendation changes");
        hook.SetActions(null, null, true, false, false, observedBusy: true);
        Invoke(hook, "PulseHeldAction");
        Require(HotkeyBinding.Attempts == 3, "busy blocks held output");
        hook.SetActions(one, null, false, true, false, observedBusy: false);
        Invoke(hook, "HandleUp", TriggerBinding.M5);
        Invoke(hook, "PulseHeldAction");
        Require(HotkeyBinding.Attempts == 3, "released trigger never sends");

        using var channel = new M5Hook();
        channel.SetActions(one, null, false, true, false, losslessStartsProtectedChannel: true);
        Invoke(channel, "HandleDown", TriggerBinding.M5);
        channel.SetActions(two, null, false, true, false, observedBusy: false);
        Invoke(channel, "PulseHeldAction");
        Require(HotkeyBinding.Attempts == 4, "stale idle cannot bypass channel-start latch");
        channel.SetActions(null, null, true, false, false, observedBusy: true);
        Invoke(channel, "PulseHeldAction");
        channel.SetActions(two, null, false, true, false, observedBusy: false);
        Invoke(channel, "PulseHeldAction");
        Require(HotkeyBinding.Attempts == 5, "confirmed channel stop resumes newest action");
        using var preserve = new M5Hook();
        preserve.SetActions(one, two, false, true, false);
        Invoke(preserve, "HandleDown", TriggerBinding.M4);
        Invoke(preserve, "PulseHeldAction");
        Require(HotkeyBinding.Attempts == 5, "M5 permission must not open M4 gate");
        preserve.SetActions(one, two, false, true, true);
        Invoke(preserve, "PulseHeldAction");
        Require(HotkeyBinding.Attempts == 6, "M4 resumes only after its gate opens");
        Console.WriteLine("offline hook timing/diagnostics tests passed (no native input)");
    }
}

// Test-only replacements. Production project never compiles this directory.
internal sealed class HotkeyBinding(string canonical)
{
    internal string Canonical => canonical;
    internal static int Attempts;
    internal void Pulse() => Attempts++;
    internal bool Pulse(out string result)
    {
        Attempts++;
        result = "mock-only";
        return true;
    }
}

internal static class DiagnosticLog
{
    internal static bool Enabled => true;
    internal static readonly List<string> Lines = [];
    internal static void Write(string line) => Lines.Add(line);
}

// Same-namespace resolution affects only this test assembly. No real-time sleeps
// or scheduler-dependent assertions, and no clock injection in production code.
internal static class Environment
{
    internal static long TickCount64 => 1000;
}
