import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// クレカCSV取り込みプレビューの1行ぶんの下書き。
class CardImportDraftRow {
  final String? dateIso; // "YYYY-MM-DD"（不明は null）
  final String name; // 取引内容（編集後の店名）
  final int amount; // 金額（円）
  final String major; // 会計科目（大）
  final String sub; // 会計科目（小）
  final bool excluded; // 取り込みから除外

  const CardImportDraftRow({
    required this.dateIso,
    required this.name,
    required this.amount,
    required this.major,
    required this.sub,
    required this.excluded,
  });

  Map<String, dynamic> toJson() => {
        'date': dateIso,
        'name': name,
        'amount': amount,
        'major': major,
        'sub': sub,
        'excluded': excluded,
      };

  factory CardImportDraftRow.fromJson(Map<String, dynamic> j) =>
      CardImportDraftRow(
        dateIso: j['date'] as String?,
        name: j['name'] as String? ?? '',
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        major: j['major'] as String? ?? '',
        sub: j['sub'] as String? ?? '',
        excluded: j['excluded'] as bool? ?? false,
      );
}

/// クレカCSV取り込みの下書き（カード×対象月ごと）。
class CardImportDraft {
  final String card;
  final String ym; // "YYYY-MM"
  final List<CardImportDraftRow> rows;
  final String savedAtIso;

  const CardImportDraft({
    required this.card,
    required this.ym,
    required this.rows,
    required this.savedAtIso,
  });

  String toJsonString() => jsonEncode({
        'card': card,
        'ym': ym,
        'rows': rows.map((r) => r.toJson()).toList(),
        'savedAt': savedAtIso,
      });

  factory CardImportDraft.fromJsonString(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return CardImportDraft(
      card: j['card'] as String? ?? '',
      ym: j['ym'] as String? ?? '',
      rows: ((j['rows'] as List?) ?? [])
          .map((e) => CardImportDraftRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      savedAtIso: j['savedAt'] as String? ?? '',
    );
  }
}

/// クレカ取り込み下書きの保存先（端末ローカル＝SharedPreferences）。
/// 下書きは編集途中の一時データなので、まずは端末内に保持する。
class CardImportDraftRepository {
  CardImportDraftRepository._();
  static final CardImportDraftRepository instance =
      CardImportDraftRepository._();

  String _key(String card, String ym) =>
      'futa.${AppModeManager.instance.current.keyPrefix}.card_import_draft.$card.$ym';

  Future<void> save(CardImportDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(draft.card, draft.ym), draft.toJsonString());
  }

  Future<CardImportDraft?> load(String card, String ym) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(card, ym));
    if (raw == null) return null;
    try {
      return CardImportDraft.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool> exists(String card, String ym) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key(card, ym));
  }

  Future<void> delete(String card, String ym) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(card, ym));
  }
}
