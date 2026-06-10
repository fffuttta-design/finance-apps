import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../utils/thousands_separator_input_formatter.dart';
import 'brand_logo.dart';

/// サブスク（固定費/変動費）の追加・編集シートを表示し、編集結果を返す。
///
/// 設定画面（SubscriptionListScreen）と支出タブ（V2ExpensesScreen）の両方から
/// 同じ編集UIを直接開けるよう、トップレベル関数として共通化したもの。
/// 返り値が null の場合はキャンセル。保存は呼び出し側で行う。
/// 「＋ 新しいカテゴリ…」選択時に名前を入力させる小ダイアログ。
Future<String?> _promptNewCategory(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: const Text('新しいカテゴリ'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'カテゴリ名',
          hintText: '例: 住居系 / 娯楽系 / 通信',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(dctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, null),
            child: const Text('キャンセル')),
        FilledButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text),
            child: const Text('追加')),
      ],
    ),
  );
}

Future<Subscription?> showSubscriptionEditSheet(
  BuildContext context, {
  Subscription? initial,
  required List<String> paymentMethods,
  required List<String> categories,
  List<String> accountingMajors = const [],
}) {
  final nameCtrl = TextEditingController(text: initial?.name ?? '');
  final amountCtrl = TextEditingController(
      text: initial != null ? formatAmount(initial.amount) : '');
  final billingDayCtrl =
      TextEditingController(text: initial?.billingDay?.toString() ?? '');
  final memoCtrl = TextEditingController(text: initial?.memo ?? '');
  final iconUrlCtrl = TextEditingController(text: initial?.iconUrl ?? '');
  // カテゴリ（=セクション）。プルダウンで既存から選択。新規は「＋新規」で追加。
  final cats = <String>[
    for (final c in categories)
      if (c.trim().isNotEmpty) c.trim(),
  ];
  String? categorySel =
      (initial?.category?.trim().isEmpty ?? true) ? null : initial!.category!.trim();
  if (categorySel != null && !cats.contains(categorySel)) {
    cats.add(categorySel);
  }
  SubscriptionCycle cycle = initial?.cycle ?? SubscriptionCycle.monthly;
  SubscriptionAmountType amountType =
      initial?.amountType ?? SubscriptionAmountType.fixed;
  DateTime? nextDate = initial?.nextBillingDate;
  String? paymentMethod = initial?.paymentMethod;
  // 紐づける会計科目（PL科目）。accountingMajors に無い値でも保持する。
  String? plMajor = initial?.plMajor;
  // PL計上の開始年月（"YYYY-MM"）。これより前は業績PLに計上しない。
  String? startYm = initial?.startYearMonth;

  Future<void> pickAnnualDate(StateSetter setLocal) async {
    DateTime temp = nextDate ?? DateTime.now();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: 280,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(sheet, null),
                      child: const Text('キャンセル')),
                  const Text('次回請求日',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  TextButton(
                      onPressed: () => Navigator.pop(sheet, temp),
                      child: const Text('完了',
                          style: TextStyle(
                              color: Color(0xFF1A237E),
                              fontWeight: FontWeight.w700))),
                ],
              ),
              Container(height: 1, color: const Color(0xFFE5E7EB)),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: temp,
                  minimumDate: DateTime(2020),
                  maximumDate: DateTime(2035, 12, 31),
                  dateOrder: DatePickerDateOrder.ymd,
                  onDateTimeChanged: (d) => temp = d,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setLocal(() => nextDate = picked);
  }

  Future<void> pickStartMonth(StateSetter setLocal) async {
    DateTime temp = startYm != null && startYm!.contains('-')
        ? DateTime(int.parse(startYm!.split('-')[0]),
            int.parse(startYm!.split('-')[1]))
        : DateTime.now();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: 280,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(sheet, null),
                      child: const Text('キャンセル')),
                  const Text('計上開始年月',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  TextButton(
                      onPressed: () => Navigator.pop(sheet, temp),
                      child: const Text('完了',
                          style: TextStyle(
                              color: Color(0xFF1A237E),
                              fontWeight: FontWeight.w700))),
                ],
              ),
              Container(height: 1, color: const Color(0xFFE5E7EB)),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.monthYear,
                  initialDateTime: temp,
                  minimumDate: DateTime(2018),
                  maximumDate: DateTime(2035, 12, 31),
                  dateOrder: DatePickerDateOrder.ymd,
                  onDateTimeChanged: (d) => temp = d,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setLocal(() => startYm =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}');
    }
  }

  Widget logoUrlField(void Function(VoidCallback fn) setLocal) {
    void convertDomain() {
      final input = iconUrlCtrl.text.trim();
      if (input.isEmpty) return;
      if (input.contains('favicon') ||
          RegExp(r'\.(png|jpg|jpeg|svg|gif|webp|ico)(\?|$)',
                  caseSensitive: false)
              .hasMatch(input)) {
        return;
      }
      final url = domainToFaviconUrl(input);
      if (url != null) setLocal(() => iconUrlCtrl.text = url);
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: iconUrlCtrl,
            decoration: InputDecoration(
              labelText: 'ロゴURL or ドメイン（任意）',
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
          iconUrl:
              iconUrlCtrl.text.trim().isEmpty ? null : iconUrlCtrl.text.trim(),
          fallbackEmoji: '🔁',
          size: 40,
        ),
      ],
    );
  }

  return showModalBottomSheet<Subscription?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final isValid = nameCtrl.text.trim().isNotEmpty &&
            (parseAmount(amountCtrl.text) ?? 0) > 0;

        void onSave() {
          final name = nameCtrl.text.trim();
          final amount = parseAmount(amountCtrl.text);
          if (name.isEmpty || amount == null || amount <= 0) {
            Navigator.pop(ctx, null);
            return;
          }
          final billingDay = int.tryParse(billingDayCtrl.text.trim());
          final memo =
              memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
          final iconUrl = iconUrlCtrl.text.trim().isEmpty
              ? null
              : iconUrlCtrl.text.trim();
          final category =
              (categorySel == null || categorySel!.trim().isEmpty)
                  ? null
                  : categorySel!.trim();
          final pl = (plMajor == null || plMajor!.trim().isEmpty)
              ? null
              : plMajor!.trim();
          final result = Subscription(
            id: initial?.id ??
                DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            amount: amount,
            cycle: cycle,
            amountType: amountType,
            billingDay:
                cycle == SubscriptionCycle.monthly ? billingDay : null,
            nextBillingDate:
                cycle == SubscriptionCycle.annually ? nextDate : null,
            paymentMethod: paymentMethod,
            memo: memo,
            iconUrl: iconUrl,
            category: category,
            plMajor: pl,
            startYearMonth:
                (startYm == null || startYm!.trim().isEmpty)
                    ? null
                    : startYm,
            // 変動費の月別実額は編集で消さない（保持）。
            monthlyActuals: initial?.monthlyActuals ?? const {},
          );
          Navigator.pop(ctx, result);
        }

        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                          initial == null ? '固定費を追加' : '固定費を編集',
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
                                labelText: '名前（必須）',
                                hintText: '例: ChatGPT, 電気代',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always),
                            onChanged: (_) => setLocal(() {})),
                        const SizedBox(height: 12),
                        TextField(
                          controller: amountCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            HalfWidthDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(),
                          ],
                          decoration: InputDecoration(
                            labelText:
                                amountType == SubscriptionAmountType.fixed
                                    ? '金額 円（必須）'
                                    : '目安金額 円（必須）',
                            helperText: amountType ==
                                    SubscriptionAmountType.variable
                                ? '実際の請求額は月により変動'
                                : null,
                            floatingLabelBehavior:
                                FloatingLabelBehavior.always,
                          ),
                          onChanged: (_) => setLocal(() {}),
                        ),
                        const SizedBox(height: 16),
                        const Text('金額タイプ',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280))),
                        const SizedBox(height: 4),
                        SegmentedButton<SubscriptionAmountType>(
                          segments: const [
                            ButtonSegment(
                              value: SubscriptionAmountType.fixed,
                              label: Text('定額'),
                              icon: Icon(Icons.lock_outline),
                            ),
                            ButtonSegment(
                              value: SubscriptionAmountType.variable,
                              label: Text('変動'),
                              icon: Icon(Icons.trending_up),
                            ),
                          ],
                          selected: {amountType},
                          onSelectionChanged: (s) =>
                              setLocal(() => amountType = s.first),
                        ),
                        const SizedBox(height: 16),
                        const Text('請求サイクル',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280))),
                        const SizedBox(height: 4),
                        SegmentedButton<SubscriptionCycle>(
                          segments: const [
                            ButtonSegment(
                              value: SubscriptionCycle.monthly,
                              label: Text('月払い'),
                              icon: Icon(Icons.calendar_view_month),
                            ),
                            ButtonSegment(
                              value: SubscriptionCycle.annually,
                              label: Text('年払い'),
                              icon: Icon(Icons.calendar_today),
                            ),
                          ],
                          selected: {cycle},
                          onSelectionChanged: (s) =>
                              setLocal(() => cycle = s.first),
                        ),
                        const SizedBox(height: 16),
                        if (cycle == SubscriptionCycle.monthly) ...[
                          TextField(
                            controller: billingDayCtrl,
                            keyboardType: TextInputType.number,
                            maxLength: 2,
                            decoration: const InputDecoration(
                              labelText: '毎月の請求日（1〜31、任意）',
                              counterText: '',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                        ] else ...[
                          InkWell(
                            onTap: () => pickAnnualDate(setLocal),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: const Color(0xFFE5E7EB)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today,
                                      size: 16, color: Color(0xFF6B7280)),
                                  const SizedBox(width: 8),
                                  Text(
                                    nextDate == null
                                        ? '次回請求日を選択'
                                        : '${nextDate!.year}年${nextDate!.month}月${nextDate!.day}日',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: nextDate == null
                                            ? const Color(0xFF9CA3AF)
                                            : const Color(0xFF111827)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (paymentMethods.isNotEmpty)
                          DropdownButtonFormField<String>(
                            initialValue: paymentMethod,
                            decoration: InputDecoration(
                              labelText: '支払方法（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              suffixIcon: paymentMethod != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear,
                                          size: 18),
                                      visualDensity: VisualDensity.compact,
                                      tooltip: '支払方法をクリア',
                                      onPressed: () => setLocal(
                                          () => paymentMethod = null),
                                    )
                                  : null,
                            ),
                            items: paymentMethods
                                .map((p) => DropdownMenuItem(
                                    value: p, child: Text(p)))
                                .toList(),
                            onChanged: (v) =>
                                setLocal(() => paymentMethod = v),
                          ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: categorySel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'カテゴリ（任意）',
                            floatingLabelBehavior:
                                FloatingLabelBehavior.always,
                            helperText: '同じカテゴリ名でまとめてセクション表示されます',
                          ),
                          hint: const Text('（未分類）'),
                          items: [
                            const DropdownMenuItem<String>(
                                value: null, child: Text('（未分類）')),
                            for (final c in cats)
                              DropdownMenuItem<String>(
                                  value: c, child: Text(c)),
                            const DropdownMenuItem<String>(
                                value: '__new__',
                                child: Text('＋ 新しいカテゴリ…',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700))),
                          ],
                          onChanged: (v) async {
                            if (v == '__new__') {
                              final name = await _promptNewCategory(ctx);
                              if (name == null || name.trim().isEmpty) return;
                              final n = name.trim();
                              setLocal(() {
                                if (!cats.contains(n)) cats.add(n);
                                categorySel = n;
                              });
                            } else {
                              setLocal(() => categorySel = v);
                            }
                          },
                        ),
                        if (accountingMajors.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue:
                                accountingMajors.contains(plMajor)
                                    ? plMajor
                                    : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: '会計科目（任意・業績PLに合算）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              helperText:
                                  '「固定費」は支払形態。実体の科目（通信費・賃借料等）を選ぶとPLに反映',
                              suffixIcon: plMajor != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear,
                                          size: 18),
                                      visualDensity:
                                          VisualDensity.compact,
                                      tooltip: '会計科目をクリア',
                                      onPressed: () =>
                                          setLocal(() => plMajor = null),
                                    )
                                  : null,
                            ),
                            items: accountingMajors
                                .map((m) => DropdownMenuItem(
                                    value: m, child: Text(m)))
                                .toList(),
                            onChanged: (v) =>
                                setLocal(() => plMajor = v),
                          ),
                          if (plMajor != null) ...[
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () => pickStartMonth(setLocal),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: '計上開始年月（任意）',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  helperText:
                                      'この月より前は業績PLに計上しません（未来は当月まで）',
                                  suffixIcon: startYm != null
                                      ? IconButton(
                                          icon: const Icon(Icons.clear,
                                              size: 18),
                                          visualDensity:
                                              VisualDensity.compact,
                                          onPressed: () => setLocal(
                                              () => startYm = null),
                                        )
                                      : const Icon(
                                          Icons.calendar_today,
                                          size: 18),
                                ),
                                child: Text(
                                  startYm == null
                                      ? '未設定（開始から計上）'
                                      : '${startYm!.split('-')[0]}年${int.parse(startYm!.split('-')[1])}月〜',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: startYm == null
                                          ? const Color(0xFF9CA3AF)
                                          : const Color(0xFF111827)),
                                ),
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        logoUrlField(setLocal),
                        const SizedBox(height: 12),
                        TextField(
                            controller: memoCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                                labelText: '備考（任意）',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always)),
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
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
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
}
