import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var mainWindowController: MainWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = MainWindowController()
    mainWindowController = controller
    controller.showWindow(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    controller.startServices()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationWillTerminate(_ notification: Notification) {
    mainWindowController?.stopServices()
  }
}

@main
enum JustACBridgeApplication {
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
  }
}
