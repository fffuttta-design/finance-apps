# Takuharu Finance - Firestore rules deploy (FREE Spark plan OK; no Blaze needed)
#   Enables the planning comment section (plan_items/{}/comments permission).
#   Notifications are handled by the VPS 'takuharu-notifier' (not Cloud Functions),
#   so Cloud Functions / Blaze are NOT required.
#
# How to run: paste this into Explorer's address bar and press Enter:
#   powershell -NoExit -ExecutionPolicy Bypass -File "C:\dev\CoreBusinessTools\finance-apps\firebase\takuharu\deploy_firebase.ps1"

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host "==== Takuharu Finance: Firestore rules deploy ====" -ForegroundColor Magenta

# Resolve firebase: prefer global 'firebase', otherwise use 'npx firebase-tools'
$useNpx = $false
$fb = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $fb) {
  Write-Host "Global 'firebase' not found -> using 'npx firebase-tools' (no global install needed)." -ForegroundColor Yellow
  $npx = Get-Command npx -ErrorAction SilentlyContinue
  if (-not $npx) {
    Write-Host "Node.js / npx not found. Please install Node.js, then re-run this script." -ForegroundColor Red
    exit 1
  }
  $useNpx = $true
}

function Invoke-FB {
  param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $FbArgs)
  if ($useNpx) {
    & npx --yes firebase-tools@latest @FbArgs
  } else {
    & firebase @FbArgs
  }
}

# Login (no-op if already logged in). Use takuharumika@gmail.com.
Write-Host "[login] Checking Firebase login (use takuharumika@gmail.com)..." -ForegroundColor Cyan
Invoke-FB login

# Deploy Firestore rules only (free; enables the comment section)
Write-Host "[deploy] Deploying Firestore rules..." -ForegroundColor Cyan
Invoke-FB deploy --only "firestore:rules" --project takuharu-finance

if ($LASTEXITCODE -eq 0) {
  Write-Host ""
  Write-Host "==== DONE: the planning comment section is now enabled. ====" -ForegroundColor Green
} else {
  Write-Host ""
  Write-Host "==== FAILED. See the messages above (often it just needs login). ====" -ForegroundColor Red
}
