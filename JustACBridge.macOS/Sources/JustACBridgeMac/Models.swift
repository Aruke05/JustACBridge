import CoreGraphics
import Foundation

struct Recommendation {
  let exists: Bool
  let isItem: Bool
  let id: Int
  let hotkey: String
  let bound: Bool
  let offGCD: Bool
}

struct Packet {
  let protocolVersion: UInt8
  let sequence: UInt16
  let gameTickMs: Int
  let queueReady: Bool
  let gcdRemainingMs: Int
  let isChanneling: Bool
  let isCasting: Bool
  let lossless: Recommendation
  let preserveBurst: Recommendation

  var isBusy: Bool { isChanneling || isCasting }
  var losslessCanPulse: Bool { queueReady || lossless.offGCD }
  var preserveCanPulse: Bool { queueReady || preserveBurst.offGCD }
}

struct PixelGeometry: CustomStringConvertible {
  let pitch100: Int
  let originX: Int
  let originY: Int

  var description: String {
    String(format: "%.2fpx，origin=(%d,%d)", Double(pitch100) / 100.0, originX, originY)
  }
}

struct ReaderUpdate {
  let state: String
  let window: String
  let packet: Packet?
  let geometry: PixelGeometry?
  let captureMs: Double
}

enum ActionSlot {
  case lossless
  case preserveBurst
}

enum TriggerKind: String, Codable {
  case keyboard
  case mouse
}

struct TriggerBinding: Codable, Hashable {
  let kind: TriggerKind
  let code: Int64

  static let m4 = TriggerBinding(kind: .mouse, code: 3)
  static let m5 = TriggerBinding(kind: .mouse, code: 4)

  var display: String {
    if kind == .mouse {
      if code == 3 { return "M4" }
      if code == 4 { return "M5" }
      return "鼠标键 \(code + 1)"
    }
    return KeyNames.displayName(for: CGKeyCode(code))
  }
}
