# たくはるファイナンス Android配信スクリプト (FutaFinanceと同方式)
#
# フロー:
# 1. pubspec.yaml からバージョン取得
# 2. APKビルド (release・debug鍵署名)
# 3. release/takuharu-version.json を更新
# 4. git commit & push
# 5. gh release create で GitHub Release 作成 + APK アセット添付
# 6. I:\マイドライブ\TakuharuFinance\apks\ へAPKをコピー(最新1つだけ残す)
#
# 使い方: pubspec.yaml の version を +1 してから実行。
# 引数: -ReleaseNotes "リリースノート" / -SkipRelease

param(
  [string]$ReleaseNotes = "",
  [switch]$SkipRelease
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

$appDir = Join-Path $root "apps\takuharu_finance"
$apkSrc = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"
$versionJson = Join-Path $root "release\takuharu-version.json"
$repo = "fffuttta-design/finance-apps"
$driveApks = "I:\マイドライブ\TakuharuFinance\apks"

$env:Path = "$env:Path;$env:LOCALAPPDATA\Pub\Cache\bin;$env:LOCALAPPDATA\Android\Sdk\platform-tools"

# === 1. バージョン取得 ===
$pubspecPath = Join-Path $appDir "pubspec.yaml"
$content = Get-Content $pubspecPath -Raw
if ($content -notmatch '(?m)^version:\s*([\d\.]+)\+(\d+)\s*$') {
  Write-Error "pubspec.yaml から version を取得できませんでした"
  exit 1
}
$version = $Matches[1]
$buildNumber = $Matches[2]
$fullVersion = "$version+$buildNumber"
$tag = "takuharu-v$version"
$assetName = "takuharu-finance-v$version.apk"
$downloadUrl = "https://github.com/$repo/releases/download/$tag/$assetName"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Magenta
Write-Host " たくはるファイナンス Deploy: v$fullVersion" -ForegroundColor Magenta
Write-Host " Tag: $tag / Asset: $assetName" -ForegroundColor DarkGray
Write-Host "===============================================" -ForegroundColor Magenta

if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
  $ReleaseNotes = "v$fullVersion リリース"
}

# === 2. APKビルド ===
Write-Host "[1/5] APKビルド (release)..." -ForegroundColor Yellow
Set-Location $appDir
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
  Set-Location $root
  Write-Error "ビルド失敗"
  exit 1
}
Set-Location $root
$apkSize = [math]::Round((Get-Item $apkSrc).Length / 1MB, 1)
Write-Host "  OK APK生成: $apkSize MB" -ForegroundColor Green

# === 3. version.json 更新 ===
Write-Host "[2/5] release/takuharu-version.json 更新..." -ForegroundColor Yellow
$json = [PSCustomObject]@{
  version = $version
  buildNumber = $buildNumber
  downloadUrl = $downloadUrl
  releaseNotes = $ReleaseNotes
} | ConvertTo-Json -Depth 5
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($versionJson, $json, $utf8NoBom)
Write-Host "  OK version: $fullVersion" -ForegroundColor Green

# === 6. ドライブ(I:)へコピー (最新1つだけ残す) ===
Write-Host "[3/5] I:ドライブ(takuharumika)へコピー..." -ForegroundColor Yellow
if (Test-Path "I:\") {
  New-Item -ItemType Directory -Force $driveApks | Out-Null
  Get-ChildItem $driveApks -Filter "*.apk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  Copy-Item -Path $apkSrc -Destination (Join-Path $driveApks $assetName) -Force
  Write-Host "  OK $driveApks\$assetName" -ForegroundColor Green
} else {
  Write-Host "  -- I:ドライブ未マウント (Driveコピーをスキップ)" -ForegroundColor Yellow
}

if ($SkipRelease) {
  Write-Host "[4/5][5/5] git/Release: スキップ" -ForegroundColor DarkGray
  Write-Host " ローカル更新のみ完了: v$fullVersion" -ForegroundColor Green
  exit 0
}

# === 4. git commit & push ===
Write-Host "[4/5] git commit and push..." -ForegroundColor Yellow
git add release/takuharu-version.json
$gitStatus = git status --porcelain release/takuharu-version.json
if ($gitStatus) {
  git commit -m "release(takuharu): v$fullVersion - $ReleaseNotes"
}
git push origin main
if ($LASTEXITCODE -ne 0) { Write-Error "git push 失敗"; exit 1 }
Write-Host "  OK push完了" -ForegroundColor Green

# === 5. GitHub Release作成 ===
Write-Host "[5/5] GitHub Release 作成 (tag: $tag)..." -ForegroundColor Yellow
gh release view $tag --repo $repo 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
  gh release delete $tag --repo $repo --yes --cleanup-tag
}
$apkRenamed = Join-Path $appDir "build\$assetName"
Copy-Item -Path $apkSrc -Destination $apkRenamed -Force
gh release create $tag $apkRenamed `
  --repo $repo `
  --title "たくはるファイナンス v$fullVersion" `
  --notes $ReleaseNotes
if ($LASTEXITCODE -ne 0) { Write-Error "gh release create 失敗"; exit 1 }
Write-Host "  OK Release作成完了 (asset: $assetName)" -ForegroundColor Green

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host " Deploy完了: v$fullVersion" -ForegroundColor Green
Write-Host " Release: https://github.com/$repo/releases/tag/$tag" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
