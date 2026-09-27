import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Borderless (square corners, no title bar or shadow) for clean screen
    // recordings of the split-screen demo.
    self.styleMask = [.borderless]
    self.hasShadow = false
    self.contentViewController = flutterViewController
    // 1920x1080 actual pixels, whatever the display's scale factor.
    let scale = (self.screen ?? NSScreen.main)?.backingScaleFactor ?? 1.0
    self.setContentSize(NSSize(width: 1920.0 / scale, height: 1080.0 / scale))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // Borderless windows don't take keyboard focus by default.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
