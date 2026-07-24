using System.Drawing;

namespace JustACBridgeM5;

internal sealed class MainForm : Form
{
    private readonly Label _state = new() { AutoSize = true, Font = new Font("Microsoft YaHei UI", 16, FontStyle.Bold), ForeColor = Color.DarkOrange };
    private readonly Label _window = new() { AutoSize = true };
    private readonly Label _first = new() { AutoSize = true, Font = new Font("Consolas", 14, FontStyle.Bold) };
    private readonly Label _second = new() { AutoSize = true, Font = new Font("Consolas", 11) };
    private readonly Label _details = new() { AutoSize = true, ForeColor = Color.DimGray };
    private readonly CheckBox _enabled = new() { AutoSize = true, Checked = true, Text = "拦截 M5（鼠标前侧键）并发送第一推荐快捷键" };
    private readonly RadioButton _extreme = new() { AutoSize = true, Checked = true, Text = "极限：连续捕获，零人为等待（推荐）" };
    private readonly RadioButton _balanced = new() { AutoSize = true, Text = "均衡：每 5ms 捕获一次" };
    private readonly WowPixelReader _reader = new();
    private readonly M5Hook _hook = new();
    private volatile bool _lastBusy;

    internal MainForm()
    {
        Text = "JustACBridge M5 实时映射";
        ClientSize = new Size(610, 300);
        MinimumSize = new Size(626, 339);
        Font = new Font("Microsoft YaHei UI", 9);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;

        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
            Padding = new Padding(20), AutoScroll = true
        };
        panel.Controls.Add(_state);
        panel.Controls.Add(_window);
        panel.Controls.Add(new Label { AutoSize = true, Text = "第一推荐 → M5：", Margin = new Padding(3, 16, 3, 0) });
        panel.Controls.Add(_first);
        panel.Controls.Add(new Label { AutoSize = true, Text = "第二推荐（仅显示）：", Margin = new Padding(3, 10, 3, 0) });
        panel.Controls.Add(_second);
        panel.Controls.Add(_details);
        panel.Controls.Add(_enabled);
        panel.Controls.Add(_extreme);
        panel.Controls.Add(_balanced);
        Controls.Add(panel);

        _enabled.CheckedChanged += (_, _) => _hook.Enabled = _enabled.Checked;
        _extreme.CheckedChanged += (_, _) => { if (_extreme.Checked) _reader.SetPollMs(0); };
        _balanced.CheckedChanged += (_, _) => { if (_balanced.Checked) _reader.SetPollMs(5); };
        _reader.Updated += OnReaderUpdate;
        Shown += (_, _) => StartServices();
    }

    private void StartServices()
    {
        try
        {
            _hook.Start();
            _reader.Start(0);
        }
        catch (Exception ex)
        {
            _state.Text = "启动失败";
            _state.ForeColor = Color.Firebrick;
            _details.Text = ex.Message;
        }
    }

    private void OnReaderUpdate(ReaderUpdate update)
    {
        if (IsDisposed) return;
        if (update.Packet is { } packet)
        {
            _lastBusy = packet.IsBusy;
            if (packet.IsBusy)
                _hook.SetAction(null, true);
            else if (packet.First is { Exists: true, Bound: true } &&
                     HotkeyBinding.TryParse(packet.First.Hotkey, out var binding, out _))
                _hook.SetAction(binding, false);
            else
                _hook.SetAction(null, false);
        }
        else
            _hook.SetAction(null, _lastBusy); // Busy 状态下遇到撕裂帧时保持保护，直到读到明确的空闲包。
        try { BeginInvoke(() => ApplyUpdate(update)); }
        catch (InvalidOperationException) { }
    }

    private void ApplyUpdate(ReaderUpdate update)
    {
        _state.Text = update.State;
        _window.Text = update.Window;
        _state.ForeColor = update.Packet is null ? Color.DarkOrange : Color.ForestGreen;
        if (update.Packet is null)
        {
            _first.Text = "— 等待有效数据 —";
            _first.ForeColor = Color.DimGray;
            _second.Text = "—";
            _details.Text = update.CaptureMs > 0 ? $"最近一次捕获={update.CaptureMs:F2}ms" : "";
            return;
        }

        Packet p = update.Packet;
        if (p.IsBusy)
        {
            _state.Text = p.IsChanneling ? "持续引导保护：M5 已完全屏蔽" : "施法读条保护：M5 已完全屏蔽";
            _state.ForeColor = Color.RoyalBlue;
        }
        _first.Text = Format(p.First);
        _second.Text = Format(p.Second);
        string castState = p.IsChanneling ? "channeling" : p.IsCasting ? "casting/empowering" : "idle";
        _details.Text = $"seq={p.Sequence}  tick={p.GameTickMs}  状态={castState}  解码={update.CaptureMs:F2}ms  pitch={update.Geometry}";
        string error = "";
        if (p.First.Exists && p.First.Bound && HotkeyBinding.TryParse(p.First.Hotkey, out var binding, out error))
        {
            _first.ForeColor = p.IsBusy ? Color.DimGray : Color.ForestGreen;
        }
        else
        {
            _first.ForeColor = Color.Firebrick;
            if (p.First.Exists && p.First.Bound && !string.IsNullOrEmpty(error)) _details.Text += "  |  " + error;
        }
    }

    private static string Format(Recommendation r) => !r.Exists ? "— 无 —" : $"{(r.IsItem ? "物品" : "法术")} {r.Id}    [{(string.IsNullOrEmpty(r.Hotkey) ? "未绑定" : r.Hotkey)}]";

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _reader.Dispose();
        _hook.Dispose();
        base.OnFormClosed(e);
    }
}
