import CoreGraphics
import Foundation

struct HotkeyBinding {
  private enum Stroke {
    case keyboard(CGKeyCode)
    case mouse(CGMouseButton)
    case wheel(Int32)
  }

  let display: String
  private let modifiers: CGEventFlags
  private let stroke: Stroke

  static func parse(_ text: String) -> (HotkeyBinding?, String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return (nil, "快捷键为空") }
    var canonical = expandAbbreviation(trimmed.uppercased())
    var modifiers: CGEventFlags = []

    while true {
      if canonical.hasPrefix("CTRL-") {
        modifiers.insert(.maskControl)
        canonical.removeFirst(5)
      } else if canonical.hasPrefix("CONTROL-") {
        modifiers.insert(.maskControl)
        canonical.removeFirst(8)
      } else if canonical.hasPrefix("SHIFT-") {
        modifiers.insert(.maskShift)
        canonical.removeFirst(6)
      } else if canonical.hasPrefix("ALT-") {
        modifiers.insert(.maskAlternate)
        canonical.removeFirst(4)
      } else {
        break
      }
    }

    if let button = mouseButton(canonical) {
      return (HotkeyBinding(display: trimmed, modifiers: modifiers, stroke: .mouse(button)), "")
    }
    if canonical == "MOUSEWHEELUP" {
      return (HotkeyBinding(display: trimmed, modifiers: modifiers, stroke: .wheel(1)), "")
    }
    if canonical == "MOUSEWHEELDOWN" {
      return (HotkeyBinding(display: trimmed, modifiers: modifiers, stroke: .wheel(-1)), "")
    }
    if let keyCode = KeyNames.keyCode(for: canonical) {
      return (HotkeyBinding(display: trimmed, modifiers: modifiers, stroke: .keyboard(keyCode)), "")
    }
    if canonical.hasPrefix("PAD") {
      return (nil, "手柄键暂不支持 macOS 事件注入")
    }
    return (nil, "不支持的键名：\(canonical)")
  }

  func pulse(marker: Int64) {
    switch stroke {
    case .keyboard(let code):
      postKeyboard(code, down: true, marker: marker)
      postKeyboard(code, down: false, marker: marker)
    case .mouse(let button):
      postMouse(button, down: true, marker: marker)
      postMouse(button, down: false, marker: marker)
    case .wheel(let delta):
      guard
        let event = CGEvent(
          scrollWheelEvent2Source: nil,
          units: .line,
          wheelCount: 1,
          wheel1: delta,
          wheel2: 0,
          wheel3: 0
        )
      else { return }
      event.flags = modifiers
      event.setIntegerValueField(.eventSourceUserData, value: marker)
      event.post(tap: .cghidEventTap)
    }
  }

  private func postKeyboard(_ code: CGKeyCode, down: Bool, marker: Int64) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
      return
    }
    event.flags = modifiers
    event.setIntegerValueField(.eventSourceUserData, value: marker)
    event.post(tap: .cghidEventTap)
  }

  private func postMouse(_ button: CGMouseButton, down: Bool, marker: Int64) {
    let type: CGEventType
    switch button {
    case .left: type = down ? .leftMouseDown : .leftMouseUp
    case .right: type = down ? .rightMouseDown : .rightMouseUp
    default: type = down ? .otherMouseDown : .otherMouseUp
    }
    let location = CGEvent(source: nil)?.location ?? .zero
    guard
      let event = CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: location,
        mouseButton: button
      )
    else { return }
    event.flags = modifiers
    event.setIntegerValueField(.eventSourceUserData, value: marker)
    event.post(tap: .cghidEventTap)
  }

  private static func mouseButton(_ value: String) -> CGMouseButton? {
    switch value {
    case "BUTTON1": return .left
    case "BUTTON2": return .right
    case "BUTTON3": return .center
    case "BUTTON4": return CGMouseButton(rawValue: 3)
    case "BUTTON5": return CGMouseButton(rawValue: 4)
    default: return nil
    }
  }

  private static func expandAbbreviation(_ value: String) -> String {
    if value.hasPrefix("SHIFT-") || value.hasPrefix("CTRL-")
      || value.hasPrefix("CONTROL-") || value.hasPrefix("ALT-")
    {
      return value
    }

    if value.count > 1 {
      let characters = Array(value)
      let maximum = min(3, characters.count - 1)
      for count in stride(from: maximum, through: 1, by: -1) {
        let prefix = characters[0..<count]
        guard prefix.allSatisfy({ $0 == "S" || $0 == "C" || $0 == "A" }) else { continue }
        let suffix = String(characters[count...])
        let expandedKey = expandKey(suffix)
        guard canCreate(expandedKey) else { continue }
        let expandedModifiers = prefix.map {
          $0 == "S" ? "SHIFT-" : $0 == "C" ? "CTRL-" : "ALT-"
        }.joined()
        return expandedModifiers + expandedKey
      }
    }
    let expanded = expandKey(value)
    return canCreate(expanded) ? expanded : value
  }

  private static func canCreate(_ value: String) -> Bool {
    mouseButton(value) != nil
      || value == "MOUSEWHEELUP"
      || value == "MOUSEWHEELDOWN"
      || KeyNames.keyCode(for: value) != nil
  }

  private static func expandKey(_ value: String) -> String {
    let aliases: [String: String] = [
      "M1": "BUTTON1", "M2": "BUTTON2", "M3": "BUTTON3", "M4": "BUTTON4", "M5": "BUTTON5",
      "MWU": "MOUSEWHEELUP", "MWD": "MOUSEWHEELDOWN",
      "N/": "NUMPADDIVIDE", "N*": "NUMPADMULTIPLY", "N-": "NUMPADMINUS",
      "N+": "NUMPADPLUS", "N.": "NUMPADDECIMAL", "NE": "NUMPADENTER", "NLK": "NUMLOCK",
      "PU": "PAGEUP", "PD": "PAGEDOWN", "INS": "INSERT", "DEL": "DELETE", "HM": "HOME",
      "DN": "DOWN", "LT": "LEFT", "RT": "RIGHT", "BS": "BACKSPACE", "CL": "CAPSLOCK",
      "ESC": "ESCAPE", "PS": "PRINTSCREEN", "SL": "SCROLLLOCK", "PA": "PAUSE",
      "SPC": "SPACE", "ENT": "ENTER",
    ]
    if let alias = aliases[value] { return alias }
    if value.count == 2, value.first == "N", let digit = value.last, digit.isNumber {
      return "NUMPAD\(digit)"
    }
    return value
  }
}

