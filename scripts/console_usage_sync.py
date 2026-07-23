"""Anthropic Console から Claude の使用量を取ってきて、二村秘書VPSへ流し込む。

🔥 なぜこれが要るのか
Anthropic の公式 Admin API（使用量API）は**個人アカウントでは鍵を発行できない**
（`/settings/admin-keys` が404）。一方で **Console の画面が裏で叩いている内部API**
`/api/organizations/{org}/usage_activities` は、日付範囲を指定すると
**キー名 × モデル × トークン内訳** を丸ごと返してくれる。ログイン済みのブラウザからなら
これを呼べるので、Playwright の永続プロファイルでログインを保持して定期実行する。
（YouTubeアナリティクス / Lステップ分析と同じ「APIが無いので画面側から取る」型）

使い方:
    py scripts\\console_usage_sync.py            # 直近2か月を取り込む
    py scripts\\console_usage_sync.py --months 6 # 6か月ぶん遡る
    py scripts\\console_usage_sync.py --login    # 初回ログイン（ブラウザが開く）

終了コード: 0=成功 / 2=ログインが切れている（要 --login） / 1=その他の失敗
"""
from __future__ import annotations

import argparse
import io
import json
import os
import sys
import urllib.request
from datetime import date

sys.stdout.reconfigure(encoding="utf-8")

# ブラウザのログインを保持する場所（Cookieが入る＝実質的な鍵なので _secrets 配下）
PROFILE_DIR = r"C:\dev\_secrets\console-profile"
KEY_FILE = r"C:\dev\_secrets\ai-usage-key.txt"
ENDPOINT = "https://hisho.run-strategy.jp/ai-usage"
USAGE_URL = "https://platform.claude.com/usage"

# ページ内で走らせる取得処理。組織IDは画面が叩いたURLから拾うので決め打ちしない。
FETCH_JS = r"""
async (months) => {
  // 組織IDは画面側の状態に出ているので、まず workspaces API を叩いて確かめる。
  // 手っ取り早く、既に読み込まれた <script> や fetch 履歴に頼らず /api/organizations を試す。
  let org = null;
  const m = document.documentElement.innerHTML.match(
    /organizations\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/);
  if (m) org = m[1];
  if (!org) {
    const r = await fetch('/api/bootstrap', {credentials: 'include'}).catch(() => null);
    if (r && r.ok) {
      const t = await r.text();
      const m2 = t.match(/"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"/);
      if (m2) org = m2[1];
    }
  }
  if (!org) return {error: 'org_not_found'};

  const out = {org: org, months: {}};
  for (const mo of months) {
    const [y, n] = mo.split('-').map(Number);
    const nx = n === 12 ? `${y + 1}-01-01`
                        : `${y}-${String(n + 1).padStart(2, '0')}-01`;
    const url = `/api/organizations/${org}/usage_activities`
              + `?starting_on=${mo}-01&ending_before=${nx}&categories=true&granularity=daily`;
    const r = await fetch(url, {credentials: 'include'});
    if (r.status === 401 || r.status === 403) return {error: 'unauthorized'};
    if (!r.ok) { out.months[mo] = {error: r.status}; continue; }
    const j = await r.json();
    const agg = {};
    for (const d of Object.keys(j.usages || {})) {
      for (const u of j.usages[d]) {
        const k = (u.key_name || '(不明)') + '|' + (u.model_name || '');
        agg[k] = agg[k] || [0, 0, 0, 0];
        agg[k][0] += u.input_no_cache || 0;
        agg[k][1] += u.output || 0;
        agg[k][2] += (u.input_cache_write || 0) + (u.input_cache_write_1h || 0);
        agg[k][3] += u.input_cache_read || 0;
      }
    }
    out.months[mo] = agg;
  }
  return out;
}
"""

# Consoleのキー名 → 集計側のアプリID（自前計測と同じ名前に寄せる）
ALIAS = {"二村秘書Bot": "futahisho"}


def _months(n: int) -> list[str]:
    """今月からさかのぼって n か月ぶんのキー（新しい順）。"""
    y, m = date.today().year, date.today().month
    out = []
    for _ in range(n):
        out.append(f"{y}-{m:02d}")
        m -= 1
        if m == 0:
            y, m = y - 1, 12
    return out


def _post(payload: dict) -> dict:
    key = io.open(KEY_FILE, encoding="utf-8").read().strip()
    req = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={"content-type": "application/json", "x-usage-key": key},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def run(months: int, login: bool) -> int:
    from playwright.sync_api import sync_playwright

    os.makedirs(PROFILE_DIR, exist_ok=True)
    targets = _months(months)

    with sync_playwright() as pw:
        ctx = pw.chromium.launch_persistent_context(
            PROFILE_DIR, headless=not login, channel="chrome",
            args=["--disable-blink-features=AutomationControlled"],
        )
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.goto(USAGE_URL, wait_until="domcontentloaded", timeout=90_000)

        if login:
            print("ブラウザでAnthropicにログインしてください。")
            print("使用量ページが表示されたら、この窓に Enter を押してください。")
            input()

        # ログイン画面へ飛ばされていたら、取得はできない
        if "login" in page.url or "auth" in page.url:
            print("❌ ログインが切れています。`--login` を付けて実行し直してください。")
            ctx.close()
            return 2

        try:
            data = page.evaluate(FETCH_JS, targets)
        except Exception as e:            # noqa: BLE001
            print("❌ 取得に失敗:", str(e)[:200])
            ctx.close()
            return 1
        ctx.close()

    if not isinstance(data, dict) or data.get("error"):
        print("❌ 取得に失敗:", (data or {}).get("error"))
        return 2 if (data or {}).get("error") == "unauthorized" else 1

    total = 0
    for month, agg in (data.get("months") or {}).items():
        if not isinstance(agg, dict) or agg.get("error"):
            print(f"  {month}: 取得できず（{agg}）")
            continue
        events = []
        for k, v in agg.items():
            name, model = k.split("|", 1)
            events.append({
                "app": ALIAS.get(name, name),
                "model": model,
                "kind": "console",
                # 月の途中の固定時刻にまとめる（日別はConsole側で見るので月次で十分）
                "ts": f"{month}-15T12:00:00",
                "usage": {
                    "input_tokens": v[0], "output_tokens": v[1],
                    "cache_creation_input_tokens": v[2],
                    "cache_read_input_tokens": v[3],
                },
            })
        if not events:
            print(f"  {month}: 使用なし")
            continue
        # 同じ月の console 行を丸ごと置き換える（再実行しても二重にならない）
        res = _post({"replace": {"kind": "console", "month": month}, "events": events})
        print(f"  {month}: {res.get('saved', 0)} 行 取り込み")
        total += res.get("saved", 0)

    print(f"✅ 合計 {total} 行を取り込みました")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--months", type=int, default=2, help="さかのぼる月数（既定2）")
    ap.add_argument("--login", action="store_true", help="初回ログイン（ブラウザを開く）")
    a = ap.parse_args()
    sys.exit(run(a.months, a.login))
