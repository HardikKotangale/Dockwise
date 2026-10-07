#!/usr/bin/env bash
# Dockwise setup for macOS. Safe to run again: it only installs what is missing.
#   ./scripts/setup_mac.sh            install what is missing, then prepare the project
#   ./scripts/setup_mac.sh --check    only report what is installed
set -uo pipefail

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MISSING=0

ok()   { printf "  ok       %s\n" "$1"; }
miss() { printf "  MISSING  %s\n" "$1"; MISSING=1; }
have() { command -v "$1" >/dev/null 2>&1; }

# install_brew <label> <formula|cask> <name> <present-test-command>
install_brew() {
  local label="$1" kind="$2" name="$3" test="$4"
  if eval "$test" >/dev/null 2>&1; then ok "$label"; return; fi
  miss "$label"
  if [ "$CHECK_ONLY" = 0 ]; then
    echo "           installing $label ..."
    if [ "$kind" = cask ]; then brew install --cask "$name"; else brew install "$name"; fi
  fi
}

echo "Dockwise setup (macOS)"
echo

if ! have brew; then
  miss "Homebrew"
  echo "  Install Homebrew first, then run this script again:"
  echo '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  exit 1
fi
ok "Homebrew"

# git comes with the Xcode command line tools
if xcode-select -p >/dev/null 2>&1; then ok "Command line tools (git)"; else
  miss "Command line tools (git)"
  [ "$CHECK_ONLY" = 0 ] && xcode-select --install
fi

install_brew "Flutter"         cask    flutter       "have flutter"
install_brew "JDK 17"          formula openjdk@17    "[ -d \"\$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk\" ]"
install_brew "Android Studio"  cask    android-studio "[ -d '/Applications/Android Studio.app' ]"
install_brew "CocoaPods"       formula cocoapods     "have pod"

# Xcode is only needed for iPhone builds, and only the App Store can install it
if xcodebuild -version >/dev/null 2>&1; then ok "Xcode ($(xcodebuild -version | head -1))"; else
  miss "Xcode (only needed for iPhone). Install it from the App Store, open it once, then run: sudo xcodebuild -runFirstLaunch"
fi

if [ "$CHECK_ONLY" = 1 ]; then
  echo
  [ "$MISSING" = 0 ] && echo "Everything is installed." || echo "Run ./scripts/setup_mac.sh (without --check) to install what is missing."
  exit 0
fi

echo
echo "Configuring Flutter ..."
JDK="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
[ -d "$JDK" ] && flutter config --jdk-dir "$JDK" >/dev/null && ok "Flutter uses JDK 17"
if [ -d "$HOME/Library/Android/sdk" ]; then
  yes | flutter doctor --android-licenses >/dev/null 2>&1 && ok "Android licenses accepted"
else
  echo "  note     Open Android Studio once and finish its setup wizard (it downloads the Android SDK),"
  echo "           then run this script again to accept the licenses."
fi

echo
echo "Preparing the project ..."
cd "$ROOT/app" && flutter pub get
CFG="$ROOT/app/lib/src/services/spotify_config.dart"
if [ ! -f "$CFG" ]; then
  cp "$ROOT/app/lib/src/services/spotify_config.example.dart" "$CFG"
  echo "  created  app/lib/src/services/spotify_config.dart (add your Spotify Client ID there, optional)"
fi

echo
flutter doctor
echo
echo "Done. Connect a phone with USB debugging on and run:  cd app && flutter run"
