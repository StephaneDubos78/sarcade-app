param(
  [string]$ServerUrl = "http://localhost:8000",
  [Parameter(Mandatory=$true)][string]$EventId,
  [string]$DeviceId = "pco-windows"
)

$ErrorActionPreference="Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "[SARCADE] Windows demo launcher" -ForegroundColor Cyan
if(-not (Get-Command flutter -ErrorAction SilentlyContinue)){
  Write-Host "Flutter is not installed or not in PATH." -ForegroundColor Red
  Write-Host "Run tool\install-flutter-windows.ps1 as Administrator, restart PowerShell, then retry."
  exit 1
}

Write-Host "Flutter:"
flutter --version

Write-Host "Checking SARCADE Server: $ServerUrl/health"
try {
  $health=Invoke-RestMethod -Uri "$ServerUrl/health" -TimeoutSec 5
  if($health.status -ne "ok"){ throw "Unexpected health response" }
} catch {
  Write-Host "SARCADE Server is not reachable at $ServerUrl" -ForegroundColor Red
  exit 1
}

Write-Host "Preparing Windows desktop runner..."
if(-not (Test-Path ".\windows")){
  flutter create --platforms=windows .
}
flutter pub get

Write-Host "Launching event $EventId..."
flutter run -d windows --dart-define=SARCADE_SERVER_URL=$ServerUrl --dart-define=SARCADE_EVENT_ID=$EventId --dart-define=SARCADE_DEVICE_ID=$DeviceId
