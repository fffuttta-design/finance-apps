import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../../../data/app_mode.dart';
import '../../../data/income_source_repository.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/v2_card.dart';

/// v2.1 ネイティブ収入マスタ panel。
/// - 一覧テーブルは v2.1 ネイティブ
/// - 「＋追加」ボタンと各行タップで、その場の編集シート（_showSourceSheet）を
///   開いて追加 / 編集 / 削除 / アーカイブを行う（別ページには遷移しない）。
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

  /// 追加（initial=null）/ 編集（initial=対象）をその場のダイアログで行う。
  /// 別ページ（IncomeMasterScreen）には遷移しない。
  Future<void> _editInline(IncomeSource? initial) async {
    final res = await _showSourceSheet(context, initial: initial);
    if (res == null) return;
    final cfg = _config;
    if (cfg == null) return;
    final list = [...cfg.sources];
    if (res.deleted && initial != null) {
      list.removeWhere((s) => s.id == initial.id);
    } else if (res.saved != null) {
      if (initial == null) {
        list.add(res.saved!);
      } else {
        final i = list.indexWhere((s) => s.id == initial.id);
        if (i >= 0) {
          list[i] = res.saved!;
        } else {
          list.add(res.saved!);
        }
      }
    }
    await _repo.save(cfg.copyWith(sources: list));
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
              // その場で1件追加（別ページに遷移しない）。各行タップで編集。
              FilledButton.icon(
                onPressed: _config == null ? null : () => _editInline(null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('追加'),
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
                            Expanded(
                                child: Text('名前',
                                    style: V2Typography
                                        .tableHeader)),
                            const SizedBox(width: V2Spacing.sm),
                            SizedBox(
                                width: 64,
                                child: Text('サイクル',
                                    style: V2Typography
                                        .tableHeader)),
                            const SizedBox(width: V2Spacing.sm),
                            SizedBox(
                                width: 48,
                                child: Text('日',
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
                            onTap: () => _editInline(visible[i]),
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
              // 名前（残り幅いっぱい）。アーカイブは行を薄く表示して区別。
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.name,
                        style: V2Typography.bodyStrong.copyWith(
                            color: muted
                                ? V2Colors.textMuted
                                : V2Colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (muted) ...[
                      const SizedBox(width: 6),
                      Text('（アーカイブ）',
                          style: V2Typography.micro
                              .copyWith(color: V2Colors.textMuted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              // サイクル（小さめのバッジ。文字幅にフィット）
              SizedBox(
                width: 64,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: V2Colors.accentSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(widget.cycleLabel,
                        style: V2Typography.micro.copyWith(
                            color: V2Colors.accent,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: V2Spacing.sm),
              SizedBox(
                width: 48,
                child: Text(
                  s.dayOfMonth != null ? '${s.dayOfMonth}日' : '—',
                  textAlign: TextAlign.right,
                  style: V2Typography.numericCell.copyWith(
                      color: muted
                          ? V2Colors.textMuted
                          : V2Colors.textBody),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 収入マスタ編集シートの結果（保存 / 削除）。
class _IncomeSheetResult {
  final IncomeSource? saved;
  final bool deleted;
  const _IncomeSheetResult.save(this.saved) : deleted = false;
  const _IncomeSheetResult.delete()
      : saved = null,
        deleted = true;
}

/// 収入マスタの追加/編集を「その場で」行う軽量シート。
/// initial=null なら追加、指定すれば編集（削除・アーカイブ切替も可）。
/// 返り値が null ならキャンセル。
Future<_IncomeSheetResult?> _showSourceSheet(BuildContext context,
    {IncomeSource? initial}) {
  final nameCtrl = TextEditingController(text: initial?.name ?? '');
  final dayCtrl =
      TextEditingController(text: initial?.dayOfMonth?.toString() ?? '');
  final memoCtrl = TextEditingController(text: initial?.memo ?? '');
  IncomeCycle cycle = initial?.cycle ?? IncomeCycle.monthly;
  bool archived = initial?.archived ?? false;
  final isEdit = initial != null;

  return showModalBottomSheet<_IncomeSheetResult?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final isValid = nameCtrl.text.trim().isNotEmpty;
        void onSave() {
          final name = nameCtrl.text.trim();
          if (name.isEmpty) {
            Navigator.pop(ctx, null);
            return;
          }
          Navigator.pop(
            ctx,
            _IncomeSheetResult.save(IncomeSource(
              id: initial?.id ??
                  DateTime.now().microsecondsSinceEpoch.toString(),
              name: name,
              clientName: initial?.clientName,
              expectedAmount: initial?.expectedAmount,
              cycle: cycle,
              dayOfMonth: cycle == IncomeCycle.oneTime
                  ? null
                  : int.tryParse(dayCtrl.text.trim()),
              memo: memoCtrl.text.trim().isEmpty
                  ? null
                  : memoCtrl.text.trim(),
              archived: archived,
            )),
          );
        }

        Future<void> onDelete() async {
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (dctx) => AlertDialog(
              title: const Text('削除しますか？'),
              content: Text('「${initial!.name}」を削除します。元に戻せません。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dctx, false),
                    child: const Text('キャンセル')),
                FilledButton(
                    onPressed: () => Navigator.pop(dctx, true),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626)),
                    child: const Text('削除')),
              ],
            ),
          );
          if (ok == true && ctx.mounted) {
            Navigator.pop(ctx, const _IncomeSheetResult.delete());
          }
        }

        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                Text(isEdit ? '収入マスタを編集' : '収入マスタを追加',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827))),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: !isEdit,
                  decoration: const InputDecoration(
                    labelText: '名称（必須）',
                    border: OutlineInputBorder(),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<IncomeCycle>(
                  initialValue: cycle,
                  decoration: const InputDecoration(
                    labelText: '発生サイクル',
                    border: OutlineInputBorder(),
                    isDense: true,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                  items: IncomeCycle.values
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                                IncomeSource(id: '_', name: '_', cycle: c)
                                    .cycleLabel),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => cycle = v);
                  },
                ),
                if (cycle != IncomeCycle.oneTime) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: dayCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 2,
                    decoration: const InputDecoration(
                      labelText: '入金日（1〜31、任意）',
                      counterText: '',
                      border: OutlineInputBorder(),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: memoCtrl,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    labelText: '備考（任意）',
                    border: OutlineInputBorder(),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
                if (isEdit) ...[
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('アーカイブ（一覧から隠す）'),
                    value: archived,
                    onChanged: (v) => setLocal(() => archived = v),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (isEdit) ...[
                      OutlinedButton(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline,
                                size: 18, color: Color(0xFFDC2626)),
                            SizedBox(width: 4),
                            Text('削除',
                                style: TextStyle(color: Color(0xFFDC2626))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('キャンセル'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: isValid ? onSave : null,
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('保存',
                            style:
                                TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
