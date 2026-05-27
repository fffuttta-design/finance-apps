#!/usr/bin/env python3
"""
FutaFinance のバックアップ JSON を生成する（差分含む最新スナップショット）。

- 事業モード: 取引、固定費、カテゴリ、カード、チェックリスト
- 個人モード: 取引、固定費、カテゴリ、カード、チェックリスト

出力先:
  H:\\マイドライブ\\ツール開発\\FutaFinance\\
  ├── futa-finance-data.json                   ← 常にここが最新（取り込みターゲット）
  └── archive\\data-{timestamp}-{note}.json    ← 過去スナップショット

実行時の挙動:
  1. 既存の futa-finance-*.json があれば archive\\ にタイムスタンプ付きで退避
  2. 新規に futa-finance-data.json を生成

使い方:
  python generate_initial_backup.py
  python generate_initial_backup.py --note "オリコ/JCBアイコン更新"
"""
import argparse
import json
import os
import shutil
import time
from datetime import datetime

# ───────────────────────────────────────────
# ID 生成（microseconds + counter で確実にユニーク）
# ───────────────────────────────────────────
_id_counter = 0
_id_base = int(time.time() * 1_000_000)


def gen_id(prefix: str = "") -> str:
    global _id_counter
    _id_counter += 1
    return f"{prefix}{_id_base + _id_counter}"


# ───────────────────────────────────────────
# 共通ヘルパー
# ───────────────────────────────────────────
def iso_date(y, m, d):
    """Transaction.date 用 ISO8601 (00:00:00 JST扱い、Z無し)"""
    return f"{y:04d}-{m:02d}-{d:02d}T00:00:00.000"


def fav(domain):
    return f"https://www.google.com/s2/favicons?domain={domain}&sz=128"


def transaction(date_str, major, sub, desc, amount, payment,
                 type_="expense", memo=None, original_currency=None,
                 original_amount=None):
    return {
        "id": gen_id("tx-"),
        "date": date_str,
        "type": type_,
        "categoryMajor": major,
        "categorySub": sub,
        "paymentMethod": payment,
        "description": desc,
        "amount": amount,
        "receiptUrl": None,
        "memo": memo,
        "incomeSourceId": None,
        "originalCurrency": original_currency,
        "originalAmount": original_amount,
    }


def subscription(name, amount, cycle, amount_type, payment, category,
                 icon_url=None, billing_day=None, memo=None,
                 next_billing_date=None):
    return {
        "id": gen_id("sub-"),
        "name": name,
        "amount": amount,
        "cycle": cycle,  # "monthly" | "annually"
        "amountType": amount_type,  # "fixed" | "variable"
        "billingDay": billing_day,
        "nextBillingDate": next_billing_date,
        "paymentMethod": payment,
        "memo": memo,
        "iconUrl": icon_url,
        "category": category,
    }


def checklist_item(name, url=None, memo=None, children=None, link_type=None):
    return {
        "id": gen_id("ck-"),
        "name": name,
        "url": url,
        "memo": memo,
        "children": children or [],
        "linkType": link_type,
    }


# ═══════════════════════════════════════════════════════════════
# 事業モード（business / b）
# ═══════════════════════════════════════════════════════════════

