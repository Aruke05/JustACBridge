using System.Drawing;

namespace JustACBridgeM5;

internal sealed class MainForm : Form
{
    private readonly Label _state = new() { AutoSize = true, Font = new Font("Microsoft YaHei UI", 16, FontStyle.Bold), ForeColor = Color.DarkOrange };
    private readonly Label _window = new() { AutoSize = true };
    private readonly Label _lossless = new() { AutoSize = true, Font = new Font("Consolas", 14, FontStyle.Bold) };
    private readonly Label _preserve = new() { AutoSize = true, Font = new Font("Consolas", 14, FontStyle.Bold) };
    private readonly Label _details = new() { AutoSize = true, ForeColor = Color.DimGray };
    private readonly CheckBox _enabled = new() { AutoSize = true, Checked = true, Text = "启用双键按住连发" };
    private readonly Button _setLossless = new() { AutoSize = true };
    private readonly Button _setPreserve = new() { AutoSize = true };
    private readonly RadioButton _extreme = new() { AutoSize = true, Checked = true, Text = "极限：连续捕获，零人为等待（推荐）" };
    private readonly RadioButton _balanced = new() { AutoSize = true, Text = "均衡：每 5ms 捕获一次" };
    private readonly WowPixelReader _reader = new();
    private readonly M5Hook _hook = new();
    private TriggerBinding _losslessTrigger;
    private TriggerBinding _preserveTrigger;
    private volatile bool _lastBusy;

    internal MainForm()
    {
        AppSettings settings = AppSettings.Load();
        _losslessTrigger = settings.Lossless.ToBinding();
        _preserveTrigger = settings.PreserveBurst.ToBinding();

        Text = "JustACBridge 双键实时映射";
        ClientSize = new Size(700, 410);
        MinimumSize = new Size(716, 449);
        Font = new Font("Microsoft YaHei UI", 9);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;

        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(20),
            AutoScroll = true
        };
        panel.Controls.Add(_state);
        panel.Controls.Add(_window);
        panel.Controls.Add(new Label { AutoSize = true, Text = "无损版（完整 JustAC 第一推荐）：", Margin = new Padding(3, 16, 3, 0) });
        panel.Controls.Add(_lossless);
        panel.Controls.Add(_setLossless);
        panel.Controls.Add(new Label { AutoSize = true, Text = "保留爆发版（跳过大爆发、药水和主动饰品）：", Margin = new Padding(3, 12, 3, 0) });
        panel.Controls.Add(_preserve);
        panel.Controls.Add(_setPreserve);
        panel.Controls.Add(_details);
        panel.Controls.Add(new Label
        {
            AutoSize = true,
            ForeColor = Color.RoyalBlue,
            Text = "按住功能键自动连发；读条、蓄力和引导期间暂停，施法结束后继续。"
        });
        panel.Controls.Add(_enabled);
        panel.Controls.Add(_extreme);
        panel.Controls.Add(_balanced);
        Controls.Add(panel);
        UpdateTriggerButtons();

