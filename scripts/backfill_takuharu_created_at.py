# -*- coding: utf-8 -*-
"""
たくはるファイナンス：既存の取引に「登録日時(createdAt)」を後付けする。

新規保存では add/addAll が createdAt を入れるようになったが、既存データには無い。
そこで、書き込み時刻として入っている updatedAt(サーバー時刻) を createdAt に写す。
- 一度も編集していない取引なら updatedAt ＝ 登録時刻そのもの。
- 編集済みの取引は「最後に直した時刻」になる（真の登録時刻は残っていないため近似）。

createdAt が既に入っている取引は触らない（冪等）。
アプリと同じ「タイムゾーンなしのローカルISO文字列(JST)」で書く。

    py backfill_takuharu_created_at.py --dry-run   # 変更せず件数だけ
    py backfill_takuharu_created_at.py             # 実行
"""
import sys
from datetime import timezone, timedelta

sys.stdout.reconfigure(encoding="utf-8")

from google.cloud import firestore
from google.oauth2 import service_account

KEY_PATH = r"C:\dev\_secrets\takuharu-finance-sa.json"
PROJECT_ID = "takuharu-finance"
HID = "TAKUHARU"
JST = timezone(timedelta(hours=9))

dry = "--dry-run" in sys.argv

cred = service_account.Credentials.from_service_account_file(KEY_PATH)
db = firestore.Client(project=PROJECT_ID, credentials=cred)

coll = db.collection(f"households/{HID}/transactions")
docs = list(coll.stream())

filled = 0
skipped_has = 0
skipped_no_src = 0
for d in docs:
    m = d.to_dict() or {}
    if m.get("createdAt"):
        skipped_has += 1
        continue
    src = m.get("updatedAt")
    if src is None:
        skipped_no_src += 1
        continue
    # Firestore Timestamp(UTC aware) → JST naive ISO（アプリと同じ書式）
    dt = src.astimezone(JST).replace(tzinfo=None)
    iso = dt.isoformat()
    if dry:
        filled += 1
        if filled <= 8:
            desc = m.get("description") or m.get("categoryMajor") or "(名称なし)"
            print(f"  {d.id[:8]}… {desc} -> {iso}")
    else:
        d.reference.set({"createdAt": iso}, merge=True)
        filled += 1

print("---")
print(f"総件数         : {len(docs)}")
print(f"createdAt付与   : {filled}{'（dry-run・未書込）' if dry else ''}")
print(f"既にあり(skip)  : {skipped_has}")
print(f"元時刻なし(skip): {skipped_no_src}")
