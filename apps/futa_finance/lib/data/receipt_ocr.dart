/// レシート記録ポップアップの「まとめて1件 / 品目ごと」切替時に
/// Navigator.pop へ渡すセンチネル値。フロー側がこれを受けてもう片方を開く。
const String kReceiptSwitchMode = '__switch_record_mode__';

/// レシートの1品目（内訳）。
class ReceiptItem {
  final String name;
  final int price;
  const ReceiptItem({required this.name, required this.price});
}

/// レシートOCRの解析結果。
///
/// 解析は [ReceiptOcrCloud]（Gemini）で行う。
/// 旧・端末内OCR（Google ML Kit）は廃止済み。
class ReceiptOcrResult {
  final String rawText;
  final int? amount;
  final DateTime? date;
  final String? storeName;

  /// 内訳（品目）の要約。備考にプリフィルする（クラウド版で抽出）。
  final String? memo;

  /// 構造化した品目一覧（クラウド版で抽出）。品目ごとの複数記録に使う。
  final List<ReceiptItem>? items;

  /// 会計科目の推定（素の名前。例: "消耗品費"）。カテゴリ自動選択に使う。
  final String? categoryGuess;

  const ReceiptOcrResult({
    required this.rawText,
    this.amount,
    this.date,
    this.storeName,
    this.memo,
    this.items,
    this.categoryGuess,
  });
}
