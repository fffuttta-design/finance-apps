import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 法人税等の「概算計上」設定。
///
/// 業績タブの PL で、税引前利益に実効税率をかけて法人税等（概算）を計上し、
/// 税引後の当期純利益を表示するための設定。確定申告の数字ではなく見込み。
class TaxEstimateRepository extends ChangeNotifier {
  TaxEstimateRepository._();
  static final TaxEstimateRepository instance = TaxEstimateRepository._();

  static const _kEnabled = 'futa.tax.est.enabled';
  static const _kRate = 'futa.tax.est.rate';

  bool _enabled = true; // 既定でON（ユーザー選択）。
  double _rate = 0.30; // 既定の実効税率 30%。
  bool _loaded = false;

  bool get enabled => _enabled;

  /// 実効税率（0.0〜1.0）。
  double get rate => _rate;

  /// 表示用パーセント（例: 30）。
  int get ratePercent => (_rate * 100).round();

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool(_kEnabled) ?? true;
    _rate = p.getDouble(_kRate) ?? 0.30;
    _loaded = true;
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
    notifyListeners();
  }

  /// [percent] は 0〜99 の整数（例: 30）。
  Future<void> setRatePercent(int percent) async {
    _rate = (percent.clamp(0, 99)) / 100.0;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kRate, _rate);
    notifyListeners();
  }

  /// 税引前利益(配列)から概算法人税(配列)を計算。黒字の分だけ課税、赤字は0。
  List<int> estimateFor(List<int> preTaxMonthly) {
    if (!_enabled) {
      return List<int>.filled(preTaxMonthly.length, 0);
    }
    return preTaxMonthly
        .map((v) => v > 0 ? (v * _rate).round() : 0)
        .toList();
  }
}
