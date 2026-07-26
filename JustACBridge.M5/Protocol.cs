namespace JustACBridgeM5;

internal sealed record Recommendation(bool Exists, bool IsItem, int Id, string Hotkey, bool Bound);
internal sealed record Packet(byte ProtocolVersion, ushort Sequence, int GameTickMs, bool QueueReady, int GcdRemainingMs,
    bool IsChanneling, bool IsCasting,
    Recommendation Lossless, Recommendation PreserveBurst)
{
    internal bool IsBusy => IsChanneling || IsCasting;
}

internal static unsafe class PixelProtocol
{
    internal const int Width = 296;
    internal const int Height = 80;
    private const int Columns = 48;
    private const int Bytes = 72;

    internal readonly record struct Geometry(int Pitch100, int OriginX, int OriginY)
    {
        public override string ToString() => $"{Pitch100 / 100.0:F2}px，origin=({OriginX},{OriginY})";
    }

    internal static bool TryFind(byte* bgra, out Geometry geometry, Span<byte> payload)
    {
        ReadOnlySpan<byte> header = "JAC"u8;
        for (int pitch100 = 200; pitch100 <= 600; pitch100++)
        {
            for (int oy = 0; oy < 5; oy++)
            {
                int y = oy + pitch100 / 200;
                if (y >= Height) continue;
                for (int ox = 0; ox < 5; ox++)
                {
                    bool match = true;
                    for (int bit = 0; bit < 24; bit++)
                    {
                        int x = ox + ((2 * bit + 1) * pitch100 / 200);
                        int expected = (header[bit >> 3] >> (7 - (bit & 7))) & 1;
                        if (x >= Width || ReadBit(bgra, x, y) != expected) { match = false; break; }
                    }
                    if (!match) continue;

                    var candidate = new Geometry(pitch100, ox, oy);
                    DecodePixels(bgra, candidate, payload);
                    if (Validate(payload)) { geometry = candidate; return true; }
                }
            }
        }
        geometry = default;
        return false;
    }

    internal static void DecodePixels(byte* bgra, Geometry geometry, Span<byte> payload)
    {
        payload.Clear();
        for (int bit = 0; bit < Bytes * 8; bit++)
        {
            int column = bit % Columns;
            int row = bit / Columns;
            int x = geometry.OriginX + ((2 * column + 1) * geometry.Pitch100 / 200);
            int y = geometry.OriginY + ((2 * row + 1) * geometry.Pitch100 / 200);
            if ((uint)x >= Width || (uint)y >= Height) return;
            if (ReadBit(bgra, x, y) != 0)
                payload[bit >> 3] |= (byte)(1 << (7 - (bit & 7)));
        }
    }

    private static int ReadBit(byte* bgra, int x, int y)
    {
        byte* p = bgra + ((y * Width + x) * 4);
        return (p[0] + p[1] + p[2]) / 3 >= 128 ? 1 : 0;
    }

    internal static bool TryDecode(ReadOnlySpan<byte> data, out Packet? packet)
    {
        packet = null;
        if (!Validate(data)) return false;
        packet = DecodeValidated(data);
        return true;
    }

    internal static bool Validate(ReadOnlySpan<byte> data)
    {
        if (data.Length != Bytes || !data[..3].SequenceEqual("JAC"u8) ||
            data[3] is not (1 or 2 or 3) || !data[69..72].SequenceEqual("END"u8))
            return false;
        int sum1 = 0, sum2 = 0, rolling = 0;
        for (int i = 0; i < 66; i++)
        {
            sum1 = (sum1 + data[i]) % 255;
            sum2 = (sum2 + sum1) % 255;
            rolling = (rolling * 33 + data[i]) & 255;
        }
        if (data[66] != sum1 || data[67] != sum2 || data[68] != rolling || data[10] > 24 || data[38] > 24)
            return false;

        return true;
    }

    internal static Packet DecodeValidated(ReadOnlySpan<byte> data)
    {
        byte flags = data[6];
        bool firstExists = (flags & 0x01) != 0;
        bool secondExists = (flags & 0x08) != 0;
        return new Packet(
            data[3],
            (ushort)(data[4] | data[5] << 8),
            data[3] >= 3 ? 0 : U24(data, 63),
            data[3] < 3 || data[63] != 0,
            data[3] >= 3 ? data[64] | data[65] << 8 : 0,
            (flags & 0x40) != 0,
            (flags & 0x80) != 0,
            new Recommendation(firstExists, (flags & 0x02) != 0, firstExists ? U24(data, 7) : 0,
                firstExists ? System.Text.Encoding.UTF8.GetString(data.Slice(11, data[10])) : "", (flags & 0x04) != 0),
            new Recommendation(secondExists, (flags & 0x10) != 0, secondExists ? U24(data, 35) : 0,
                secondExists ? System.Text.Encoding.UTF8.GetString(data.Slice(39, data[38])) : "", (flags & 0x20) != 0));
    }

    private static int U24(ReadOnlySpan<byte> data, int offset) => data[offset] | data[offset + 1] << 8 | data[offset + 2] << 16;
}
