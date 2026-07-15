import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/settings_repository.dart';
import '../data/transaction_repository.dart';
import '../data/transfer_template.dart';
import '../widgets/memo_field.dart';
import '../utils/date_pick.dart';
import '../utils/modal_input.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';

/// 振替入力モーダルを表示する。保存/削除成功時は true を返す。
/// [editing] を渡すと「振替を編集」モードで開く（プリフィル＋更新/削除）。
/// [editing] が支出/収入のときは「振替に変更」モード＝同じIDのまま振替に作り替える
/// （ExpenseInputScreen の「この取引を振替に変更」から呼ばれる）。
Future<bool?> showTransferInputModal(BuildContext context,
    {core.Transaction? editing}) {
  // 支出/収入のフォームと同じ出し方（PC=中央のコンパクトなダイアログ／スマホ=下からのシート）。
  // ⚠ 以前はここだけ独自に「画面の95%の高さのシート」を出していたため、
  //   「支出を編集」から「振替に変更」を押すと見た目がガラッと変わって不自然だった。
  return showInputSheet<bool>(context, TransferInputScreen(editing: editing));
}

/// 振替入力画面（口座間のお金の移動）。
/// 収支には影響せず、口座残高だけが付け替わる。
/// 例:
///   - GMOあおぞら → 三井住友（事業資金移動）
///   - 銀行 → 現金（ATM 引出し）
///   - 銀行 → クレジットカード（カード引落）
class TransferInputScreen extends StatefulWidget {
  const TransferInputScreen({super.key, this.initialFromAccount, this.editing});

  /// 起動時に移動元口座をプリセット（口座詳細画面から呼ばれた時など）。
  final String? initialFromAccount;

  /// 編集対象の取引（null=新規作成）。
  /// 振替なら「振替を編集」。支出/収入なら「振替に変更」＝同じIDのまま振替に作り替える。
  final core.Transaction? editing;

  @override
  State<TransferInputScreen> createState() => _TransferInputScreenState();
}

class _TransferInputScreenState extends State<TransferInputScreen> {
  final _settings = SettingsRepository();
  core.PaymentMethodsConfig? _payments;
  List<TransferTemplate> _templates = const [];

  DateTime _date = DateTime.now();
  String? _fromAccount;
  String? _toAccount;
  final _amountCtrl = NoComposingUnderlineController();
  final _memoCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  /// 支出/収入を振替に作り替えるモード（＝「振替に変更」から開いた）。
  bool get _isConverting =>
      widget.editing != null &&
      widget.editing!.type != core.TransactionType.transfer;

  @override
  void initState() {
    super.initState();
    // 編集モードなら既存値でプリフィル。
    final e = widget.editing;
    if (e != null) {
      _date = e.date;
      _fromAccount = e.transferFromAccount;
      _toAccount = e.transferToAccount;
      // 支出/収入から来たときは振替の口座がまだ無い。支払方法（例: 住信SBI）を
      // 移動元の初期値にする（口座候補に無ければ _load が未選択に落とす）。
      if (_isConverting && _fromAccount == null) {
        final pm = e.paymentMethod.trim();
        if (pm.isNotEmpty) _fromAccount = pm;
      }
      _amountCtrl.text = formatAmount(e.amount);
      _memoCtrl.text = e.memo ?? '';
      // 自動命名（移動元 → 移動先）でなければ、付けた名前として復元。
      final auto = '${e.transferFromAccount} → ${e.transferToAccount}';
      if (e.description.trim().isNotEmpty && e.description != auto) {
        _nameCtrl.text = e.description;
      }
    }
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await _settings.loadPayments();
    final t = await _settings.loadTransferTemplates();
    if (!mounted) return;
    setState(() {
      _payments = p;
      _templates = t.templates;
      if (_fromAccount == null && widget.initialFromAccount != null) {
        _fromAccount = widget.initialFromAccount;
      }
      // 候補に無い口座名（休眠にした/改名した口座、支払方法がクレカだった支出からの
      // 変更など）が残っていると Dropdown が値を見つけられず画面が落ちる。
      // 未選択に落として選び直してもらう。
      final fromOk = _accountChoices().map((c) => c.value).toSet();
      final toOk =
          _accountChoices(includeCards: true).map((c) => c.value).toSet();
      if (_fromAccount != null && !fromOk.contains(_fromAccount)) {
        _fromAccount = null;
      }
      if (_toAccount != null && !toOk.contains(_toAccount)) {
        _toAccount = null;
      }
    });
  }

