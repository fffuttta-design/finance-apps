# build_desktop.ps1 - Build the FutaFinance Electron desktop app.
#   1. flutter build web (offline, base-href /)
#   2. copy build/web -> desktop/web-dist
#   3. generate desktop/oauth.json from win_oauth.key
#   4. npm install (first time) + electron-builder portable
#   5. copy the portable .exe to a local install dir under C:\dev for testing
#
# ASCII only (Windows PowerShell 5.1 mis-parses Japanese in no-BOM .ps1).
param(
  [string]$Version = "",
  [switch]$NoBuildWeb,   # skip flutter web build (reuse existing web-dist)
  [switch]$Publish       # also copy to Drive release folder + version.txt
)
$ErrorActionPreference = "Stop"

$ScriptDir  = $PSScriptRoot
$ProjectDir = Split-Path $ScriptDir -Parent          # desktop/
$AppDir     = Split-Path $ProjectDir -Parent          # apps/futa_finance/
$RepoRoot   = Split-Path (Split-Path $AppDir -Parent) -Parent  # finance-apps/

Write-Host "== FutaFinance desktop build ==" -ForegroundColor Cyan
Write-Host "project: $ProjectDir"

# ---- 0. optional version bump in package.json ----
$pkgPath = Join-Path $ProjectDir "package.json"
if ($Version -ne "") {
  $pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $pkg.version = $Version
  $json = $pkg | ConvertTo-Json -Depth 30
  [System.IO.File]::WriteAllText($pkgPath, $json, [System.Text.UTF8Encoding]::new($false))
  Write-Host "version -> $Version"
}

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

# ---- 2. copy build/web -> desktop/web-dist ----
Write-Host "[2/5] copy web build -> web-dist" -ForegroundColor Yellow
$webSrc = Join-Path $AppDir "build\web"
$webDst = Join-Path $ProjectDir "web-dist"
if (-not (Test-Path $webSrc)) { throw "web build not found: $webSrc" }
if (Test-Path $webDst) { Remove-Item $webDst -Recurse -Force }
Copy-Item $webSrc $webDst -Recurse -Force

# ---- 3. oauth.json from win_oauth.key ----
Write-Host "[3/5] write oauth.json" -ForegroundColor Yellow
$keyPath = Join-Path $AppDir "win_oauth.key"
if (Test-Path $keyPath) {
  $secret = (Get-Content $keyPath -Raw).Trim()
  $oauthObj = @{ clientSecret = $secret }
  $oauthJson = $oauthObj | ConvertTo-Json
  [System.IO.File]::WriteAllText((Join-Path $ProjectDir "oauth.json"), $oauthJson, [System.Text.UTF8Encoding]::new($false))
} else {
  Write-Host "  WARN: win_oauth.key not found; login will fail until provided." -ForegroundColor Red
}

# ---- 4. npm install + electron-builder ----
Push-Location $ProjectDir
try {
  if (-not (Test-Path (Join-Path $ProjectDir "node_modules"))) {
    Write-Host "[4/5] npm install..." -ForegroundColor Yellow
    & npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
  } else {
    Write-Host "[4/5] npm install skipped (node_modules present)" -ForegroundColor DarkGray
  }
  Write-Host "      electron-builder (portable)..." -ForegroundColor Yellow
  & npm run build
  if ($LASTEXITCODE -ne 0) { throw "electron-builder failed" }
} finally { Pop-Location }

# ---- 5. copy exe to local install dir (visible under C:\dev) ----
$exe = Get-ChildItem (Join-Path $ProjectDir "dist") -Filter "FutaFinance-*.exe" -File |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $exe) { throw "portable exe not found under dist/" }
Write-Host ("[5/5] built: {0} ({1:N1} MB)" -f $exe.Name, ($exe.Length/1MB)) -ForegroundColor Green

$installDir = Join-Path $RepoRoot "windows-app-electron"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
$installExe = Join-Path $installDir "FutaFinance.exe"
Copy-Item $exe.FullName $installExe -Force
Write-Host "installed (for testing): $installExe" -ForegroundColor Green

# ---- optional: publish to Drive ----
if ($Publish) {
  $jp1 = -join ([char]0x30DE,[char]0x30A4,[char]0x30C9,[char]0x30E9,[char]0x30A4,[char]0x30D6) # My Drive (kana)
  $jp2 = -join ([char]0x30C4,[char]0x30FC,[char]0x30EB,[char]0x958B,[char]0x767A)               # tool dev
  $suffix = "$jp1\$jp2\FutaFinance-Desktop"
  $cands = @("H:\$suffix", "G:\$suffix")
  $driveDir = $null
  foreach ($c in $cands) { if (Test-Path (Split-Path $c -Parent)) { $driveDir = $c; break } }
  if ($driveDir) {
    New-Item -ItemType Directory -Force -Path $driveDir | Out-Null
    Copy-Item $exe.FullName (Join-Path $driveDir "FutaFinance.exe") -Force
    $ver = (Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json).version
    [System.IO.File]::WriteAllText((Join-Path $driveDir "version.txt"), $ver, [System.Text.UTF8Encoding]::new($false))
    Write-Host "published to Drive: $driveDir (v$ver)" -ForegroundColor Green
  } else {
    Write-Host "Drive folder not found; skipped publish." -ForegroundColor DarkGray
  }
}

Write-Host "== done ==" -ForegroundColor Cyan
Write-Host "Run it: $installExe"
