$ErrorActionPreference="Stop"
Write-Host "[SARCADE] Installing NuGet CLI..." -ForegroundColor Cyan
winget install --id Microsoft.NuGet -e --source winget --accept-source-agreements --accept-package-agreements
$env:Path=[Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User")
Write-Host "NuGet sources:" -ForegroundColor Cyan
nuget sources
$hasNugetOrg=(nuget sources | Select-String "https://api.nuget.org/v3/index.json")
if(-not $hasNugetOrg){
  nuget sources Add -Name "nuget.org" -Source "https://api.nuget.org/v3/index.json"
}
nuget sources Enable -Name "nuget.org"
nuget sources
Write-Host "Run: flutter clean ; flutter pub get ; then retry SARCADE." -ForegroundColor Green
