import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/account.dart';
import '../data/account_repository.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 口座・クレカマスタ＋残高管理。
/// 登録した口座/クレカの現在残高（初期残高±収支）を表示。記録の支払元に使う。
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(title: const Text('口座・残高')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('追加', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Account>>(
              stream: AccountRepository.instance.watch(hid),
              builder: (context, accSnap) {
                final accounts = accSnap.data ?? const <Account>[];
                return StreamBuilder<List<core.Transaction>>(
                  stream: TxRepository.instance.watch(hid),
                  builder: (context, txSnap) {
                    final txns = txSnap.data ?? const <core.Transaction>[];
                    final balances = {
                      for (final a in accounts) a.id: a.balanceFrom(txns)
                    };
                    final total =
                        balances.values.fold<int>(0, (s, b) => s + b);
                    if (accounts.isEmpty) {
                      return _empty();
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      children: [
                        _totalCard(total),
                        const SizedBox(height: 16),
                        ...accounts.map((a) =>
                            _tile(context, a, balances[a.id] ?? 0)),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _totalCard(int total) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8FA8), Color(0xFFFF6B8A)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            const Text('総残高',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(formatYen(total),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      );

  Widget _tile(BuildContext context, Account a, int balance) {
    final neg = balance < 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onTap: () => _openEdit(context, a),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: AppColors.pink.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(a.type.icon, color: AppColors.pinkDark),
        ),
        title: Text(a.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(a.type.label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        trailing: Text(formatYen(balance),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: neg ? AppColors.expense : AppColors.text)),
      ),
    );
  }

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  size: 48, color: Color(0xFFF3C6D2)),
              SizedBox(height: 10),
              Text('口座・クレカを追加してね ♡',
                  style: TextStyle(color: AppColors.textSub, fontSize: 13)),
              SizedBox(height: 4),
              Text('右下の「追加」から、銀行・クレカ・現金などを登録できます',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSub, fontSize: 11)),
            ],
          ),
        ),
      );

  Future<void> _openEdit(BuildContext context, [Account? editing]) async {
    final result = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AccountEditSheet(editing: editing),
      ),
    );
    if (result == null) return;
    final hid = HouseholdService.instance.householdId;
    if (hid == null) return;
    if (result.name == '__delete__') {
      await AccountRepository.instance.delete(hid, result.id);
    } else {
      await AccountRepository.instance.save(hid, result);
    }
  }
}

class _AccountEditSheet extends StatefulWidget {
  final Account? editing;
  const _AccountEditSheet({this.editing});

  @override
  State<_AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends State<_AccountEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _balance;
  AccountType _type = AccountType.bank;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _name = TextEditingController(text: e?.name ?? '');
    _balance =
        TextEditingController(text: e != null ? e.initialBalance.toString() : '');
    _type = e?.type ?? AccountType.bank;
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名前を入力してね')),
      );
      return;
    }
    final id = widget.editing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    Navigator.pop(
      context,
      Account(
        id: id,
        name: name,
        type: _type,
        initialBalance: int.tryParse(_balance.text.trim()) ?? 0,
      ),
    );
  }

  void _delete() {
    final e = widget.editing;
    if (e == null) return;
    // name=__delete__ を削除シグナルに。
    Navigator.pop(context, e.copyWith(name: '__delete__'));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.editing != null ? '口座・クレカを編集' : '口座・クレカを追加',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: '名前', hintText: '例: 三井住友カード / ゆうちょ / 現金'),
          ),
          const SizedBox(height: 14),
          const Text('種別',
              style: TextStyle(fontSize: 12, color: AppColors.textSub)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final t in AccountType.values)
                ChoiceChip(
                  avatar: Icon(t.icon,
                      size: 16,
                      color: _type == t ? AppColors.pinkDark : AppColors.textSub),
                  label: Text(t.label),
                  selected: _type == t,
                  selectedColor: AppColors.pinkSoft,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _balance,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: '今の残高（初期残高）',
                prefixText: '¥ ',
                helperText: '登録時点の残高。以後は収支で自動増減します'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
            child: Text(widget.editing != null ? '保存する' : '追加する ♡'),
          ),
          if (widget.editing != null)
            TextButton(
              onPressed: _delete,
              child: const Text('削除する',
                  style: TextStyle(color: AppColors.expense)),
            ),
        ],
      ),
    );
  }
}
