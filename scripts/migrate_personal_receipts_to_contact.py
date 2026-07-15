r"""個人レシートの証憑を fffuttta のドライブから contact@ へ移す一回きりの移行スクリプト。

背景（2026-07-15）:
    FutaFinanceアプリ本体は contact@ のDriveへ、二村秘書BOTは fffuttta のDriveへ
    個人レシートを保存しており、**保存先が2アカウントに分裂**していた。
    BOT側の既定トークンを drive_token.json(contact@) に直したので、
    **過去にfffuttta側へ保存された証憑だけ**を contact@ へ移す。

やること（--apply を付けたときだけ書き込む。既定は下見のみ）:
    1. Firestore の個人モード取引から receiptUrl のあるものを集める
    2. 各ファイルの所有者を Drive API で調べ、**fffuttta所有のものだけ**を対象にする
    3. contact@ の `FutaFinanceレシート/個人用/YYYY年/MM月/` へ files.copy（＝contact@所有の複製）
    4. Firestore の receiptUrl を新しいリンクへ貼り替える
    5. 元ファイル（fffuttta所有）は**このスクリプトでは消さない**。
       contact@のトークンでは他人のファイルを消せないため、G:ドライブ(fffuttta)の
       マウント経由でユーザー側/別手順で消す。消す前に必ず本スクリプトの成功を確認すること。

実行（VPS上。drive_token.json と futa-finance-admin.json がある場所で）:
    cd /opt/bots/FutaHisho
    .venv/bin/python migrate_personal_receipts_to_contact.py           # 下見
    .venv/bin/python migrate_personal_receipts_to_contact.py --apply   # 実行
"""
from __future__ import annotations

import json
import re
import sys

sys.path.insert(0, "/opt/bots/FutaHisho")

import config  # noqa: E402
from core import finance_receipt as fr  # noqa: E402
from core import futafinance as ff  # noqa: E402

APPLY = "--apply" in sys.argv

# 移行対象の所有者（このアカウントが持っている証憑だけ contact@ へ移す）。
OLD_OWNER = "fffuttta@gmail.com"


def file_id_from_url(url: str) -> str | None:
    """Drive の閲覧リンクからファイルIDを取り出す（アプリの fileIdFromUrl と同じ規則）。"""
    m = re.search(r"/d/([A-Za-z0-9_-]+)", url or "") or \
        re.search(r"[?&]id=([A-Za-z0-9_-]+)", url or "")
    return m.group(1) if m else None


def main() -> None:
    print(f"=== 個人レシート移行 {'【本番実行】' if APPLY else '【下見のみ・書き込みなし】'} ===")
    drive = fr._service(config.FUTA_RECEIPT_TOKEN)  # contact@
    db = ff._client()
    uid = config.FUTAFINANCE_UID
    if not uid:
        raise SystemExit("FUTAFINANCE_UID が未設定です")

    # 1. 個人モードで receiptUrl を持つ取引を集める
    coll = db.collection(f"users/{uid}/transactions")
    targets = []
    for snap in coll.where("mode", "==", "personal").stream():
        d = snap.to_dict() or {}
        url = d.get("receiptUrl")
        fid = file_id_from_url(url) if url else None
        if not fid:
            continue
        # 2. 所有者を調べる（公開ファイルなので contact@ でも読める）
        try:
            meta = drive.files().get(
                fileId=fid, fields="id,name,owners(emailAddress),mimeType",
                supportsAllDrives=True).execute()
        except Exception as e:  # noqa: BLE001
            print(f"  [skip] 取得できず tx={snap.id} file={fid}: {e}")
            continue
        owners = [o.get("emailAddress") for o in meta.get("owners", [])]
        if OLD_OWNER not in owners:
            continue  # すでに contact@ 所有＝移行不要
        targets.append({
            "txId": snap.id, "fileId": fid, "name": meta.get("name"),
            "date": d.get("date"), "store": d.get("store"),
            "amount": d.get("amount"), "owners": owners,
        })

    print(f"\n移行対象: {len(targets)}件（{OLD_OWNER} 所有の証憑）")
    for t in targets:
        print(f"  - {t['date']} {t['store']} {t['amount']}円 / {t['name']} (tx={t['txId']})")
    if not targets:
        print("対象なし。終了します。")
        return
    if not APPLY:
        print("\n下見のみ。実行するには --apply を付けてください。")
        return

    # 3〜4. contact@ へコピーして Firestore を貼り替え
    results = []
    for t in targets:
        month_id = _month_folder(drive, str(t["date"]))
        copied = drive.files().copy(
            fileId=t["fileId"], body={"name": t["name"], "parents": [month_id]},
            fields="id,webViewLink", supportsAllDrives=True).execute()
        new_id, new_url = copied["id"], copied.get("webViewLink")
        # アプリのログインアカウントが変わっても開けるよう、保険で公開を付ける（元と同条件）。
        try:
            drive.permissions().create(
                fileId=new_id, body={"type": "anyone", "role": "reader"},
                supportsAllDrives=True).execute()
        except Exception as e:  # noqa: BLE001
            print(f"  [warn] 公開付与に失敗 {new_id}: {e}")
        db.document(f"users/{config.FUTAFINANCE_UID}/transactions/{t['txId']}").update(
            {"receiptUrl": new_url})
        results.append({**t, "newFileId": new_id, "newUrl": new_url})
        print(f"  ✅ {t['name']} → contact@ ({new_id}) / receiptUrl 貼替済")

    print("\n=== 完了 ===")
    print("元ファイル（fffuttta所有）は残っています。動作確認後に G: ドライブから削除してください：")
    for r in results:
        print(f"  旧 {r['fileId']}  ({r['name']})")
    with open("/tmp/receipt_migration_result.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("結果: /tmp/receipt_migration_result.json")


def _month_folder(drive, date_str: str) -> str:
    """contact@ 側の `FutaFinanceレシート/個人用/YYYY年/MM月/` を用意してIDを返す。"""
    root = fr._find_or_create_root(drive, fr._FUTA_ROOT_NAME)
    mode = fr._find_or_create_folder(drive, fr._FUTA_MODE_PERSONAL, root)
    year, month = fr._year_month(date_str)
    year_id = fr._find_or_create_folder(drive, year, mode)
    return fr._find_or_create_folder(drive, month, year_id)


if __name__ == "__main__":
    main()