        _enabled.CheckedChanged += (_, _) => _hook.Enabled = _enabled.Checked;
        _setLossless.Click += (_, _) => BeginTriggerCapture(ActionSlot.Lossless);
        _setPreserve.Click += (_, _) => BeginTriggerCapture(ActionSlot.PreserveBurst);
        _extreme.CheckedChanged += (_, _) => { if (_extreme.Checked) _reader.SetPollMs(0); };
        _balanced.CheckedChanged += (_, _) => { if (_balanced.Checked) _reader.SetPollMs(5); };
        _hook.TriggerCaptured += OnTriggerCaptured;
        _reader.Updated += OnReaderUpdate;
        Shown += (_, _) => StartServices();
    }

    private void StartServices()
    {
        try
        {
            _hook.ConfigureTriggers(_losslessTrigger, _preserveTrigger);
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

    private void BeginTriggerCapture(ActionSlot slot)
    {
        _hook.BeginCapture(slot);
        UpdateTriggerButtons();
        _setLossless.Enabled = slot != ActionSlot.Lossless;
        _setPreserve.Enabled = slot != ActionSlot.PreserveBurst;
        Button active = slot == ActionSlot.Lossless ? _setLossless : _setPreserve;
        active.Text = "请按下新的功能键…（支持 M4/M5 或键盘键）";
    }

    private void OnTriggerCaptured(ActionSlot slot, TriggerBinding trigger)
    {
        if (IsDisposed) return;
        try { BeginInvoke(() => ApplyCapturedTrigger(slot, trigger)); }
        catch (InvalidOperationException) { }
    }

    private void ApplyCapturedTrigger(ActionSlot slot, TriggerBinding trigger)
    {
        if (slot == ActionSlot.Lossless)
        {
            TriggerBinding old = _losslessTrigger;
            _losslessTrigger = trigger;
            if (_preserveTrigger == trigger) _preserveTrigger = old;
        }
        else
        {
            TriggerBinding old = _preserveTrigger;
            _preserveTrigger = trigger;
            if (_losslessTrigger == trigger) _losslessTrigger = old;
        }

        _hook.ConfigureTriggers(_losslessTrigger, _preserveTrigger);
        new AppSettings(
            TriggerSetting.From(_losslessTrigger),
            TriggerSetting.From(_preserveTrigger)).Save();
        UpdateTriggerButtons();
    }

    private void UpdateTriggerButtons()
    {
        _setLossless.Enabled = true;
        _setPreserve.Enabled = true;
        _setLossless.Text = $"设置无损版功能键（当前：{_losslessTrigger.Display}）";
        _setPreserve.Text = $"设置保留爆发版功能键（当前：{_preserveTrigger.Display}）";
    }

    private void OnReaderUpdate(ReaderUpdate update)
    {
        if (IsDisposed) return;
        if (update.Packet is { } packet)
        {
            _lastBusy = packet.IsBusy;
            if (packet.IsBusy)
            {
                _hook.SetActions(null, null, true, false);
            }
            else
            {
                HotkeyBinding? lossless = ParseBinding(packet.Lossless);
                HotkeyBinding? preserve = packet.ProtocolVersion >= 2 ? ParseBinding(packet.PreserveBurst) : null;
                _hook.SetActions(lossless, preserve, false, packet.QueueReady);
            }
        }
        else
        {
            // Busy 状态下遇到撕裂帧时保持保护，直到读到明确的空闲包。
            _hook.SetActions(null, null, _lastBusy, false);
        }

        try { BeginInvoke(() => ApplyUpdate(update)); }
        catch (InvalidOperationException) { }
    }

    private static HotkeyBinding? ParseBinding(Recommendation recommendation) =>
        recommendation is { Exists: true, Bound: true } &&
        HotkeyBinding.TryParse(recommendation.Hotkey, out var binding, out _) ? binding : null;

    private void ApplyUpdate(ReaderUpdate update)
    {
        _state.Text = update.State;
        _window.Text = update.Window;
        _state.ForeColor = update.Packet is null ? Color.DarkOrange : Color.ForestGreen;
        if (update.Packet is null)
        {
            _lossless.Text = "— 等待有效数据 —";
            _lossless.ForeColor = Color.DimGray;
            _preserve.Text = "—";
            _preserve.ForeColor = Color.DimGray;
            _details.Text = update.CaptureMs > 0 ? $"最近一次捕获={update.CaptureMs:F2}ms" : "";
            return;
        }

        Packet p = update.Packet;
        if (p.IsBusy)
        {
            _state.Text = p.IsChanneling ? "持续引导保护：两个功能键均已屏蔽" : "施法读条保护：两个功能键均已屏蔽";
            _state.ForeColor = Color.RoyalBlue;
        }
        else if (!p.QueueReady)
        {
            _state.Text = $"等待最佳入队窗口：GCD 约剩 {p.GcdRemainingMs}ms";
            _state.ForeColor = Color.DarkOrange;
        }

        _lossless.Text = $"{_losslessTrigger.Display} → {Format(p.Lossless)}";
        _preserve.Text = p.ProtocolVersion >= 2
            ? $"{_preserveTrigger.Display} → {Format(p.PreserveBurst)}"
            : $"{_preserveTrigger.Display} → — WoW 插件需升级到协议 v2 —";
        string castState = p.IsChanneling ? "channeling" : p.IsCasting ? "casting/empowering" : "idle";
        string timing = p.ProtocolVersion >= 3
            ? $"入队={(p.QueueReady ? "开放" : "等待")}  gcd≈{p.GcdRemainingMs}ms"
            : $"tick={p.GameTickMs}  兼容连发";
        _details.Text = $"v{p.ProtocolVersion}  seq={p.Sequence}  {timing}  状态={castState}  解码={update.CaptureMs:F2}ms  pitch={update.Geometry}";
        _lossless.ForeColor = BindingColor(p.Lossless, p.IsBusy, out string losslessError);
        string preserveError = "";
        _preserve.ForeColor = p.ProtocolVersion >= 2
            ? BindingColor(p.PreserveBurst, p.IsBusy, out preserveError)
            : Color.Firebrick;
        if (!string.IsNullOrEmpty(losslessError)) _details.Text += "  | 无损：" + losslessError;
        if (!string.IsNullOrEmpty(preserveError)) _details.Text += "  | 保爆：" + preserveError;
    }

    private static Color BindingColor(Recommendation recommendation, bool busy, out string error)
    {
        error = "";
        if (recommendation.Exists && recommendation.Bound &&
            HotkeyBinding.TryParse(recommendation.Hotkey, out _, out error))
            return busy ? Color.DimGray : Color.ForestGreen;
        return recommendation.Exists ? Color.Firebrick : Color.DimGray;
    }

    private static string Format(Recommendation r) =>
        !r.Exists ? "— 无可用推荐 —" : $"{(r.IsItem ? "物品" : "法术")} {r.Id}    [{(string.IsNullOrEmpty(r.Hotkey) ? "未绑定" : r.Hotkey)}]";

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _hook.CancelCapture();
        _reader.Dispose();
        _hook.Dispose();
        base.OnFormClosed(e);
    }
}
