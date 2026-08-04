import CoreGraphics
import Foundation

enum PixelProtocol {
  static let columns = 48
  static let rows = 12
  static let byteCount = 72

  static func find(in image: CGImage) -> (PixelGeometry, [UInt8])? {
    guard let pixels = ImagePixels(image) else { return nil }
    let header: [UInt8] = [0x4A, 0x41, 0x43]
    let maxOriginX = min(16, max(0, pixels.width - 1))
    let maxOriginY = min(80, max(0, pixels.height - 1))

    for pitch100 in 200...600 {
      for originY in 0...maxOriginY {
        let y = originY + pitch100 / 200
        guard y < pixels.height else { continue }
        for originX in 0...maxOriginX {
          var matches = true
          for bit in 0..<24 {
            let x = originX + ((2 * bit + 1) * pitch100 / 200)
            let expected = Int((header[bit >> 3] >> UInt8(7 - (bit & 7))) & 1)
            if x >= pixels.width || pixels.bit(x: x, y: y) != expected {
              matches = false
              break
            }
          }
          guard matches else { continue }
          let geometry = PixelGeometry(pitch100: pitch100, originX: originX, originY: originY)
          if let payload = decodePixels(pixels, geometry: geometry), validate(payload) {
            return (geometry, payload)
          }
        }
      }
    }
    return nil
  }

  static func decode(image: CGImage, geometry: PixelGeometry) -> [UInt8]? {
    guard let pixels = ImagePixels(image) else { return nil }
    return decodePixels(pixels, geometry: geometry)
  }

  static func validate(_ data: [UInt8]) -> Bool {
    guard data.count == byteCount,
      Array(data[0..<3]) == [0x4A, 0x41, 0x43],
      [1, 2, 3, 4].contains(data[3]),
      Array(data[69..<72]) == [0x45, 0x4E, 0x44],
      data[10] <= 24,
      data[38] <= 24
    else {
      return false
    }

    var sum1 = 0
    var sum2 = 0
    var rolling = 0
    for value in data[0..<66] {
      sum1 = (sum1 + Int(value)) % 255
      sum2 = (sum2 + sum1) % 255
      rolling = (rolling * 33 + Int(value)) & 255
    }
    return data[66] == UInt8(sum1)
      && data[67] == UInt8(sum2)
      && data[68] == UInt8(rolling)
  }

  static func decodeValidated(_ data: [UInt8]) -> Packet {
    let flags = data[6]
    let firstExists = flags & 0x01 != 0
    let secondExists = flags & 0x08 != 0
    let version = data[3]
    return Packet(
      protocolVersion: version,
      sequence: UInt16(data[4]) | UInt16(data[5]) << 8,
      gameTickMs: version >= 3 ? 0 : u24(data, 63),
      queueReady: version < 3 || (data[63] & 0x01) != 0,
      gcdRemainingMs: version >= 3 ? Int(data[64]) | Int(data[65]) << 8 : 0,
      isChanneling: flags & 0x40 != 0,
      isCasting: flags & 0x80 != 0,
      lossless: Recommendation(
        exists: firstExists,
        isItem: flags & 0x02 != 0,
        id: firstExists ? u24(data, 7) : 0,
        hotkey: firstExists ? string(data, offset: 11, length: Int(data[10])) : "",
        bound: flags & 0x04 != 0
      ),
      preserveBurst: Recommendation(
        exists: secondExists,
        isItem: flags & 0x10 != 0,
        id: secondExists ? u24(data, 35) : 0,
        hotkey: secondExists ? string(data, offset: 39, length: Int(data[38])) : "",
        bound: flags & 0x20 != 0
      )
    )
  }

  private static func decodePixels(_ pixels: ImagePixels, geometry: PixelGeometry) -> [UInt8]? {
    var payload = [UInt8](repeating: 0, count: byteCount)
    for bit in 0..<(byteCount * 8) {
      let column = bit % columns
      let row = bit / columns
      let x = geometry.originX + ((2 * column + 1) * geometry.pitch100 / 200)
      let y = geometry.originY + ((2 * row + 1) * geometry.pitch100 / 200)
      guard x >= 0, x < pixels.width, y >= 0, y < pixels.height else { return nil }
      if pixels.bit(x: x, y: y) != 0 {
        payload[bit >> 3] |= UInt8(1 << (7 - (bit & 7)))
      }
    }
    return payload
  }

  private static func u24(_ data: [UInt8], _ offset: Int) -> Int {
    Int(data[offset]) | Int(data[offset + 1]) << 8 | Int(data[offset + 2]) << 16
  }

  private static func string(_ data: [UInt8], offset: Int, length: Int) -> String {
    String(bytes: data[offset..<(offset + length)], encoding: .utf8) ?? ""
  }
}

private final class ImagePixels {
  let width: Int
  let height: Int
  private let bytesPerRow: Int
  private let bytesPerPixel: Int
  private let data: CFData
  private let bytes: UnsafePointer<UInt8>

  init?(_ image: CGImage) {
    guard image.bitsPerComponent == 8,
      image.bitsPerPixel >= 24,
      let providerData = image.dataProvider?.data,
      let pointer = CFDataGetBytePtr(providerData)
    else {
      return nil
    }
    width = image.width
    height = image.height
    bytesPerRow = image.bytesPerRow
    bytesPerPixel = image.bitsPerPixel / 8
    data = providerData
    bytes = pointer
  }

  func bit(x: Int, y: Int) -> Int {
    let offset = y * bytesPerRow + x * bytesPerPixel
    let brightness = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
    return brightness >= 128 ? 1 : 0
  }
}
