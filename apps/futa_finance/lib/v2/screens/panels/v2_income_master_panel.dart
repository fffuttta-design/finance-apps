import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../../../data/app_mode.dart';
import '../../../data/income_source_repository.dart';
import '../../../screens/income_master_screen.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/v2_card.dart';

/// v2.1 ネイティブ収入マスタ panel。
/// - 一覧テーブルは v2.1 ネイティブ
/// - 追加 / 編集 / 削除 / アーカイブ操作は v1 IncomeMasterScreen を
///   fullscreen で開いて行う（v1 の _editDialog BottomSheet を流用）
class V2IncomeMasterPanel extends StatefulWidget {
  const V2IncomeMasterPanel({super.key});

  @override
  State<V2IncomeMasterPanel> createState() =>
      _V2IncomeMasterPanelState();
}

class _V2IncomeMasterPanelState extends State<V2IncomeMasterPanel>
    with ModeAwareMixin {
  final _repo = IncomeSourceRepository.instance;
  IncomeSourceConfig? _config;
  bool _showArchived = false;

  @override
  void onModeChanged() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.load();
    if (!mounted) return;
    setState(() => _config = c);
  }

  Future<void> _openEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IncomeMasterScreen()),
    );
    if (mounted) await _load();
  }

  String _cycleLabel(IncomeCycle c) {
    switch (c) {
      case IncomeCycle.oneTime:
        return '都度';
      case IncomeCycle.monthly:
        return '毎月';
      case IncomeCycle.quarterly:
        return '四半期';
      case IncomeCycle.semiAnnually:
        return '半年';
      case IncomeCycle.annually:
        return '毎年';
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final all = config.sources;
    final visible = _showArchived
        ? all
        : all.where((s) => !s.archived).toList();
    final archivedCount = all.where((s) => s.archived).length;
    final isBusiness =
        AppModeManager.instance.current == AppMode.business;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── ヘッダー ──
        Padding(
          padding: const EdgeInsets.fromLTRB(
              V2Spacing.sm, 0, V2Spacing.sm, V2Spacing.sm),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: V2Colors.positiveSoft,
                  borderRadius: BorderRadius.circular(
                      V2Spacing.radiusSm),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.savings_outlined,
                    size: 20, color: V2Colors.positive),
              ),
              const SizedBox(width: V2Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBusiness ? '売上マスタ' : '収入マスタ',
                      style: V2Typography.h1,
                    ),
                    const SizedBox(height: V2Spacing.xs),
                    Text(
                      isBusiness
                          ? '継続売上・単発売上のテンプレを登録。入金記録時に呼び出せます。'
                          : '継続収入・単発収入のテンプレを登録。入金記録時に呼び出せます。',
                      style: V2Typography.caption.copyWith(
                          color: V2Colors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              FilledButton.icon(
                onPressed: _openEditor,
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('編集 / 追加'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 34),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
        ),
        // ── サマリーバー + アーカイブ表示切替 ──
        V2Card(
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.lg, vertical: V2Spacing.sm),
          child: Row(
            children: [
              Text('${visible.length} 件',
                  style: V2Typography.bodyStrong),
              if (archivedCount > 0) ...[
                const SizedBox(width: V2Spacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.sm, vertical: 1),
                  decoration: BoxDecoration(
                    color: V2Colors.surfaceMuted,
                    borderRadius:
                        BorderRadius.circular(V2Spacing.radiusXs),
                  ),
                  child: Text('アーカイブ $archivedCount',
                      style: V2Typography.micro.copyWith(
                          color: V2Colors.textMuted)),
                ),
              ],
              const Spacer(),
              if (archivedCount > 0) ...[
                Text('アーカイブを表示',
                    style: V2Typography.caption.copyWith(
                        color: V2Colors.textSecondary)),
                const SizedBox(width: V2Spacing.sm),
                Switch.adaptive(
                  value: _showArchived,
                  onChanged: (v) =>
                      setState(() => _showArchived = v),
                  activeThumbColor: V2Colors.accent,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.md),
        // ── 一覧テーブル ──
        Expanded(
          child: V2Card(
            padding: EdgeInsets.zero,
            child: visible.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inbox_outlined,
                            size: 36, color: V2Colors.textMuted),
                        const SizedBox(height: V2Spacing.sm),
                        Text(
                            archivedCount > 0 && !_showArchived
                                ? 'アクティブな収入マスタなし\n（アーカイブ $archivedCount 件）'
                                : '収入マスタはまだありません',
                            textAlign: TextAlign.center,
                            style: V2Typography.caption.copyWith(
                                color: V2Colors.textSecondary)),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ヘッダー
                      Container(
                        color: V2Colors.surfaceMuted,
                        padding: const EdgeInsets.symmetric(
                            horizontal: V2Spacing.lg, vertical: 7),
                        child: Row(
                          children: [
                            SizedBox(
                                width: 140,
                                child: Text('名前',
                                    style: V2Typography
                                        .tableHeader)),
                            const SizedBox(width: V2Spacing.sm),
                            SizedBox(
                                width: 80,
                                child: Text('サイクル',
                                    style: V2Typography
                                        .tableHeader)),
                            const SizedBox(width: V2Spacing.sm),
                            SizedBox(
                                width: 60,
                                child: Text('日',
                                    style: V2Typography
                                        .tableHeader,
                                    textAlign: TextAlign.right)),
                            const SizedBox(width: V2Spacing.sm),
                            Expanded(
                                child: Text('メモ',
                                    style: V2Typography
                                        .tableHeader)),
                            const SizedBox(width: V2Spacing.sm),
                            SizedBox(
                                width: 70,
                                child: Text('状態',
                                    style: V2Typography
                                        .tableHeader,
                                    textAlign: TextAlign.right)),
                          ],
                        ),
                      ),
                      // 行
                      Expanded(
                        child: ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, i) => _IncomeRow(
                            s: visible[i],
                            cycleLabel: _cycleLabel(visible[i].cycle),
                            onTap: _openEditor,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _IncomeRow extends StatefulWidget {
  final IncomeSource s;
  final String cycleLabel;
  final VoidCallback onTap;
  const _IncomeRow({
    required this.s,
    required this.cycleLabel,
    required this.onTap,
  });

  @override
  State<_IncomeRow> createState() => _IncomeRowState();
}

class _IncomeRowState extends State<_IncomeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final muted = s.archived;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hover ? V2Colors.hover : V2Colors.surface,
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.lg, vertical: 8),
          decoration: BoxDecoration(
            color: _hover
                ? V2Colors.hover
                : (muted
                    ? V2Colors.surfaceMuted.withValues(alpha: 0.4)
                    : V2Colors.surface),
            border: const Border(
                top: BorderSide(
                    color: V2Colors.divider, width: 1)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  s.name,
                  style: V2Typography.bodyStrong.copyWith(
                      color: muted
                          ? V2Colors.textMuted
                          : V2Colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              SizedBox(
                width: 80,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: V2Colors.accentSoft,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(widget.cycleLabel,
                      style: V2Typography.micro.copyWith(
                          color: V2Colors.accent,
                          fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              SizedBox(
                width: 60,
                child: Text(
                  s.dayOfMonth != null ? '${s.dayOfMonth}日' : '—',
                  textAlign: TextAlign.right,
                  style: V2Typography.numericCell.copyWith(
                      color: muted
                          ? V2Colors.textMuted
                          : V2Colors.textBody),
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              Expanded(
                child: Text(
                  s.memo?.isEmpty ?? true ? '—' : s.memo!,
                  style: V2Typography.caption.copyWith(
                      color: muted
                          ? V2Colors.textMuted
                          : V2Colors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              SizedBox(
                width: 70,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: s.archived
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: V2Colors.surfaceMuted,
                            borderRadius:
                                BorderRadius.circular(3),
                          ),
                          child: Text('アーカイブ',
                              style: V2Typography.micro
                                  .copyWith(
                                      color: V2Colors
                                          .textMuted)),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: V2Colors.positiveSoft,
                            borderRadius:
                                BorderRadius.circular(3),
                          ),
                          child: Text('アクティブ',
                              style: V2Typography.micro
                                  .copyWith(
                                      color:
                                          V2Colors.positive,
                                      fontWeight:
                                          FontWeight.w700)),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
