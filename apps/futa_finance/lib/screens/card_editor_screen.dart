import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../widgets/brand_logo.dart';
import '../widgets/centered_body.dart';

/// クレジットカードの登録CRUD。
class CardEditorScreen extends StatefulWidget {
  const CardEditorScreen({super.key});

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  final _repo = SettingsRepository();
  PaymentMethodsConfig? _config;

  // ブランドカラー選択UIは廃止（ロゴURL指定で代替）。
  // モデル側 brandColorValue は既存データ互換のためフィールドだけ残してある。

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
    final iconUrlCtrl =
        TextEditingController(text: initial?.iconUrl ?? '');
    final memoCtrl = TextEditingController(text: initial?.memo ?? '');
    // 引き落とし日は Dropdown 選択。null = 未設定。
    int? selectedPaymentDay = initial?.paymentDay;

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
            final iconUrl = iconUrlCtrl.text.trim().isEmpty
                ? null
                : iconUrlCtrl.text.trim();
            final memo =
                memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
            final paymentDay = selectedPaymentDay;
            if (initial == null) {
              Navigator.pop(
                  ctx,
                  RegisteredCreditCard(
                    id: _genId(),
                    name: name,
                    // last4 入力UIは廃止、新規は null
                    // brandColorValue は新規入力UIから削除。null で保存。
                    // 累積利用額はホーム画面で取引から自動計算する
                    iconUrl: iconUrl,
                    memo: memo,
                    paymentDay: paymentDay,
                  ));
            } else {
              Navigator.pop(
                  ctx,
                  initial.copyWith(
                    name: name,
                    // last4 は initial 値を維持（破壊しない）
                    // brandColorValue は initial 値を維持（破壊しない）
                    iconUrl: iconUrl,
                    memo: memo,
                    clearMemo: memo == null,
                    paymentDay: paymentDay,
                    clearPaymentDay: paymentDay == null,
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
                          // 備考欄（1行）
                          TextField(
                            controller: memoCtrl,
                            maxLines: 1,
                            decoration: const InputDecoration(
                              labelText: '備考（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 引き落とし日: Dropdown 選択（1〜31 or 未設定）
                          DropdownButtonFormField<int?>(
                            initialValue: selectedPaymentDay,
                            decoration: const InputDecoration(
                              labelText: '引き落とし日（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                            items: <DropdownMenuItem<int?>>[
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('— 未設定 —',
                                    style: TextStyle(
                                        color: Color(0xFF9CA3AF))),
                              ),
                              for (var d = 1; d <= 31; d++)
                                DropdownMenuItem<int?>(
                                  value: d,
                                  child: Text('$d 日'),
                                ),
                            ],
                            onChanged: (v) =>
                                setLocal(() => selectedPaymentDay = v),
                          ),
                          const SizedBox(height: 12),
                          _logoUrlField(iconUrlCtrl, '💳', setLocal),
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
      body: CenteredBody(
        child: config == null
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
                  // 引き落とし日（任意）。last4 表示はUIから廃止。
                  if (c.paymentDay != null) ...[
                    const SizedBox(height: 2),
                    Text('毎月${c.paymentDay}日引落',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1A237E),
                            fontWeight: FontWeight.w600)),
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
