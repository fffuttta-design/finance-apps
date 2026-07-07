import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/csv_picker.dart';
import '../data/transaction_repository.dart';
import '../utils/formatters.dart';
import '../utils/kana.dart';
import '../v2/widgets/month_nav_bar.dart';

/// 銀行の入出金明細CSVを、指定した月ぶんだけ取り込む画面。
///
/// 仕様（ユーザー要件）:
/// - 対象の月を選び、その月の行だけを取り込む。
/// - 取り込み時は「その口座・その月」の既存明細を一度クリアして置き換える。
/// - 各行が「振替」かどうかを選べる。摘要に本人名（ﾌﾀﾑﾗ ﾀｸﾐ 等）が入る振込は、
///   自分の口座間移動なので既定で「振替」として判定しておく。
///
/// 対応銀行（ヘッダー行から列と文字コードを自動判別するので、銀行を選ぶ必要はない）:
/// - 新生銀行（SBI新生）: UTF-8(BOM) / "取引日","摘要","出金金額","入金金額","残高","メモ"
/// - GMOあおぞらネット銀行: Shift-JIS / "日付","摘要","入金金額","出金金額","残高","メモ"
///   （入金・出金の列順が新生と逆、かつ日付が YYYYMMDD 区切りなし）
///
/// ＝ 入金/出金は列の**位置**ではなく**ヘッダー名**で特定するため、どちらの銀行でも
///   正しく振り分けられる。
class BankCsvImportScreen extends StatefulWidget {
  const BankCsvImportScreen({
    super.key,
    required this.account,
    required this.initialMonth,
  });

  final core.RegisteredBankAccount account;
  final DateTime initialMonth;

  @override
  State<BankCsvImportScreen> createState() => _BankCsvImportScreenState();
}

class _BankCsvImportScreenState extends State<BankCsvImportScreen> {
  late DateTime _month =
      DateTime(widget.initialMonth.year, widget.initialMonth.month);
  final List<_ParsedRow> _all = [];
  String? _fileName;
  String? _bankLabel; // 判別できた銀行名（バナー表示用）
  bool _busy = false;

  /// 現在の対象月の行だけ。
  List<_ParsedRow> get _rows => _all
      .where((r) => r.date.year == _month.year && r.date.month == _month.month)
      .toList();

