import AppKit
import ApplicationServices
import CoreGraphics

final class MainWindowController: NSWindowController {
  private static let blizzardSpellID = 190356
  private static let blizzardCancelSuppressionSeconds: TimeInterval = 3

  private let stateLabel = label(size: 20, weight: .bold, color: .systemOrange)
  private let windowLabel = label(size: 13, color: .secondaryLabelColor)
  private let losslessLabel = label(size: 18, weight: .semibold)
  private let preserveLabel = label(size: 18, weight: .semibold)
  private let detailsLabel = label(size: 12, color: .secondaryLabelColor)
  private let permissionLabel = label(size: 12, color: .secondaryLabelColor)
  private let enabledCheckbox = NSButton(checkboxWithTitle: "启用双键按住连发", target: nil, action: nil)
  private let setLosslessButton = NSButton(title: "", target: nil, action: nil)
  private let setPreserveButton = NSButton(title: "", target: nil, action: nil)
  private let permissionButton = NSButton(title: "检查并请求权限", target: nil, action: nil)
  private let settingsButton = NSButton(title: "打开隐私设置", target: nil, action: nil)
  private let captureMode = NSSegmentedControl(
    labels: ["极限", "均衡 5ms"], trackingMode: .selectOne, target: nil, action: nil)
  private let reader = PixelReader()
  private let input = InputBridge()
  private var settings = AppSettings.load()
  private var lastBusy = false
  private var lastPacket: Packet?
  private var blizzardSuppressedUntil: Date?

  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "JustACBridge macOS"
    window.center()
    self.init(window: window)
    buildUI()
    wireEvents()
    updateTriggerButtons()
  }

  func startServices() {
    refreshPermissions(request: true)
    input.configureTriggers(lossless: settings.lossless, preserveBurst: settings.preserveBurst)
    if input.start() {
      enabledCheckbox.state = .on
    }
    reader.start(pollMilliseconds: 5)
  }

  func stopServices() {
    reader.stop()
    input.stop()
  }

  private func buildUI() {
    guard let content = window?.contentView else { return }
    stateLabel.stringValue = "正在启动…"
    windowLabel.stringValue = "尚未连接 WoW"
    losslessLabel.stringValue = "— 等待有效数据 —"
    preserveLabel.stringValue = "—"
    detailsLabel.stringValue = ""
    detailsLabel.lineBreakMode = .byWordWrapping
    detailsLabel.maximumNumberOfLines = 3
    permissionLabel.lineBreakMode = .byWordWrapping
    permissionLabel.maximumNumberOfLines = 3
    enabledCheckbox.state = .on
    captureMode.selectedSegment = 1

    let losslessTitle = Self.label(size: 13)
    losslessTitle.stringValue = "主推荐（移动或超出射程时使用安全替代）"
    let preserveTitle = Self.label(size: 13)
    preserveTitle.stringValue = "保留爆发版（跳过大爆发、药水和主动饰品）"
    let hint = Self.label(size: 12, color: .systemBlue)
    hint.stringValue = "按住功能键自动连发；施法期间保护，并遵守 v3 GCD 最佳入队窗口。"

    let permissionButtons = NSStackView(views: [permissionButton, settingsButton])
    permissionButtons.orientation = .horizontal
    permissionButtons.spacing = 8
    permissionButtons.alignment = .centerY

    let options = NSStackView(views: [enabledCheckbox, captureMode])
    options.orientation = .horizontal
    options.spacing = 18
    options.alignment = .centerY

    let stack = NSStackView(views: [
      stateLabel, windowLabel,
      losslessTitle, losslessLabel, setLosslessButton,
      preserveTitle, preserveLabel, setPreserveButton,
      detailsLabel, hint, options,
      Self.separator(),
      permissionLabel, permissionButtons,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 9
    stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      stack.topAnchor.constraint(equalTo: content.topAnchor),
      detailsLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
      permissionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
    ])
  }

  private func wireEvents() {
    enabledCheckbox.target = self
    enabledCheckbox.action = #selector(enabledChanged)
    setLosslessButton.target = self
    setLosslessButton.action = #selector(captureLossless)
    setPreserveButton.target = self
    setPreserveButton.action = #selector(capturePreserve)
    permissionButton.target = self
    permissionButton.action = #selector(requestPermissions)
    settingsButton.target = self
    settingsButton.action = #selector(openPrivacySettings)
    captureMode.target = self
    captureMode.action = #selector(captureModeChanged)
    reader.onUpdate = { [weak self] update in self?.apply(update) }
    input.onTriggerCaptured = { [weak self] slot, trigger in
      self?.applyCapturedTrigger(slot: slot, trigger: trigger)
    }
    input.onRightClickWhileHolding = { [weak self] slot in
      self?.suppressCancelledBlizzard(for: slot)
    }
  }

  @objc private func enabledChanged() {
    input.setEnabled(enabledCheckbox.state == .on)
  }

  @objc private func captureLossless() {
    beginTriggerCapture(.lossless)
  }

  @objc private func capturePreserve() {
    beginTriggerCapture(.preserveBurst)
  }

  @objc private func captureModeChanged() {
    reader.setPollMilliseconds(captureMode.selectedSegment == 0 ? 0 : 5)
  }

  @objc private func requestPermissions() {
    refreshPermissions(request: true)
    if !input.eventTapInstalled {
      _ = input.start()
    }
  }

  @objc private func openPrivacySettings() {
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
  }

  private func beginTriggerCapture(_ slot: ActionSlot) {
    input.beginCapture(slot)
    setLosslessButton.isEnabled = slot != .lossless
    setPreserveButton.isEnabled = slot != .preserveBurst
    if slot == .lossless {
      setLosslessButton.title = "请按新的 M4/M5 或键盘键…"
    } else {
      setPreserveButton.title = "请按新的 M4/M5 或键盘键…"
    }
  }

  private func applyCapturedTrigger(slot: ActionSlot, trigger: TriggerBinding) {
    if slot == .lossless {
      let old = settings.lossless
      settings.lossless = trigger
      if settings.preserveBurst == trigger { settings.preserveBurst = old }
    } else {
      let old = settings.preserveBurst
      settings.preserveBurst = trigger
      if settings.lossless == trigger { settings.lossless = old }
    }
    settings.save()
    input.configureTriggers(lossless: settings.lossless, preserveBurst: settings.preserveBurst)
    updateTriggerButtons()
  }

  private func updateTriggerButtons() {
    setLosslessButton.isEnabled = true
    setPreserveButton.isEnabled = true
    setLosslessButton.title = "设置无损版功能键（当前：\(settings.lossless.display)）"
    setPreserveButton.title = "设置保留爆发版功能键（当前：\(settings.preserveBurst.display)）"
  }

  private func apply(_ update: ReaderUpdate) {
    if let packet = update.packet {
      lastPacket = packet
      lastBusy = packet.isBusy
      applyInputActions(packet)
    } else {
      input.setActions(
        lossless: nil, preserveBurst: nil, suppressWithoutBinding: lastBusy, canPulse: false)
    }

    stateLabel.stringValue = update.state
    windowLabel.stringValue = update.window
    stateLabel.textColor = update.packet == nil ? .systemOrange : .systemGreen
    guard let packet = update.packet else {
      losslessLabel.stringValue = "— 等待有效数据 —"
      losslessLabel.textColor = .secondaryLabelColor
      preserveLabel.stringValue = "—"
      preserveLabel.textColor = .secondaryLabelColor
      detailsLabel.stringValue =
        update.captureMs > 0
        ? String(format: "最近一次捕获 %.2fms", update.captureMs) : ""
      return
    }

    if packet.isBusy {
      stateLabel.stringValue =
        packet.isChanneling
        ? "持续引导保护：两个功能键均已屏蔽"
        : "施法读条保护：两个功能键均已屏蔽"
      stateLabel.textColor = .systemBlue
    } else if !packet.queueReady {
      stateLabel.stringValue = "等待最佳入队窗口：GCD 约剩 \(packet.gcdRemainingMs)ms"
      stateLabel.textColor = .systemOrange
    } else if let remaining = blizzardSuppressionRemaining() {
      stateLabel.stringValue = String(format: "已取消暴风雪：%.1f 秒内不再释放", remaining)
      stateLabel.textColor = .systemOrange
    }

    losslessLabel.stringValue = "\(settings.lossless.display) → \(format(packet.lossless))"
    preserveLabel.stringValue =
      packet.protocolVersion >= 2
      ? "\(settings.preserveBurst.display) → \(format(packet.preserveBurst))"
      : "\(settings.preserveBurst.display) → — WoW 插件需升级到协议 v2 —"
    let castState =
      packet.isChanneling ? "channeling" : packet.isCasting ? "casting/empowering" : "idle"
    let timing =
      packet.protocolVersion >= 3
      ? "入队=\(packet.queueReady ? "开放" : "等待") gcd≈\(packet.gcdRemainingMs)ms"
      : "tick=\(packet.gameTickMs) 兼容连发"
    detailsLabel.stringValue = String(
      format: "v%d seq=%d %@ 状态=%@ 解码=%.2fms pitch=%@",
      packet.protocolVersion,
      packet.sequence,
      timing,
      castState,
      update.captureMs,
      update.geometry?.description ?? "—"
    )
    losslessLabel.textColor = bindingColor(packet.lossless, busy: packet.isBusy)
    preserveLabel.textColor =
      packet.protocolVersion >= 2
      ? bindingColor(packet.preserveBurst, busy: packet.isBusy) : .systemRed
  }

  private func parse(_ recommendation: Recommendation) -> HotkeyBinding? {
    guard recommendation.exists, recommendation.bound else { return nil }
    return HotkeyBinding.parse(recommendation.hotkey).0
  }

  private func applyInputActions(_ packet: Packet) {
    if packet.isBusy {
      input.setActions(
        lossless: nil, preserveBurst: nil, suppressWithoutBinding: true, canPulse: false)
      return
    }

    let losslessSuppressed = isBlizzardSuppressed(packet.lossless)
    let preserveSuppressed =
      packet.protocolVersion >= 2 && isBlizzardSuppressed(packet.preserveBurst)
    input.setActions(
      lossless: losslessSuppressed ? nil : parse(packet.lossless),
      preserveBurst: packet.protocolVersion >= 2 && !preserveSuppressed
        ? parse(packet.preserveBurst) : nil,
      suppressWithoutBinding: false,
      canPulse: packet.queueReady,
      suppressLosslessWithoutBinding: losslessSuppressed,
      suppressPreserveWithoutBinding: preserveSuppressed
    )
  }

  private func suppressCancelledBlizzard(for slot: ActionSlot) {
    guard let packet = lastPacket else { return }
    let recommendation = slot == .lossless ? packet.lossless : packet.preserveBurst
    guard recommendation.exists, !recommendation.isItem,
      recommendation.id == Self.blizzardSpellID
    else {
      return
    }

    blizzardSuppressedUntil =
      Date().addingTimeInterval(Self.blizzardCancelSuppressionSeconds)
    applyInputActions(packet)
    stateLabel.stringValue = "已取消暴风雪：3.0 秒内不再释放"
    stateLabel.textColor = .systemOrange
  }

  private func isBlizzardSuppressed(_ recommendation: Recommendation) -> Bool {
    recommendation.exists && !recommendation.isItem
      && recommendation.id == Self.blizzardSpellID
      && blizzardSuppressionRemaining() != nil
  }

  private func blizzardSuppressionRemaining() -> TimeInterval? {
    guard let until = blizzardSuppressedUntil else { return nil }
    let remaining = until.timeIntervalSinceNow
    if remaining > 0 { return remaining }
    blizzardSuppressedUntil = nil
    return nil
  }

  private func bindingColor(_ recommendation: Recommendation, busy: Bool) -> NSColor {
    if recommendation.exists, recommendation.bound,
      HotkeyBinding.parse(recommendation.hotkey).0 != nil
    {
      return busy ? .secondaryLabelColor : .systemGreen
    }
    return recommendation.exists ? .systemRed : .secondaryLabelColor
  }

  private func format(_ recommendation: Recommendation) -> String {
    guard recommendation.exists else { return "— 无可用推荐 —" }
    let kind = recommendation.isItem ? "物品" : "法术"
    let hotkey = recommendation.hotkey.isEmpty ? "未绑定" : recommendation.hotkey
    return "\(kind) \(recommendation.id)    [\(hotkey)]"
  }

  private func refreshPermissions(request: Bool) {
    let accessibilityOptions =
      [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: request
      ] as CFDictionary
    let accessibility = AXIsProcessTrustedWithOptions(accessibilityOptions)
    let screen = CGPreflightScreenCaptureAccess() || (request && CGRequestScreenCaptureAccess())
    permissionLabel.stringValue =
      "权限：屏幕录制 \(screen ? "✓" : "✗")　辅助功能/输入监听 \(accessibility ? "✓" : "✗")。首次授权后如未生效，请退出并重新打开本应用。"
    permissionLabel.textColor = screen && accessibility ? .systemGreen : .systemOrange
  }

  private static func label(
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = .labelColor
  ) -> NSTextField {
    let field = NSTextField(labelWithString: "")
    field.font = NSFont.systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
  }

  private static func separator() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    return box
  }
}