# ── カテゴリ（businessDefaults と一致）
business_categories = {
    "majors": [
        {"name": "固定費(定額)", "iconKey": "📅",
         "subs": ["通信費", "ソフトウェア料金", "ライセンス料金", "顧問経費", "賃料", "コンサル・研修費"],
         "subIcons": None},
        {"name": "固定費(変動)", "iconKey": "💸",
         "subs": ["通信費", "ソフトウェア料金", "ライセンス料金", "顧問経費", "賃料", "コンサル・研修費"],
         "subIcons": None},
        {"name": "消耗品費", "iconKey": "📦",
         "subs": ["機材", "資材", "装飾品", "ソフトウェア"],
         "subIcons": None},
        {"name": "旅費交通費", "iconKey": "🚗", "subs": ["タクシー", "新幹線"],
         "subIcons": None},
        {"name": "交際費", "iconKey": "🍴", "subs": ["会食"],
         "subIcons": None},
        {"name": "研修費", "iconKey": "🎓", "subs": ["セミナー", "コンサル"],
         "subIcons": None},
        {"name": "会議費", "iconKey": "💼",
         "subs": ["セルフカフェ", "コワーキングスペース", "軽食", "会食"],
         "subIcons": None},
        {"name": "雑費", "iconKey": "🏷️", "subs": ["営業用等", "新聞図書費"],
         "subIcons": None},
    ]
}

# ── 銀行口座（事業用）+ カード（三井住友メイン）
# ロゴURLはユーザー指定（gstatic/typeshukatsu）。
B_GMOAOZORA_ICON = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTNPayB53fbtJRfNDHDMtHzCS-teEeUvpaSsw&s"
B_SBI_ICON = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRR8VnOMXkDO5mRRZZsZck9z4W6vSenaHJW5w&s"
B_SMBC_BANK_ICON = "https://typeshukatsu.jp/image?table=m_company&column=logo_image&id=1136"

business_payments = {
    "bankAccounts": [
        {
            "id": "b-acc-gmoaozora",
            "name": "GMOあおぞらネット銀行",
            "last4": None,
            "startingBalance": None,
            "currentBalance": None,
            "accountType": "bank",
            "iconUrl": B_GMOAOZORA_ICON,
            "memo": "事業用",
        },
        {
            "id": "b-acc-sbi",
            "name": "住信SBIネット銀行",
            "last4": None,
            "startingBalance": None,
            "currentBalance": None,
            "accountType": "bank",
            "iconUrl": B_SBI_ICON,
            "memo": "事業用",
        },
        {
            "id": "b-acc-smbc-bank",
            "name": "三井住友銀行",
            "last4": None,
            "startingBalance": None,
            "currentBalance": None,
            "accountType": "bank",
            "iconUrl": B_SMBC_BANK_ICON,
            "memo": "事業用",
        },
    ],
    "creditCards": [
        {
            "id": "card-smbc",
            "name": "三井住友カード",
            "last4": None,
            "brandColorValue": 0xFF1A237E,
            "currentBalance": None,
            "iconUrl": fav("smbc-card.com"),
            "memo": "事業用メインカード",
        }
    ],
}

# ── 取引（32件）。アプリ表示は「N.カテゴリ名」形式。
SMBC = "三井住友カード"
BANK_FUR = "銀行引落"

