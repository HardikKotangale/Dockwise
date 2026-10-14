#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void HandleSystemCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Borderless over the whole monitor, or back to the window it was.
  bool SetFullscreen(bool enabled);

  // Over the other windows again (after Spotify opens on top).
  bool BringToFront();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // "standby_pro/system": the native calls the Dart app makes (keep-awake,
  // full screen).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_channel_;

  // Full screen, and the window to go back to when it ends.
  bool fullscreen_ = false;
  LONG_PTR windowed_style_ = 0;
  WINDOWPLACEMENT windowed_placement_{};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
