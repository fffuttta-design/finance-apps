# takuharu_finance Android deploy script (GitHub Releases)
#
# Flow:
# 1. Get version from pubspec.yaml
# 2. Build APK (release)
# 3. Install on connected device (optional)
# 4. Create GitHub Release with APK
# 5. Update release/takuharu-version.json
# 6. git commit & push
#
# Usage: Run this script after bumping version in pubspec.yaml.
# Args:
#   -ReleaseNotes "notes"   (default: "v{version} release")
#   -SkipInstall            (skip adb install)
#   -SkipRelease            (skip GitHub Release + git push)

param(
  [string]$ReleaseNotes = "",
  [switch]$SkipInstall,
  [switch]$SkipRelease
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

$appDir = Join-Path $root "apps\takuharu_finance"
$apkSrc = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"
$versionJson = Join-Path $root "release\takuharu-version.json"
$repo = "fffuttta-design/finance-apps"

$env:Path = "$env:Path;$env:LOCALAPPDATA\Pub\Cache\bin;$env:LOCALAPPDATA\Android\Sdk\platform-tools"

# 1. Get version
$pubspecPath = Join-Path $appDir "pubspec.yaml"
$content = Get-Content $pubspecPath -Raw
if ($content -notmatch '(?m)^version:\s*([\d\.]+)\+(\d+)\s*$') {
  Write-Error "pubspec.yaml version parse failed"
  exit 1
}
$version = $Matches[1]
$buildNumber = $Matches[2]
$fullVersion = "$version+$buildNumber"
$tag = "takuharu-v$version"
$assetName = "takuharu-finance-v$version.apk"
$downloadUrl = "https://github.com/$repo/releases/download/$tag/$assetName"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " takuharu_finance Deploy: v$fullVersion" -ForegroundColor Cyan
Write-Host " Tag:   $tag" -ForegroundColor DarkGray
Write-Host " Asset: $assetName" -ForegroundColor DarkGray
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
  $ReleaseNotes = "v$fullVersion release"
}

# 2. Build APK
Write-Host "[1/5] APK build (release)..." -ForegroundColor Yellow
Set-Location $appDir
$geminiKeyFile = Join-Path $appDir "gemini.key"
$dartDefines = @()
if (Test-Path $geminiKeyFile) {
  $gk = (Get-Content $geminiKeyFile -Raw).Trim()
  if (-not [string]::IsNullOrWhiteSpace($gk)) {
    $dartDefines += "--dart-define=GEMINI_API_KEY=$gk"
    Write-Host "  GEMINI_API_KEY injected" -ForegroundColor DarkGray
  }
}
flutter build apk --release @dartDefines
if ($LASTEXITCODE -ne 0) {
  Set-Location $root
  Write-Error "Build failed"
  exit 1
}
Set-Location $root

$apkSize = [math]::Round((Get-Item $apkSrc).Length / 1MB, 1)
Write-Host "  OK APK: $apkSize MB" -ForegroundColor Green

# 3. Install on device
if (-not $SkipInstall) {
  Write-Host ""
  Write-Host "[2/5] adb install..." -ForegroundColor Yellow
  $devices = adb devices 2>$null | Select-String "device$"
  if ($devices) {
    $device = ($devices[0] -split '\s+')[0]
    adb -s $device install -r $apkSrc
    if ($LASTEXITCODE -eq 0) {
      Write-Host "  OK installed ($device)" -ForegroundColor Green
    } else {
      Write-Host "  -- install failed (continuing)" -ForegroundColor Yellow
    }
  } else {
    Write-Host "  -- no device connected (skip)" -ForegroundColor Yellow
  }
} else {
  Write-Host "[2/5] adb install: skip" -ForegroundColor DarkGray
}

# 4. Update version.json
Write-Host ""
Write-Host "[3/5] release/takuharu-version.json update..." -ForegroundColor Yellow
$json = [PSCustomObject]@{
  version = $version
  buildNumber = $buildNumber
  downloadUrl = $downloadUrl
  releaseNotes = $ReleaseNotes
} | ConvertTo-Json -Depth 5
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($versionJson, $json, $utf8NoBom)
Write-Host "  OK $version+$buildNumber" -ForegroundColor Green

if ($SkipRelease) {
  Write-Host "[4/5] GitHub Release: skip" -ForegroundColor DarkGray
  Write-Host "[5/5] git push: skip" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "===============================================" -ForegroundColor Green
  Write-Host " Local only: v$fullVersion" -ForegroundColor Green
  Write-Host "===============================================" -ForegroundColor Green
  exit 0
}

# 5. GitHub Release (before push to avoid 404 window)
Write-Host ""
Write-Host "[4/5] GitHub Release create (tag: $tag)..." -ForegroundColor Yellow
gh release view $tag --repo $repo 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
  Write-Host "  Deleting existing release $tag..." -ForegroundColor Yellow
  gh release delete $tag --repo $repo --yes --cleanup-tag
}

$apkRenamed = Join-Path $appDir "build\$assetName"
Copy-Item -Path $apkSrc -Destination $apkRenamed -Force

gh release create $tag $apkRenamed `
  --repo $repo `
  --title "takuharu-finance v$fullVersion" `
  --notes $ReleaseNotes
if ($LASTEXITCODE -ne 0) {
  Write-Error "gh release create failed"
  exit 1
}
Write-Host "  OK Release created" -ForegroundColor Green

# 6. git commit & push
Write-Host ""
Write-Host "[5/5] git commit and push..." -ForegroundColor Yellow
git add release/takuharu-version.json
$gitStatus = git status --porcelain release/takuharu-version.json
if ($gitStatus) {
  git commit -m "release(takuharu): v$fullVersion - $ReleaseNotes"
  if ($LASTEXITCODE -ne 0) {
    Write-Error "git commit failed"
    exit 1
  }
}
git push origin main
if ($LASTEXITCODE -ne 0) {
  Write-Error "git push failed"
  exit 1
}
Write-Host "  OK pushed" -ForegroundColor Green

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host " Deploy done: v$fullVersion" -ForegroundColor Green
Write-Host " Release: https://github.com/$repo/releases/tag/$tag" -ForegroundColor Green
Write-Host " APK URL: $downloadUrl" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
