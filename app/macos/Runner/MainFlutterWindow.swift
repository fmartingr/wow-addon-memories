import Cocoa
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // The Dart code reads --hidden from its arguments, which macOS does not
    // pass on by default.
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // A hidden start (--hidden, from the login entry) keeps the window hidden at
  // launch; the Dart code shows it unless the tray icon holds the app.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    if CommandLine.arguments.contains("--hidden") {
      hiddenWindowAtLaunch()
    }
  }
}
