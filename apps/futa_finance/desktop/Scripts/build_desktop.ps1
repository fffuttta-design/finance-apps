# build_desktop.ps1 - Build the FutaFinance Electron desktop app (dir/unpacked + robocopy update).
#   FutaMemo-style update model: distribute an unpacked folder, robocopy to %LOCALAPPDATA%,
#   relaunch via explorer.exe. Stable, no NSIS.
#   1. version/build from pubspec; write build-info.json (packaged into the app)
#   2. flutter build web (offline, base-href /) -> web-dist
#   3. oauth.json from win_oauth.key
#   4. electron-builder --win dir -> dist/win-unpacked
#   5. write dist/win-unpacked/version.json
#   6. -Publish: robocopy win-unpacked -> Drive FutaFinance-Desktop\app
#
# ASCII only (Windows PowerShell 5.1 mis-parses Japanese in no-BOM .ps1).
param(
  [switch]$NoBuildWeb,
  [switch]$Publish
)
$ErrorActionPreference = "Stop"

$ScriptDir  = $PSScriptRoot
$ProjectDir = Split-Path $ScriptDir -Parent          # desktop/
$AppDir     = Split-Path $ProjectDir -Parent          # apps/futa_finance/

Write-Host "== FutaFinance desktop build (dir) ==" -ForegroundColor Cyan

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

# ---- 1. flutter build web (offline) ----
if (-not $NoBuildWeb) {
  Write-Host "[1/5] flutter build web (offline)..." -ForegroundColor Yellow
  Push-Location $AppDir
  try {
    & flutter build web --release --no-web-resources-cdn --base-href "/"
    if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }
  } finally { Pop-Location }
} else {
  Write-Host "[1/5] skip flutter build web (-NoBuildWeb)" -ForegroundColor DarkGray
}

# ---- 2. copy build/web -> desktop/web-dist (strip service worker) ----
Write-Host "[2/5] copy web build -> web-dist" -ForegroundColor Yellow
$webSrc = Join-Path $AppDir "build\web"
$webDst = Join-Path $ProjectDir "web-dist"
if (-not (Test-Path $webSrc)) { throw "web build not found: $webSrc" }
if (Test-Path $webDst) { Remove-Item $webDst -Recurse -Force }
Copy-Item $webSrc $webDst -Recurse -Force
$sw = Join-Path $webDst "flutter_service_worker.js"
if (Test-Path $sw) { Remove-Item $sw -Force }

# ---- 3. oauth.json from win_oauth.key ----
Write-Host "[3/5] write oauth.json" -ForegroundColor Yellow
$keyPath = Join-Path $AppDir "win_oauth.key"
if (Test-Path $keyPath) {
  $secret = (Get-Content $keyPath -Raw).Trim()
  [System.IO.File]::WriteAllText((Join-Path $ProjectDir "oauth.json"), (@{ clientSecret = $secret } | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
} else {
  Write-Host "  WARN: win_oauth.key not found; login will fail." -ForegroundColor Red
}

# ---- 4. electron-builder --win dir ----
Push-Location $ProjectDir
try {
  if (-not (Test-Path (Join-Path $ProjectDir "node_modules"))) {
    Write-Host "[4/5] npm install..." -ForegroundColor Yellow
    & npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
  } else {
    Write-Host "[4/5] npm install skipped (node_modules present)" -ForegroundColor DarkGray
  }
  Write-Host "      electron-builder (dir)..." -ForegroundColor Yellow
  & npm run build
  if ($LASTEXITCODE -ne 0) { throw "electron-builder failed" }
} finally { Pop-Location }

# ---- 5. write version.json into win-unpacked ----
$unpacked = Join-Path $ProjectDir "dist\win-unpacked"
if (-not (Test-Path (Join-Path $unpacked "FutaFinance.exe"))) { throw "win-unpacked not found" }
[System.IO.File]::WriteAllText((Join-Path $unpacked "version.json"), $buildInfoJson, [System.Text.UTF8Encoding]::new($false))
Write-Host "[5/5] built unpacked app (v$Version build $Build)" -ForegroundColor Green
Write-Host "unpacked: $unpacked"

# ---- optional: publish to Drive (robocopy win-unpacked -> Drive app\) ----
if ($Publish) {
  $jp1 = -join ([char]0x30DE,[char]0x30A4,[char]0x30C9,[char]0x30E9,[char]0x30A4,[char]0x30D6) # My Drive (kana)
  $jp2 = -join ([char]0x30C4,[char]0x30FC,[char]0x30EB,[char]0x958B,[char]0x767A)               # tool dev
  $suffix = "$jp1\$jp2\FutaFinance-Desktop"
  $cands = @("H:\$suffix", "G:\$suffix")
  $driveDir = $null
  foreach ($c in $cands) { if (Test-Path (Split-Path $c -Parent)) { $driveDir = $c; break } }
  if ($driveDir) {
    $appDst = Join-Path $driveDir "app"
    New-Item -ItemType Directory -Force -Path $appDst | Out-Null
    robocopy "$unpacked" "$appDst" /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy to Drive failed (code $LASTEXITCODE)" }
    Write-Host "published to Drive: $appDst (v$Version build $Build)" -ForegroundColor Green
  } else {
    Write-Host "Drive folder not found; skipped publish." -ForegroundColor DarkGray
  }
}

Write-Host "== done ==" -ForegroundColor Cyan
Write-Host "First-time install: run  <Drive>\FutaFinance-Desktop\app\FutaFinance.exe  once."
