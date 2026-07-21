# -*- coding: utf-8 -*-
"""たくはるファイナンス：差額調整のカテゴリ直し（PCから直接Firestoreを更新）。

過去に「その他」で記録された「消費税・調整」「値引き・調整」の行を、
そのレシートの主たるカテゴリ（品目の金額合計が一番大きいカテゴリ）へ付け替える。
金額・日付・品名は変更しない。何度実行しても安全（冪等）。

使い方:
    py scripts/repair_takuharu_adjustment_categories.py --dry-run   # 確認だけ
    py scripts/repair_takuharu_adjustment_categories.py             # 実行

必要なもの:
    C:\\dev\\_secrets\\takuharu-finance-sa.json （takuharu-finance のサービスアカウント鍵）
"""
import argparse
import io
import os
import sys
from collections import defaultdict

from google.cloud import firestore
from google.oauth2 import service_account

# Windowsのcp932でUnicodeEscapeしないよう標準出力をUTF-8に固定する。
sys.stdout.reconfigure(encoding="utf-8")

KEY_PATH = r"C:\dev\_secrets\takuharu-finance-sa.json"
PROJECT_ID = "takuharu-finance"
HID = "TAKUHARU"
ADJ_NAMES = ("消費税・調整", "値引き・調整")


def dominant_category(items, fallback="その他"):
    """(カテゴリ, 金額) の並びから、金額合計が最大のカテゴリを返す。"""
    sums = defaultdict(int)
    for cat, amount in items:
        if cat:
            sums[cat] += amount
    if not sums:
        return fallback
    return max(sums.items(), key=lambda kv: kv[1])[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="更新せず内容だけ表示")
    args = ap.parse_args()

    if not os.path.exists(KEY_PATH):
        print(f"サービスアカウント鍵がありません: {KEY_PATH}")
        return 1
    creds = service_account.Credentials.from_service_account_file(KEY_PATH)
    db = firestore.Client(project=PROJECT_ID, credentials=creds)
    coll = db.collection("households").document(HID).collection("transactions")

    # 差額調整の行を集める。
    adj_docs = []
    for name in ADJ_NAMES:
        adj_docs.extend(coll.where("description", "==", name).stream())
    print(f"差額調整の行: {len(adj_docs)}件")

    # レシートごとの品目をまとめて引く（同じレシートは1回だけ）。
    members_cache = {}
    fixed = 0
    for d in adj_docs:
        data = d.to_dict() or {}
        rid = data.get("receiptId")
        if not rid:
            continue
        if rid not in members_cache:
            members_cache[rid] = [
                m.to_dict() or {} for m in coll.where("receiptId", "==", rid).stream()
            ]
        members = members_cache[rid]
        cat = dominant_category(
            (m.get("categoryMajor", ""), int(m.get("amount", 0)))
            for m in members
            if m.get("description") not in ADJ_NAMES
        )
        now = data.get("categoryMajor", "")
        if cat == now:
            continue
        store = data.get("store") or "(店名なし)"
        print(f"  {data.get('date')} {store} {data.get('description')} "
              f"¥{data.get('amount')}  {now} → {cat}")
        if not args.dry_run:
            d.reference.set({"categoryMajor": cat, "categorySub": ""}, merge=True)
        fixed += 1

    verb = "直せる" if args.dry_run else "直した"
    print(f"{verb}件数: {fixed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
