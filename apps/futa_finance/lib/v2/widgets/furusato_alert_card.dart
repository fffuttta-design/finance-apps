import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../../data/app_mode.dart';
import '../../data/furusato.dart';
import '../../data/furusato_repository.dart';
import '../../data/transaction_repository.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'v2_card.dart';

/// ホームに出す、ふるさと納税の期限アラート。
///
/// 年中出しっぱなしにすると誰も読まなくなるので、**手を打てる時期にだけ**出す。
///   - 12月　　　　… 枠が余っている（12/31の決済で締切）
///   - 1/1〜1/10　 … ワンストップ特例の申請期限
///   - 1月〜3月　　… 受領証明書が未着（確定申告に間に合わせる）
/// 条件に当てはまらないときは何も描かない（SizedBox.shrink）。
class FurusatoAlertCard extends StatefulWidget {
  const FurusatoAlertCard({super.key});

  @override
  State<FurusatoAlertCard> createState() => _FurusatoAlertCardState();
}

class _FurusatoAlertCardState extends State<FurusatoAlertCard> {
  _Alert? _alert;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 事業モードでは出さない（ふるさと納税は個人の所得控除で、
    // 法人の口座・カードから払うと役員貸付になる＝事業側に居るのが誤り）。
    if (AppModeManager.instance.current == AppMode.business) return;

    final cfg = await FurusatoRepository.instance.load();
    final txs = await TransactionRepository.instance.loadAll();
    if (!mounted) return;
    setState(() => _alert = _evaluate(cfg, txs, DateTime.now()));
  }

  /// 表示すべきアラートを1つだけ選ぶ（複数出して薄めない）。
  static _Alert? _evaluate(
      FurusatoConfig cfg, List<Transaction> txs, DateTime now) {
    List<Transaction> donationsOf(int year) => txs
        .where((t) =>
            t.type == TransactionType.expense &&
            t.date.year == year &&
            t.category.major == cfg.categoryMajor &&
            t.category.sub == cfg.categorySub)
        .toList();

    // ── 1月〜3月：前年分の後始末 ──
    if (now.month <= 3) {
      final year = now.year - 1;
      final last = donationsOf(year);
      if (last.isNotEmpty) {
        final y = cfg.yearOf(year);
        final deadline = FurusatoConfig.onestopDeadlineFor(year);
        if (y.useOnestop && !now.isAfter(deadline)) {
          final notApplied =
              last.where((t) => !cfg.entryOf(t.id).onestopApplied).length;
          if (notApplied > 0) {
            final days = deadline.difference(now).inDays;
            return _Alert(
              icon: Icons.assignment_late_outlined,
              color: V2Colors.negative,
              title: 'ワンストップ特例の申請期限まであと$days日',
              body: '$year年の寄付で未申請が$notApplied件あります。'
                  '${deadline.month}/${deadline.day}必着です。'
                  '出さないまま確定申告もしないと、控除が丸ごと消えます。',
            );
          }
        }
        final missing = last
            .where((t) => !cfg.entryOf(t.id).certificate.isReady)
            .length;
        if (missing > 0) {
          return _Alert(
            icon: Icons.description_outlined,
            color: V2Colors.warning,
            title: '受領証明書が$missing件そろっていません',
            body: '$year年の寄付分です。確定申告に間に合わないと、'
                'その分は控除されずただの買い物になります。',
          );
        }
      }
    }

    // ── 12月：枠の使い残し ──
    if (now.month == 12) {
      final y = cfg.yearOf(now.year);
      final used = donationsOf(now.year).fold(0, (s, t) => s + t.amount);
      if (y.limitAmount > 0 && used < y.limitAmount) {
        final left = DateTime(now.year, 12, 31).difference(now).inDays + 1;
        return _Alert(
          icon: Icons.schedule,
          color: V2Colors.info,
          title: 'ふるさと納税の枠が'
              '${formatYen(y.limitAmount - used)}余っています',
          body: '今年はあと$left日。クレジットカードは12/31の決済完了分までが'
              '今年扱いです。枠は使い切るほど得をします。',
        );
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final a = _alert;
    if (a == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.md),
      child: V2Card(
        background: a.color.withValues(alpha: 0.06),
        borderColor: a.color.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(a.icon, size: 20, color: a.color),
            const SizedBox(width: V2Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title,
                      style: V2Typography.bodyStrong
                          .copyWith(color: a.color)),
                  const SizedBox(height: V2Spacing.xs),
                  Text(a.body,
                      style: V2Typography.caption
                          .copyWith(color: V2Colors.textBody)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Alert {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Alert({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
}