business_transactions = [
    # 5月1日: 固定費(定額) 7件
    transaction(iso_date(2026, 5, 1), "0.固定費(定額)", "コンサル・研修費",
                "Chilol(YouTubeコミュニティ)", 980, SMBC),
    transaction(iso_date(2026, 5, 1), "0.固定費(定額)", "ソフトウェア料金",
                "gyazo", 590, SMBC),
    transaction(iso_date(2026, 5, 1), "0.固定費(定額)", "ソフトウェア料金",
                "GoogleWorkSpace(ドメイン・サーバー)", 2090, SMBC),
    transaction(iso_date(2026, 5, 1), "0.固定費(定額)", "ソフトウェア料金",
                "gigafile便:スタンダートプラン", 198, SMBC),
    transaction(iso_date(2026, 5, 1), "0.固定費(定額)", "ソフトウェア料金",
                "kndle unlimited", 980, SMBC),
    transaction(iso_date(2026, 5, 1), "0.固定費(定額)", "顧問経費",
                "VS税務顧問", 38500, BANK_FUR),
    transaction(iso_date(2026, 5, 1), "0.固定費(定額)", "通信費",
                "Wi-Fi料金・コミュファ光", 6820, SMBC),
    # 5月1日: 固定費(変動) 3件
    transaction(iso_date(2026, 5, 1), "1.固定費(変動)", "ソフトウェア料金",
                "ChatGPT", 3583, SMBC),
    transaction(iso_date(2026, 5, 1), "1.固定費(変動)", "ソフトウェア料金",
                "Claude Pro", 3580, SMBC),
    transaction(iso_date(2026, 5, 1), "1.固定費(変動)", "通信費",
                "携帯料金・LINEモバイル", 6402, SMBC),
    # 5月6日: 消耗品費(Claude) 2件
    transaction(iso_date(2026, 5, 6), "2.消耗品費", "ソフトウェア",
                "Clade 5$", 898, SMBC),
    transaction(iso_date(2026, 5, 6), "2.消耗品費", "ソフトウェア",
                "Clade 5$", 898, SMBC),
    # 5月7日: 雑費
    transaction(iso_date(2026, 5, 7), "7.雑費", "新聞図書費",
                "鬼速PDCA", 1267, SMBC),
    # 5月10日: Claude 2件
    transaction(iso_date(2026, 5, 10), "2.消耗品費", "ソフトウェア",
                "Clade 5$", 895, SMBC),
    transaction(iso_date(2026, 5, 10), "2.消耗品費", "ソフトウェア",
                "Clade 5$", 895, SMBC),
    # 5月11日: Claude 4件 + 雑費 1件
    transaction(iso_date(2026, 5, 11), "2.消耗品費", "ソフトウェア",
                "Clade 10$", 1790, SMBC),
    transaction(iso_date(2026, 5, 11), "2.消耗品費", "ソフトウェア",
                "Clade 5$", 895, SMBC),
    transaction(iso_date(2026, 5, 11), "2.消耗品費", "ソフトウェア",
                "Clade 5$", 895, SMBC),
    transaction(iso_date(2026, 5, 11), "2.消耗品費", "ソフトウェア",
                "Clade 7$", 1253, SMBC),
    transaction(iso_date(2026, 5, 11), "7.雑費", "新聞図書費",
                "2025-2026年版 みんなが欲しかった！ FPの教科書 3級",
                1472, SMBC),
    # 5月12日: Claude 2件 + 雑費 1件
    transaction(iso_date(2026, 5, 12), "2.消耗品費", "ソフトウェア",
                "Clade 5$", 895, SMBC),
    transaction(iso_date(2026, 5, 12), "2.消耗品費", "ソフトウェア",
                "Clade 5$", 897, SMBC),
    transaction(iso_date(2026, 5, 12), "7.雑費", "新聞図書費",
                "起業家 (幻冬舎文庫)", 644, SMBC),
    # 5月13日: Clade 50$
    transaction(iso_date(2026, 5, 13), "2.消耗品費", "ソフトウェア",
                "Clade 50$", 8074, SMBC),
    # 5月20日: 機材/資材/雑費/Claude USD
    transaction(iso_date(2026, 5, 20), "2.消耗品費", "機材",
                "ハンディ扇風機", 2850, SMBC),
    transaction(iso_date(2026, 5, 20), "2.消耗品費", "資材",
                "椅子クッション", 1330, SMBC),
    transaction(iso_date(2026, 5, 20), "7.雑費", "新聞図書費",
                "成長以外すべて死", 1339, SMBC),
    # Claude Code Max5$プラン: 94.78 USD → 150 円/USDで概算 14217円
    transaction(iso_date(2026, 5, 20), "2.消耗品費", "ソフトウェア",
                "Claude Code Max5$プラン", 14217, SMBC,
                memo="原通貨: USD 94.78（為替150円/USD仮定）",
                original_currency="USD", original_amount=94.78),
    # 5月21日: 会議費
    transaction(iso_date(2026, 5, 21), "6.会議費", "セルフカフェ",
                "1時間予約", 359, SMBC),
    # 5月22日: 交際費
    transaction(iso_date(2026, 5, 22), "4.交際費", "会食",
                "食い物やわん", 8591, SMBC),
    # 5月24日: 資材
    transaction(iso_date(2026, 5, 24), "2.消耗品費", "資材",
                "ガジェポーチ＆時計", 4791, SMBC),
    # 5月26日: 資材
    transaction(iso_date(2026, 5, 26), "2.消耗品費", "資材",
                "タブケース＆カバー、スタンド", 4815, SMBC),
]

