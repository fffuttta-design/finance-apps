r"""復元不能になった領収書リンクを「領収書なし」に戻す一回きりのスクリプト。

対象（2026-07-15 調査で確定）:
    2026-06-05 ファミマ 680円 を品目ごとに分けた3件。
    証憑ファイル `1KKEn54-mkA2pBcYEoMz0GPYcKd_ZdeCe` は 2026-06-05 12:32 に
    正常にアップロードされた（webViewLink が `?usp=drivesdk` 形式＝API応答）が、
    その後 Drive 上で削除され、**ゴミ箱の30日自動削除で完全消滅**した。
    fffuttta / contact@ 両方の full-drive トークンでゴミ箱まで探して不在を確認済み。
    アプリ・BOTともに Drive ファイルを削除するコードは存在しない（＝アプリのバグではない）。

やること:
    receiptUrl を null、receiptSaved を False にする（＝開けないのに「保存済み」と
    出る状態の解消）。**receiptId は残す**＝同じレシートの3品を明細で1行に
    まとめる表示（v1.0.528〜）に使っているため。

実行（VPSで。firebase-admin鍵 futa-finance-admin.json のある場所）:
    scp scripts/clear_dead_receipt_links.py root@160.251.137.175:/tmp/
    ssh root@160.251.137.175 "cd /opt/bots/FutaHisho && .venv/bin/python /tmp/clear_dead_receipt_links.py"
"""
import sys

sys.path.insert(0, "/opt/bots/FutaHisho")
import config  # noqa: E402
from core import futafinance as ff  # noqa: E402

TXS = ["1780630347702272-0", "1780630347702304-1", "1780630347702313-2"]
DEAD = "1KKEn54-mkA2pBcYEoMz0GPYcKd_ZdeCe"

db = ff._client()
uid = config.FUTAFINANCE_UID
for t in TXS:
    ref = db.document(f"users/{uid}/transactions/{t}")
    d = ref.get().to_dict() or {}
    # 安全弁: 消す対象が本当に例の死んだリンクのときだけ触る
    if DEAD not in (d.get("receiptUrl") or ""):
        print(f"  [skip] {t}: 対象のリンクではない -> {d.get('receiptUrl')}")
        continue
    ref.update({"receiptUrl": None, "receiptSaved": False})
    print(f"  OK {t}: {d.get('description')} {d.get('amount')}円 -> 領収書なし"
          f"（receiptId={d.get('receiptId')} は保持）")
print("完了")
