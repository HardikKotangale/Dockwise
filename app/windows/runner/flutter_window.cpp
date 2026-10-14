#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// The "enabled" flag the Dart side sends with setKeepAwake and setFullscreen.
bool EnabledArgument(const flutter::MethodCall<flutter::EncodableValue>& call) {
  if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
    auto it = args->find(flutter::EncodableValue("enabled"));
    if (it != args->end()) {
      if (const auto* value = std::get_if<bool>(&it->second)) {
        return *value;
      }
    }
  }
  return false;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  system_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "standby_pro/system",
          &flutter::StandardMethodCodec::GetInstance());
  system_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleSystemCall(call, std::move(result));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SetThreadExecutionState(ES_CONTINUOUS);  // let the screen sleep again
  system_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// The native side of the Dart StandbySystemService on a PC. Only keep-awake
// and full screen; the Dart side treats every other call as missing.
void FlutterWindow::HandleSystemCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "setKeepAwake") {
    // keeps the display (and the PC) awake while the bedside display wants it
    EXECUTION_STATE flags = ES_CONTINUOUS;
    if (EnabledArgument(call)) {
      flags |= ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED;
    }
    result->Success(
        flutter::EncodableValue(SetThreadExecutionState(flags) != 0));
  } else if (method == "setFullscreen") {
    result->Success(flutter::EncodableValue(SetFullscreen(EnabledArgument(call))));
  } else {
    result->NotImplemented();
  }
}

// Borderless over the whole monitor the window is on (taskbar included), and
// back to exactly the window it was: size, place and maximized state.
bool FlutterWindow::SetFullscreen(bool enabled) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return false;
  }
  if (enabled == fullscreen_) {
    return true;
  }
  if (enabled) {
    windowed_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
    windowed_placement_.length = sizeof(WINDOWPLACEMENT);
    MONITORINFO monitor{sizeof(MONITORINFO)};
    if (!GetWindowPlacement(hwnd, &windowed_placement_) ||
        !GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                        &monitor)) {
      return false;
    }
    SetWindowLongPtr(hwnd, GWL_STYLE, windowed_style_ & ~WS_OVERLAPPEDWINDOW);
    const RECT& area = monitor.rcMonitor;
    SetWindowPos(hwnd, HWND_TOP, area.left, area.top, area.right - area.left,
                 area.bottom - area.top,
                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    SetWindowLongPtr(hwnd, GWL_STYLE, windowed_style_);
    SetWindowPlacement(hwnd, &windowed_placement_);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED);
  }
  fullscreen_ = enabled;
  return true;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
