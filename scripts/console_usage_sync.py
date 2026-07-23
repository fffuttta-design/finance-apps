"""Anthropic Console から Claude の使用量を取ってきて、二村秘書VPSへ流し込む。

🔥 なぜこれが要るのか
Anthropic の公式 Admin API（使用量API）は**個人アカウントでは鍵を発行できない**
（`/settings/admin-keys` が404）。一方で **Console の画面が裏で叩いている内部API**
`/api/organizations/{org}/usage_activities` は、日付範囲を指定すると
**キー名 × モデル × トークン内訳** を丸ごと返してくれる。ログイン済みのブラウザからなら
これを呼べるので、ログイン状態（Cookie）を保存して使い回す。

🔥 役割の分け方（ここが肝）
  ①【PCで1回だけ】 --login  … 画面でログインし、Cookieを1つのJSONに保存する。
      Consoleのログインには画面操作とメールのコード入力が要るので、これだけは人の手が要る。
      ⚠️ **Googleログインは使えない**。Googleは自動操作されたブラウザからの認証を
        わざと拒否する（空のポップアップが出て進めない）。「メールアドレスで続ける」を選ぶこと。
  ②【VPSで毎日】  通常実行     … そのJSONを読んで headless で取得し、VPSの /ai-usage へPOST。
      PCの電源に依存しない。Cookieが切れたら 48時間の見張りがLINEで知らせる。

使い方:
    py scripts\\console_usage_sync.py --login          # ①PCで1回（ブラウザが開く）
    py scripts\\console_usage_sync.py --months 6       # ②取り込み（VPSのcronはこれ）

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

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# Windows なら _secrets、VPS なら実行ディレクトリ。環境変数で上書きできる。
_WIN = os.name == "nt"
SESSION_FILE = os.environ.get(
    "CONSOLE_SESSION_FILE",
    r"C:\dev\_secrets\console-session.json" if _WIN else "/opt/apps/claude-usage/session.json")
KEY_FILE = os.environ.get(
    "AI_USAGE_KEY_FILE",
    r"C:\dev\_secrets\ai-usage-key.txt" if _WIN else "/opt/apps/claude-usage/ai-usage-key.txt")
ENDPOINT = os.environ.get("AI_USAGE_ENDPOINT", "https://hisho.run-strategy.jp/ai-usage")
USAGE_URL = "https://platform.claude.com/usage"
# 判明済みの組織ID（探索に失敗したときの最後の砦。組織を変えたらここも変える）
ORG_ID = os.environ.get("CONSOLE_ORG_ID", "ea21edf1-b29b-491a-b13c-5ceb6328e580")

# ページ内で走らせる取得処理。組織IDは画面のHTMLから拾うので決め打ちしない。
FETCH_JS = r"""
async ([months, KNOWN_ORG]) => {
  // 組織IDはAPIから取る。HTMLから拾うと headless で描画前に読んで空振りする（実際に踏んだ）。
  const uuid = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/;
  // 🔥 判明済みの組織IDを最優先で使う。自動探索を先にすると、/api/organizations が返す
  //    別のUUID（ワークスペース等）を掴んでしまい 401 になる（2026-07-23に実際に踏んだ）。
  let org = KNOWN_ORG || null;
  for (const path of (org ? [] :  ['/api/organizations', '/api/bootstrap', '/api/auth/current_account'])) {
    const r = await fetch(path, {credentials: 'include'}).catch(() => null);
    if (!r || !r.ok) continue;   // 401でも諦めない（その口が無いだけのことがある）
    const t = await r.text();
    const m = t.match(uuid);
    if (m) { org = m[1]; break; }
  }
  if (!org) {
    const m2 = document.documentElement.innerHTML.match(
      /organizations\/([0-9a-f-]{36})/);
    if (m2) org = m2[1];
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


# ログインできたかを、画面ではなく**実際にAPIが答えるか**で判定する。
# 🔥 「Enterを押したら保存」だと、別のウィンドウでログインした場合に
#    未ログインのCookieをそのまま保存してしまう（2026-07-23に実際に踏んだ）。
_PROBE_JS = r"""
async (org) => {
  const r = await fetch(
    `/api/organizations/${org}/usage_activities`
    + `?starting_on=2026-07-01&ending_before=2026-07-02&granularity=daily`,
    {credentials: 'include'}).catch(() => null);
  return r ? r.status : 0;
}
"""


def do_login() -> int:
    """①PCで1回だけ。画面でログインして、Cookieを SESSION_FILE に保存する。

    ⚠️ 保存するのは「本当にログインできた」と確認できたときだけ。
    """
    import time
    from playwright.sync_api import sync_playwright

    os.makedirs(os.path.dirname(SESSION_FILE), exist_ok=True)
    print("=" * 56)
    print(" Anthropic Console にログインしてください")
    print("=" * 56)
    print(" ⚠️ 開いた窓の中だけで操作してください（別のChromeでログインしても無効です）")
    print(" ⚠️ 「Google で続行」は使えません（Googleが自動操作ブラウザを拒否します）")
    print("    → 「メールアドレスで続ける」を選び、メールのコードでログイン")
    print()
    print(" ログインできたか自動で確認します。Enterを押す必要はありません。")
    print("=" * 56)

    with sync_playwright() as pw:
        br = pw.chromium.launch(headless=False, channel="chrome")
        ctx = br.new_context()
        page = ctx.new_page()
        page.goto(USAGE_URL, wait_until="domcontentloaded", timeout=120_000)

        deadline = time.time() + 600          # 10分待つ
        ok = False
        while time.time() < deadline:
            try:
                status = page.evaluate(_PROBE_JS, ORG_ID)
            except Exception:                 # noqa: BLE001  ページ遷移中など
                status = 0
            if status == 200:
                ok = True
                break
            time.sleep(3)

        if not ok:
            print("❌ ログインを確認できませんでした（10分でタイムアウト）。もう一度お試しください。")
            br.close()
            return 2

        ctx.storage_state(path=SESSION_FILE)
        br.close()

    print(f"✅ ログインを確認して保存しました: {SESSION_FILE}")
    print("   このファイルをVPSへ置けば、以降は毎日VPSが自動で取り込みます。")
    return 0


def do_fetch(months: int) -> int:
    """②毎日の取り込み。保存済みCookieで headless 実行する。"""
    from playwright.sync_api import sync_playwright

    if not os.path.exists(SESSION_FILE):
        print(f"❌ ログイン情報がありません（{SESSION_FILE}）。PCで --login を実行してください。")
        return 2

    targets = _months(months)
    with sync_playwright() as pw:
        br = pw.chromium.launch(headless=True)
        ctx = br.new_context(storage_state=SESSION_FILE)
        page = ctx.new_page()
        page.goto(USAGE_URL, wait_until="networkidle", timeout=120_000)
        if "login" in page.url or "auth" in page.url:
            print("❌ ログインが切れています。PCで --login を実行し直してください。")
            br.close()
            return 2
        try:
            data = page.evaluate(FETCH_JS, [targets, ORG_ID])
        except Exception as e:            # noqa: BLE001
            print("❌ 取得に失敗:", str(e)[:200])
            br.close()
            return 1
        br.close()

    if not isinstance(data, dict) or data.get("error"):
        err = (data or {}).get("error")
        print("❌ 取得に失敗:", err)
        return 2 if err in ("unauthorized", "org_not_found") else 1

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
                # 月の途中の固定時刻にまとめる（日別はConsole側で見られるので月次で十分）
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
    ap.add_argument("--login", action="store_true", help="①PCで1回だけ：ログインしてCookieを保存")
    a = ap.parse_args()
    sys.exit(do_login() if a.login else do_fetch(a.months))