  Future<void> _pick() async {
    final picked = await pickCsvFile();
    if (picked == null || !mounted) return;
    try {
      final result = _parseCsv(picked.bytes);
      setState(() {
        _all
          ..clear()
          ..addAll(result.rows);
        _fileName = picked.name;
        _bankLabel = result.bankLabel;
      });
      if (_rows.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${_month.year}年${_month.month}月の明細がCSVにありません。月を切り替えてください。')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSVの読み込みに失敗しました: $e')),
        );
      }
    }
  }

  /// CSVバイト列を文字列にデコード。UTF-8(BOM可) を優先し、文字化けする（U+FFFD を含む）
  /// なら Shift-JIS(cp932)、最後の保険で Latin-1 を試す。
  /// → 新生(UTF-8)も GMOあおぞら(Shift-JIS)も同じ入口で読める。
  String _decodeBytes(Uint8List bytes) {
    try {
      final u = utf8.decode(bytes); // 厳密：不正バイトがあれば例外
      final s = (u.isNotEmpty && u.codeUnitAt(0) == 0xFEFF)
          ? u.substring(1) // UTF-8 BOM 除去
          : u;
      if (!s.contains('�')) return s;
    } catch (_) {}
    try {
      final s = shiftJis.decode(bytes);
      if (s.trim().isNotEmpty) return s;
    } catch (_) {}
    return latin1.decode(bytes, allowInvalid: true);
  }

  /// ヘッダー行から列位置と文字コードを自動判別して行を取り出す。
  _ParseResult _parseCsv(Uint8List bytes) {
    final text = _decodeBytes(bytes);
    final lines = text
        .split(RegExp(r'\r\n|\n|\r'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw '空のCSVです';
    }

    // 1行目＝ヘッダー。列名から各データ列の位置を特定する。
    final header = _splitCsvLine(lines[0]).map((c) => c.trim()).toList();
    int findCol(bool Function(String) test, {int fallback = -1}) {
      for (var i = 0; i < header.length; i++) {
        if (test(header[i])) return i;
      }
      return fallback;
    }

    final dateIdx = findCol(
        (h) => h == '取引日' || h == '日付' || h.contains('取引日') || h.contains('日付'),
        fallback: 0);
    final descIdx = findCol(
        (h) => h.contains('摘要') || h.contains('適用') || h.contains('内容') || h.contains('お取引内容'),
        fallback: 1);
    final inIdx = findCol((h) => h.contains('入金'));
    final outIdx = findCol((h) => h.contains('出金'));
    final memoIdx = findCol((h) => h.contains('メモ') || h.contains('備考'));

    if (inIdx < 0 || outIdx < 0) {
      throw '入金金額／出金金額の列が見つかりません（対応形式：新生銀行 / GMOあおぞら）';
    }

    // 判別できた銀行名（バナー表示のみ・処理には影響しない）。
    String? bankLabel;
    if (header.isNotEmpty && header[0] == '日付') {
      bankLabel = 'GMOあおぞらネット銀行';
    } else if (header.isNotEmpty && header[0] == '取引日') {
      bankLabel = '新生銀行（SBI新生）';
    }

    String cell(List<String> cols, int idx) =>
        (idx >= 0 && idx < cols.length) ? cols[idx].trim() : '';

    final out = <_ParsedRow>[];
    for (var i = 1; i < lines.length; i++) {
      final cols = _splitCsvLine(lines[i]);
      if (cols.isEmpty) continue;
      final date = _parseDate(cell(cols, dateIdx));
      if (date == null) continue; // 日付でない行は無視
      // 半角カナ→全角カナに正規化（濁点ﾞの字形欠けで□になる文字化けを防ぐ）。
      final desc = halfToFullKana(cell(cols, descIdx));
      final inAmt = _parseInt(cell(cols, inIdx));
      final outAmt = _parseInt(cell(cols, outIdx));
      final memo = halfToFullKana(cell(cols, memoIdx));
      if (inAmt == 0 && outAmt == 0) continue;
      out.add(_ParsedRow(
        date: date,
        desc: desc,
        outAmount: outAmt,
        inAmount: inAmt,
        memo: memo.isEmpty ? null : memo,
        isTransfer: _looksLikeTransfer(desc),
      ));
    }
    return _ParseResult(rows: out, bankLabel: bankLabel);
  }

  /// 本人名義の振込＝自分の口座間移動なので「振替」既定。
  bool _looksLikeTransfer(String desc) {
    final n = desc.replaceAll(' ', '').replaceAll('　', '');
    return n.contains('ﾌﾀﾑﾗ') ||
        n.contains('二村') ||
        n.contains('フタムラ');
  }

  List<String> _splitCsvLine(String line) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          sb.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          out.add(sb.toString());
          sb.clear();
        } else {
          sb.write(c);
        }
      }
    }
    out.add(sb.toString());
    return out;
  }

  /// YYYY/MM/DD・YYYY-MM-DD（新生）と YYYYMMDD 区切りなし（GMOあおぞら）の両対応。
  DateTime? _parseDate(String s) {
    final t = s.trim();
    final sep = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})').firstMatch(t);
    if (sep != null) {
      return DateTime(int.parse(sep.group(1)!), int.parse(sep.group(2)!),
          int.parse(sep.group(3)!));
    }
    final packed = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(t);
    if (packed != null) {
      return DateTime(int.parse(packed.group(1)!), int.parse(packed.group(2)!),
          int.parse(packed.group(3)!));
    }
    return null;
  }

  int _parseInt(String s) =>
      int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  Future<void> _confirmAndImport() async {
    final rows = _rows;
    if (rows.isEmpty) return;
    final name = widget.account.name;
    final m = _month;
    final all = await TransactionRepository.instance.loadAll();
    final removeCount =
        all.where((t) => _involves(t, name) && _inMonth(t, m)).length;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('この月のデータを置き換えます'),
        content: Text(
            '${m.year}年${m.month}月の「${widget.account.name}」の既存明細 $removeCount 件を削除し、\n'
            'CSVの ${rows.length} 件（うち振替 ${rows.where((r) => r.isTransfer).length} 件）を取り込みます。\n\n'
            'よろしいですか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('取り込む')),
        ],
      ),
    );
    if (ok != true) return;
    await _import(rows, all);
  }

  bool _involves(core.Transaction t, String name) =>
      t.type == core.TransactionType.transfer
          ? (t.transferFromAccount == name || t.transferToAccount == name)
          : t.paymentMethod == name;

  bool _inMonth(core.Transaction t, DateTime m) =>
      t.date.year == m.year && t.date.month == m.month;

  Future<void> _import(
      List<_ParsedRow> rows, List<core.Transaction> all) async {
    // 非同期処理の後に context 経由で閉じると Windows で不発になり、取り込み画面が
    // くるくるのまま残る（＝背後の通帳が押せなくなる）。Navigator/Messenger は
    // await の前にキャプチャして確実に閉じる。
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final name = widget.account.name;
      final m = _month;
      // ① この口座・この月の既存明細を除外（＝クリア）。
      final kept =
          all.where((t) => !(_involves(t, name) && _inMonth(t, m))).toList();
      // ② CSVから取引を生成。
      final base = DateTime.now().microsecondsSinceEpoch;
      final now = DateTime.now();
      final ym = '${m.year}${m.month.toString().padLeft(2, '0')}';
      final imported = <core.Transaction>[];
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final id = 'bankcsv_${ym}_${base}_$i';
        if (r.isTransfer) {
          final out = r.outAmount > 0; // お金が出る＝振替元がこの口座
          imported.add(core.Transaction(
            id: id,
            date: r.date,
            type: core.TransactionType.transfer,
            category: const core.Category(major: '振替', sub: ''),
            paymentMethod: name,
            description: r.desc,
            amount: r.amount,
            transferFromAccount: out ? name : null,
            transferToAccount: out ? null : name,
            memo: r.memo,
            createdAt: now,
          ));
        } else {
          final isExpense = r.outAmount > 0;
          imported.add(core.Transaction(
            id: id,
            date: r.date,
            type: isExpense
                ? core.TransactionType.expense
                : core.TransactionType.income,
            category: const core.Category(major: '未分類', sub: ''),
            paymentMethod: name,
            description: r.desc,
            amount: r.amount,
            memo: r.memo,
            createdAt: now,
          ));
        }
      }
      await TransactionRepository.instance.replaceAll([...kept, ...imported]);
      messenger.showSnackBar(
        SnackBar(content: Text('${rows.length}件を取り込みました')),
      );
      // mounted に依存せず、キャプチャした Navigator で確実に閉じる。
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('取り込みに失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final transferCount = rows.where((r) => r.isTransfer).length;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.account.name} CSV取り込み',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // 対象月セレクタ。
          Container(
            color: const Color(0xFFF7F8FA),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                const Text('取り込む月: ',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                MonthNavBar(
                  label: '${_month.year}年${_month.month}月',
                  onPrev: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1)),
                  onNext: () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1)),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(_fileName == null ? 'CSVを選ぶ' : 'CSVを選び直す'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 説明バナー。
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF7ED),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              _fileName == null
                  ? 'CSVを選ぶと、その月の明細だけを取り込みます。'
                      '（新生銀行・GMOあおぞらネット銀行のCSVに自動対応）'
                  : '取り込むと、この月の「${widget.account.name}」の既存明細は消えて置き換わります。'
                      '「振替」ON の行は収支に入りません（口座間の移動）。',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
            ),
          ),
          if (_fileName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined,
                      size: 16, color: Color(0xFF6B7280)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        _bankLabel == null
                            ? '$_fileName'
                            : '$_fileName（$_bankLabel）',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                  ),
                  Text('${rows.length}件（振替 $transferCount）',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                ],
              ),
            ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                        _fileName == null
                            ? 'CSVファイルを選んでください'
                            : 'この月の明細はありません',
                        style: const TextStyle(color: Color(0xFF9CA3AF))),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFF1F2F4)),
                    itemBuilder: (_, i) => _rowTile(rows[i]),
                  ),
          ),
        ],
      ),
      bottomSheet: (rows.isEmpty)
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _confirmAndImport,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download_done),
                    label: Text('${rows.length}件を取り込む（この月を置き換え）'),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _rowTile(_ParsedRow r) {
    final isExpense = r.outAmount > 0;
    final Color amtColor = r.isTransfer
        ? const Color(0xFF2563EB)
        : (isExpense ? const Color(0xFFDC2626) : const Color(0xFF16A34A));
    final sign = isExpense ? '-' : '+';
    return InkWell(
      onTap: () => setState(() => r.isTransfer = !r.isTransfer),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text('${r.date.month}/${r.date.day}',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.desc.isEmpty ? '（摘要なし）' : r.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF111827))),
                  const SizedBox(height: 2),
                  Text(
                      r.isTransfer
                          ? '振替（収支に入れない）'
                          : (isExpense ? '出金 → 支出' : '入金 → 収入'),
                      style: TextStyle(fontSize: 11, color: amtColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('$sign${formatYen(r.amount)}',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: amtColor)),
            const SizedBox(width: 10),
            // 振替トグル。
            Column(
              children: [
                Switch(
                  value: r.isTransfer,
                  onChanged: (v) => setState(() => r.isTransfer = v),
                  activeThumbColor: const Color(0xFF2563EB),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Text('振替',
                    style: TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// パース結果（行 + 判別できた銀行名）。
class _ParseResult {
  _ParseResult({required this.rows, this.bankLabel});
  final List<_ParsedRow> rows;
  final String? bankLabel;
}

/// CSVから読み取った1行（取り込み前のプレビュー用）。
class _ParsedRow {
  _ParsedRow({
    required this.date,
    required this.desc,
    required this.outAmount,
    required this.inAmount,
    required this.isTransfer,
    this.memo,
  });

  final DateTime date;
  final String desc;
  final int outAmount; // 出金金額
  final int inAmount; // 入金金額
  final String? memo;
  bool isTransfer; // ユーザーが切り替え可能

  int get amount => outAmount > 0 ? outAmount : inAmount;
}
