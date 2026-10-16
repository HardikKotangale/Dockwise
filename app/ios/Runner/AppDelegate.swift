import Flutter
import UIKit
import AudioToolbox
import AVFoundation
import CoreHaptics
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ---- the timer's end: sound and buzz ----
  // The system's own sounds are short blips, so the sounds are made here: a
  // beeping alarm, a three-note chime, a little fanfare. The session is
  // "ambient", so the silent switch mutes them, as it should.
  private var timerPlayer: AVAudioPlayer?
  private var backgroundTask = UIBackgroundTaskIdentifier.invalid
  private var haptics: CHHapticEngine?

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

  private func playTimerSound(_ name: String) {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.ambient)
    try? session.setActive(true)
    timerPlayer = try? AVAudioPlayer(data: clip(name))
    timerPlayer?.volume = 1
    timerPlayer?.play()
  }

  // Three firm pulses with Core Haptics; the older system buzz if that fails.
  private func buzz() {
    if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
      do {
        if haptics == nil {
          haptics = try CHHapticEngine()
          haptics?.isAutoShutdownEnabled = true
          haptics?.resetHandler = { [weak self] in try? self?.haptics?.start() }
        }
        try haptics?.start()
        var events = [CHHapticEvent]()
        for i in 0..<3 {
          events.append(
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
              ],
              relativeTime: Double(i) * 0.5,
              duration: 0.35))
        }
        let pattern = try CHHapticPattern(events: events, parameters: [])
        try haptics?.makePlayer(with: pattern).start(atTime: 0)
        return
      } catch {}
    }
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Same channel the Android app uses. Only what iOS allows is answered here;
    // everything else (media keys of other apps, auto-start...) is "not implemented"
    // and the Dart side treats that as "not available".
    let channel = FlutterMethodChannel(
      name: "standby_pro/system",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    let calendar = CalendarBridge()
    FlutterMethodChannel(
      name: "standby_pro/calendar",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in calendar.handle(call, result) }
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "setKeepAwake":  // no auto-lock while the bedside display is up
        UIApplication.shared.isIdleTimerDisabled = (args?["enabled"] as? Bool) ?? false
        result(true)
      case "setBrightness":
        UIScreen.main.brightness = CGFloat((args?["value"] as? Double) ?? 0.7)
        result(true)
      case "screenSide":
        // iOS names landscapes by the home-button side; answer by where the TOP of
        // the phone is (what the motion sensor sees): landscapeRight = top to the left
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch scene?.interfaceOrientation {
        case .landscapeRight: result("landscapeLeft")
        case .landscapeLeft: result("landscapeRight")
        default: result("portrait")
        }
      case "launchApp":  // open another app by its URL scheme, e.g. spotify://
        let text = (args?["url"] as? String) ?? ""
        if let url = URL(string: text), !text.isEmpty {
          UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
        } else {
          result(false)
        }
      case "timerAlert":
        // The silent switch mutes the sound by itself, and an app cannot read
        // it, so the buzz (when on) is what you feel then.
        let sound = (args?["sound"] as? String) ?? "alarm"
        let vibrate = (args?["vibrate"] as? Bool) ?? true
        if sound != "none" { self.playTimerSound(sound) }
        if vibrate { self.buzz() }
        result(true)
      case "beginBackgroundWork":
        // iOS keeps the app running for a short while after it goes to the
        // background (about 30 s): enough to start Spotify playing and say so
        if self.backgroundTask == .invalid {
          self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "spotify") {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
          }
        }
        result(true)
      case "endBackgroundWork":
        if self.backgroundTask != .invalid {
          UIApplication.shared.endBackgroundTask(self.backgroundTask)
          self.backgroundTask = .invalid
        }
        result(true)
      case "returnPrompt":
        // iOS never lets an app bring itself to the front from the background.
        // The one way back that is one tap: a notification that opens Hushdock.
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
          guard granted else { return result(false) }
          let content = UNMutableNotificationContent()
          content.title = "Playing on this iPhone"
          content.body = "Tap to go back to Hushdock."
          let request = UNNotificationRequest(
            identifier: "hushdock.return", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
          center.add(request) { error in result(error == nil) }
        }
      case "deviceModel":
        result(UIDevice.current.model)  // e.g. "iPhone"; used to prefer this phone in Spotify
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// ---- the Calendar card's Meetings tab -------------------------------------
// Read-only. Only the fields the tab shows leave this file (title, times,
// all-day, calendar name), only for the next few days, and the title is left
// out when the tab is set to hide titles. Nothing is written or stored.
import EventKit

final class CalendarBridge {
  private let store = EKEventStore()

  // the calendar's own colour as 0xAARRGGBB (0 when it cannot be read)
  private static func argb(_ c: CGColor) -> Int {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let s = c.converted(to: space, intent: .defaultIntent, options: nil),
      let p = s.components, p.count >= 3
    else { return 0 }
    func byte(_ v: CGFloat) -> Int { Int(max(0, min(1, v)) * 255) }
    return 0xFF00_0000 | (byte(p[0]) << 16) | (byte(p[1]) << 8) | byte(p[2])
  }

  private static func access() -> String {
    let s = EKEventStore.authorizationStatus(for: .event)
    if #available(macOS 14.0, iOS 17.0, *) {
      if s == .fullAccess { return "granted" }
      if s == .writeOnly { return "denied" }
    }
    switch s {
    case .notDetermined: return "unknown"
    case .authorized: return "granted"
    default: return "denied"
    }
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "status":
      result(CalendarBridge.access())
    case "request":
      let done: (Bool, Error?) -> Void = { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
      if #available(macOS 14.0, iOS 17.0, *) {
        store.requestFullAccessToEvents(completion: done)
      } else {
        store.requestAccess(to: .event, completion: done)
      }
    case "events":
      guard CalendarBridge.access() == "granted" else { return result([]) }
      let days = min(max((args?["days"] as? Int) ?? 3, 1), 14)
      let titles = (args?["titles"] as? Bool) ?? true
      let start = Calendar.current.startOfDay(for: Date())
      guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else {
        return result([])
      }
      let found = store.events(
        matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
      let list = found
        .filter { $0.status != .canceled }
        .sorted { $0.startDate < $1.startDate }
        .prefix(60)
        .map { e -> [String: Any] in
          [
            "title": titles ? (e.title ?? "") : "",
            "start": Int(e.startDate.timeIntervalSince1970 * 1000),
            "end": Int(e.endDate.timeIntervalSince1970 * 1000),
            "allDay": e.isAllDay,
            "calendar": e.calendar.title,
            "color": CalendarBridge.argb(e.calendar.cgColor),
          ]
        }
      result(Array(list))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
