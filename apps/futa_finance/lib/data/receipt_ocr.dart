import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// レシートOCRの解析結果。
class ReceiptOcrResult {
  final String rawText;
  final int? amount;
  final DateTime? date;
  final String? storeName;

  const ReceiptOcrResult({
    required this.rawText,
    this.amount,
    this.date,
    this.storeName,
  });
}

/// レシート撮影 → 端末内OCR（Google ML Kit・日本語）→ 金額/日付/店名を推定。
/// Android 専用（ML Kit は Web では動作しない）。
class ReceiptOcr {
  ReceiptOcr._();
  static final ReceiptOcr instance = ReceiptOcr._();

  /// 画像を選択（カメラ/ギャラリー）してOCL解析。キャンセル時は null。
  Future<ReceiptOcrResult?> captureAndRecognize(
      {required ImageSource source}) async {
    final picker = ImagePicker();
    final xfile =
        await picker.pickImage(source: source, imageQuality: 90);
    if (xfile == null) return null;

    final input = InputImage.fromFilePath(xfile.path);
    final recognizer =
        TextRecognizer(script: TextRecognitionScript.japanese);
    try {
      final recognized = await recognizer.processImage(input);
      return _parse(recognized.text);
    } finally {
      await recognizer.close();
    }
  }

  /// OCRテキストから金額・日付・店名を推定。
  ReceiptOcrResult _parse(String text) {
    final lines = text.split('\n');
    // 金額として拾ってはいけない行（ID・電話・コード・ポイント・釣り等）。
    bool isExcluded(String l) =>
        l.contains('登録番号') ||
        l.contains('電話') ||
        l.contains('TEL') ||
        l.contains('コード') ||
        l.contains('会員') ||
        l.contains('番号') ||
        l.contains('ポイント') ||
        l.contains('預') ||
        l.contains('おつり') ||
        l.contains('お釣') ||
        l.contains('釣') ||
        l.contains('有効期限');

    // ¥ / \ / ￥ が付いた数字だけを金額候補にする（店コードや電話番号の誤検出を防ぐ）。
    final yenRe = RegExp(r'[¥\\￥]\s?([0-9][0-9,]{0,9})');
    // フォールバック用: カンマ区切りの数字（1,065 など。3桁以上の金額っぽいもの）。
    final commaRe = RegExp(r'([0-9]{1,3}(?:,[0-9]{3})+)');

    int? maxYen; // ¥付きの最大額
    int? totalLine; // 「合計」行の額
    int? maxComma; // フォールバック
    for (final line in lines) {
      if (isExcluded(line)) continue;
      final isTotal = line.contains('合計') ||
          line.contains('合 計') ||
          line.contains('合計金額') ||
          line.contains('お会計') ||
          line.contains('お買上') ||
          line.contains('買上') ||
          line.toLowerCase().contains('total');
      for (final m in yenRe.allMatches(line)) {
        final v = int.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v == null || v < 10 || v > 100000000) continue;
        if (maxYen == null || v > maxYen) maxYen = v;
        if (isTotal && (totalLine == null || v > totalLine)) totalLine = v;
      }
      for (final m in commaRe.allMatches(line)) {
        final v = int.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v == null || v < 100 || v > 100000000) continue;
        if (maxComma == null || v > maxComma) maxComma = v;
      }
    }
    // 合計行の¥ > ¥付き最大 > カンマ数字最大 の優先で決定。
    final amount = totalLine ?? maxYen ?? maxComma;

    // 店名: 最初の意味のある行（数字だけ/記号だけは除外）。
    String? store;
    for (final line in lines) {
      final t = line.trim();
      if (t.length < 2) continue;
      if (RegExp(r'^[0-9,\.\-/¥\s]+$').hasMatch(t)) continue;
      store = t;
      break;
    }

    return ReceiptOcrResult(
      rawText: text,
      amount: amount,
      date: _parseDate(text),
      storeName: store,
    );
  }

  DateTime? _parseDate(String text) {
    // 2026/06/03, 2026年6月3日, 2026-06-03, 2026.06.03 等。
    final re = RegExp(r'(20\d{2})[/年\-\.](\d{1,2})[/月\-\.](\d{1,2})');
    final m = re.firstMatch(text);
    if (m != null) {
      final y = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final d = int.parse(m.group(3)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        return DateTime(y, mo, d);
      }
    }
    return null;
  }
}
