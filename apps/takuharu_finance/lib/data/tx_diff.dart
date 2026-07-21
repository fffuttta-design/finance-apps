import 'package:finance_core/finance_core.dart' as core;

import '../utils/format.dart';
import 'household_service.dart';

/// 変更点として見る項目。
/// レシートまとめ編集では「レシート全体に効く項目（[kTxCommonFields]）」と
/// 「品目ごとの項目（[kTxItemFields]）」を分けて出すために使う。
enum TxField { amount, description, category, date, payment, store, paidBy, personalFor }

/// レシート全体に効く項目（1枚につき1回だけ出す）。
const Set<TxField> kTxCommonFields = {
  TxField.date,
  TxField.payment,
  TxField.store,
  TxField.paidBy,
};

/// 品目ごとに違いうる項目。
const Set<TxField> kTxItemFields = {
  TxField.amount,
  TxField.description,
  TxField.category,
  TxField.personalFor,
};

/// 取引の「編集前 → 編集後」を、人が読める変更点の並びにする。
///
/// たくはるカレンダーの「〇〇が予定を変更しました（時刻・場所）」と同じ考え方で、
/// 明細を直したときにチャットへ残す変更履歴の材料に使う。
/// 変わっていない項目は含めない（＝空リストなら「実質なにも変わっていない」）。
List<String> txDiff(core.Transaction before, core.Transaction after,
    {Set<TxField>? fields}) {
  final out = <String>[];
  void add(TxField f, String label, String a, String b) {
    if (fields != null && !fields.contains(f)) return;
    if (a == b) return;
    out.add('$label $a → $b');
  }

  add(TxField.amount, '金額', formatYen(before.amount), formatYen(after.amount));
  add(TxField.description, '品名', _orDash(before.description),
      _orDash(after.description));
  add(TxField.category, 'カテゴリ', _orDash(before.category.major),
      _orDash(after.category.major));
  add(TxField.date, '日付', _date(before.date), _date(after.date));
  add(TxField.payment, '支払い', _orDash(before.paymentMethod),
      _orDash(after.paymentMethod));
  add(TxField.store, 'お店', _orDash(before.store), _orDash(after.store));
  add(TxField.paidBy, '払った人', _who(before.paidBy), _who(after.paidBy));
  add(TxField.personalFor, '個人わく', _who(before.personalFor),
      _who(after.personalFor));
  return out;
}

/// 変更点リストを1本のチャット文にする。変更が無ければ null（＝投稿しない）。
///
/// [what] は「記録」「レシート」など、直した対象の呼び名。
String? txChangeLogText(String actorName, String what, List<String> changes) {
  if (changes.isEmpty) return null;
  return '$actorNameが$whatを直しました\n${changes.join('\n')}';
}

/// uid を表示名にする（世帯メンバー名）。ログの「〇〇が」の部分。
String txActorName(String uid) =>
    HouseholdService.instance.memberNames[uid] ?? 'だれか';

/// 品目1件の見出し（変更履歴の行頭に付ける短い名前）。
String txItemLabel(core.Transaction t) =>
    t.description.trim().isEmpty ? t.category.major : t.description.trim();

String _orDash(String? s) =>
    (s == null || s.trim().isEmpty) ? '（なし）' : s.trim();

String _date(DateTime d) => '${d.month}/${d.day}';

/// uid を表示名にする（未設定なら「なし」）。個人わく・払った人の表示用。
String _who(String? uid) {
  if (uid == null || uid.isEmpty) return 'なし';
  return HouseholdService.instance.memberNames[uid] ?? 'あいて';
}
