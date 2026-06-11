# =====================================================================
#  FutaFinance Windows desktop deploy
#    build -> install to finance-apps\windows-app -> make shortcuts
#    (optional) zip to Google Drive
#
#  NOTE: ASCII-only on purpose. Windows PowerShell 5.1 misreads
#        UTF-8 (no BOM) .ps1 files and can break parsing on Japanese
#        comments. Keep this file ASCII to stay safe.
#
#  Usage:  powershell -ExecutionPolicy Bypass -File .\deploy_windows.ps1
#          powershell -ExecutionPolicy Bypass -File .\deploy_windows.ps1 -NoBuild
#          powershell -ExecutionPolicy Bypass -File .\deploy_windows.ps1 -Drive
# =====================================================================
param(
  [switch]$NoBuild,
  [switch]$Drive
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repo = $PSScriptRoot
$app  = Join-Path $repo 'apps\futa_finance'
$pubspec = Join-Path $app 'pubspec.yaml'

# --- read version from pubspec ---
$verLine = Select-String -Path $pubspec -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)' | Select-Object -First 1
if (-not $verLine) { throw 'could not read version from pubspec.yaml' }
$version = $verLine.Matches[0].Groups[1].Value
$build   = $verLine.Matches[0].Groups[2].Value
Write-Host "==============================================="
Write-Host " FutaFinance Windows Deploy: v$version+$build"
Write-Host "==============================================="

# --- build ---
if (-not $NoBuild) {
  Write-Host "[1/5] flutter build windows --release ..."
  Push-Location $app
  flutter build windows --release
  Pop-Location
} else {
  Write-Host "[1/5] build skipped (-NoBuild)"
}

$src = Join-Path $app 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $src 'futa_finance.exe'))) {
  throw "build output not found: $src"
}

# --- install location ---
#  Profile paths like %LOCALAPPDATA% are NOT reliably visible across the
#  dev environment, so install under the project (a shared C:\dev location).
#  Kept inside finance-apps but git-ignored (see .gitignore: /windows-app/).
$install = Join-Path $repo 'windows-app'
Write-Host "[2/5] install to: $install"

# stop running instance so files can be overwritten
Get-Process futa_finance -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 400

New-Item -ItemType Directory -Force -Path $install | Out-Null
# mirror copy, excluding build intermediates (.lib/.exp/.pdb) and VERSION.txt
robocopy $src $install /MIR /XF *.lib *.exp *.pdb VERSION.txt /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed (code=$LASTEXITCODE)" }
$global:LASTEXITCODE = 0

"v$version+$build" | Out-File -FilePath (Join-Path $install 'VERSION.txt') -Encoding ascii

$exe = Join-Path $install 'futa_finance.exe'

# --- shortcuts (desktop + start menu) ---
Write-Host "[3/5] shortcuts"
function New-Shortcut($lnkPath, $target) {
  $ws = New-Object -ComObject WScript.Shell
  $s = $ws.CreateShortcut($lnkPath)
  $s.TargetPath = $target
  $s.WorkingDirectory = (Split-Path $target)
  $s.Description = "FutaFinance (Windows)"
  $s.Save()
}
$desktop = [Environment]::GetFolderPath('Desktop')
New-Shortcut (Join-Path $desktop 'FutaFinance.lnk') $exe
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
New-Shortcut (Join-Path $startMenu 'FutaFinance.lnk') $exe

# --- (optional) zip to Drive ---
if ($Drive) {
  $driveDir = 'H:\マイドライブ\ツール開発\FutaFinance\windows'
  Write-Host "[4/5] zip to Drive: $driveDir"
  if (Test-Path 'H:\') {
    New-Item -ItemType Directory -Force -Path $driveDir | Out-Null
    Get-ChildItem $driveDir -Filter 'FutaFinance-Windows-*.zip' -ErrorAction SilentlyContinue | Remove-Item -Force
    $zip = Join-Path $driveDir "FutaFinance-Windows-v$version.zip"
    Compress-Archive -Path (Join-Path $install '*') -DestinationPath $zip -Force
    Write-Host "  OK $zip"
  } else {
    Write-Host "  -- H: drive not mounted. skipped"
  }
} else {
  Write-Host "[4/5] Drive zip skipped (use -Drive to enable)"
}

Write-Host "[5/5] done"
Write-Host "==============================================="
Write-Host " install: $install"
Write-Host " run:     $exe"
Write-Host "==============================================="
