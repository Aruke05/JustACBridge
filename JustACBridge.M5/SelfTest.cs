namespace JustACBridgeM5;

internal static unsafe class SelfTest
{
    internal static int Run()
    {
        byte[] sample = Convert.FromHexString("4a41430101002dea4a0101340000000000000000000000000000000000000000000000f7760001310000000000000000000000000000000000000000000000c028c8bbcf16454e44");
        if (!PixelProtocol.TryDecode(sample, out var packet) || packet is null || packet.ProtocolVersion != 1 ||
            packet.Sequence != 1 || packet.Lossless.Id != 84714 || packet.Lossless.Hotkey != "4" ||
            packet.PreserveBurst.Id != 30455 || packet.PreserveBurst.Hotkey != "1")
        {
            Console.Error.WriteLine("protocol self-test failed");
            return 1;
        }
        byte[] version2 = (byte[])sample.Clone();
        version2[3] = 2;
        RewriteChecksums(version2);
        if (!PixelProtocol.TryDecode(version2, out var v2Packet) || v2Packet is not { ProtocolVersion: 2 } ||
            !v2Packet.QueueReady || v2Packet.Lossless.Id != 84714 || v2Packet.PreserveBurst.Id != 30455)
        {
            Console.Error.WriteLine("protocol v2 self-test failed");
            return 6;
        }
        byte[] version3 = (byte[])sample.Clone();
        version3[3] = 3;
        version3[63] = 0;
        version3[64] = 0xDC; // 220 ms
        version3[65] = 0;
        RewriteChecksums(version3);
        if (!PixelProtocol.TryDecode(version3, out var v3Waiting) ||
            v3Waiting is not { ProtocolVersion: 3, QueueReady: false, GcdRemainingMs: 220 })
        {
            Console.Error.WriteLine("protocol v3 queue-wait self-test failed");
            return 13;
        }
        version3[63] = 1;
        version3[64] = 100;
        RewriteChecksums(version3);
        if (!PixelProtocol.TryDecode(version3, out var v3Ready) ||
            v3Ready is not { QueueReady: true, GcdRemainingMs: 100 })
        {
            Console.Error.WriteLine("protocol v3 queue-ready self-test failed");
            return 14;
        }
        byte[] version3OffGcd = (byte[])version3.Clone();
        version3OffGcd[63] = 0x08; // M5 off-GCD only; ordinary queue gate closed
        RewriteChecksums(version3OffGcd);
        if (!PixelProtocol.TryDecode(version3OffGcd, out var v3OffGcd) ||
            v3OffGcd is not { QueueReady: false } ||
            !v3OffGcd.Lossless.OffGcd || v3OffGcd.PreserveBurst.OffGcd ||
            !v3OffGcd.LosslessCanPulse || v3OffGcd.PreserveCanPulse)
        {
            Console.Error.WriteLine("protocol v3 off-GCD self-test failed");
            return 23;
        }
        byte[] version4 = (byte[])version3.Clone();
        version4[3] = 4;
        version4[63] = 0x06; // moving + movement filter, queue gate closed
        RewriteChecksums(version4);
        if (!PixelProtocol.TryDecode(version4, out var v4Moving) ||
            v4Moving is not { ProtocolVersion: 4, QueueReady: false, IsMoving: true, MovementFilter: true })
        {
            Console.Error.WriteLine("protocol v4 movement-state self-test failed");
            return 15;
        }
        byte[] busy = (byte[])sample.Clone();
        busy[6] |= 0x40;
        RewriteChecksums(busy);
        if (!PixelProtocol.TryDecode(busy, out var busyPacket) || busyPacket is not { IsChanneling: true, IsCasting: false, IsBusy: true })
        {
            Console.Error.WriteLine("cast-state self-test failed");
            return 2;
        }
        byte[] casting = (byte[])sample.Clone();
        casting[6] |= 0x80;
        RewriteChecksums(casting);
        if (!PixelProtocol.TryDecode(casting, out var castingPacket) ||
            castingPacket is not { IsChanneling: false, IsCasting: true, IsBusy: true })
        {
            Console.Error.WriteLine("casting-state self-test failed");
            return 11;
        }
        byte[] image = new byte[PixelProtocol.Width * PixelProtocol.Height * 4];
        const double pitch = 3.41;
        for (int y = 0; y < PixelProtocol.Height; y++)
            for (int x = 0; x < PixelProtocol.Width; x++)
            {
                int column = (int)((x - 1) / pitch);
                int row = (int)(y / pitch);
                if (x < 1 || column is < 0 or >= 48 || row is < 0 or >= 12) continue;
                int bit = row * 48 + column;
                if (((sample[bit >> 3] >> (7 - (bit & 7))) & 1) == 0) continue;
                int offset = (y * PixelProtocol.Width + x) * 4;
                image[offset] = image[offset + 1] = image[offset + 2] = 255;
            }
        Span<byte> detected = stackalloc byte[72];
        fixed (byte* pixels = image)
        {
            if (!PixelProtocol.TryFind(pixels, out _, detected) || !detected.SequenceEqual(sample))
            {
                Console.Error.WriteLine("geometry self-test failed");
                return 3;
            }
        }

        string[] supported =
        [
            "1", "SHIFT-1", "CTRL-F", "ALT-NUMPAD1", "BUTTON4", "MOUSEWHEELUP", "-",
            "S5", "SV", "C1", "AV", "SC5", "M4", "MwU", "N1", "SSpc"
        ];
        foreach (string key in supported)
        {
            if (!HotkeyBinding.TryParse(key, out _, out string error))
            {
                Console.Error.WriteLine($"hotkey self-test failed: {key}: {error}");
                return 4;
            }
        }
        Dictionary<string, string> abbreviatedBindings = new(StringComparer.OrdinalIgnoreCase)
        {
            ["S5"] = "SHIFT-5",
            ["SV"] = "SHIFT-V",
            ["C1"] = "CTRL-1",
            ["AV"] = "ALT-V",
            ["SC5"] = "SHIFT-CTRL-5",
            ["M4"] = "BUTTON4",
            ["MwU"] = "MOUSEWHEELUP",
            ["N1"] = "NUMPAD1",
            ["SSpc"] = "SHIFT-SPACE"
        };
        foreach ((string abbreviated, string canonical) in abbreviatedBindings)
        {
            if (!HotkeyBinding.TryParse(abbreviated, out var parsed, out _) || parsed?.Canonical != canonical)
            {
                Console.Error.WriteLine($"abbreviated hotkey self-test failed: {abbreviated} -> {parsed?.Canonical}");
                return 12;
            }
        }
        int inputSize = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.INPUT>();
        if (inputSize != 40)
        {
            Console.Error.WriteLine($"unexpected INPUT size: {inputSize}");
            return 5;
        }
        int keyboardHookSize = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.KBDLLHOOKSTRUCT>();
        int mouseHookSize = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.MSLLHOOKSTRUCT>();
        if (keyboardHookSize != 24 || mouseHookSize != 32)
        {
            Console.Error.WriteLine($"unexpected hook struct size: keyboard={keyboardHookSize}, mouse={mouseHookSize}");
            return 7;
        }
        TriggerBinding[] triggers =
        [
            TriggerBinding.M4,
            TriggerBinding.M5,
            new TriggerBinding(TriggerKind.Keyboard, (uint)Keys.A),
            new TriggerBinding(TriggerKind.Keyboard, (uint)Keys.F12)
        ];
        foreach (TriggerBinding trigger in triggers)
        {
            if (TriggerSetting.From(trigger).ToBinding() != trigger)
            {
                Console.Error.WriteLine($"trigger setting round-trip failed: {trigger.Display}");
                return 8;
            }
        }
        if (TriggerBinding.M4.Display != "M4" || TriggerBinding.M5.Display != "M5" ||
            triggers[2].Display != "A" || triggers[3].Display != "F12")
        {
            Console.Error.WriteLine("trigger display self-test failed");
            return 9;
        }
        var stableDelay = new StableRecommendationDelay();
        if (stableDelay.Observe(1449, 100, 1000) ||
            stableDelay.Observe(1449, 100, 1099) ||
            !stableDelay.Observe(1449, 100, 1100) ||
            !stableDelay.Observe(30451, 0, 1101) ||
            stableDelay.Observe(1449, 100, 1102) ||
            !stableDelay.Observe(1449, 100, 1202))
        {
            Console.Error.WriteLine("stable recommendation delay self-test failed");
            return 16;
        }
        var repeatSendGate = new RepeatSendGate(250);
        if (!repeatSendGate.TryCommit("4", 1000) ||
            repeatSendGate.TryCommit("4", 1170) ||
            repeatSendGate.RemainingMs("4", 1170) != 80 ||
            !repeatSendGate.TryCommit("5", 1170) ||
            !repeatSendGate.TryCommit("4", 1250))
        {
            Console.Error.WriteLine("repeat send acknowledgement gate self-test failed");
            return 17;
        }
        var protectedLatch = new ProtectedChannelSendLatch(2000);
        protectedLatch.Arm(1000);
        if (!protectedLatch.Blocks(1001) || protectedLatch.State != "pendingstart")
        {
            Console.Error.WriteLine("protected channel pending latch self-test failed");
            return 18;
        }
        protectedLatch.ObserveBusy(false); // stale idle packet must not release it
        if (!protectedLatch.Blocks(1100))
        {
            Console.Error.WriteLine("protected channel stale-idle latch self-test failed");
            return 19;
        }
        protectedLatch.ObserveBusy(true);
        if (!protectedLatch.Blocks(5000) || protectedLatch.State != "confirmedchannel")
        {
            Console.Error.WriteLine("protected channel confirmed latch self-test failed");
            return 20;
        }
        protectedLatch.ObserveBusy(false);
        if (protectedLatch.Blocks(5001) || protectedLatch.State != "idle")
        {
            Console.Error.WriteLine("protected channel release latch self-test failed");
            return 21;
        }
        protectedLatch.Arm(6000);
        if (protectedLatch.Blocks(8000))
        {
            Console.Error.WriteLine("protected channel timeout latch self-test failed");
            return 22;
        }
        Console.WriteLine("self-test passed");
        return 0;
    }

