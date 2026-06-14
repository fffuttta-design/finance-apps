# build_desktop.ps1 - Build FutaFinance Electron desktop app (NSIS + electron-updater).
#   Update model: electron-builder publishes NSIS setup + latest.yml to GitHub Release.
#   electron-updater in the app checks latest.yml and auto-downloads/installs silently.
#   1. version/build from pubspec; write build-info.json (packaged into the app)
#   2. flutter build web (offline, base-href /) -> web-dist
#   3. oauth.json from win_oauth.key
#   4. npm install (ensure electron-updater is present)
#   5. electron-builder --win nsis --publish always (GH_TOKEN required)
#      -> dist/FutaFinance-setup.exe + dist/latest.yml -> GitHub Release
#   6. safety re-upload of exe + latest.yml via gh CLI (parallel-publish bug guard)
#
# ASCII only (Windows PowerShell 5.1 mis-parses Japanese in no-BOM .ps1).
param(
  [switch]$NoBuildWeb,
  [switch]$Publish
)
$ErrorActionPreference = "Stop"

$ScriptDir  = $PSScriptRoot
$ProjectDir = Split-Path $ScriptDir -Parent
$AppDir     = Split-Path $ProjectDir -Parent
$RepoRoot   = Split-Path (Split-Path $AppDir -Parent) -Parent

Write-Host "== FutaFinance desktop build (NSIS + electron-updater) ==" -ForegroundColor Cyan

# ---- 0. version + buildNumber from pubspec ----
$pubspec = Get-Content (Join-Path $AppDir "pubspec.yaml") -Raw
$Version = "0.0.0"; $Build = 0
if ($pubspec -match "(?m)^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)") {
  $Version = $Matches[1]; $Build = [int]$Matches[2]
}
Write-Host "version $Version  build $Build"

$pkgPath = Join-Path $ProjectDir "package.json"
$pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pkg.version = $Version
[System.IO.File]::WriteAllText($pkgPath, ($pkg | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))

$builtAt = (Get-Date).ToUniversalTime().ToString("o")
$buildInfoJson = (@{ version = $Version; buildNumber = $Build; builtAt = $builtAt } | ConvertTo-Json)
[System.IO.File]::WriteAllText((Join-Path $ProjectDir "build-info.json"), $buildInfoJson, [System.Text.UTF8Encoding]::new($false))

# ---- 1. flutter build web ----
if (-not $NoBuildWeb) {
  Write-Host "[1/4] flutter build web (offline)..." -ForegroundColor Yellow
  Push-Location $AppDir
  try {
    & flutter build web --release --no-web-resources-cdn --base-href "/"
    if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }
  } finally { Pop-Location }
} else {
  Write-Host "[1/4] skip flutter build web (-NoBuildWeb)" -ForegroundColor DarkGray
}

# ---- 2. copy build/web -> desktop/web-dist ----
Write-Host "[2/4] copy web build -> web-dist" -ForegroundColor Yellow
$webSrc = Join-Path $AppDir "build\web"
$webDst = Join-Path $ProjectDir "web-dist"
if (-not (Test-Path $webSrc)) { throw "web build not found: $webSrc" }
if (Test-Path $webDst) { Remove-Item $webDst -Recurse -Force }
Copy-Item $webSrc $webDst -Recurse -Force
$sw = Join-Path $webDst "flutter_service_worker.js"
if (Test-Path $sw) { Remove-Item $sw -Force }

# ---- 3. oauth.json from win_oauth.key ----
Write-Host "[3/4] write oauth.json" -ForegroundColor Yellow
$keyPath = Join-Path $AppDir "win_oauth.key"
if (Test-Path $keyPath) {
  $secret = (Get-Content $keyPath -Raw).Trim()
  [System.IO.File]::WriteAllText((Join-Path $ProjectDir "oauth.json"), (@{ clientSecret = $secret } | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
} else {
  Write-Host "  WARN: win_oauth.key not found; login will fail." -ForegroundColor Red
}

# ---- 4. npm install + electron-builder ----
Push-Location $ProjectDir
try {
  Write-Host "[4/4] npm install..." -ForegroundColor Yellow
  & npm install
  if ($LASTEXITCODE -ne 0) { throw "npm install failed" }

  if ($Publish) {
    if (-not $env:GH_TOKEN) {
      $ghToken = (& gh auth token 2>$null)
      if ($ghToken) { $env:GH_TOKEN = $ghToken }
      else { throw "GH_TOKEN not set. Run 'gh auth login' or set GH_TOKEN." }
    }
    Write-Host "      electron-builder --win nsis --publish always..." -ForegroundColor Yellow
    & npm run dist
    if ($LASTEXITCODE -ne 0) { throw "electron-builder failed" }
  } else {
    Write-Host "      electron-builder --win nsis (local only)..." -ForegroundColor Yellow
    & npm run build
    if ($LASTEXITCODE -ne 0) { throw "electron-builder failed" }
  }
} finally { Pop-Location }

$setupExe = Join-Path $ProjectDir "dist\FutaFinance-setup.exe"
$latestYml = Join-Path $ProjectDir "dist\latest.yml"
if (-not (Test-Path $setupExe)) { throw "FutaFinance-setup.exe not found in dist/" }
Write-Host "built: $setupExe" -ForegroundColor Green

# ---- optional: safety re-upload (parallel-publish bug guard) ----
if ($Publish) {
  $Tag = "v$Version"
  Write-Host "[Safety] re-upload setup.exe + latest.yml to $Tag..." -ForegroundColor Yellow
  if (Test-Path $latestYml) {
    gh release upload $Tag $setupExe $latestYml --repo fffuttta-design/finance-apps --clobber
  } else {
    gh release upload $Tag $setupExe --repo fffuttta-design/finance-apps --clobber
  }
  gh release edit $Tag --repo fffuttta-design/finance-apps --draft=false | Out-Null
  Write-Host "published to GitHub Release: $Tag" -ForegroundColor Green
}

Write-Host "== done ==" -ForegroundColor Cyan
Write-Host "First-time install: run FutaFinance-setup.exe from GitHub Releases."
Write-Host "After that, electron-updater handles all future updates automatically."
