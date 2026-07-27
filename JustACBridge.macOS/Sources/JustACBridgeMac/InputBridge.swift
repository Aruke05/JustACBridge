import ApplicationServices
import CoreGraphics
import Foundation

final class InputBridge {
  var onTriggerCaptured: ((ActionSlot, TriggerBinding) -> Void)?
  private(set) var eventTapInstalled = false

  private static let injectedMarker: Int64 = 0x4A_41_43_42_4D_41_43
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var repeatTimer: DispatchSourceTimer?
  private var actions = ActionMap(
    lossless: nil, preserveBurst: nil, suppressWithoutBinding: false, canPulse: false)
  private var triggers = TriggerMap(lossless: .m5, preserveBurst: .m4)
  private var captureRequest: ActionSlot?
  private var losslessHeld: TriggerBinding?
  private var preserveHeld: TriggerBinding?
  private var blockedUps = Set<TriggerBinding>()
  private var enabled = true

  func configureTriggers(lossless: TriggerBinding, preserveBurst: TriggerBinding) {
    cancelHeldActions(blockFollowingUp: true)
    triggers = TriggerMap(lossless: lossless, preserveBurst: preserveBurst)
  }

  func setEnabled(_ value: Bool) {
    enabled = value
    if !value { cancelHeldActions(blockFollowingUp: true) }
  }

  func beginCapture(_ slot: ActionSlot) {
    captureRequest = slot
  }

  func cancelCapture() {
    captureRequest = nil
  }

  func setActions(
    lossless: HotkeyBinding?,
    preserveBurst: HotkeyBinding?,
    suppressWithoutBinding: Bool,
    canPulse: Bool
  ) {
    actions = ActionMap(
      lossless: lossless,
      preserveBurst: preserveBurst,
      suppressWithoutBinding: suppressWithoutBinding,
      canPulse: canPulse
    )
    pulseHeldAction()
  }

  @discardableResult
  func start() -> Bool {
    guard eventTap == nil else { return true }
    let mask =
      CGEventMask(1 << CGEventType.keyDown.rawValue)
      | CGEventMask(1 << CGEventType.keyUp.rawValue)
      | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
      | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let bridge = Unmanaged<InputBridge>.fromOpaque(userInfo).takeUnretainedValue()
      return bridge.handle(type: type, event: event)
    }
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: pointer
      )
    else {
      eventTapInstalled = false
      return false
    }

    eventTap = tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    if let source = runLoopSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
    CGEvent.tapEnable(tap: tap, enable: true)
    eventTapInstalled = true

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(
      deadline: .now() + .milliseconds(20), repeating: .milliseconds(20), leeway: .milliseconds(1))
    timer.setEventHandler { [weak self] in self?.pulseHeldAction() }
    timer.resume()
    repeatTimer = timer
    return true
  }

  func stop() {
    repeatTimer?.cancel()
    repeatTimer = nil
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    runLoopSource = nil
    eventTap = nil
    eventTapInstalled = false
    cancelHeldActions(blockFollowingUp: false)
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) == Self.injectedMarker {
      return Unmanaged.passUnretained(event)
    }

    let trigger: TriggerBinding
    let isDown: Bool
    switch type {
    case .keyDown, .keyUp:
      trigger = TriggerBinding(
        kind: .keyboard, code: event.getIntegerValueField(.keyboardEventKeycode))
      isDown = type == .keyDown
    case .otherMouseDown, .otherMouseUp:
      let button = event.getIntegerValueField(.mouseEventButtonNumber)
      guard button == 3 || button == 4 else { return Unmanaged.passUnretained(event) }
      trigger = TriggerBinding(kind: .mouse, code: button)
      isDown = type == .otherMouseDown
    default:
      return Unmanaged.passUnretained(event)
    }

    if isDown {
      if let slot = captureRequest {
        captureRequest = nil
        blockedUps.insert(trigger)
        onTriggerCaptured?(slot, trigger)
        return nil
      }
      if handleDown(trigger) { return nil }
    } else if handleUp(trigger) {
      return nil
    }
    return Unmanaged.passUnretained(event)
  }

  private func handleDown(_ trigger: TriggerBinding) -> Bool {
    guard enabled else { return false }
    if trigger == triggers.lossless {
      if actions.lossless != nil || actions.suppressWithoutBinding {
        cancelHeldAction(&preserveHeld, blockFollowingUp: true)
      }
      return pressSlot(
        trigger,
        binding: actions.lossless,
        suppressWithoutBinding: actions.suppressWithoutBinding,
        canPulse: actions.canPulse,
        held: &losslessHeld
      )
    }
    if trigger == triggers.preserveBurst {
      if actions.preserveBurst != nil || actions.suppressWithoutBinding {
        cancelHeldAction(&losslessHeld, blockFollowingUp: true)
      }
      return pressSlot(
        trigger,
        binding: actions.preserveBurst,
        suppressWithoutBinding: actions.suppressWithoutBinding,
        canPulse: actions.canPulse,
        held: &preserveHeld
      )
    }
    return false
  }

  private func handleUp(_ trigger: TriggerBinding) -> Bool {
    var handled = releaseHeldAction(trigger, held: &losslessHeld)
    handled = releaseHeldAction(trigger, held: &preserveHeld) || handled
    return blockedUps.remove(trigger) != nil || handled
  }

  private func pressSlot(
    _ trigger: TriggerBinding,
    binding: HotkeyBinding?,
    suppressWithoutBinding: Bool,
    canPulse: Bool,
    held: inout TriggerBinding?
  ) -> Bool {
    if held == trigger || blockedUps.contains(trigger) { return true }
    cancelHeldAction(&held, blockFollowingUp: true)
    if let binding {
      held = trigger
      if canPulse { binding.pulse(marker: Self.injectedMarker) }
      return true
    }
    guard suppressWithoutBinding else { return false }
    held = trigger
    return true
  }

  private func releaseHeldAction(_ trigger: TriggerBinding, held: inout TriggerBinding?) -> Bool {
    guard held == trigger else { return false }
    held = nil
    return true
  }

  private func cancelHeldAction(_ held: inout TriggerBinding?, blockFollowingUp: Bool) {
    guard let trigger = held else { return }
    if blockFollowingUp { blockedUps.insert(trigger) }
    held = nil
  }

  private func cancelHeldActions(blockFollowingUp: Bool) {
    cancelHeldAction(&losslessHeld, blockFollowingUp: blockFollowingUp)
    cancelHeldAction(&preserveHeld, blockFollowingUp: blockFollowingUp)
    if !blockFollowingUp { blockedUps.removeAll() }
  }

  private func pulseHeldAction() {
    guard enabled, !actions.suppressWithoutBinding, actions.canPulse else { return }
    if losslessHeld != nil, let binding = actions.lossless {
      binding.pulse(marker: Self.injectedMarker)
    } else if preserveHeld != nil, let binding = actions.preserveBurst {
      binding.pulse(marker: Self.injectedMarker)
    }
  }
}

private struct ActionMap {
  let lossless: HotkeyBinding?
  let preserveBurst: HotkeyBinding?
  let suppressWithoutBinding: Bool
  let canPulse: Bool
}

private struct TriggerMap {
  let lossless: TriggerBinding
  let preserveBurst: TriggerBinding
}
