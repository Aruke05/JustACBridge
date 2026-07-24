namespace JustACBridgeM5;

internal sealed class HotkeyBinding
{
    private readonly List<Stroke> _modifiers;
    private readonly Stroke _key;
    private readonly NativeMethods.INPUT[] _pressInputs;
    private readonly NativeMethods.INPUT[] _releaseInputs;
    internal string Display { get; }

    private HotkeyBinding(string display, List<Stroke> modifiers, Stroke key)
    {
        Display = display;
        _modifiers = modifiers;
        _key = key;
        _pressInputs = [.. modifiers.Select(x => x.Input(false)), key.Input(false)];
        _releaseInputs = [key.Input(true), .. modifiers.AsEnumerable().Reverse().Select(x => x.Input(true))];
    }

    internal static bool TryParse(string text, out HotkeyBinding? binding, out string error)
    {
        binding = null;
        error = "";
        if (string.IsNullOrWhiteSpace(text)) { error = "快捷键为空"; return false; }
        string remaining = text.Trim().ToUpperInvariant();
        var modifiers = new List<Stroke>();
        while (true)
        {
            ushort vk;
            int prefixLength;
            if (remaining.StartsWith("CTRL-", StringComparison.Ordinal)) { vk = 0xA2; prefixLength = 5; }
            else if (remaining.StartsWith("CONTROL-", StringComparison.Ordinal)) { vk = 0xA2; prefixLength = 8; }
            else if (remaining.StartsWith("SHIFT-", StringComparison.Ordinal)) { vk = 0xA0; prefixLength = 6; }
            else if (remaining.StartsWith("ALT-", StringComparison.Ordinal)) { vk = 0xA4; prefixLength = 4; }
            else break;
            modifiers.Add(Stroke.Keyboard(vk));
            remaining = remaining[prefixLength..];
        }
        string keyName = remaining;
        if (!Stroke.TryCreate(keyName, out var key))
        {
            error = keyName.StartsWith("PAD", StringComparison.Ordinal) ? "手柄键暂不支持 SendInput" : $"不支持的键名：{keyName}";
            return false;
        }
        binding = new HotkeyBinding(text, modifiers, key);
        return true;
    }

    internal void Press()
    {
        Send(_pressInputs);
    }

    internal void Release()
    {
        Send(_releaseInputs);
    }

    private static void Send(NativeMethods.INPUT[] inputs)
    {
        NativeMethods.SendInput((uint)inputs.Length, inputs, System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.INPUT>());
    }