# ── 固定費（10件）
CHILOL_ICON = "https://static.camp-fire.jp/uploads/project_version/image/1389478/2b58f368-1d31-46ed-832f-2f9af7856b19.jpeg"
VSG_ICON = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTCPzLNB6t9-ev9QAOwgvXacn3XN1SzzOkCaw&s"
LINEMOBILE_ICON = "https://mobile.line.me/img/support/top_icon_acount_03.png"

business_subscriptions = {
    "subscriptions": [
        subscription("Chilol(YouTubeコミュニティ)", 980, "monthly", "fixed",
                     SMBC, "コンサル・研修", icon_url=CHILOL_ICON),
        subscription("gyazo", 590, "monthly", "fixed", SMBC, "ソフトウェア",
                     icon_url=fav("gyazo.com")),
        subscription("Google Workspace", 2090, "monthly", "fixed", SMBC,
                     "ソフトウェア", icon_url=fav("workspace.google.com")),
        subscription("gigafile便", 198, "monthly", "fixed", SMBC,
                     "ソフトウェア", icon_url=fav("gigafile.nu")),
        subscription("Kindle Unlimited", 980, "monthly", "fixed", SMBC,
                     "ソフトウェア", icon_url=fav("amazon.co.jp")),
        subscription("VS税務顧問", 38500, "monthly", "fixed", BANK_FUR,
                     "顧問・税務", icon_url=VSG_ICON),
        subscription("Wi-Fi料金・コミュファ光", 6820, "monthly", "fixed",
                     SMBC, "通信", icon_url=fav("commufa.jp")),
        subscription("ChatGPT", 3583, "monthly", "variable", SMBC,
                     "ソフトウェア", icon_url=fav("chatgpt.com")),
        subscription("Claude Pro", 3580, "monthly", "variable", SMBC,
                     "ソフトウェア", icon_url=fav("claude.ai")),
        subscription("携帯料金・LINEモバイル", 6402, "monthly", "variable",
                     SMBC, "通信", icon_url=LINEMOBILE_ICON),
    ]
}

# ── チェックリスト（事業用デフォルト）
# 「銀行口座の入出金を確認」「クレカ使用履歴」は linkType で動的展開。
# 表示時に登録されている口座/クレカが子項目として自動的に並ぶ。
business_checklist = {
    "items": [
        checklist_item("銀行口座の入出金を確認",
                       link_type="bank_accounts"),
        checklist_item("クレカ使用履歴の確認",
                       link_type="credit_cards"),
        checklist_item("源泉徴収の確認・記録",
                       memo="クライアントから引かれた源泉額を集計"),
        checklist_item("請求書の発行漏れ確認"),
        checklist_item("入金未済の請求書の追跡"),
    ]
}

# ═══════════════════════════════════════════════════════════════
# 個人モード（personal / p）
# ═══════════════════════════════════════════════════════════════

