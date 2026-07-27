import Foundation

struct AppSettings {
  var lossless: TriggerBinding
  var preserveBurst: TriggerBinding

  static func load() -> AppSettings {
    let defaults = UserDefaults.standard
    guard
      let losslessKind = defaults.string(forKey: "lossless.kind").flatMap(
        TriggerKind.init(rawValue:)),
      let preserveKind = defaults.string(forKey: "preserve.kind").flatMap(
        TriggerKind.init(rawValue:))
    else {
      return AppSettings(lossless: .m5, preserveBurst: .m4)
    }
    let lossless = TriggerBinding(
      kind: losslessKind, code: Int64(defaults.integer(forKey: "lossless.code")))
    let preserve = TriggerBinding(
      kind: preserveKind, code: Int64(defaults.integer(forKey: "preserve.code")))
    guard lossless != preserve else { return AppSettings(lossless: .m5, preserveBurst: .m4) }
    return AppSettings(lossless: lossless, preserveBurst: preserve)
  }

  func save() {
    let defaults = UserDefaults.standard
    defaults.set(lossless.kind.rawValue, forKey: "lossless.kind")
    defaults.set(Int(lossless.code), forKey: "lossless.code")
    defaults.set(preserveBurst.kind.rawValue, forKey: "preserve.kind")
    defaults.set(Int(preserveBurst.code), forKey: "preserve.code")
  }
}
