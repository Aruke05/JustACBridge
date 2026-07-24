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
            v2Packet.Lossless.Id != 84714 || v2Packet.PreserveBurst.Id != 30455)
        {
            Console.Error.WriteLine("protocol v2 self-test failed");
            return 6;
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

        string[] supported = ["1", "SHIFT-1", "CTRL-F", "ALT-NUMPAD1", "BUTTON4", "MOUSEWHEELUP", "-"];
        foreach (string key in supported)
        {
            if (!HotkeyBinding.TryParse(key, out _, out string error))
            {
                Console.Error.WriteLine($"hotkey self-test failed: {key}: {error}");
                return 4;
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
