import Cocoa
import FlutterMacOS
import AVFoundation
import IOKit.pwr_mgt

class MainFlutterWindow: NSWindow {
  private var keepAwakeId: IOPMAssertionID = 0
  private var keepingAwake = false
  private var timerPlayer: AVAudioPlayer?
  private var art: (url: String, data: Data?) = ("", nil)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // fill the screen's usable area (below the menu bar, above the Dock), not
    // the small default window; the green button still goes full screen
    let windowFrame = NSScreen.main?.visibleFrame ?? self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 420, height: 300)
    // no title bar band: the display runs under it (the three window buttons
    // stay, small, in the top-left corner)
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Same channel as the Windows runner; anything else is NotImplemented,
    // which the Dart side tolerates.
    FlutterMethodChannel(
      name: "standby_pro/system",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }

    super.awakeFromNib()
    // once the window is up: offer to move a downloaded copy to Applications
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      (NSApp.delegate as? AppDelegate)?.offerMoveToApplications()
    }
  }

  deinit { setKeepAwake(false) }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "setKeepAwake":
      setKeepAwake((args?["enabled"] as? Bool) ?? false)
      result(true)
    case "setFullscreen":
      let on = (args?["enabled"] as? Bool) ?? false
      if on != styleMask.contains(.fullScreen) { toggleFullScreen(nil) }
      result(true)
    case "launchApp":
      let text = (args?["url"] as? String) ?? ""
      guard let url = URL(string: text), !text.isEmpty else { return result(false) }
      // no app answers the scheme (Spotify not installed) -> false. Asking
      // the open itself, not looking the app up first: the lookup can come
      // back empty inside the sandbox.
      let config = NSWorkspace.OpenConfiguration()
      config.activates = true
      NSWorkspace.shared.open(url, configuration: config) { app, error in
        DispatchQueue.main.async { result(error == nil && app != nil) }
      }
    case "timerAlert":
      // the sound only: a Mac has nothing to vibrate
      let sound = (args?["sound"] as? String) ?? "alarm"
      timerPlayer?.stop()
      if sound != "none" {
        timerPlayer = try? AVAudioPlayer(data: clip(sound))
        timerPlayer?.volume = 1
        timerPlayer?.play()
      }
      result(true)
    case "nowPlaying":
      result(spotifyNowPlaying())
    case "mediaCommand":
      switch (args?["command"] as? String) ?? "" {
      case "playPause": result(spotifyScript("playpause") != nil)
      case "next": result(spotifyScript("next track") != nil)
      case "previous": result(spotifyScript("previous track") != nil)
      default: result(false)
      }
    case "seekBy":
      let ms = (args?["deltaMs"] as? Int) ?? 0
      result(spotifyScript("set player position to (player position) + (\(ms) / 1000)") != nil)
    case "seekTo":
      let ms = (args?["positionMs"] as? Int) ?? 0
      result(spotifyScript("set player position to (\(ms) / 1000)") != nil)
    case "deviceModel":
      // Spotify names this Mac's device after it
      result(Host.current().localizedName ?? "")
    case "bringToFront":
      NSApp.activate(ignoringOtherApps: true)
      makeKeyAndOrderFront(nil)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }



  // The Spotify desktop app, driven with AppleScript: no Spotify account
  // login, no developer app, no user limit. Never launches Spotify (a
  // "tell" would): it is only asked while it is already running.
  private func spotifyRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
  }

  private func spotifyScript(_ body: String) -> NSAppleEventDescriptor? {
    guard spotifyRunning() else { return nil }
    var error: NSDictionary?
    let out = NSAppleScript(source: "tell application \"Spotify\"\n\(body)\nend tell")?
      .executeAndReturnError(&error)
    if let error { NSLog("Hushdock: Spotify script failed: \(error)") }
    return error == nil ? out : nil
  }

  private func spotifyNowPlaying() -> [String: Any]? {
    guard let d = spotifyScript("""
      if player state is stopped then return {}
      set artUrl to ""
      try
        set artUrl to artwork url of current track
      end try
      return {player state as string, name of current track, artist of current track, (player position * 1000) as integer, duration of current track, artUrl}
      """), d.numberOfItems >= 6
    else { return nil }
    func text(_ i: Int) -> String { d.atIndex(i)?.stringValue ?? "" }
    let url = text(6)
    if url != art.url {
      art = (url, nil)
      if let u = URL(string: url), !url.isEmpty {
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
          DispatchQueue.main.async { if self?.art.url == url { self?.art.data = data } }
        }.resume()
      }
    }
    var m: [String: Any] = [
      "title": text(2),
      "artist": text(3),
      "app": "Spotify",
      "playing": text(1) == "playing",
      "position": Int(d.atIndex(4)?.int32Value ?? 0),
      "duration": Int(d.atIndex(5)?.int32Value ?? 0),
    ]
    if let data = art.data { m["art"] = FlutterStandardTypedData(bytes: data) }
    return m
  }

  // The same three clips as the iPhone: a 22.05 kHz mono WAV made in memory.
  private func tone(_ f: Double, _ secs: Double, decay: Double = 0) -> [Int16] {
    let rate = 22050.0
    let n = Int(secs * rate)
    var out = [Int16](repeating: 0, count: n)
    for i in 0..<n {
      let t = Double(i) / rate
      var env = min(1.0, t / 0.004, (secs - t) / 0.01)
      if decay > 0 { env *= exp(-decay * t) }
      let v = sin(2 * .pi * f * t) + 0.35 * sin(4 * .pi * f * t)
      out[i] = Int16(max(-1, min(1, v * env * 0.55)) * 30000)
    }
    return out
  }

  private func quiet(_ secs: Double) -> [Int16] {
    [Int16](repeating: 0, count: Int(secs * 22050))
  }

  private func clip(_ name: String) -> Data {
    var s = [Int16]()
    switch name {
    case "chime":
      for f in [1318.5, 1568.0, 2093.0] { s += tone(f, 0.9, decay: 4) }
      s += quiet(0.3)
    case "fanfare":
      for _ in 0..<2 {
        for (f, d) in [(523.25, 0.14), (659.25, 0.14), (783.99, 0.14), (1046.5, 0.55)] {
          s += tone(f, d)
          s += quiet(0.04)
        }
        s += quiet(0.25)
      }
    default:  // a beeping alarm clock: groups of four beeps
      for _ in 0..<3 {
        for _ in 0..<4 { s += tone(880, 0.1); s += quiet(0.07) }
        s += quiet(0.4)
      }
    }
    var d = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
    d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + s.count * 2))
    d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
    u32(22050); u32(22050 * 2); u16(2); u16(16)
    d.append("data".data(using: .ascii)!); u32(UInt32(s.count * 2))
    s.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
    return d
  }

  private func setKeepAwake(_ on: Bool) {
    if on == keepingAwake { return }
    if on {
      keepingAwake = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "Hushdock is showing the clock" as CFString,
        &keepAwakeId) == kIOReturnSuccess
    } else {
      IOPMAssertionRelease(keepAwakeId)
      keepingAwake = false
    }
  }
}