# ── カテゴリ（ユーザー提示の表記揺れに合わせて生成）
personal_categories = {
    "majors": [
        {"name": "固定費", "iconKey": "🏠",
         "subs": ["家賃", "自己投資", "経費", "娯楽"],
         "subIcons": None},
        {"name": "食費", "iconKey": "🍔",
         "subs": ["UberEats・外食", "飲み物", "健康投資", "筋トレ投資", "おやつ", "自販機"],
         "subIcons": None},
        {"name": "生活維持費", "iconKey": "🧴",
         "subs": ["生活必需品", "生活便利品"],
         "subIcons": None},
        {"name": "交際費", "iconKey": "🎉", "subs": ["食事", "奢り"],
         "subIcons": None},
        {"name": "美容/衣服", "iconKey": "👗",
         "subs": ["スキンケア", "美容院", "その他美容品", "トップス系",
                  "ボトムス系", "カバン系", "アクセ系", "靴系", "下着/靴下系"],
         "subIcons": None},
        {"name": "病院/薬", "iconKey": "💊", "subs": ["歯医者", "内科"],
         "subIcons": None},
        {"name": "交通費", "iconKey": "🚗",
         "subs": ["Suicaチャージ", "タクシー", "新幹線"],
         "subIcons": None},
        {"name": "自己投資・経費", "iconKey": "📚",
         "subs": ["書籍", "雑費", "筋トレ", "外見改善", "アプリ", "その他"],
         "subIcons": None},
        {"name": "趣味", "iconKey": "🎮", "subs": ["その他"],
         "subIcons": None},
        {"name": "特別出費", "iconKey": "⭐",
         "subs": ["R活動経費", "裁判費用", "高額投資"],
         "subIcons": None},
    ]
}

# ── 個人モードの資金口座（銀行/電子マネー）+ カード4枚
def bank(id_, name, account_type, icon_url, memo=None):
    """資金口座（RegisteredBankAccount）の JSON 辞書を生成。"""
    return {
        "id": id_,
        "name": name,
        "last4": None,
        "startingBalance": None,
        "currentBalance": None,
        "accountType": account_type,  # "bank" | "cash" | "emoney"
        "iconUrl": icon_url,
        "memo": memo,
    }


personal_payments = {
    "bankAccounts": [
        bank("acc-shinsei", "新生銀行", "bank",
             fav("shinseibank.com")),
        bank("acc-gmoaozora", "GMOあおぞらネット銀行", "bank",
             fav("gmo-aozora.com")),
        bank("acc-yucho", "ゆうちょ銀行", "bank",
             "https://yt3.googleusercontent.com/ytc/AIdro_lYMcKofAw_eXIpo_DbmPizIsdXzyU8f9LEnDiMxyx-Zw=s900-c-k-c0x00ffffff-no-rj"),
        bank("acc-aeon", "イオン銀行", "bank",
             "https://www.aeonbank.co.jp/common/aeon_logo.png"),
        bank("acc-paypay", "PayPay", "emoney",
             fav("paypay.ne.jp")),
    ],
    "creditCards": [
        {
            "id": "card-orico",
            "name": "オリコカード",
            "last4": None,
            "brandColorValue": 0xFFE65100,
            "currentBalance": None,
            "iconUrl": "https://www.brand-yurai.net/logoimg/JXWtyRMNIbzPItiV.gif",
            "memo": None,
        },
        {
            "id": "card-rakuten",
            "name": "楽天カード",
            "last4": None,
            "brandColorValue": 0xFFD32F2F,
            "currentBalance": None,
            "iconUrl": fav("rakuten-card.co.jp"),
            "memo": None,
        },
        {
            "id": "card-aeon",
            "name": "イオンカード",
            "last4": None,
            "brandColorValue": 0xFFDB2777,
            "currentBalance": None,
            "iconUrl": fav("aeon.co.jp"),
            "memo": None,
        },
        {
            "id": "card-jcb",
            "name": "JCBカード",
            "last4": None,
            "brandColorValue": 0xFF1976D2,
            "currentBalance": None,
            "iconUrl": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/40/JCB_logo.svg/960px-JCB_logo.svg.png",
            "memo": None,
        },
    ],
}

# ── 取引（33件）。「クレカ」表記は全部オリコカードに変換
ORICO = "オリコカード"
CASH = "現金"

