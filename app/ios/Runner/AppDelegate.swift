import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Same channel the Android app uses. Only what iOS allows is answered here;
    // everything else (media keys of other apps, auto-start...) is "not implemented"
    // and the Dart side treats that as "not available".
    let channel = FlutterMethodChannel(
      name: "standby_pro/system",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "setKeepAwake":  // no auto-lock while the bedside display is up
        UIApplication.shared.isIdleTimerDisabled = (args?["enabled"] as? Bool) ?? false
        result(true)
      case "setBrightness":
        UIScreen.main.brightness = CGFloat((args?["value"] as? Double) ?? 0.7)
        result(true)
      case "deviceModel":
        result(UIDevice.current.model)  // e.g. "iPhone"; used to prefer this phone in Spotify
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
