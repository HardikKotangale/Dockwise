import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  // ---- Move to Applications ------------------------------------------------
  // A downloaded app that is run from the Downloads folder or a zip's
  // temporary place (macOS "translocation") is offered a move to /Applications,
  // once; "Do not ask again" is kept. The development build (no quarantine,
  // not translocated) is never asked.

  private let declinedKey = "moveToApplicationsDeclined"

  private func hasQuarantine(_ path: String) -> Bool {
    return getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
  }

  func offerMoveToApplications() {
    let bundle = Bundle.main.bundleURL
    let path = bundle.path
    // `-HushdockOfferMove YES` on the command line forces the offer (to try it)
    let forced = UserDefaults.standard.bool(forKey: "HushdockOfferMove")
    if !forced {
      if UserDefaults.standard.bool(forKey: declinedKey) { return }
      if path.hasPrefix("/Applications/") { return }
      if !(path.contains("/AppTranslocation/") || hasQuarantine(path)) { return }
    }

    let alert = NSAlert()
    alert.messageText = "Move Hushdock to the Applications folder?"
    alert.informativeText =
      "Hushdock works best from the Applications folder, where it opens from Launchpad and Spotlight."
    alert.addButton(withTitle: "Move to Applications")
    alert.addButton(withTitle: "Not Now")
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = "Do not ask again"
    let answer = alert.runModal()
    if alert.suppressionButton?.state == .on {
      UserDefaults.standard.set(true, forKey: declinedKey)
    }
    if answer == .alertFirstButtonReturn { moveToApplications(from: bundle) }
  }

  private func tell(_ title: String, _ text: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.runModal()
  }

  // A sandboxed app cannot make a copy of itself that it (or anyone) may run:
  // macOS marks every file a sandboxed app writes as "created by an AppSandbox,
  // exec/open not allowed". So the copy is made by Finder, asked through an
  // Apple event (the person is asked once to let Hushdock control Finder).
  private func finderCopy(of source: URL) -> URL? {
    let script = """
      tell application "Finder"
        set src to (POSIX file "\(source.path)") as alias
        duplicate src to (POSIX file "/Applications" as alias) with replacing
      end tell
      """
    var error: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&error)
    let dest = URL(fileURLWithPath: "/Applications/Hushdock.app")
    if error == nil, FileManager.default.fileExists(atPath: dest.path) { return dest }
    return nil
  }

  private func moveToApplications(from source: URL) {
    guard let dest = finderCopy(of: source) else {
      // Finder was not allowed, or could not copy: show where to drag it.
      NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
      NSWorkspace.shared.activateFileViewerSelecting([source])
      tell(
        "Drag Hushdock into Applications",
        "Two Finder windows are open: Hushdock and Applications. Drag Hushdock.app into the Applications window, then open it from there."
      )
      return
    }
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: dest, configuration: config) { app, error in
      DispatchQueue.main.async {
        if app != nil {
          NSApp.terminate(nil)
        } else {
          // Do not quit: this copy is still the one that works.
          self.tell(
            "Hushdock was moved to Applications",
            "Open it from the Applications folder."
              + (error.map { " (\($0.localizedDescription))" } ?? ""))
        }
      }
    }
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
