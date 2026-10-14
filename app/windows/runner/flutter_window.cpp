#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shellapi.h>
#include <mmsystem.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

constexpr double kPi = 3.14159265358979323846;

// The timer's end sound, made here (the same three clips as on the phones):
// a 22.05 kHz mono WAV in memory.
std::vector<int16_t> Tone(double f, double secs, double decay = 0) {
  const double rate = 22050.0;
  const int n = static_cast<int>(secs * rate);
  std::vector<int16_t> out(n);
  for (int i = 0; i < n; i++) {
    double t = i / rate;
    double env = std::min({1.0, t / 0.004, (secs - t) / 0.01});
    if (decay > 0) env *= std::exp(-decay * t);
    double v = std::sin(2 * kPi * f * t) + 0.35 * std::sin(4 * kPi * f * t);
    out[i] = static_cast<int16_t>(std::clamp(v * env * 0.55, -1.0, 1.0) * 30000);
  }
  return out;
}

void Append(std::vector<int16_t>& s, const std::vector<int16_t>& more) {
  s.insert(s.end(), more.begin(), more.end());
}

std::vector<int16_t> Quiet(double secs) {
  return std::vector<int16_t>(static_cast<size_t>(secs * 22050.0), 0);
}

std::string TimerClip(const std::string& name) {
  std::vector<int16_t> s;
  if (name == "chime") {
    for (double f : {1318.5, 1568.0, 2093.0}) Append(s, Tone(f, 0.9, 4));
    Append(s, Quiet(0.3));
  } else if (name == "fanfare") {
    for (int r = 0; r < 2; r++) {
      const double notes[4][2] = {
          {523.25, 0.14}, {659.25, 0.14}, {783.99, 0.14}, {1046.5, 0.55}};
      for (const auto& n : notes) {
        Append(s, Tone(n[0], n[1]));
        Append(s, Quiet(0.04));
      }
      Append(s, Quiet(0.25));
    }
  } else {  // a beeping alarm clock: groups of four beeps
    for (int g = 0; g < 3; g++) {
      for (int b = 0; b < 4; b++) {
        Append(s, Tone(880, 0.1));
        Append(s, Quiet(0.07));
      }
      Append(s, Quiet(0.4));
    }
  }
  std::string d;
  auto u32 = [&d](uint32_t v) { d.append(reinterpret_cast<const char*>(&v), 4); };
  auto u16 = [&d](uint16_t v) { d.append(reinterpret_cast<const char*>(&v), 2); };
  const uint32_t bytes = static_cast<uint32_t>(s.size() * 2);
  d.append("RIFF"); u32(36 + bytes);
  d.append("WAVEfmt "); u32(16); u16(1); u16(1);
  u32(22050); u32(22050 * 2); u16(2); u16(16);
  d.append("data"); u32(bytes);
  d.append(reinterpret_cast<const char*>(s.data()), bytes);
  return d;
}

// Plays the clip without waiting. The buffer must outlive the playback, so
// it is kept until the next alert replaces it.
bool PlayTimerSound(const std::string& name) {
  static std::string clip;
  PlaySoundW(nullptr, nullptr, 0);  // stop a clip still playing
  clip = TimerClip(name);
  return PlaySoundW(reinterpret_cast<LPCWSTR>(clip.data()), nullptr,
                    SND_MEMORY | SND_ASYNC | SND_NODEFAULT) != FALSE;
}

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

// A text argument of the call, "" when it is missing.
std::string StringArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key) {
  if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
    auto it = args->find(flutter::EncodableValue(key));
    if (it != args->end()) {
      if (const auto* value = std::get_if<std::string>(&it->second)) {
        return *value;
      }
    }
  }
  return std::string();
}

std::wstring Utf16FromUtf8(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  int length = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                   static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      wide.data(), length);
  return wide;
}

// Opens [url] with whatever handles it: a web page in the browser, an app's
// own link (spotify:) in that app. An app link whose scheme nothing has
// registered fails here, instead of Windows asking which app to look for.
bool OpenUrl(const std::string& url) {
  const auto colon = url.find(':');
  if (colon == std::string::npos || colon == 0) {
    return false;
  }
  const std::wstring scheme = Utf16FromUtf8(url.substr(0, colon));
  if (scheme != L"http" && scheme != L"https") {
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CLASSES_ROOT, scheme.c_str(), 0, KEY_READ, &key) !=
        ERROR_SUCCESS) {
      return false;  // not installed
    }
    RegCloseKey(key);
  }
  const std::wstring target = Utf16FromUtf8(url);
  const auto done = reinterpret_cast<INT_PTR>(ShellExecuteW(
      nullptr, L"open", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
  return done > 32;
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

// The native side of the Dart StandbySystemService on a PC: keep-awake, full
// screen, opening links and apps, the PC's name and coming back to the front.
// The Dart side treats every other call as missing.
void FlutterWindow::HandleSystemCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "launchApp") {
    result->Success(flutter::EncodableValue(OpenUrl(StringArgument(call, "url"))));
  } else if (method == "deviceModel") {
    // the PC's name: the Spotify desktop app shows up under it by default
    wchar_t name[MAX_COMPUTERNAME_LENGTH + 1];
    DWORD size = MAX_COMPUTERNAME_LENGTH + 1;
    result->Success(flutter::EncodableValue(
        GetComputerNameW(name, &size) ? Utf8FromUtf16(name) : std::string()));
  } else if (method == "timerAlert") {
    // the sound only: a PC has nothing to vibrate
    const std::string sound = StringArgument(call, "sound");
    result->Success(flutter::EncodableValue(
        sound == "none" ? true : PlayTimerSound(sound.empty() ? "alarm" : sound)));
  } else if (method == "bringToFront") {
    result->Success(flutter::EncodableValue(BringToFront()));
  } else if (method == "setKeepAwake") {
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

// Over the other windows again (Spotify's comes up on top when it opens).
// Windows lets only the app in front hand the front over, so for a moment
// this window shares input with the one in front, which may do it.
bool FlutterWindow::BringToFront() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return false;
  }
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  const DWORD front =
      GetWindowThreadProcessId(GetForegroundWindow(), nullptr);
  const DWORD mine = GetCurrentThreadId();
  const bool attach = front != 0 && front != mine;
  if (attach) {
    AttachThreadInput(front, mine, TRUE);
  }
  BringWindowToTop(hwnd);
  const bool done = SetForegroundWindow(hwnd) != 0;
  if (attach) {
    AttachThreadInput(front, mine, FALSE);
  }
  return done;
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
