# Dockwise setup for Windows. Safe to run again: it only installs what is missing.
#   .\scripts\setup_windows.ps1           install what is missing, then prepare the project
#   .\scripts\setup_windows.ps1 -Check    only report what is installed
# Run it in a normal PowerShell window (not "Run as administrator"); Windows may
# ask for permission while winget installs a program.
# iPhone builds are not possible on Windows. Android builds and tests are.
param([switch]$Check)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$script:Missing = $false

function Ok($t)   { Write-Host ("  ok       " + $t) }
function Miss($t) { Write-Host ("  MISSING  " + $t); $script:Missing = $true }
function Have($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}

function Install-Winget($label, $id, $test) {
  if (& $test) { Ok $label; return }
  Miss $label
  if (-not $Check) {
    Write-Host "           installing $label ..."
    winget install --id $id -e --accept-package-agreements --accept-source-agreements
    Refresh-Path
  }
}

Write-Host "Dockwise setup (Windows)"
Write-Host ""

if (-not (Have winget)) {
  Miss "winget (comes with Windows 10/11; update 'App Installer' from the Microsoft Store)"
  exit 1
}
Ok "winget"

Install-Winget "Git"            "Git.Git"                       { Have git }
Install-Winget "JDK 17"         "EclipseAdoptium.Temurin.17.JDK" { [bool](Get-ChildItem "$env:ProgramFiles\Eclipse Adoptium" -Filter 'jdk-17*' -ErrorAction SilentlyContinue) }
Install-Winget "Android Studio" "Google.AndroidStudio"          { Test-Path "$env:ProgramFiles\Android\Android Studio" }

# Flutter has no installer: it is a git checkout that we put on PATH
$FlutterDir = Join-Path $env:USERPROFILE 'flutter'
if (Have flutter) { Ok "Flutter" }
elseif (Test-Path "$FlutterDir\bin\flutter.bat") { Ok "Flutter (in $FlutterDir, not on PATH yet)"; $env:Path += ";$FlutterDir\bin" }
else {
  Miss "Flutter"
  if (-not $Check) {
    if (-not (Have git)) { Write-Host "  Git is needed first. Close this window, open a new one and run the script again."; exit 1 }
    git clone https://github.com/flutter/flutter.git -b stable $FlutterDir
    $env:Path += ";$FlutterDir\bin"
  }
}
if ((-not $Check) -and (Test-Path "$FlutterDir\bin")) {
  $user = [Environment]::GetEnvironmentVariable('Path','User')
  if ($user -notlike "*$FlutterDir\bin*") {
    [Environment]::SetEnvironmentVariable('Path', "$user;$FlutterDir\bin", 'User')
    Write-Host "  added    $FlutterDir\bin to your PATH (new windows will see it)"
  }
}

if ($Check) {
  Write-Host ""
  if ($script:Missing) { Write-Host "Run .\scripts\setup_windows.ps1 (without -Check) to install what is missing." }
  else { Write-Host "Everything is installed." }
  exit 0
}

Write-Host ""
Write-Host "Configuring Flutter ..."
$jdk = Get-ChildItem "$env:ProgramFiles\Eclipse Adoptium" -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($jdk) { flutter config --jdk-dir $jdk.FullName | Out-Null; Ok "Flutter uses JDK 17" }
if (Test-Path "$env:LOCALAPPDATA\Android\Sdk") {
  (1..30 | ForEach-Object { 'y' }) | flutter doctor --android-licenses 2>&1 | Out-Null
  Ok "Android licenses accepted"
} else {
  Write-Host "  note     Open Android Studio once and finish its setup wizard (it downloads the Android SDK),"
  Write-Host "           then run this script again to accept the licenses."
}

Write-Host ""
Write-Host "Preparing the project ..."
Push-Location "$Root\app"
flutter pub get
Pop-Location
$cfg = "$Root\app\lib\src\services\spotify_config.dart"
if (-not (Test-Path $cfg)) {
  Copy-Item "$Root\app\lib\src\services\spotify_config.example.dart" $cfg
  Write-Host "  created  app\lib\src\services\spotify_config.dart (add your Spotify Client ID there, optional)"
}

Write-Host ""
flutter doctor
Write-Host ""
Write-Host "Done. Connect a phone with USB debugging on and run:  cd app; flutter run"