enum KeyNames {
  private static let keys: [String: CGKeyCode] = [
    "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
    "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
    "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "EQUALS": 24, "=": 24, "9": 25, "7": 26, "MINUS": 27,
    "-": 27, "8": 28, "0": 29, "RBRACKET": 30, "]": 30, "O": 31,
    "U": 32, "LBRACKET": 33, "[": 33, "I": 34, "P": 35, "ENTER": 36,
    "L": 37, "J": 38, "APOSTROPHE": 39, "'": 39, "K": 40,
    "SEMICOLON": 41, ";": 41, "BACKSLASH": 42, "\\": 42, "COMMA": 43,
    ",": 43, "SLASH": 44, "/": 44, "N": 45, "M": 46, "PERIOD": 47,
    ".": 47, "TAB": 48, "SPACE": 49, "GRAVE": 50, "`": 50,
    "BACKSPACE": 51, "ESCAPE": 53, "CAPSLOCK": 57,
    "NUMPADDECIMAL": 65, "NUMPADMULTIPLY": 67, "NUMPADPLUS": 69,
    "NUMLOCK": 71, "NUMPADDIVIDE": 75, "NUMPADENTER": 76, "NUMPADMINUS": 78,
    "NUMPAD0": 82, "NUMPAD1": 83, "NUMPAD2": 84, "NUMPAD3": 85,
    "NUMPAD4": 86, "NUMPAD5": 87, "NUMPAD6": 88, "NUMPAD7": 89,
    "NUMPAD8": 91, "NUMPAD9": 92,
    "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97,
    "F7": 98, "F8": 100, "F9": 101, "F10": 109, "F11": 103, "F12": 111,
    "F13": 105, "F14": 107, "F15": 113, "F16": 106, "F17": 64,
    "F18": 79, "F19": 80, "F20": 90,
    "INSERT": 114, "HOME": 115, "PAGEUP": 116, "DELETE": 117, "END": 119,
    "PAGEDOWN": 121, "LEFT": 123, "RIGHT": 124, "DOWN": 125, "UP": 126,
  ]

  static func keyCode(for name: String) -> CGKeyCode? { keys[name] }

  static func displayName(for code: CGKeyCode) -> String {
    let preferred = [
      "SPACE", "TAB", "ENTER", "ESCAPE", "BACKSPACE", "INSERT", "DELETE",
      "HOME", "END", "PAGEUP", "PAGEDOWN", "UP", "DOWN", "LEFT", "RIGHT",
    ]
    for name in preferred where keys[name] == code { return name.capitalized }
    if let name = keys.first(where: { $0.value == code && $0.key.count <= 3 })?.key {
      return name
    }
    return "Key \(code)"
  }
}
