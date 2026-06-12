# たくはるファイナンス Firebase 配信（Functions + Firestoreルール）
# プランニングの「相手へ通知」と「コメント欄」を有効にするために必要。
#
# 使い方: エクスプローラーのアドレスバーに次を貼って Enter:
#   powershell -NoExit -ExecutionPolicy Bypass -File "C:\dev\CoreBusinessTools\finance-apps\firebase\takuharu\deploy_firebase.ps1"

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host "==== たくはるファイナンス Firebase 配信 ====" -ForegroundColor Magenta

# firebase CLI の有無を確認
$fb = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $fb) {
  Write-Host "firebase コマンドが見つかりません。先に次を実行してください:" -ForegroundColor Yellow
  Write-Host "  npm install -g firebase-tools" -ForegroundColor Yellow
  Write-Host "  firebase login" -ForegroundColor Yellow
  exit 1
}

# Functions と Firestore ルールをまとめて配信
firebase deploy --only "functions,firestore:rules" --project takuharu-finance

if ($LASTEXITCODE -eq 0) {
  Write-Host ""
  Write-Host "==== 配信完了 ====" -ForegroundColor Green
  Write-Host "プランニングの通知・コメントが有効になりました。" -ForegroundColor Green
} else {
  Write-Host ""
  Write-Host "配信に失敗しました。未ログインの場合は 'firebase login' を実行してから再度お試しください。" -ForegroundColor Red
}
