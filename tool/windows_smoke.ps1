# Start test of the Windows client (card « Client Windows : écran gris au
# démarrage », 31 Oct 2026). Used by the CI (x64 runner, ARM64 runner) and
# usable by hand on a PC:
#   powershell -ExecutionPolicy Bypass -File tool\windows_smoke.ps1 -Exe "C:\Program Files\SARCADE\sarcade_app.exe" -Out smoke
# Writes to -Out: report.json (from the app), capture.png (screen after a few
# seconds), demarrage.log (startup log). Exit code 0 when the first screen
# showed without error.
param([Parameter(Mandatory=$true)][string]$Exe, [string]$Out = "smoke", [int]$CaptureAfter = 6, [int]$Timeout = 90)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$report = Join-Path $Out "report.json"
Remove-Item $report -ErrorAction SilentlyContinue
$env:SARCADE_SMOKE_FILE = $report
Write-Host "Architecture: $env:PROCESSOR_ARCHITECTURE ; exe: $Exe"
# Fresh log: the unit tests of the same machine write to it too.
$log = Join-Path $env:LOCALAPPDATA "SARCADE\logs\demarrage.log"
Remove-Item $log -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds $CaptureAfter
try {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $Out "capture.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  Write-Host "Capture saved"
} catch { Write-Host "No capture: $_" }
if (-not $p.WaitForExit($Timeout * 1000)) {
  Write-Host "::error title=Windows start::the app did not end within $Timeout s (first screen never drawn?)"
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
if (Test-Path $log) {
  Copy-Item $log (Join-Path $Out "demarrage.log"); Write-Host "--- demarrage.log"; Get-Content $log -Tail 80
  # Readable from the API without downloading the artifact (one annotation).
  $tail = (Get-Content $log -Tail 12) -join "%0A"
  Write-Host "::notice title=Windows start log ($env:PROCESSOR_ARCHITECTURE)::$tail"
}
else { Write-Host "::warning title=Windows start::no startup log (Dart code never ran?)" }
if (-not (Test-Path $report)) { Write-Host "::error title=Windows start::no report: the first screen was not drawn"; exit 1 }
$r = Get-Content $report -Raw | ConvertFrom-Json
Write-Host "--- report.json"; Get-Content $report
if (-not $r.first_frame) { Write-Host "::error title=Windows start::first screen not drawn"; exit 1 }
if ($r.errors.Count -gt 0) {
  foreach ($e in $r.errors) { Write-Host "::error title=Windows start::$($e -replace "`r?`n", ' ')" }
  exit 1
}
Write-Host "::notice title=Windows start ($env:PROCESSOR_ARCHITECTURE)::first screen drawn without error"
Write-Host "First screen drawn without error"
exit 0
