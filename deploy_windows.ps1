# =====================================================================
#  FutaFinance Windows デスクトップ版 デプロイ
#   ビルド → %LOCALAPPDATA%\FutaFinance へ常設 → ショートカット作成
#   （任意）Drive へ zip 配布
#
#  使い方:  pwsh .\deploy_windows.ps1
#           pwsh .\deploy_windows.ps1 -NoBuild   # 既存ビルドをそのまま設置
#           pwsh .\deploy_windows.ps1 -Drive     # Drive へ zip もコピー
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

# --- バージョン取得 ---
$verLine = Select-String -Path $pubspec -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)' | Select-Object -First 1
if (-not $verLine) { throw 'pubspec.yaml から version を読めませんでした' }
$version = $verLine.Matches[0].Groups[1].Value
$build   = $verLine.Matches[0].Groups[2].Value
Write-Host "==============================================="
Write-Host " FutaFinance Windows Deploy: v$version+$build"
Write-Host "==============================================="

# --- ビルド ---
if (-not $NoBuild) {
  Write-Host "[1/5] flutter build windows --release ..."
  Push-Location $app
  flutter build windows --release
  Pop-Location
} else {
  Write-Host "[1/5] ビルドはスキップ (-NoBuild)"
}

$src = Join-Path $app 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $src 'futa_finance.exe'))) {
  throw "ビルド成果物が見つかりません: $src"
}

# --- 常設先へコピー (%LOCALAPPDATA%\FutaFinance) ---
$install = Join-Path $env:LOCALAPPDATA 'FutaFinance'
Write-Host "[2/5] 常設先へ配置: $install"

# 起動中なら止める（上書きのため）
Get-Process futa_finance -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 400

New-Item -ItemType Directory -Force -Path $install | Out-Null
# robocopy でミラー。中間生成物(.lib/.exp/.pdb)は除外。
# robocopy の終了コードは 0-7 が正常。
robocopy $src $install /MIR /XF *.lib *.exp *.pdb VERSION.txt /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy 失敗 (code=$LASTEXITCODE)" }
$global:LASTEXITCODE = 0

# バージョン情報を残す
"v$version+$build" | Out-File -FilePath (Join-Path $install 'VERSION.txt') -Encoding utf8

$exe = Join-Path $install 'futa_finance.exe'

# --- ショートカット作成（デスクトップ + スタートメニュー） ---
Write-Host "[3/5] ショートカット作成"
function New-Shortcut($lnkPath, $target) {
  $ws = New-Object -ComObject WScript.Shell
  $s = $ws.CreateShortcut($lnkPath)
  $s.TargetPath = $target
  $s.WorkingDirectory = (Split-Path $target)
  $s.Description = "FutaFinance 事業用財務管理 (Windows)"
  $s.Save()
}
$desktop = [Environment]::GetFolderPath('Desktop')
New-Shortcut (Join-Path $desktop 'FutaFinance.lnk') $exe
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
New-Shortcut (Join-Path $startMenu 'FutaFinance.lnk') $exe
# 旧テスト用ショートカットがあれば掃除
$oldLnk = Join-Path $desktop 'FutaFinance (Windows版テスト).lnk'
if (Test-Path $oldLnk) { Remove-Item $oldLnk -Force }

# --- (任意) Drive へ zip 配布 ---
if ($Drive) {
  $driveDir = 'H:\マイドライブ\ツール開発\FutaFinance\windows'
  Write-Host "[4/5] Drive へ zip 配布: $driveDir"
  if (Test-Path 'H:\') {
    New-Item -ItemType Directory -Force -Path $driveDir | Out-Null
    # 最新1つだけ残す
    Get-ChildItem $driveDir -Filter 'FutaFinance-Windows-*.zip' -ErrorAction SilentlyContinue | Remove-Item -Force
    $zip = Join-Path $driveDir "FutaFinance-Windows-v$version.zip"
    Compress-Archive -Path (Join-Path $install '*') -DestinationPath $zip -Force
    Write-Host "  OK $zip"
  } else {
    Write-Host "  -- H: ドライブ未接続。スキップ"
  }
} else {
  Write-Host "[4/5] Drive 配布はスキップ (-Drive で有効)"
}

Write-Host "[5/5] 完了"
Write-Host "==============================================="
Write-Host " インストール先: $install"
Write-Host " 起動: デスクトップ/スタートメニューの『FutaFinance』"
Write-Host "==============================================="
