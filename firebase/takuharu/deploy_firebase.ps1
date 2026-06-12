# Takuharu Finance - Firebase deploy
#   Step 1: Firestore rules  (works on the FREE Spark plan) -> enables comments
#   Step 2: Cloud Functions   (needs the Blaze pay-as-you-go plan) -> enables notifications
#
# How to run: paste this into Explorer's address bar and press Enter:
#   powershell -NoExit -ExecutionPolicy Bypass -File "C:\dev\CoreBusinessTools\finance-apps\firebase\takuharu\deploy_firebase.ps1"

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host "==== Takuharu Finance: Firebase deploy ====" -ForegroundColor Magenta

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

# Login (no-op if already logged in; opens a browser otherwise). Use takuharumika@gmail.com.
Write-Host "[login] Checking Firebase login (use takuharumika@gmail.com)..." -ForegroundColor Cyan
Invoke-FB login

# Step 1: Firestore rules (free plan OK) -> comments
Write-Host "[1/2] Deploying Firestore rules (enables the comment section)..." -ForegroundColor Cyan
Invoke-FB deploy --only "firestore:rules" --project takuharu-finance
$rulesOk = ($LASTEXITCODE -eq 0)

# Step 2: Cloud Functions (Blaze plan required) -> notifications
Write-Host "[2/2] Deploying Cloud Functions (enables partner notifications; needs Blaze plan)..." -ForegroundColor Cyan
Invoke-FB deploy --only "functions" --project takuharu-finance
$funcOk = ($LASTEXITCODE -eq 0)

Write-Host ""
Write-Host "==== RESULT ====" -ForegroundColor Magenta
if ($rulesOk) {
  Write-Host "[OK] Firestore rules deployed -> the comment section now works." -ForegroundColor Green
} else {
  Write-Host "[NG] Firestore rules deploy failed (see messages above)." -ForegroundColor Red
}
if ($funcOk) {
  Write-Host "[OK] Cloud Functions deployed -> partner notifications now work." -ForegroundColor Green
} else {
  Write-Host "[NG] Cloud Functions NOT deployed. The project needs the Blaze (pay-as-you-go) plan." -ForegroundColor Yellow
  Write-Host "     Upgrade here, then re-run this script:" -ForegroundColor Yellow
  Write-Host "     https://console.firebase.google.com/project/takuharu-finance/usage/details" -ForegroundColor Yellow
}