personal_transactions = [
    # 5月1日: 固定費 5件 + 食費 1件 + 病院/薬 3件 + 交通費 1件
    transaction(iso_date(2026, 5, 1), "0.固定費", "自己投資",
                "あすけん", 480, ORICO),
    transaction(iso_date(2026, 5, 1), "0.固定費", "自己投資",
                "Auns Gym", 6578, ORICO),
    transaction(iso_date(2026, 5, 1), "0.固定費", "経費",
                "GoogleOne", 290, ORICO),
    transaction(iso_date(2026, 5, 1), "0.固定費", "自己投資",
                "ASPI ジム(月2回プラン)", 17680, ORICO),
    transaction(iso_date(2026, 5, 1), "0.固定費", "娯楽",
                "AmazonPrime", 600, ORICO),
    transaction(iso_date(2026, 5, 1), "1.食費", "UberEats・外食",
                "吉野家", 1595, ORICO),
    transaction(iso_date(2026, 5, 1), "5.病院/薬", "内科",
                "風邪薬", 790, ORICO),
    transaction(iso_date(2026, 5, 1), "5.病院/薬", "内科",
                "病院薬", 795, ORICO),
    transaction(iso_date(2026, 5, 1), "5.病院/薬", "内科",
                "金山内科", 2550, ORICO),
    transaction(iso_date(2026, 5, 1), "6.交通費", "タクシー",
                "自宅→金山内科", 1100, ORICO),
    # 5月2日: 食費
    transaction(iso_date(2026, 5, 2), "1.食費", "UberEats・外食",
                "讃岐製麺", 1333, ORICO),
    # 5月4日: 自己投資・経費
    transaction(iso_date(2026, 5, 4), "7.自己投資・経費", "雑費",
                "マウスパッド", 720, ORICO),
    # 5月6日: 食費 2件
    transaction(iso_date(2026, 5, 6), "1.食費", "UberEats・外食",
                "讃岐製麺", 1408, ORICO),
    transaction(iso_date(2026, 5, 6), "1.食費", "UberEats・外食",
                "吉野家", 1595, ORICO),
    # 5月7日: 美容/衣服 1件 + 交通費 3件
    transaction(iso_date(2026, 5, 7), "4.美容/衣服", "美容院",
                "GOALD", 5500, ORICO),
    transaction(iso_date(2026, 5, 7), "6.交通費", "タクシー",
                "自宅→金山駅", 1000, ORICO),
    transaction(iso_date(2026, 5, 7), "6.交通費", "タクシー",
                "GOALD→金山駅", 1900, ORICO),
    transaction(iso_date(2026, 5, 7), "6.交通費", "Suicaチャージ",
                "入金(チャージ)額:1,000円", 1000, ORICO),
    # 5月8日: 筋トレ
    transaction(iso_date(2026, 5, 8), "7.自己投資・経費", "筋トレ",
                "ファミマ筋トレ飯", 2074, ORICO),
    # 5月9日: タクシー + 筋トレ + 交際費
    transaction(iso_date(2026, 5, 9), "6.交通費", "タクシー",
                "自宅→金山", 1000, ORICO),
    transaction(iso_date(2026, 5, 9), "7.自己投資・経費", "筋トレ",
                "トレーニングウェア", 7179, ORICO),
    transaction(iso_date(2026, 5, 9), "7.自己投資・経費", "筋トレ",
                "ファミマ筋トレ飯", 537, ORICO),
    transaction(iso_date(2026, 5, 9), "3.交際費", "食事",
                "次郎・牛煌・煙力", 12278, CASH),
    # 5月11日: 筋トレ
    transaction(iso_date(2026, 5, 11), "7.自己投資・経費", "筋トレ",
                "ファミマ筋トレ飯", 1136, ORICO),
    # 5月12日: 筋トレ
    transaction(iso_date(2026, 5, 12), "7.自己投資・経費", "筋トレ",
                "ファミマ筋トレ飯", 1959, ORICO),
    # 5月15日: タクシー
    transaction(iso_date(2026, 5, 15), "6.交通費", "タクシー",
                "自宅→VS", 2600, ORICO),
    # 5月16日: タクシー + 美容/衣服
    transaction(iso_date(2026, 5, 16), "6.交通費", "タクシー",
                "自宅→金山", 900, ORICO),
    transaction(iso_date(2026, 5, 16), "4.美容/衣服", "その他美容品",
                "レナトゥスクリニック麻酔", 2200, ORICO),
    # 5月19日: スキンケア
    transaction(iso_date(2026, 5, 19), "4.美容/衣服", "スキンケア",
                "乳液", 1100, ORICO),
    # 5月22日: 食費
    transaction(iso_date(2026, 5, 22), "1.食費", "UberEats・外食",
                "カフェ用昼飯", 635, ORICO),
    # 5月24日: 食費
    transaction(iso_date(2026, 5, 24), "1.食費", "UberEats・外食",
                "ローソン昼飯", 1670, ORICO),
    # 5月26日: 美容/衣服 + 食費
    transaction(iso_date(2026, 5, 26), "4.美容/衣服", "その他美容品",
                "DEMI DO シャンプー詰替え用", 4633, ORICO),
    transaction(iso_date(2026, 5, 26), "1.食費", "UberEats・外食",
                "ローソン昼飯", 1227, ORICO),
]

