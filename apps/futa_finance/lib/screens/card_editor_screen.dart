import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../widgets/brand_logo.dart';

/// クレジットカードの登録CRUD。
class CardEditorScreen extends StatefulWidget {
  const CardEditorScreen({super.key});

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  final _repo = SettingsRepository();
  PaymentMethodsConfig? _config;

  // 選べるブランドカラー候補
  static const _colorPalette = <int>[
    0xFF1A237E, // 紺
    0xFF1976D2, // 青
    0xFF388E3C, // 緑
    0xFFE65100, // オレンジ
    0xFFD32F2F, // 赤
    0xFF7B1FA2, // 紫
    0xFF455A64, // グレー
    0xFFFFB300, // 山吹
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.loadPayments();
    if (!mounted) return;
    setState(() => _config = c);
  }

  Future<void> _save() async {
    final c = _config;
    if (c != null) await _repo.savePayments(c);
  }

  void _update(List<RegisteredCreditCard> newCards) {
    setState(() => _config = _config!.copyWith(creditCards: newCards));
    _save();
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<RegisteredCreditCard?> _editDialog(
      BuildContext context, RegisteredCreditCard? initial) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final last4Ctrl = TextEditingController(text: initial?.last4 ?? '');
    final iconUrlCtrl =
        TextEditingController(text: initial?.iconUrl ?? '');
    final memoCtrl = TextEditingController(text: initial?.memo ?? '');
    int selectedColor = initial?.brandColorValue ?? _colorPalette.first;

    // BottomSheet で編集フォーム表示（subscription_list と同じパターン）。
    final result = await showModalBottomSheet<RegisteredCreditCard?>(
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
            final last4 = last4Ctrl.text.trim().isEmpty
                ? null
                : last4Ctrl.text.trim();
            final iconUrl = iconUrlCtrl.text.trim().isEmpty
                ? null
                : iconUrlCtrl.text.trim();
            final memo =
                memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
            if (initial == null) {
              Navigator.pop(
                  ctx,
                  RegisteredCreditCard(
                    id: _genId(),
                    name: name,
                    last4: last4,
                    brandColorValue: selectedColor,
                    // 累積利用額はホーム画面で取引から自動計算する
                    iconUrl: iconUrl,
                    memo: memo,
                  ));
            } else {
              Navigator.pop(
                  ctx,
                  initial.copyWith(
                    name: name,
                    last4: last4,
                    brandColorValue: selectedColor,
                    iconUrl: iconUrl,
                    memo: memo,
                    clearMemo: memo == null,
                  ));
            }
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: FractionallySizedBox(
              heightFactor: 0.92,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            initial == null
                                ? 'クレジットカードを追加'
                                : 'クレジットカードを編集',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Color(0xFF9CA3AF)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(ctx, null),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                              controller: nameCtrl,
                              autofocus: initial == null,
                              decoration: const InputDecoration(
                                labelText: 'カード名（必須）',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                              ),
                              onChanged: (_) => setLocal(() {})),
                          const SizedBox(height: 12),
                          TextField(
                            controller: last4Ctrl,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            decoration: const InputDecoration(
                              labelText: 'カード番号 下4桁（任意）',
                              counterText: '',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 備考欄を下4桁直後に配置（1行）
                          TextField(
                            controller: memoCtrl,
                            maxLines: 1,
                            decoration: const InputDecoration(
                              labelText: '備考（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _logoUrlField(iconUrlCtrl, '💳', setLocal),
                          const SizedBox(height: 16),
                          const Text('ブランドカラー（ロゴ未設定時に使用）',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280))),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: _colorPalette.map((c) {
                              final selected = c == selectedColor;
                              return GestureDetector(
                                onTap: () =>
                                    setLocal(() => selectedColor = c),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Color(c),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? Colors.black
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                    padding:
                        const EdgeInsets.fromLTRB(20, 10, 20, 12),
                    child: Row(
                      children: [
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
                                style: TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return result;
  }

  Future<void> _add() async {
    final r = await _editDialog(context, null);
    if (r == null) return;
    _update([..._config!.creditCards, r]);
  }

  Future<void> _edit(int i) async {
    final r = await _editDialog(context, _config!.creditCards[i]);
    if (r == null) return;
    final list = [..._config!.creditCards];
    list[i] = r;
    _update(list);
  }

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${_config!.creditCards[i].name} を削除？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    final list = [..._config!.creditCards]..removeAt(i);
    _update(list);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'クレジットカード',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: 'クレジットカードを追加',
            onPressed: config == null ? null : _add,
          ),
        ],
      ),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: config.creditCards.isEmpty
                  ? _empty()
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: config.creditCards.length,
                      onReorder: _reorder,
                      buildDefaultDragHandles: false,
                      itemBuilder: (context, i) {
                        final c = config.creditCards[i];
                        return _tile(
                          ValueKey('card-${c.id}'),
                          c,
                          i,
                          () => _edit(i),
                          () => _delete(i),
                        );
                      },
                    ),
            ),
    );
  }

  /// クレカリスト全体の並び替え。
  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final list = [..._config!.creditCards];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _update(list);
  }

  Widget _tile(
      Key key,
      RegisteredCreditCard c,
      int dragIndex,
      VoidCallback onEdit,
      VoidCallback onDelete) {
    final color = c.brandColorValue == null
        ? const Color(0xFF6B7280)
        : Color(c.brandColorValue!);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      // 銀行と同様に、ListTile の固定余白を避けて独自レイアウトで密度を制御。
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ドラッグハンドル
            ReorderableDragStartListener(
              index: dragIndex,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.drag_indicator,
                    color: Color(0xFFD1D5DB), size: 22),
              ),
            ),
            c.iconUrl != null && c.iconUrl!.isNotEmpty
                ? BrandLogo(
                    iconUrl: c.iconUrl,
                    fallbackEmoji: '💳',
                    size: 36)
                : Container(
                    width: 36,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.credit_card,
                        color: Colors.white, size: 16),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827))),
                  if (c.last4 != null) ...[
                    const SizedBox(height: 2),
                    Text('****${c.last4}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280))),
                  ],
                  if (c.memo != null && c.memo!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      c.memo!,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                          fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.edit,
                  size: 18, color: Color(0xFF6B7280)),
              onPressed: onEdit,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Color(0xFFDC2626)),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  /// ロゴURL入力欄（共通）。
  Widget _logoUrlField(TextEditingController ctrl, String fallbackEmoji,
      void Function(VoidCallback fn) setLocal) {
    void convertDomain() {
      final input = ctrl.text.trim();
      if (input.isEmpty) return;
      if (input.contains('favicon') ||
          RegExp(r'\.(png|jpg|jpeg|svg|gif|webp|ico)(\?|$)',
                  caseSensitive: false)
              .hasMatch(input)) {
        return;
      }
      final url = domainToFaviconUrl(input);
      if (url != null) setLocal(() => ctrl.text = url);
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: 'ロゴURL',
              isDense: true,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              suffixIcon: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.travel_explore, size: 18),
                tooltip: 'ドメインを favicon URL に変換',
                onPressed: convertDomain,
              ),
            ),
            onChanged: (_) => setLocal(() {}),
          ),
        ),
        const SizedBox(width: 10),
        BrandLogo(
          iconUrl: ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
          fallbackEmoji: fallbackEmoji,
          size: 40,
        ),
      ],
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.credit_card, size: 64, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('クレジットカードが未登録です',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('クレジットカードを追加'),
              onPressed: _add,
            ),
          ],
        ),
      );
}
