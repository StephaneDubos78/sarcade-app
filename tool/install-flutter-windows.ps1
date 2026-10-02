# SARCADE development client prerequisites - Windows
# Run from an elevated PowerShell.
$ErrorActionPreference="Stop"

function Has($n){ [bool](Get-Command $n -ErrorAction SilentlyContinue) }
if(-not (Has "winget")){ throw "winget is required." }

Write-Host "[SARCADE] Installing Git..." -ForegroundColor Cyan
winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements

Write-Host "[SARCADE] Installing NuGet CLI..." -ForegroundColor Cyan
winget install --id Microsoft.NuGet -e --source winget --accept-source-agreements --accept-package-agreements

Write-Host "[SARCADE] Installing Visual Studio Build Tools / C++ workload..." -ForegroundColor Cyan
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget --accept-source-agreements --accept-package-agreements --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

$flutterRoot="C:\dev\flutter"
if(-not (Test-Path "$flutterRoot\bin\flutter.bat")){
  Write-Host "[SARCADE] Flutter SDK is not installed automatically by this script to avoid pinning an obsolete archive." -ForegroundColor Yellow
  Write-Host "Install the current Flutter stable SDK in C:\dev\flutter, then add C:\dev\flutter\bin to PATH."
} else {
  Write-Host "Flutter already present: $flutterRoot" -ForegroundColor Green
}

Write-Host ""
Write-Host "After Flutter is available, run:"
Write-Host "flutter config --enable-windows-desktop"
Write-Host "flutter doctor -v"