# ── 固定費（6件、家賃含む）
ASPI_ICON = "https://aspirest.com/cms/wp-content/uploads/2023/11/aspi_logo.jpg"
AUNS_ICON = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQRDHfvX1do0Rjz43dQDYDhYHK5uMvBXB0paA&s"

personal_subscriptions = {
    "subscriptions": [
        subscription("あすけん", 480, "monthly", "fixed", ORICO,
                     "自己投資", icon_url=fav("asken.jp")),
        subscription("Auns Gym", 6578, "monthly", "fixed", ORICO,
                     "自己投資", icon_url=AUNS_ICON),
        subscription("Google One", 290, "monthly", "fixed", ORICO,
                     "経費", icon_url=fav("one.google.com")),
        subscription("ASPIジム", 17680, "monthly", "fixed", ORICO,
                     "自己投資", icon_url=ASPI_ICON),
        subscription("Amazon Prime", 600, "monthly", "fixed", ORICO,
                     "娯楽", icon_url=fav("amazon.co.jp")),
        subscription("家賃", 105000, "monthly", "fixed", "振込",
                     "家賃", billing_day=10),
    ]
}

# ── チェックリスト（個人用、階層構造）
# 銀行口座/クレカは linkType で登録済みアイテムを動的展開。
personal_checklist = {
    "items": [
        checklist_item("クレジットカード明細の確認",
                       link_type="credit_cards"),
        checklist_item("銀行口座の入出金確認",
                       link_type="bank_accounts"),
        checklist_item("巡回サイト", children=[
            checklist_item("UberEats",
                           url="https://www.ubereats.com/jp"),
            checklist_item("Amazon",
                           url="https://www.amazon.co.jp/"),
            checklist_item("GO Taxi",
                           url="https://go.mo-t.com/"),
            checklist_item("モバイルSuica",
                           url="https://www.mobilesuica.com/"),
            checklist_item("自販機履歴",
                           memo="ジハンピ等"),
            checklist_item("Google Pay",
                           url="https://pay.google.com/"),
        ]),
        checklist_item("家賃の引落確認"),
    ]
}

# ═══════════════════════════════════════════════════════════════
# 出力（アーカイブ自動退避付き）
# ═══════════════════════════════════════════════════════════════

# ── 引数パース
parser = argparse.ArgumentParser(
    description="FutaFinance バックアップ生成（アーカイブ自動退避付き）")
