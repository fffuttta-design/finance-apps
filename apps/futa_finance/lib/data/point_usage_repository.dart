import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ポイント払い（Vポイント・ファミペイ）の記録を読むリポジトリ。
///
/// 🔴 **取引(transactions)とは別コレクション＝収支・残高・月次スナップショット・PL の計算に
/// 一切入らない。** 本人方針（2026-09-11）＝本人はポイントを資産として持っていない
/// （買い物をすると勝手に貯まるもの）。資産に無い物を使っても資産は動かないので、
/// 収支に入れると会計が狂う。ここに残すのは「**何にポイントを使ったか＝どんな価値を
/// 手に入れたか**」の記録だけ。
///
/// 🔥 `amount` は **本来の値段**（ポイント数＝円相当）。**0円ではない。**
///    0円だと「いくらの価値の物を手に入れたか」が消えて、あとから何も読み取れなくなるため。
///
/// ⚠ 一部充当は**ここに来ない**。カード請求が出る買い物（例: 楽天で¥10,979のうち10,684pt充当
///    →請求¥295）は実際の出金があるので、従来どおり transactions に ¥295 で入る。
///    ここに来るのは「**カード請求が0＝全額ポイント**」のときだけ。
///
/// 読み取り元: `users/{uid}/point_usages/{id}`
/// 書き込み元: 二村秘書VPS `core/finance/ledger/futafinance.py: write_point_usages()`
///   Amazon注文メールのカード下4桁が **4154=Vポイント / 2121=ファミペイ** のときに自動で書かれる。
///   🔥 **本人は手で登録しない**（確認カードも出さない）＝下4桁で確定し、例外が無いため。
class PointUsage {
  const PointUsage({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.pointType,
    this.store,
    this.last4,
    this.orderNo,
    this.source,
    this.memo,
  });

  final String id;
  final DateTime date;
  final String description;

  /// 本来の値段（ポイント数＝円相当）。収支には足さない。
  final int amount;

  /// 'Vポイント' / 'ファミペイ' など。
  final String pointType;

  final String? store;
  final String? last4;
  final String? orderNo;
  final String? source;
  final String? memo;

  static PointUsage? tryFromJson(Map<String, dynamic> j) {
    final raw = j['date'];
    final date = raw is String ? DateTime.tryParse(raw) : null;
    if (date == null) return null;
    return PointUsage(
      id: (j['id'] ?? '').toString(),
      date: date,
      description: (j['description'] ?? '').toString(),
      amount: (j['amount'] is num) ? (j['amount'] as num).round() : 0,
      pointType: (j['pointType'] ?? '').toString(),
      store: j['store']?.toString(),
      last4: j['last4']?.toString(),
      orderNo: j['orderNo']?.toString(),
      source: j['source']?.toString(),
      memo: j['memo']?.toString(),
    );
  }
}

class PointUsageRepository {
  PointUsageRepository._();
  static final PointUsageRepository instance = PointUsageRepository._();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  bool get available => _uid != null;

  /// 新しい順に読む。
  ///
  /// ⚠ `mode` と `date` を同時に where すると Firestore の**複合インデックス**が要る
  /// （このプロジェクトは複合indexを作らない方針）。並べ替えは date だけで行い、
  /// モードの絞り込みはアプリ側でやる。
  Future<List<PointUsage>> fetchAll({String? mode}) async {
    final uid = _uid;
    if (uid == null) return const [];
    final snap = await FirebaseFirestore.instance
        .collection('users/$uid/point_usages')
        .orderBy('date', descending: true)
        .limit(500)
        .get();
    final out = <PointUsage>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (mode != null && mode.isNotEmpty && m['mode'] != mode) continue;
      final u = PointUsage.tryFromJson(m);
      if (u != null) out.add(u);
    }
    return out;
  }
}
