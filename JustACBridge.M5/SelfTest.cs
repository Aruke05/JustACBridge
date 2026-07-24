namespace JustACBridgeM5;

internal static unsafe class SelfTest
{
    internal static int Run()
    {
        byte[] sample = Convert.FromHexString("4a41430101002dea4a0101340000000000000000000000000000000000000000000000f7760001310000000000000000000000000000000000000000000000c028c8bbcf16454e44");
        if (!PixelProtocol.TryDecode(sample, out var packet) || packet is null || packet.Sequence != 1 || packet.First.Id != 84714 || packet.First.Hotkey != "4" || packet.Second.Id != 30455 || packet.Second.Hotkey != "1")
        {
            Console.Error.WriteLine("protocol self-test failed");
            return 1;
        }
        byte[] busy = (byte[])sample.Clone();
        busy[6] |= 0x40;
        RewriteChecksums(busy);
        if (!PixelProtocol.TryDecode(busy, out var busyPacket) || busyPacket is not { IsChanneling: true, IsCasting: false, IsBusy: true })
        {
            Console.Error.WriteLine("cast-state self-test failed");
            return 2;
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
        Console.WriteLine($"probe passed: {result.Window}; seq={packet.Sequence}; first={packet.First.Hotkey}; second={packet.Second.Hotkey}; initial={result.CaptureMs:F2}ms; {result.Geometry}");
        return 0;
    }
}