parser.add_argument(
    "--note",
    required=True,
    help="バックアップの目的・概要（ファイル名と JSON 内 note に反映）。"
         "例: '個人モードに資金口座5つ追加'",
)
args = parser.parse_args()


def safe_tag(s: str) -> str:
    """ファイル名で安全な文字だけ残す（日本語OK、記号は最小限）。"""
    keep = []
    for ch in s:
        # 日本語は範囲リテラルでマッチさせず、文字種で判定
        if ch.isalnum():
            keep.append(ch)
        elif ch in "-_":
            keep.append(ch)
        elif "぀" <= ch <= "ゟ":  # ひらがな
            keep.append(ch)
        elif "゠" <= ch <= "ヿ":  # カタカナ
            keep.append(ch)
        elif "一" <= ch <= "鿿":  # 漢字
            keep.append(ch)
        else:
            keep.append("-")
    # 連続するハイフンを1個に圧縮
    s2 = "".join(keep)
    while "--" in s2:
        s2 = s2.replace("--", "-")
    return s2.strip("-")[:60] or "update"


backup = {
    "appVersion": "1.0.28",
    "exportedAt": datetime.now().isoformat(),
    "schema": 1,
    "note": args.note,
    "data": {
        "business": {
            "categories": business_categories,
            "payments": business_payments,
            "transactions": business_transactions,
            "subscriptions": business_subscriptions,
            "checklist": business_checklist,
        },
        "personal": {
            "categories": personal_categories,
            "payments": personal_payments,
            "transactions": personal_transactions,
            "subscriptions": personal_subscriptions,
            "checklist": personal_checklist,
        },
    },
}

# ── パス設定
output_dir = r"H:\マイドライブ\ツール開発\FutaFinance"
archive_dir = os.path.join(output_dir, "archive")
# ファイル名に概要(slug)を反映：取り込み時の取り違え防止
note_slug = safe_tag(args.note)
output_filename = f"futa-finance-data-{note_slug}.json"
output_path = os.path.join(output_dir, output_filename)

os.makedirs(output_dir, exist_ok=True)
os.makedirs(archive_dir, exist_ok=True)

# ── 既存 JSON をアーカイブに退避
archived = []
for name in os.listdir(output_dir):
    if not name.endswith(".json"):
        continue
    if not name.startswith("futa-finance-"):
        continue
    old_path = os.path.join(output_dir, name)
    if not os.path.isfile(old_path):
        continue
    # 更新時刻ベースのタイムスタンプ
    mtime = datetime.fromtimestamp(os.path.getmtime(old_path))
    stamp = mtime.strftime("%Y%m%d-%H%M")
    # 元のファイル名末尾をヒントに付ける
    tail = name.replace("futa-finance-", "").replace(".json", "")
    archive_name = f"data-{stamp}-{safe_tag(tail)}.json"
    archive_path = os.path.join(archive_dir, archive_name)
    # 同名があれば連番付与
    counter = 1
    while os.path.exists(archive_path):
        archive_path = os.path.join(
            archive_dir, f"data-{stamp}-{safe_tag(tail)}-{counter}.json"
        )
        counter += 1
    shutil.move(old_path, archive_path)
    archived.append((name, os.path.basename(archive_path)))

# ── 新規生成
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(backup, f, ensure_ascii=False, indent=2)

# ── サマリ表示
b_tx = len(business_transactions)
b_sub = len(business_subscriptions["subscriptions"])
p_tx = len(personal_transactions)
p_sub = len(personal_subscriptions["subscriptions"])
size_kb = os.path.getsize(output_path) / 1024

if archived:
    print("[archive] moved old files:")
    for src, dst in archived:
        print(f"  - {src} -> archive/{dst}")
print(f"[OK] export: {output_path}")
print(f"     note: {args.note}")
print(f"     size: {size_kb:.1f} KB")
print(f"     business: tx={b_tx}, subscriptions={b_sub}")
print(f"     personal: tx={p_tx}, subscriptions={p_sub}")