  /// 移動元/先の候補（value=口座名 / label=[種別]口座名）。
  /// 銀行/現金/電子マネー + 固定の「現金」。休眠中(inactive)の口座は除外。
  /// [includeCards]=true のとき、登録済みのクレジットカードを**全部**加える
  /// （カード引落の移動先用）。休眠カードも隠さない＝必要なカードが選べなくなる事故を防ぐ。
  List<({String value, String label})> _accountChoices({bool includeCards = false}) {
    final p = _payments;
    final list = <({String value, String label})>[];
    if (p != null) {
      for (final b in p.bankAccounts) {
        if (b.inactive) continue; // 休眠中の口座は候補に出さない
        list.add((
          value: b.name,
          label: '[${b.accountType.shortLabel}]${b.name}',
        ));
      }
    }
    list.add((value: '現金', label: '[現金]現金'));
    if (includeCards && p != null) {
      for (final c in p.creditCards) {
        list.add((value: c.name, label: '[カード]${c.name}'));
      }
    }
    return list;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_fromAccount == null || _toAccount == null) return;
    if (_fromAccount == _toAccount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('移動元と移動先が同じです')),
      );
      return;
    }
    final amount = parseAmount(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正しい金額を入力してください')),
      );
      return;
    }
    // 名前は必須。「新生銀行 → オリコカード」の自動命名だと明細で何の移動か分からず、
    // 「オリコ先払い」のように後から見て意味が分かる名前を必ず付けてもらう。
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名前を入力してください（例: オリコ先払い）')),
      );
      return;
    }
    // 非同期の後に閉じるため Navigator を await 前にキャプチャ（Windows対策）。
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final editing = widget.editing;
      final tx = core.Transaction(
        id: editing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        date: _date,
        type: core.TransactionType.transfer,
        // 振替時は category 不要だが、空文字でも初期化が要るため固定値。
        category: const core.Category(major: '振替', sub: ''),
        // paymentMethod は使わない。互換のため空文字。
        paymentMethod: '',
        description: _nameCtrl.text.trim(),
        amount: amount,
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        transferFromAccount: _fromAccount,
        transferToAccount: _toAccount,
        // 編集時に既存メタを引き継ぐ（reviewed=検収チェックが外れないように）。
        reviewed: editing?.reviewed ?? false,
        sortOrder: editing?.sortOrder,
        createdAt: editing?.createdAt,
        // 支出から振替に変えたときに、証憑リンクや場所を落とさない
        // （振替の画面には出ないが、間違って変えたとき戻せなくなるのを防ぐ）。
        store: editing?.store,
        receiptUrl: editing?.receiptUrl,
        receiptId: editing?.receiptId,
        receiptSaved: editing?.receiptSaved ?? false,
        receiptType: editing?.receiptType,
      );
      if (editing != null) {
        await TransactionRepository.instance.update(tx);
      } else {
        await TransactionRepository.instance.add(tx);
      }
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final e = widget.editing;
    if (e == null) return;
    // 非同期の後に閉じるため Navigator を await 前にキャプチャ（Windows対策）。
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('この振替を削除しますか？'),
        content: const Text('元に戻せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await TransactionRepository.instance.delete(e.id);
      navigator.pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('削除に失敗しました: $err')));
    }
  }

  Future<void> _pickDate() async {
    // PC（広い画面）はカレンダー / スマホはホイール、で出し分け（支出・収入と統一）。
    final picked = await pickAdaptiveDate(
      context,
      initial: _date,
      first: DateTime(2018),
      last: DateTime(2035, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  // よく使う振替（テンプレ）セクション。チップタップで移動元/先をセット。
  Widget _buildTemplateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('よく使う振替',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280))),
            const Spacer(),
            TextButton.icon(
              onPressed: _openTemplateManager,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('編集'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
            ),
          ],
        ),
        if (_templates.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 4),
            child: Text('「編集」からよく使う振替（例: 新生銀行→PayPay）を登録できます',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _templates
                .map((t) => ActionChip(
                      avatar: const Icon(Icons.swap_horiz, size: 16),
                      label: Text(t.label),
                      onPressed: () => _applyTemplate(t),
                    ))
                .toList(),
          ),
      ],
    );
  }

  void _applyTemplate(TransferTemplate t) {
    setState(() {
      _fromAccount = t.fromAccount;
      _toAccount = t.toAccount;
    });
  }

  // テンプレの登録・編集・削除シート。
  Future<void> _openTemplateManager() async {
    final working = List<TransferTemplate>.from(_templates);
    // テンプレでもカード引落を組めるようにカードも候補に含める。
    final choices = _accountChoices(includeCards: true); // value/label
    String firstValue() => choices.isNotEmpty ? choices.first.value : '現金';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Widget acctDropdown(String value, ValueChanged<String> onChanged) {
              final exists = choices.any((c) => c.value == value);
              return DropdownButton<String>(
                value: exists ? value : null,
                isExpanded: true,
                hint: Text(value),
                items: choices
                    .map((c) => DropdownMenuItem(
                        value: c.value, child: Text(c.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('よく使う振替の編集',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      ...working.asMap().entries.map((e) {
                        final i = e.key;
                        final t = e.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: acctDropdown(t.fromAccount, (v) {
                                  setSheet(() => working[i] =
                                      t.copyWith(fromAccount: v));
                                }),
                              ),
                              const Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward,
                                    size: 16, color: Color(0xFF9CA3AF)),
                              ),
                              Expanded(
                                child: acctDropdown(t.toAccount, (v) {
                                  setSheet(() => working[i] =
                                      working[i].copyWith(toAccount: v));
                                }),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Color(0xFFDC2626)),
                                onPressed: () =>
                                    setSheet(() => working.removeAt(i)),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () {
                          final v = firstValue();
                          setSheet(() => working.add(TransferTemplate(
                                id: DateTime.now()
                                    .microsecondsSinceEpoch
                                    .toString(),
                                fromAccount:
                                    _fromAccount ?? v,
                                toAccount: _toAccount ?? v,
                              )));
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('セットを追加'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          // 移動元=先 の不正セットは除外して保存。
                          final cleaned = working
                              .where((t) =>
                                  t.fromAccount.isNotEmpty &&
                                  t.toAccount.isNotEmpty &&
                                  t.fromAccount != t.toAccount)
                              .toList();
                          await _settings.saveTransferTemplates(
                              TransferTemplatesConfig(templates: cleaned));
                          if (!mounted) return;
                          setState(() => _templates = cleaned);
                          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_payments == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // 移動元は口座のみ（カードから出金する振替は無いので出さない）。
    final fromCandidates =
        _accountChoices().where((c) => c.value != _toAccount).toList();
    // 移動先はカードも出す（銀行→カードの引落を記録できるように）。
    final toCandidates = _accountChoices(includeCards: true)
        .where((c) => c.value != _fromAccount)
        .toList();
    final canSave = !_saving &&
        _fromAccount != null &&
        _toAccount != null &&
        _amountCtrl.text.isNotEmpty &&
        _nameCtrl.text.trim().isNotEmpty; // 名前は必須
    final isEditing = widget.editing != null;
    return Scaffold(
      appBar: AppBar(
        // 他フォーム（支出/収入）と同じく「✕ 閉じる」に統一。
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        // タイトル・削除アイコンとも「支出を編集」と同じ見た目に揃える。
        title: Text(
            _isConverting
                ? '振替に変更'
                : (isEditing ? '振替を編集' : '振替を記録'),
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
              tooltip: 'この取引を削除',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 「振替に変更」で開いたときは、何が起きるかを先に伝える。
            if (_isConverting) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Text(
                  'この取引を振替に作り替えます。移動元と移動先を選んで保存してください。\n'
                  '保存すると支出ではなくなり、収支（PL）から外れて口座残高の移動だけになります。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // よく使う振替（テンプレ）
            _buildTemplateSection(),
            const SizedBox(height: 12),
            // 名前（必須）。支出フォームの「取引内容」と同じく一番上に置く
            // （後から明細で見たとき、何の移動か分かる名前を必ず付けてもらう）。
            _label('名前'),
            TextField(
              controller: _nameCtrl,
              decoration: _inputDecoration(hint: '例: オリコ先払い・生活費の移動'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            // 金額
            _label('金額（円）'),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                HalfWidthDigitsFormatter(),
                ThousandsSeparatorInputFormatter(),
              ],
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 18),
              decoration: _inputDecoration(hint: '0').copyWith(prefixText: '¥ '),
              onChanged: (_) => setState(() {}),
            ),
            if (_amountCtrl.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Builder(builder: (_) {
                  final v = parseAmount(_amountCtrl.text);
                  if (v == null) return const SizedBox.shrink();
                  return Text(
                    formatYen(v),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  );
                }),
              ),
            const SizedBox(height: 16),
            // 日付
            _label('日付'),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: _inputDecoration(),
                child: Text(
                  '${_date.year}/${_date.month.toString().padLeft(2, '0')}/${_date.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 移動元
            _label('移動元'),
            DropdownButtonFormField<String>(
              key: ValueKey('from_$_fromAccount'),
              initialValue: _fromAccount,
              isExpanded: true,
              decoration: _inputDecoration(hint: '選択してください'),
              items: fromCandidates
                  .map((c) =>
                      DropdownMenuItem(value: c.value, child: Text(c.label)))
                  .toList(),
              onChanged: (v) => setState(() => _fromAccount = v),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Icon(Icons.arrow_downward,
                  color: Color(0xFF9CA3AF), size: 20),
            ),
            const SizedBox(height: 8),
            // 移動先
            _label('移動先'),
            DropdownButtonFormField<String>(
              key: ValueKey('to_$_toAccount'),
              initialValue: _toAccount,
              isExpanded: true,
              decoration: _inputDecoration(hint: '選択してください'),
              items: toCandidates
                  .map((c) =>
                      DropdownMenuItem(value: c.value, child: Text(c.label)))
                  .toList(),
              onChanged: (v) => setState(() => _toAccount = v),
            ),
            const SizedBox(height: 16),
            // 備考（見出しは上の _label で出すので、枠内のラベルは空にして重複を消す）
            _label('備考（任意）'),
            MemoField(controller: _memoCtrl, label: ''),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                '※ 振替は収支には影響しません。各口座の残高だけが移動します。',
                style: TextStyle(
                    fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ),
            const SizedBox(height: 24),
            // 記録ボタン（支出/収入フォームと同じく末尾に配置）。
            FilledButton.icon(
              onPressed: canSave ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_saving
                  ? '保存中…'
                  : (isEditing ? '更新する' : '記録する')),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
        ),
      ),
          ),
        ],
      ),
    );
  }

  /// 見出し（支出/収入フォームと同じスタイル）。
  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280)),
        ),
      );

  /// 入力欄の装飾（支出/収入フォームと同じ・見出しは別で付ける）。
  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      );

}
