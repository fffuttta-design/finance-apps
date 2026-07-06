import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'memo_field.dart';
import 'package:finance_core/finance_core.dart';

import '../utils/thousands_separator_input_formatter.dart';
import 'brand_logo.dart';

/// サブスク（固定費/変動費）の追加・編集シートを表示し、編集結果を返す。
///
/// 設定画面（SubscriptionListScreen）と支出タブ（V2ExpensesScreen）の両方から
/// 同じ編集UIを直接開けるよう、トップレベル関数として共通化したもの。
/// 返り値が null の場合はキャンセル。保存は呼び出し側で行う。
Future<Subscription?> showSubscriptionEditSheet(
  BuildContext context, {
  Subscription? initial,
  required List<String> paymentMethods,
  required List<String> categories,
  List<String> accountingMajors = const [],
}) {
  final nameCtrl = TextEditingController(text: initial?.name ?? '');
  // 変換中（composing）下線が金額欄に出ないコントローラ。
  final amountCtrl = NoComposingUnderlineController(
      text: initial != null ? formatAmount(initial.amount) : '');
  // 毎月の請求日（1〜31）。プルダウンで選択。
  int? billingDay = initial?.billingDay;
  final memoCtrl = TextEditingController(text: initial?.memo ?? '');
  final iconUrlCtrl = TextEditingController(text: initial?.iconUrl ?? '');
  // ロゴのURL入力欄を開いているか。既にロゴがあるときは閉じておき（＝
  // URLをベタ表示せず「ロゴ編集」ボタンだけ）、押したら開く。
  bool logoEditing = (initial?.iconUrl ?? '').trim().isEmpty;
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

    final hasLogo = iconUrlCtrl.text.trim().isNotEmpty;
    // ロゴ設定済みで編集中でなければ、URLは出さずプレビュー＋「ロゴ編集」だけ。
    if (hasLogo && !logoEditing) {
      return Row(
        children: [
          BrandLogo(iconUrl: iconUrlCtrl.text.trim(),
              fallbackEmoji: '🔁', size: 40),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('ロゴ設定済み',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ),
          OutlinedButton.icon(
            onPressed: () => setLocal(() => logoEditing = true),
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('ロゴ編集'),
          ),
        ],
      );
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
          final memo =
              memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
          final iconUrl = iconUrlCtrl.text.trim().isEmpty
              ? null
              : iconUrlCtrl.text.trim();
          final pl = (plMajor == null || plMajor!.trim().isEmpty)
              ? null
              : plMajor!.trim();
          // カテゴリ（まとめ表示用）は会計科目を兼用する。
          final category = pl;
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
                          DropdownButtonFormField<int?>(
                            initialValue: billingDay,
                            decoration: const InputDecoration(
                              labelText: '毎月の請求日（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                  value: null, child: Text('未設定')),
                              for (var d = 1; d <= 31; d++)
                                DropdownMenuItem<int?>(
                                    value: d, child: Text('$d 日')),
                            ],
                            onChanged: (v) =>
                                setLocal(() => billingDay = v),
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
                        if (accountingMajors.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text('会計科目（カテゴリ兼用・業績PLに合算）',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280))),
                          const SizedBox(height: 2),
                          const Text(
                              '同じ科目でまとめてセクション表示。実体の科目（通信費・賃借料等）でPLにも反映',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF9CA3AF))),
                          const SizedBox(height: 8),
                          // 会計科目は「支出を記録」と同じくプルダウンで選ぶ。
                          DropdownButtonFormField<String>(
                            initialValue: plMajor,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              hintText: '選択してください（任意）',
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                  value: null, child: Text('指定なし')),
                              // 一覧に無い値（旧データ等）も選択肢として保持。
                              if (plMajor != null &&
                                  plMajor!.trim().isNotEmpty &&
                                  !accountingMajors.contains(plMajor))
                                DropdownMenuItem(
                                    value: plMajor, child: Text(plMajor!)),
                              for (final m in accountingMajors)
                                DropdownMenuItem(value: m, child: Text(m)),
                            ],
                            onChanged: (v) => setLocal(() => plMajor = v),
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
                        MemoField(controller: memoCtrl),
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
