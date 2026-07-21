# -*- coding: utf-8 -*-
"""たくはるファイナンス：差額調整行を「個人の食費わく」に按分して割り当てる。

「消費税・調整」「値引き・調整」の行は個人わく(personalFor)が空のまま作られていたため、
個人わくで買った品目の消費税ぶんだけが共用財布から出ていた。
このスクリプトは、同じレシートの品目の持ち主（personalFor）の金額比で調整額を按分し、
既存の調整行に personalFor を書き戻す。

按分の結果2つ以上のバケツ（例: 共用ぶん＋たくの個人わくぶん）に割れる場合、
行を増やすと相手に「記録したよ」通知が飛んでしまうため、**新しい行は作らない**。
その場合は最大バケツの持ち主に寄せ、対象を一覧表示する（--dry-run で事前に確認できる）。

使い方:
    py scripts/repair_takuharu_adjustment_personal.py --dry-run   # 確認だけ
    py scripts/repair_takuharu_adjustment_personal.py             # 実行

必要なもの:
    C:\\dev\\_secrets\\takuharu-finance-sa.json （takuharu-finance のサービスアカウント鍵）
"""
import argparse
import os
import sys
from collections import defaultdict

from google.cloud import firestore
from google.oauth2 import service_account

# Windowsのcp932で落ちないよう標準出力をUTF-8に固定する。
sys.stdout.reconfigure(encoding="utf-8")

KEY_PATH = r"C:\dev\_secrets\takuharu-finance-sa.json"
PROJECT_ID = "takuharu-finance"
HID = "TAKUHARU"
ADJ_NAMES = ("消費税・調整", "値引き・調整")


def split_by_owner(members, adj_amount):
    """品目の持ち主(personalFor)ごとの金額比で [adj_amount] を按分する。

    戻り値: {owner(uid または None=共用): 按分額}。端数は最大バケツへ寄せる。
    """
    weights = defaultdict(int)
    for m in members:
        if m.get("description") in ADJ_NAMES:
            continue
        owner = m.get("personalFor") or None
        weights[owner] += int(m.get("amount") or 0)
    total = sum(weights.values())
    if total == 0:
        return {}
    out = {}
    for owner, w in weights.items():
        out[owner] = int(adj_amount * w / total)
    # 端数（切り捨てぶん）は一番大きいバケツへ。
    biggest = max(weights.items(), key=lambda kv: kv[1])[0]
    out[biggest] += adj_amount - sum(out.values())
    return {k: v for k, v in out.items() if v != 0}


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

    names = (db.document(f"households/{HID}").get().to_dict() or {}).get(
        "memberNames", {}
    )

    adj_docs = []
    for name in ADJ_NAMES:
        adj_docs.extend(coll.where("description", "==", name).stream())
    print(f"差額調整の行: {len(adj_docs)}件")

    members_cache = {}
    fixed = 0
    mixed = 0
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
        amount = int(data.get("amount") or 0)
        buckets = split_by_owner(members, amount)
        if not buckets:
            continue
        # 一番大きいバケツの持ち主に寄せる（行は増やさない＝通知を飛ばさない）。
        owner = max(buckets.items(), key=lambda kv: abs(kv[1]))[0]
        now = data.get("personalFor") or None
        if owner == now:
            continue
        store = data.get("store") or "(店名なし)"
        label = names.get(owner, "共用") if owner else "共用"
        before = names.get(now, "共用") if now else "共用"
        note = ""
        if len(buckets) > 1:
            mixed += 1
            note = "  ※共用と個人が混在（一番大きいほうに寄せた）"
        print(
            f"  {data.get('date')} {store} {data.get('description')} "
            f"¥{amount}  個人わく {before} → {label}{note}"
        )
        if not args.dry_run:
            d.reference.set(
                {"personalFor": owner} if owner else {"personalFor": None}, merge=True
            )
        fixed += 1

    verb = "直せる" if args.dry_run else "直した"
    print(f"{verb}件数: {fixed}（うち共用と個人の混在: {mixed}件）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
