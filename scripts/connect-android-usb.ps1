$ErrorActionPreference = "Stop"

if ($null -eq (Get-Command adb -ErrorAction SilentlyContinue)) {
  throw "ADB is not installed or not on PATH. Enable Android SDK Platform-Tools first."
}

$devices = (& adb devices) -join "`n"
if (-not ($devices -match "device$")) {
  Write-Host "No authorized Android device detected." -ForegroundColor Yellow
  Write-Host "Connect the phone by USB, enable USB debugging, accept the RSA prompt, then run this script again."
  exit 1
}

& adb reverse tcp:8787 tcp:8787
if ($LASTEXITCODE -ne 0) {
  throw "adb reverse failed."
}

Write-Host "USB reverse tunnel ready: Android 127.0.0.1:8787 -> PC 127.0.0.1:8787" -ForegroundColor Green