    private static void RewriteChecksums(Span<byte> data)
    {
        int sum1 = 0, sum2 = 0, rolling = 0;
        for (int i = 0; i < 66; i++)
        {
            sum1 = (sum1 + data[i]) % 255;
            sum2 = (sum2 + sum1) % 255;
            rolling = (rolling * 33 + data[i]) & 255;
        }
        data[66] = (byte)sum1;
        data[67] = (byte)sum2;
        data[68] = (byte)rolling;
    }

    internal static int Probe()
    {
        using var ready = new ManualResetEventSlim(false);
        using var reader = new WowPixelReader();
        ReaderUpdate? result = null;
        reader.Updated += update =>
        {
            if (update.Packet is null) return;
            result = update;
            ready.Set();
        };
        reader.Start(0);
        if (!ready.Wait(5000) || result?.Packet is not { } packet)
        {
            Console.Error.WriteLine("probe timeout: no valid pixel packet");
            return 5;
        }
        Console.WriteLine($"probe passed: {result.Window}; v={packet.ProtocolVersion}; seq={packet.Sequence}; lossless={packet.Lossless.Hotkey}; preserve={packet.PreserveBurst.Hotkey}; initial={result.CaptureMs:F2}ms; {result.Geometry}");
        return 0;
    }

    internal static int HookSmoke()
    {
        try
        {
            using var hook = new M5Hook();
            hook.ConfigureTriggers(TriggerBinding.M5, TriggerBinding.M4);
            hook.Start();
            hook.ConfigureTriggers(
                new TriggerBinding(TriggerKind.Keyboard, (uint)Keys.F23),
                new TriggerBinding(TriggerKind.Keyboard, (uint)Keys.F24));
            Thread.Sleep(25); // Exercise the hook-thread remapping message path.
            Console.WriteLine("hook smoke-test passed");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"hook smoke-test failed: {ex.Message}");
            return 10;
        }
    }
}
