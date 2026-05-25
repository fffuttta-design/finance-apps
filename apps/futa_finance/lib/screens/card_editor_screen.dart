import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';

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
    int selectedColor = initial?.brandColorValue ?? _colorPalette.first;

    final result = await showDialog<RegisteredCreditCard?>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(initial == null ? 'クレジットカードを追加' : 'クレジットカードを編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'カード名（必須）',
                        hintText: '三井住友カード / 楽天カード など')),
                const SizedBox(height: 8),
                TextField(
                  controller: last4Ctrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'カード番号 下4桁（任意）',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                const Text('ブランドカラー',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: _colorPalette.map((c) {
                    final selected = c == selectedColor;
                    return GestureDetector(
                      onTap: () => setLocal(() => selectedColor = c),
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
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  Navigator.pop(ctx, null);
                  return;
                }
                final last4 = last4Ctrl.text.trim().isEmpty
                    ? null
                    : last4Ctrl.text.trim();
                if (initial == null) {
                  Navigator.pop(
                      ctx,
                      RegisteredCreditCard(
                        id: _genId(),
                        name: name,
                        last4: last4,
                        brandColorValue: selectedColor,
                      ));
                } else {
                  Navigator.pop(
                      ctx,
                      initial.copyWith(
                        name: name,
                        last4: last4,
                        brandColorValue: selectedColor,
                      ));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
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
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: config.creditCards.length,
                      itemBuilder: (context, i) {
                        final c = config.creditCards[i];
                        return _tile(c, () => _edit(i), () => _delete(i));
                      },
                    ),
            ),
    );
  }

  Widget _tile(
      RegisteredCreditCard c, VoidCallback onEdit, VoidCallback onDelete) {
    final color = c.brandColorValue == null
        ? const Color(0xFF6B7280)
        : Color(c.brandColorValue!);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.credit_card, color: Colors.white, size: 16),
        ),
        title: Text(c.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        subtitle: c.last4 == null
            ? null
            : Text('****${c.last4}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF6B7280))),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit,
                  size: 18, color: Color(0xFF6B7280)),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Color(0xFFDC2626)),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
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
