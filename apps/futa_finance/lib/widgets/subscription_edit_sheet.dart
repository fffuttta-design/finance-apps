import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'memo_field.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../screens/category_editor_screen.dart';
import '../screens/category_sub_editor_screen.dart';
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
  // 大カテゴリ（表示名）＋その小カテゴリ一覧。固定費に普通のカテゴリを付けるため。
  List<({String major, List<String> subs})> categoryOptions = const [],
}) {
  final nameCtrl = TextEditingController(text: initial?.name ?? '');
  // 変換中（composing）下線が金額欄に出ないコントローラ。
  final amountCtrl = NoComposingUnderlineController(
      text: initial != null ? formatAmount(initial.amount) : '');
  // 毎月の請求日（1〜31）。プルダウンで選択。
  int? billingDay = initial?.billingDay;
  final memoCtrl = TextEditingController(text: initial?.memo ?? '');
  // 場所（明細化したとき取引の store に入る）。
  final storeCtrl = TextEditingController(text: initial?.store ?? '');
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
  // 明細化に使う「普通の大/小カテゴリ」（固定費はフラグで表す）。
  String? categoryMajor = initial?.categoryMajor;
  String? categorySub = initial?.categorySub;
  // PL計上の開始年月（"YYYY-MM"）。これより前は業績PLに計上しない。
  String? startYm = initial?.startYearMonth;

  // カテゴリはこのシートからも編集できる（編集画面から戻ったら読み直す）ので、
  // 引数のリストをそのまま使わず、書き換えられるコピーを持つ。
  var options = List<({String major, List<String> subs})>.of(categoryOptions);

  String bareName(String s) =>
      s.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
  List<String> subsOfMajor(String? m) {
    if (m == null) return const [];
    for (final o in options) {
      if (o.major == m) return o.subs;
    }
    return const [];
  }

  /// カテゴリ編集画面から戻ったあと、候補を読み直して選択中の値の整合を取る。
  Future<void> reloadCategories(StateSetter setLocal) async {
    final c = await SettingsRepository().loadCategories();
    final next = <({String major, List<String> subs})>[];
    for (var i = 0; i < c.majors.length; i++) {
      final m = c.majors[i];
      if (m.inactive) continue;
      next.add((major: m.displayName(i), subs: m.subs));
    }
    setLocal(() {
      options = next;
      // 選んでいたカテゴリが消えていたら選択を外す（Dropdownが値を見つけられず落ちる）。
      if (categoryMajor != null &&
          !options.any((o) => o.major == categoryMajor)) {
        categoryMajor = null;
        categorySub = null;
      } else if (categorySub != null &&
          !subsOfMajor(categoryMajor).contains(categorySub)) {
        categorySub = null;
      }
    });
  }

  /// 小カテゴリ編集画面に渡す「大カテゴリの番号」を、表示名から引く。
  /// 表示名は "1.通信費" のように番号付きなので、素の名前でも突き合わせる。
  Future<int> majorIndexOf(String displayName) async {
    final c = await SettingsRepository().loadCategories();
    String norm(String s) => s.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
    for (var i = 0; i < c.majors.length; i++) {
      final dn = c.majors[i].displayName(i);
      if (dn == displayName || norm(dn) == norm(displayName)) return i;
    }
    return -1;
  }

  /// 「カテゴリ編集」リンク（支出フォームと同じ導線）。
  Widget categoryEditLink(String label, VoidCallback onTap) => Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.tune, size: 14),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        ),
      );

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
          // 大カテゴリを選んでいれば、それをPL科目・セクションにも兼用する
          // （番号プレフィックスを外した素の名前）。未選択なら従来の会計科目。
          final cm = (categoryMajor == null || categoryMajor!.trim().isEmpty)
              ? null
              : categoryMajor!.trim();
          final pl = cm != null
              ? bareName(cm)
              : ((plMajor == null || plMajor.trim().isEmpty)
                  ? null
                  : plMajor.trim());
          // カテゴリ（まとめ表示用）は大カテゴリ/会計科目を兼用する。
          final category = pl;
          final cs = (categorySub == null || categorySub!.trim().isEmpty)
              ? null
              : categorySub!.trim();
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
            categoryMajor: cm,
            categorySub: cs,
            store: storeCtrl.text.trim().isEmpty
                ? null
                : storeCtrl.text.trim(),
            startYearMonth:
                (startYm == null || startYm!.trim().isEmpty)
                    ? null
                    : startYm,
            // 変動費の月別実額は編集で消さない（保持）。
            monthlyActuals: initial?.monthlyActuals ?? const {},
            // 領収書の受け取り方など、その他の既存項目も保持。
            receiptKind: initial?.receiptKind,
            reviewedMonths: initial?.reviewedMonths ?? const {},
            sortOrder: initial?.sortOrder,
            endYearMonth: initial?.endYearMonth,
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
                        if (options.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Expanded(
                                child: Text('カテゴリ（明細に付く大/小カテゴリ）',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280))),
                              ),
                              // 支出フォームと同じく、ここからカテゴリ自体を編集できる。
                              categoryEditLink('カテゴリ編集', () async {
                                await Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const CategoryEditorScreen()),
                                );
                                await reloadCategories(setLocal);
                              }),
                            ],
                          ),
                          const Text(
                              '「固定費」はフラグとして持ち、大/小カテゴリは普通のカテゴリ（食費・自己投資など）を使います',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF9CA3AF))),
                          const SizedBox(height: 8),
                          // 大カテゴリ（支出を記録と同じ普通のカテゴリ）。
                          DropdownButtonFormField<String>(
                            key: ValueKey('major_${options.length}_$categoryMajor'),
                            initialValue: categoryMajor,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              labelText: '大カテゴリ',
                              hintText: '選択してください（任意）',
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                  value: null, child: Text('指定なし')),
                              if (categoryMajor != null &&
                                  categoryMajor!.trim().isNotEmpty &&
                                  !options
                                      .any((o) => o.major == categoryMajor))
                                DropdownMenuItem(
                                    value: categoryMajor,
                                    child: Text(bareName(categoryMajor!))),
                              for (final o in options)
                                DropdownMenuItem(
                                    value: o.major,
                                    child: Text(bareName(o.major))),
                            ],
                            onChanged: (v) => setLocal(() {
                              categoryMajor = v;
                              final subs = subsOfMajor(v);
                              categorySub =
                                  subs.isNotEmpty ? subs.first : null;
                            }),
                          ),
                          // 大カテゴリを選んでいれば小カテゴリの編集リンクを出す。
                          // ⚠ 小カテゴリが0件のときも出す（ここから追加したいので）。
                          if (categoryMajor != null)
                            categoryEditLink('小カテゴリ編集', () async {
                              final idx = await majorIndexOf(categoryMajor!);
                              if (idx < 0) return;
                              if (!context.mounted) return;
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => CategorySubEditorScreen(
                                        majorIndex: idx)),
                              );
                              await reloadCategories(setLocal);
                            }),
                          if (categoryMajor != null &&
                              subsOfMajor(categoryMajor).isNotEmpty) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                  'sub_${subsOfMajor(categoryMajor).length}_$categorySub'),
                              initialValue:
                                  subsOfMajor(categoryMajor).contains(categorySub)
                                      ? categorySub
                                      : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                labelText: '小カテゴリ',
                                hintText: '選択してください（任意）',
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                    value: null, child: Text('指定なし')),
                                for (final s in subsOfMajor(categoryMajor))
                                  DropdownMenuItem(
                                      value: s, child: Text(s)),
                              ],
                              onChanged: (v) =>
                                  setLocal(() => categorySub = v),
                            ),
                          ],
                          // 場所（店名・サービス名）。明細化したとき取引の「場所」に入る。
                          const SizedBox(height: 10),
                          TextField(
                            controller: storeCtrl,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              labelText: '場所（任意）',
                              hintText: '例: Amazon・コミュファ光',
                              helperText: '明細に付く「場所」。場所別の集計に出ます',
                            ),
                          ),
                          if (categoryMajor != null) ...[
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
