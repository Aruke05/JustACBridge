import AppKit
import CoreGraphics
import Foundation

final class PixelReader {
  var onUpdate: ((ReaderUpdate) -> Void)?

  private let queue = DispatchQueue(
    label: "com.aruke05.JustACBridge.pixel-reader", qos: .userInteractive)
  private var running = false
  private var pollMilliseconds = 5

  func start(pollMilliseconds: Int = 5) {
    guard !running else { return }
    self.pollMilliseconds = max(0, min(20, pollMilliseconds))
    running = true
    queue.async { [weak self] in self?.run() }
  }

  func setPollMilliseconds(_ value: Int) {
    queue.async { [weak self] in self?.pollMilliseconds = max(0, min(20, value)) }
  }

  func stop() {
    running = false
  }

  private func run() {
    var selectedWindow: WindowCandidate?
    var geometry: PixelGeometry?
    var lastSequence: UInt16?
    var wasValid = false
    var nextWindowSearch = Date.distantPast
    var lastStateReport = Date.distantPast

    while running {
      autoreleasepool {
        let loopStart = DispatchTime.now().uptimeNanoseconds
        let now = Date()
        if selectedWindow == nil || now >= nextWindowSearch {
          selectedWindow = findWowWindow()
          nextWindowSearch = now.addingTimeInterval(0.25)
          if selectedWindow == nil {
            geometry = nil
            if wasValid || now.timeIntervalSince(lastStateReport) >= 1 {
              emit(
                ReaderUpdate(
                  state: "等待 WoW 窗口",
                  window: "未找到 World of Warcraft 可见窗口",
                  packet: nil,
                  geometry: nil,
                  captureMs: 0
                ))
              lastStateReport = now
            }
            wasValid = false
            Thread.sleep(forTimeInterval: 0.1)
            return
          }
        }

        guard let window = selectedWindow,
          let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            window.id,
            [.boundsIgnoreFraming, .bestResolution]
          )
        else {
          selectedWindow = nil
          geometry = nil
          wasValid = false
          Thread.sleep(forTimeInterval: 0.05)
          return
        }

        var payload: [UInt8]?
        if let known = geometry,
          let decoded = PixelProtocol.decode(image: image, geometry: known),
          PixelProtocol.validate(decoded)
        {
          payload = decoded
        } else {
          geometry = nil
          if let found = PixelProtocol.find(in: image) {
            geometry = found.0
            payload = found.1
          }
        }

        let captureMs = Double(DispatchTime.now().uptimeNanoseconds - loopStart) / 1_000_000
        if let payload {
          let sequence = UInt16(payload[4]) | UInt16(payload[5]) << 8
          if !wasValid || lastSequence == nil || lastSequence != sequence {
            let packet = PixelProtocol.decodeValidated(payload)
            wasValid = true
            lastSequence = packet.sequence
            emit(
              ReaderUpdate(
                state: "实时映射已启用",
                window: window.description,
                packet: packet,
                geometry: geometry,
                captureMs: captureMs
              ))
          }
        } else {
          let shouldReport = wasValid || now.timeIntervalSince(lastStateReport) >= 1
          wasValid = false
          if shouldReport {
            emit(
              ReaderUpdate(
                state: "等待有效像素包",
                window: window.description,
                packet: nil,
                geometry: nil,
                captureMs: captureMs
              ))
            lastStateReport = now
          }
        }
      }

      let wait = pollMilliseconds
      if wait > 0 {
        Thread.sleep(forTimeInterval: Double(wait) / 1000.0)
      } else {
        Thread.sleep(forTimeInterval: 0.000_001)
      }
    }
  }

  private func emit(_ update: ReaderUpdate) {
    DispatchQueue.main.async { [weak self] in self?.onUpdate?(update) }
  }

  private func findWowWindow() -> WindowCandidate? {
    let applications = NSWorkspace.shared.runningApplications
      .filter({ application in
        let bundle = application.bundleIdentifier?.lowercased() ?? ""
        let name = application.localizedName?.lowercased() ?? ""
        return bundle.contains("worldofwarcraft") || name == "world of warcraft" || name == "魔兽世界"
      })
      .sorted(by: { $0.isActive && !$1.isActive })
    guard !applications.isEmpty,
      let info = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]]
    else {
      return nil
    }

    let pids = Set(applications.map(\.processIdentifier))
    let candidates = info.compactMap { entry -> WindowCandidate? in
      guard let ownerPidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
        let layerNumber = entry[kCGWindowLayer as String] as? NSNumber,
        let windowNumber = entry[kCGWindowNumber as String] as? NSNumber,
        let boundsDictionary = entry[kCGWindowBounds as String] as? [String: Any],
        let x = (boundsDictionary["X"] as? NSNumber)?.doubleValue,
        let y = (boundsDictionary["Y"] as? NSNumber)?.doubleValue,
        let width = (boundsDictionary["Width"] as? NSNumber)?.doubleValue,
        let height = (boundsDictionary["Height"] as? NSNumber)?.doubleValue,
        width >= 296,
        height >= 80
      else {
        return nil
      }
      let ownerPid = pid_t(ownerPidNumber.int32Value)
      let layer = layerNumber.intValue
      let number = windowNumber.uint32Value
      let bounds = CGRect(x: x, y: y, width: width, height: height)
      guard
        pids.contains(ownerPid),
        layer == 0,
        !bounds.isEmpty
      else {
        return nil
      }
      let app = applications.first(where: { $0.processIdentifier == ownerPid })
      let name = app?.localizedName ?? "World of Warcraft"
      return WindowCandidate(
        id: CGWindowID(number),
        description: "\(name)（窗口 \(number)）",
        area: Int(bounds.width * bounds.height),
        isActive: app?.isActive ?? false
      )
    }
    return candidates.sorted {
      if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
      return $0.area > $1.area
    }.first
  }
}

private struct WindowCandidate {
  let id: CGWindowID
  let description: String
  let area: Int
  let isActive: Bool
}
