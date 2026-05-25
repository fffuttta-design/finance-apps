import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../utils/formatters.dart';

/// 銀行口座の登録CRUD。
class AccountEditorScreen extends StatefulWidget {
  const AccountEditorScreen({super.key});

  @override
  State<AccountEditorScreen> createState() => _AccountEditorScreenState();
}

class _AccountEditorScreenState extends State<AccountEditorScreen> {
  final _repo = SettingsRepository();
  PaymentMethodsConfig? _config;

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

  void _update(List<RegisteredBankAccount> newAccounts) {
    setState(() => _config = _config!.copyWith(bankAccounts: newAccounts));
    _save();
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<RegisteredBankAccount?> _editDialog(
      BuildContext context, RegisteredBankAccount? initial) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final last4Ctrl = TextEditingController(text: initial?.last4 ?? '');
    final balanceCtrl = TextEditingController(
        text: initial?.startingBalance?.toString() ?? '');
    final result = await showDialog<RegisteredBankAccount?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(initial == null ? '銀行口座を追加' : '銀行口座を編集'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: '銀行名（必須）', hintText: '住信SBI / 三井住友 など')),
              const SizedBox(height: 8),
              TextField(
                controller: last4Ctrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: '口座番号 下4桁（任意）',
                  hintText: '1234',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: balanceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '開始時残高 円（任意）', hintText: '例: 1000000'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                Navigator.pop(context, null);
                return;
              }
              final balance = int.tryParse(balanceCtrl.text.trim());
              final last4 =
                  last4Ctrl.text.trim().isEmpty ? null : last4Ctrl.text.trim();
              if (initial == null) {
                Navigator.pop(
                    context,
                    RegisteredBankAccount(
                      id: _genId(),
                      name: name,
                      last4: last4,
                      startingBalance: balance,
                    ));
              } else {
                Navigator.pop(
                    context,
                    initial.copyWith(
                      name: name,
                      last4: last4,
                      startingBalance: balance,
                    ));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _add() async {
    final r = await _editDialog(context, null);
    if (r == null) return;
    _update([..._config!.bankAccounts, r]);
  }

  Future<void> _edit(int i) async {
    final r = await _editDialog(context, _config!.bankAccounts[i]);
    if (r == null) return;
    final list = [..._config!.bankAccounts];
    list[i] = r;
    _update(list);
  }

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${_config!.bankAccounts[i].name} を削除？'),
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
    final list = [..._config!.bankAccounts]..removeAt(i);
    _update(list);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '銀行口座',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: '銀行口座を追加',
            onPressed: config == null ? null : _add,
          ),
        ],
      ),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: config.bankAccounts.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: config.bankAccounts.length,
                      itemBuilder: (context, i) {
                        final a = config.bankAccounts[i];
                        return _tile(a, () => _edit(i), () => _delete(i));
                      },
                    ),
            ),
    );
  }

  Widget _tile(
      RegisteredBankAccount a, VoidCallback onEdit, VoidCallback onDelete) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        leading: const Icon(Icons.account_balance, color: Color(0xFF1A237E)),
        title: Text(a.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        subtitle: Text(
          [
            if (a.last4 != null) '****${a.last4}',
            if (a.startingBalance != null)
              '初期残高 ${formatYen(a.startingBalance!)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
        ),
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
            const Icon(Icons.account_balance,
                size: 64, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('銀行口座が未登録です',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('銀行口座を追加'),
              onPressed: _add,
            ),
          ],
        ),
      );
}
