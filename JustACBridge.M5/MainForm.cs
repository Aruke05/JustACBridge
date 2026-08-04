using System.Drawing;

namespace JustACBridgeM5;

internal sealed class MainForm : Form
{
    private const int BlizzardSpellId = 190356;
    private const long BlizzardCancelSuppressionMs = 3000;

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
    private readonly CheckBox _debugEnabled = new() { AutoSize = true, Text = "启用诊断日志（仅排错时）" };
    private readonly Button _copyDebug = new() { AutoSize = true, Enabled = false, Text = "复制完整诊断日志" };
    private readonly WowPixelReader _reader = new();
    private readonly M5Hook _hook = new();
    private TriggerBinding _losslessTrigger;
    private TriggerBinding _preserveTrigger;
    private volatile bool _lastBusy;
    private Packet? _lastPacket;
    private long _blizzardSuppressedUntilTick;
    private string _lastReaderTrace = "";

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
        panel.Controls.Add(new Label { AutoSize = true, Text = "主推荐（第一推荐不可移动施放或超出射程时使用安全替代）：", Margin = new Padding(3, 16, 3, 0) });
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
            Text = "按住功能键自动连发；施法期间保护，允许奥术飞弹在 GCD 末按循环截断。"
        });
        panel.Controls.Add(_enabled);
        panel.Controls.Add(_extreme);
        panel.Controls.Add(_balanced);
        panel.Controls.Add(_debugEnabled);
        panel.Controls.Add(_copyDebug);
        Controls.Add(panel);
        UpdateTriggerButtons();

        _enabled.CheckedChanged += (_, _) => _hook.Enabled = _enabled.Checked;
        _setLossless.Click += (_, _) => BeginTriggerCapture(ActionSlot.Lossless);
        _setPreserve.Click += (_, _) => BeginTriggerCapture(ActionSlot.PreserveBurst);
        _extreme.CheckedChanged += (_, _) => { if (_extreme.Checked) _reader.SetPollMs(0); };
        _balanced.CheckedChanged += (_, _) => { if (_balanced.Checked) _reader.SetPollMs(5); };
        _debugEnabled.CheckedChanged += (_, _) => ToggleDiagnostics();
        _copyDebug.Click += (_, _) => CopyDebugLog();
        _hook.TriggerCaptured += OnTriggerCaptured;
        _hook.RightClickWhileHolding += OnRightClickWhileHolding;
        _reader.Updated += OnReaderUpdate;
        Shown += (_, _) => StartServices();
    }

    private void ToggleDiagnostics()
    {
        DiagnosticLog.Enabled = _debugEnabled.Checked;
        _copyDebug.Enabled = _debugEnabled.Checked;
        _lastReaderTrace = "";
        if (_debugEnabled.Checked)
        {
            DiagnosticLog.Write($"UI diagnostics-enabled losslessTrigger={_losslessTrigger.Display} preserveTrigger={_preserveTrigger.Display}");
            Packet? packet = Volatile.Read(ref _lastPacket);
            if (packet is not null)
                DiagnosticLog.Write($"STATE current v={packet.ProtocolVersion} seq={packet.Sequence} moving={packet.IsMoving} movementFilter={packet.MovementFilter} queueReady={packet.QueueReady} gcdMs={packet.GcdRemainingMs} busy={packet.IsBusy} lossless={PacketRecommendation(packet.Lossless)} preserve={PacketRecommendation(packet.PreserveBurst)}");
            _details.Text = "诊断已开启；魔兽内同时执行 /jacb debug on。";
        }
        else
        {
            _details.Text = "诊断已关闭。";
        }
    }

    private void StartServices()
    {
        try
        {
            DiagnosticLog.Write($"UI services-start losslessTrigger={_losslessTrigger.Display} preserveTrigger={_preserveTrigger.Display}");
            _hook.ConfigureTriggers(_losslessTrigger, _preserveTrigger);
            _hook.Start();
            _reader.Start(0);
        }
        catch (Exception ex)
        {
            DiagnosticLog.Write("UI services-failed " + ex);
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
            if (DiagnosticLog.Enabled)
            {
                string traceKey = $"valid:{update.Window}:{packet.ProtocolVersion}:{packet.Sequence}:{packet.IsMoving}:{packet.MovementFilter}:{packet.QueueReady}:{packet.GcdRemainingMs}:{packet.IsBusy}:{PacketRecommendation(packet.Lossless)}:{PacketRecommendation(packet.PreserveBurst)}:{update.Geometry}";
                if (traceKey != _lastReaderTrace)
                {
                    _lastReaderTrace = traceKey;
                    DiagnosticLog.Write($"PIXEL valid window={update.Window} v={packet.ProtocolVersion} seq={packet.Sequence} moving={packet.IsMoving} movementFilter={packet.MovementFilter} queueReady={packet.QueueReady} gcdMs={packet.GcdRemainingMs} busy={packet.IsBusy} lossless={PacketRecommendation(packet.Lossless)} preserve={PacketRecommendation(packet.PreserveBurst)} geometry={update.Geometry} captureMs={update.CaptureMs:F2}");
                }
            }
            Volatile.Write(ref _lastPacket, packet);
            _lastBusy = packet.IsBusy;
            ApplyHookActions(packet);
        }
        else
        {
            if (DiagnosticLog.Enabled)
            {
                string trace = $"PIXEL invalid state={update.State} window={update.Window}";
                if (trace != _lastReaderTrace)
                {
                    _lastReaderTrace = trace;
                    DiagnosticLog.Write(trace);
                }
            }
            // Busy 状态下遇到撕裂帧时保持保护，直到读到明确的空闲包。
            _hook.SetActions(null, null, _lastBusy, false);
        }

        try { BeginInvoke(() => ApplyUpdate(update)); }
        catch (InvalidOperationException) { }
    }

    private static HotkeyBinding? ParseBinding(Recommendation recommendation) =>
        recommendation is { Exists: true, Bound: true } &&
        HotkeyBinding.TryParse(recommendation.Hotkey, out var binding, out _) ? binding : null;

    private void ApplyHookActions(Packet packet)
    {
        if (packet.IsBusy)
        {
            _hook.SetActions(null, null, true, false);
            return;
        }

        bool losslessSuppressed = IsBlizzardSuppressed(packet.Lossless);
        bool preserveSuppressed =
            packet.ProtocolVersion >= 2 && IsBlizzardSuppressed(packet.PreserveBurst);
        bool movementBlocksLossless = packet.ProtocolVersion >= 4 && packet.IsMoving && packet.MovementFilter
            && ParseBinding(packet.Lossless) is null;
        bool movementBlocksPreserve = packet.ProtocolVersion >= 4 && packet.IsMoving && packet.MovementFilter
            && ParseBinding(packet.PreserveBurst) is null;
        _hook.SetActions(
            losslessSuppressed ? null : ParseBinding(packet.Lossless),
            packet.ProtocolVersion >= 2 && !preserveSuppressed
                ? ParseBinding(packet.PreserveBurst) : null,
            false,
            packet.QueueReady,
            losslessSuppressed || movementBlocksLossless,
            preserveSuppressed || movementBlocksPreserve);
    }

    private void OnRightClickWhileHolding(ActionSlot slot)
    {
        Packet? packet = Volatile.Read(ref _lastPacket);
        if (packet is null) return;
        Recommendation recommendation =
            slot == ActionSlot.Lossless ? packet.Lossless : packet.PreserveBurst;
        if (!recommendation.Exists || recommendation.IsItem || recommendation.Id != BlizzardSpellId)
            return;

        Interlocked.Exchange(
            ref _blizzardSuppressedUntilTick,
            Environment.TickCount64 + BlizzardCancelSuppressionMs);
        ApplyHookActions(packet);
        try
        {
            BeginInvoke(() =>
            {
                _state.Text = "已取消暴风雪：3.0 秒内不再释放";
                _state.ForeColor = Color.DarkOrange;
            });
        }
        catch (InvalidOperationException) { }
    }

    private bool IsBlizzardSuppressed(Recommendation recommendation) =>
        recommendation is { Exists: true, IsItem: false, Id: BlizzardSpellId } &&
        BlizzardSuppressionRemainingMs() > 0;

    private long BlizzardSuppressionRemainingMs()
    {
        long until = Interlocked.Read(ref _blizzardSuppressedUntilTick);
        long remaining = until - Environment.TickCount64;
        if (remaining > 0) return remaining;
        if (until != 0) Interlocked.CompareExchange(ref _blizzardSuppressedUntilTick, 0, until);
        return 0;
    }

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
        else
        {
            long remaining = BlizzardSuppressionRemainingMs();
            if (p.ProtocolVersion >= 4 && p.IsMoving && p.MovementFilter &&
                (!p.Lossless.Exists || !p.PreserveBurst.Exists))
            {
                string slot = !p.Lossless.Exists && !p.PreserveBurst.Exists
                    ? "两个模式" : !p.Lossless.Exists ? "主推荐" : "保留爆发版";
                _state.Text = $"移动过滤生效：{slot}当前没有安全技能";
                _state.ForeColor = Color.DarkOrange;
            }
            else if (remaining > 0)
            {
                _state.Text = $"已取消暴风雪：{remaining / 1000.0:F1} 秒内不再释放";
                _state.ForeColor = Color.DarkOrange;
            }
        }

        _lossless.Text = $"{_losslessTrigger.Display} → {Format(p.Lossless)}";
        _preserve.Text = p.ProtocolVersion >= 2
            ? $"{_preserveTrigger.Display} → {Format(p.PreserveBurst)}"
            : $"{_preserveTrigger.Display} → — WoW 插件需升级到协议 v2 —";
        string castState = p.IsChanneling ? "channeling" : p.IsCasting ? "casting/empowering" : "idle";
        string moveState = p.ProtocolVersion >= 4
            ? $"移动={(p.IsMoving ? "是" : "否")}/{(p.MovementFilter ? "过滤开" : "过滤关")}" : "移动=协议未提供";
        string timing = p.ProtocolVersion >= 3
            ? $"入队={(p.QueueReady ? "开放" : "等待")}  gcd≈{p.GcdRemainingMs}ms"
            : $"tick={p.GameTickMs}  兼容连发";
        _details.Text = $"v{p.ProtocolVersion}  seq={p.Sequence}  {timing}  状态={castState}  {moveState}  解码={update.CaptureMs:F2}ms  pitch={update.Geometry}";
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

    private static string PacketRecommendation(Recommendation r) =>
        !r.Exists ? "none" : $"{(r.IsItem ? "item" : "spell")}:{r.Id}:{r.Hotkey}:bound={r.Bound}";

    private void CopyDebugLog()
    {
        try
        {
            Clipboard.SetText(DiagnosticLog.Snapshot());
            _copyDebug.Text = "已复制完整日志";
            _details.Text = "诊断日志已复制；原始文件：" + DiagnosticLog.FilePath;
            DiagnosticLog.Write("UI diagnostic-log-copied");
        }
        catch (Exception ex)
        {
            _details.Text = "复制失败：" + ex.Message + "；日志文件：" + DiagnosticLog.FilePath;
            DiagnosticLog.Write("UI diagnostic-log-copy-failed " + ex.Message);
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        DiagnosticLog.Enabled = false;
        _hook.CancelCapture();
        _reader.Dispose();
        _hook.Dispose();
        base.OnFormClosed(e);
    }
}