    private readonly record struct Stroke(bool IsMouse, ushort Scan, bool Extended, uint MouseDown, uint MouseUp, uint MouseData, bool Pulse)
    {
        internal static Stroke Keyboard(ushort vk)
        {
            uint mapped = NativeMethods.MapVirtualKey(vk, 4); // MAPVK_VK_TO_VSC_EX
            return new(false, (ushort)(mapped & 0xFF), (mapped & 0xFF00) != 0, 0, 0, 0, false);
        }

        internal static bool TryCreate(string name, out Stroke stroke)
        {
            if (TryMouse(name, out stroke)) return true;
            ushort vk = KeyToVirtualKey(name);
            if (vk == 0) return false;
            stroke = Keyboard(vk);
            return stroke.Scan != 0;
        }

        private static bool TryMouse(string name, out Stroke stroke)
        {
            stroke = name switch
            {
                "BUTTON1" => new(true, 0, false, NativeMethods.MOUSEEVENTF_LEFTDOWN, NativeMethods.MOUSEEVENTF_LEFTUP, 0, false),
                "BUTTON2" => new(true, 0, false, NativeMethods.MOUSEEVENTF_RIGHTDOWN, NativeMethods.MOUSEEVENTF_RIGHTUP, 0, false),
                "BUTTON3" => new(true, 0, false, NativeMethods.MOUSEEVENTF_MIDDLEDOWN, NativeMethods.MOUSEEVENTF_MIDDLEUP, 0, false),
                "BUTTON4" => new(true, 0, false, NativeMethods.MOUSEEVENTF_XDOWN, NativeMethods.MOUSEEVENTF_XUP, 1, false),
                "BUTTON5" => new(true, 0, false, NativeMethods.MOUSEEVENTF_XDOWN, NativeMethods.MOUSEEVENTF_XUP, 2, false),
                "MOUSEWHEELUP" => new(true, 0, false, NativeMethods.MOUSEEVENTF_WHEEL, 0, 120, true),
                "MOUSEWHEELDOWN" => new(true, 0, false, NativeMethods.MOUSEEVENTF_WHEEL, 0, unchecked((uint)-120), true),
                _ => default
            };
            return stroke.MouseDown != 0;
        }

        internal NativeMethods.INPUT Input(bool up)
        {
            if (IsMouse)
            {
                uint flags = Pulse ? (up ? 0 : MouseDown) : (up ? MouseUp : MouseDown);
                return new NativeMethods.INPUT { type = NativeMethods.INPUT_MOUSE, U = new NativeMethods.InputUnion { mi = new NativeMethods.MOUSEINPUT { dwFlags = flags, mouseData = MouseData } } };
            }
            uint keyFlags = NativeMethods.KEYEVENTF_SCANCODE | (Extended ? NativeMethods.KEYEVENTF_EXTENDEDKEY : 0) | (up ? NativeMethods.KEYEVENTF_KEYUP : 0);
            return new NativeMethods.INPUT { type = NativeMethods.INPUT_KEYBOARD, U = new NativeMethods.InputUnion { ki = new NativeMethods.KEYBDINPUT { wScan = Scan, dwFlags = keyFlags } } };
        }

        private static ushort KeyToVirtualKey(string key)
        {
            if (key.Length == 1 && key[0] is >= 'A' and <= 'Z') return key[0];
            if (key.Length == 1 && key[0] is >= '0' and <= '9') return key[0];
            if (key.StartsWith('F') && int.TryParse(key[1..], out int f) && f is >= 1 and <= 24) return (ushort)(0x6F + f);
            if (key.StartsWith("NUMPAD") && key.Length == 7 && key[6] is >= '0' and <= '9') return (ushort)(0x60 + key[6] - '0');
            return key switch
            {
                "ESC" or "ESCAPE" => 0x1B,
                "TAB" => 0x09,
                "SPACE" => 0x20,
                "ENTER" => 0x0D,
                "BACKSPACE" => 0x08,
                "CAPSLOCK" => 0x14,
                "NUMLOCK" => 0x90,
                "SCROLLLOCK" => 0x91,
                "INSERT" => 0x2D,
                "DELETE" => 0x2E,
                "HOME" => 0x24,
                "END" => 0x23,
                "PAGEUP" => 0x21,
                "PAGEDOWN" => 0x22,
                "UP" => 0x26,
                "DOWN" => 0x28,
                "LEFT" => 0x25,
                "RIGHT" => 0x27,
                "NUMPADDECIMAL" => 0x6E,
                "NUMPADDIVIDE" => 0x6F,
                "NUMPADMULTIPLY" => 0x6A,
                "NUMPADMINUS" => 0x6D,
                "NUMPADPLUS" => 0x6B,
                "NUMPADENTER" => 0x0D,
                "MINUS" or "-" => 0xBD,
                "EQUALS" or "=" => 0xBB,
                "LBRACKET" or "[" => 0xDB,
                "RBRACKET" or "]" => 0xDD,
                "BACKSLASH" or "\\" => 0xDC,
                "SEMICOLON" or ";" => 0xBA,
                "APOSTROPHE" or "'" => 0xDE,
                "COMMA" or "," => 0xBC,
                "PERIOD" or "." => 0xBE,
                "SLASH" or "/" => 0xBF,
                "GRAVE" or "`" => 0xC0,
                _ => 0
            };
        }
    }
}
