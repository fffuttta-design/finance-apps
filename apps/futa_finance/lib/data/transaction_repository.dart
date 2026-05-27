import 'dart:async';
import 'dart:convert';

import 'package:finance_core/finance_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

/// 取引データのローカル永続化（shared_preferences のJSON配列）。
///
/// シングルトン。Dフェーズで Firestore に置き換える前提。
/// データ変更時は [stream] に通知し、各画面が再読込できるようにする。
/// AppMode (事業/個人) ごとにキーが分かれ、データは完全分離される。
class TransactionRepository {
  TransactionRepository._();
  static final instance = TransactionRepository._();

  /// 現モード依存のキー。
  String get _key =>
      'futa.${AppModeManager.instance.current.keyPrefix}.transactions';

  final _controller = StreamController<List<Transaction>>.broadcast();

  /// 変更通知ストリーム。loadAll後の最新リストが流れる。
  Stream<List<Transaction>> get stream => _controller.stream;

  Future<List<Transaction>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<Transaction> txns) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(txns.map((t) => t.toJson()).toList());
    await prefs.setString(_key, json);
    _controller.add(txns);
  }

  Future<void> add(Transaction t) async {
    final list = await loadAll();
    list.add(t);
    await _saveAll(list);
  }

  Future<void> update(Transaction t) async {
    final list = await loadAll();
    final idx = list.indexWhere((x) => x.id == t.id);
    if (idx >= 0) {
      list[idx] = t;
      await _saveAll(list);
    }
  }

  Future<void> delete(String id) async {
    final list = await loadAll();
    list.removeWhere((t) => t.id == id);
    await _saveAll(list);
  }

  /// 全件置換（サンプルデータ投入などで使用）。
  Future<void> replaceAll(List<Transaction> txns) async {
    await _saveAll(txns);
  }

  /// 全削除。
  Future<void> clear() async {
    await _saveAll([]);
  }
}
