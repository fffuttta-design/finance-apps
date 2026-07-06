import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../widgets/memo_field.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../data/subscription_repository.dart';
import '../utils/formatters.dart';
import '../utils/thousands_separator_input_formatter.dart';
import '../widgets/brand_logo.dart';
import '../widgets/centered_body.dart';

/// 並び順モード。
/// - manual: ユーザーがドラッグで並べた順（永続化される配列の順）
/// - amountDesc: 月額換算の高い順
/// - amountAsc: 月額換算の安い順
enum _SortMode { manual, amountDesc, amountAsc }

/// セクションのグループ化軸。none=フラット表示、byCategory=ユーザーカテゴリ別、
/// byAmountType=定額/変動別。
enum _GroupMode { none, byCategory, byAmountType }

/// 固定費一覧のCRUD画面。月払い/年払い・定額/変動を統一管理。
class SubscriptionListScreen extends StatefulWidget {
  /// 起動時に自動で編集モーダルを開く対象 subscription の ID。
  /// 支出タブの「毎月引落予定」行からのディープリンク用。
  final String? initialEditId;

  const SubscriptionListScreen({super.key, this.initialEditId});

  @override
  State<SubscriptionListScreen> createState() => _SubscriptionListScreenState();
}

class _SubscriptionListScreenState extends State<SubscriptionListScreen> {
  final _repo = SubscriptionRepository.instance;
  final _settings = SettingsRepository();
  SubscriptionConfig? _config;
  PaymentMethodsConfig? _payments;

  /// 並び順モード。デフォルトは「定額/変動別＋月額の高い順」。
  /// （グループ分けは常に有効。手動ドラッグにしたいときは並び替えメニューで切替）
  _SortMode _sortMode = _SortMode.amountDesc;

  /// グループ表示モード。デフォルトは「定額/変動別」（変動費を上に目立たせる）。
  _GroupMode _groupMode = _GroupMode.byAmountType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.load();
    final p = await _settings.loadPayments();
    if (!mounted) return;
    setState(() {
      _config = c;
      _payments = p;
    });
    // ディープリンク: 起動時に編集モーダルを自動で開く（一度だけ）。
    final editId = widget.initialEditId;
    if (editId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editById(editId);
      });
    }
  }

  Future<void> _save() async {
    final c = _config;
    if (c != null) await _repo.save(c);
  }

  void _update(List<Subscription> newList) {
    setState(() => _config = _config!.copyWith(subscriptions: newList));
    _save();
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  List<String> get _paymentMethods {
    final p = _payments;
    if (p == null) return const [];
    return [
      ...p.bankAccounts.map((b) => b.name),
      ...p.creditCards.map((c) => c.name),
    ];
  }


  Future<Subscription?> _editDialog(
      BuildContext context, Subscription? initial) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    // 変換中（composing）下線が金額欄に出ないコントローラ。
    final amountCtrl = NoComposingUnderlineController(
        text: initial != null ? formatAmount(initial.amount) : '');
    // 毎月の請求日（1〜31）。プルダウンで選択。
    int? billingDay = initial?.billingDay;
    final memoCtrl = TextEditingController(text: initial?.memo ?? '');
    final iconUrlCtrl =
        TextEditingController(text: initial?.iconUrl ?? '');
    // ロゴ設定済みなら最初は「ロゴ編集」ボタンだけ（URLをベタ表示しない）。
    bool logoEditing = (initial?.iconUrl ?? '').trim().isEmpty;
    SubscriptionCycle cycle = initial?.cycle ?? SubscriptionCycle.monthly;
    SubscriptionAmountType amountType =
        initial?.amountType ?? SubscriptionAmountType.fixed;
    DateTime? nextDate = initial?.nextBillingDate;
    String? paymentMethod = initial?.paymentMethod;
    String? plMajor = initial?.plMajor;
    String? startYm = initial?.startYearMonth;
    String? endYm = initial?.endYearMonth;
    // 実明細化したときの領収書の受け取り方（'paper'/'drive'/null）。
    String? receiptKind = initial?.receiptKind;

    // 会計科目（PL科目）候補 = 現モードの大カテゴリ名（番号なし素の名前）。
    final catConfig = await _settings.loadCategories();
    final accountingMajors =
        catConfig.majors.map((m) => m.name).toList();
    if (!context.mounted) return null;

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

    Future<void> pickEndMonth(StateSetter setLocal) async {
      DateTime temp = endYm != null && endYm!.contains('-')
          ? DateTime(int.parse(endYm!.split('-')[0]),
              int.parse(endYm!.split('-')[1]))
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
                    const Text('計上終了年月',
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
        setLocal(() => endYm =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}');
      }
    }

    // 編集フォームを BottomSheet で表示する。
    // - 上端のハンドルでドラッグ可能感を出す
    // - 高さは画面の92%、内部は SingleChildScrollView でスクロール
    // - 「キャンセル/保存」は下端に固定（スクロールしても常に見える）
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
          // フォーム入力可否（バリデーション）
          final isValid = nameCtrl.text.trim().isNotEmpty &&
              (parseAmount(amountCtrl.text) ?? 0) > 0;

          void onSave() {
            final name = nameCtrl.text.trim();
            final amount = parseAmount(amountCtrl.text);
            if (name.isEmpty || amount == null || amount <= 0) {
              Navigator.pop(ctx, null);
              return;
            }
            final memo = memoCtrl.text.trim().isEmpty
                ? null
                : memoCtrl.text.trim();
            final iconUrl = iconUrlCtrl.text.trim().isEmpty
                ? null
                : iconUrlCtrl.text.trim();
            final pl = (plMajor == null || plMajor!.trim().isEmpty)
                ? null
                : plMajor!.trim();
            // カテゴリ（まとめ表示用）は会計科目を兼用する。
            final category = pl;
            final result = Subscription(
              id: initial?.id ?? _genId(),
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
              receiptKind: receiptKind,
              startYearMonth:
                  (startYm == null || startYm!.trim().isEmpty)
                      ? null
                      : startYm,
              endYearMonth: (endYm == null || endYm!.trim().isEmpty)
                  ? null
                  : endYm,
              // 変動費の月別実額は編集で消さない（保持）。
              monthlyActuals: initial?.monthlyActuals ?? const {},
            );
            Navigator.pop(ctx, result);
          }

          return Padding(
            // キーボード分のpadding（IME表示時にコンテンツが隠れない）
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: FractionallySizedBox(
              heightFactor: 0.92,
              child: Column(
                children: [
                  // ハンドル（ドラッグ可能感を視覚化）
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
                  // タイトル
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
                  // スクロール領域
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
                              helperText:
                                  amountType == SubscriptionAmountType.variable
                                      ? '実際の請求額は月により変動'
                                      : null,
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                            onChanged: (_) => setLocal(() {}),
                          ),
                          const SizedBox(height: 16),
                          // 金額タイプ
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
                          // サイクル切替
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
                          // サイクルごとの追加フィールド
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
                                        size: 16,
                                        color: Color(0xFF6B7280)),
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
                          if (_paymentMethods.isNotEmpty)
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
                                        visualDensity:
                                            VisualDensity.compact,
                                        tooltip: '支払方法をクリア',
                                        onPressed: () => setLocal(
                                            () => paymentMethod = null),
                                      )
                                    : null,
                              ),
                              items: _paymentMethods
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
                          ],
                          // 領収書の受け取り方（実明細化した取引に反映）。
                          const SizedBox(height: 16),
                          const Text('領収書の受け取り方（実明細化時に反映）',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280))),
                          const SizedBox(height: 2),
                          const Text(
                              '紙＝現物を税理士へ（自動で「保管済み」に）／ドライブ＝電子保存／指定なし',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF9CA3AF))),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('🧾 紙で保管'),
                                selected: receiptKind == 'paper',
                                onSelected: (sel) => setLocal(
                                    () => receiptKind = sel ? 'paper' : null),
                              ),
                              ChoiceChip(
                                label: const Text('📄 ドライブ'),
                                selected: receiptKind == 'drive',
                                onSelected: (sel) => setLocal(
                                    () => receiptKind = sel ? 'drive' : null),
                              ),
                              ChoiceChip(
                                label: const Text('指定なし'),
                                selected: receiptKind == null,
                                onSelected: (_) =>
                                    setLocal(() => receiptKind = null),
                              ),
                            ],
                          ),
                          // 計上期間（開始月・終了月）。会計科目の有無に関わらず常に設定可。
                          // 契約の開始/解約を記録し、業績PL計上の範囲を絞る。
                          const SizedBox(height: 16),
                          const Text('計上期間（任意）',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280))),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => pickStartMonth(setLocal),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: '開始月',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      isDense: true,
                                      suffixIcon: startYm != null
                                          ? IconButton(
                                              icon: const Icon(Icons.clear,
                                                  size: 16),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () => setLocal(
                                                  () => startYm = null),
                                            )
                                          : const Icon(
                                              Icons.calendar_today,
                                              size: 16),
                                    ),
                                    child: Text(
                                      startYm == null
                                          ? '指定なし'
                                          : '${startYm!.split('-')[0]}年${int.parse(startYm!.split('-')[1])}月〜',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: startYm == null
                                              ? const Color(0xFF9CA3AF)
                                              : const Color(0xFF111827)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: InkWell(
                                  onTap: () => pickEndMonth(setLocal),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: '終了月',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      isDense: true,
                                      suffixIcon: endYm != null
                                          ? IconButton(
                                              icon: const Icon(Icons.clear,
                                                  size: 16),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () => setLocal(
                                                  () => endYm = null),
                                            )
                                          : const Icon(
                                              Icons.event_busy,
                                              size: 16),
                                    ),
                                    child: Text(
                                      endYm == null
                                          ? '継続中'
                                          : '〜${endYm!.split('-')[0]}年${int.parse(endYm!.split('-')[1])}月',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: endYm == null
                                              ? const Color(0xFF9CA3AF)
                                              : const Color(0xFF111827)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 4, left: 2),
                            child: Text(
                              '会計科目を設定すると、この期間だけ業績PLに計上します（未来は当月まで）。',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF9CA3AF)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _logoUrlField(iconUrlCtrl, '🔁', setLocal,
                              editing: logoEditing,
                              onEdit: () =>
                                  setLocal(() => logoEditing = true)),
                          const SizedBox(height: 12),
                          MemoField(controller: memoCtrl),
                          // 下端のフッターに被らないようのpadding
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  // 固定フッター
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
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
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
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
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

  Future<void> _add() async {
    final r = await _editDialog(context, null);
    if (r == null) return;
    _update([..._config!.subscriptions, r]);
  }

  Future<void> _edit(int i) async {
    final r = await _editDialog(context, _config!.subscriptions[i]);
    if (r == null) return;
    final list = [..._config!.subscriptions];
    list[i] = r;
    _update(list);
  }

  Future<void> _delete(int i) async {
    final s = _config!.subscriptions[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${s.name} を削除？'),
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
    final list = [..._config!.subscriptions]..removeAt(i);
    _update(list);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('固定費一覧',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        actions: [
          // グループ表示モード切替（フラット / カテゴリ別 / 定額・変動別）
          PopupMenuButton<_GroupMode>(
            tooltip: 'グループ表示',
            icon: Icon(
              _groupMode == _GroupMode.none
                  ? Icons.folder_off_outlined
                  : _groupMode == _GroupMode.byAmountType
                      ? Icons.swap_vert
                      : Icons.folder,
              color: const Color(0xFF1A237E),
            ),
            initialValue: _groupMode,
            onSelected: (v) => setState(() => _groupMode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _GroupMode.byCategory,
                child: Row(children: [
                  Icon(Icons.folder, size: 18),
                  SizedBox(width: 8),
                  Text('カテゴリ別'),
                ]),
              ),
              PopupMenuItem(
                value: _GroupMode.byAmountType,
                child: Row(children: [
                  Icon(Icons.swap_vert, size: 18),
                  SizedBox(width: 8),
                  Text('定額/変動別'),
                ]),
              ),
              PopupMenuItem(
                value: _GroupMode.none,
                child: Row(children: [
                  Icon(Icons.folder_off_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('フラット（分類なし）'),
                ]),
              ),
            ],
          ),
          // 並び順
          PopupMenuButton<_SortMode>(
            tooltip: '並び順',
            icon: const Icon(Icons.sort, color: Color(0xFF1A237E)),
            initialValue: _sortMode,
            onSelected: (v) => setState(() => _sortMode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _SortMode.manual,
                child: Row(children: [
                  Icon(Icons.drag_indicator, size: 18),
                  SizedBox(width: 8),
                  Text('手動（ドラッグ並び替え）'),
                ]),
              ),
              PopupMenuItem(
                value: _SortMode.amountDesc,
                child: Row(children: [
                  Icon(Icons.south, size: 18),
                  SizedBox(width: 8),
                  Text('月額の高い順'),
                ]),
              ),
              PopupMenuItem(
                value: _SortMode.amountAsc,
                child: Row(children: [
                  Icon(Icons.north, size: 18),
                  SizedBox(width: 8),
                  Text('月額の安い順'),
                ]),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: '固定費を追加',
            onPressed: config == null ? null : _add,
          ),
        ],
      ),
      body: CenteredBody(
        child: config == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Column(
                  children: [
                    _inlineToolbar(),
                    _summaryBar(config),
                    Expanded(
                      child: config.subscriptions.isEmpty
                          ? _empty()
                          : switch (_groupMode) {
                              _GroupMode.byCategory =>
                                _categorizedList(config),
                              _GroupMode.byAmountType =>
                                _byAmountTypeList(config),
                              _GroupMode.none => _flatList(config),
                            },
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// 月額換算で並び替え（手動モードなら変更しない）。
  List<Subscription> _applySort(List<Subscription> items) {
    if (_sortMode == _SortMode.manual) return items;
    final sorted = [...items];
    sorted.sort((a, b) {
      final cmp = a.monthlyEquivalent.compareTo(b.monthlyEquivalent);
      return _sortMode == _SortMode.amountDesc ? -cmp : cmp;
    });
    return sorted;
  }

  /// カテゴリ別セクション表示。
  /// - 手動モード: 各セクション内は ReorderableListView でドラッグ並び替え可
  /// - 月額昇/降順: 各セクション内をソートして表示（並び替え不可）
  Widget _categorizedList(SubscriptionConfig config) {
    final categories = config.categoriesInOrder;
    final grouped = config.groupedByCategory;
    final isManual = _sortMode == _SortMode.manual;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      itemBuilder: (context, ci) {
        final category = categories[ci];
        final rawItems = grouped[category] ?? const <Subscription>[];
        final items = _applySort(rawItems);
        final sectionMonthly =
            items.fold<int>(0, (s, sub) => s + sub.monthlyEquivalent);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader(category, items.length, sectionMonthly),
              const SizedBox(height: 6),
              if (isManual)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: items.length,
                  onReorder: (oldIndex, newIndex) =>
                      _reorderInCategory(category, oldIndex, newIndex),
                  itemBuilder: (context, i) {
                    final s = items[i];
                    return _tile(
                      key: ValueKey('sub-${s.id}'),
                      s: s,
                      dragIndex: i,
                      draggable: true,
                      onEdit: () => _editById(s.id),
                      onDelete: () => _deleteById(s.id),
                    );
                  },
                )
              else
                Column(
                  children: items
                      .map((s) => _tile(
                            key: ValueKey('sub-${s.id}'),
                            s: s,
                            dragIndex: 0,
                            draggable: false,
                            onEdit: () => _editById(s.id),
                            onDelete: () => _deleteById(s.id),
                          ))
                      .toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 定額/変動でセクション分けする表示。
  /// 変動費は毎月入力が必要なので、まず先に並べて目立たせる。
  /// 並び替えは「同じ amountType の中だけ」で許可（種別をまたぐ移動は無効）。
  Widget _byAmountTypeList(SubscriptionConfig config) {
    final isManual = _sortMode == _SortMode.manual;
    final variableItems = _applySort(config.subscriptions
        .where((s) => s.amountType == SubscriptionAmountType.variable)
        .toList());
    final fixedItems = _applySort(config.subscriptions
        .where((s) => s.amountType == SubscriptionAmountType.fixed)
        .toList());

    Widget section(String label, List<Subscription> items, IconData icon,
        Color tint) {
      if (items.isEmpty) return const SizedBox.shrink();
      final monthlyTotal =
          items.fold<int>(0, (s, sub) => s + sub.monthlyEquivalent);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // セクションヘッダー: 種別ラベル + 件数 + 月額合算
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: tint, width: 4),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: tint),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tint)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('${items.length}',
                        style: TextStyle(
                            fontSize: 11,
                            color: tint,
                            fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  Text(
                    '月額換算 ${formatYen(monthlyTotal)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 中身（並び替えはこのセクション内だけ）
            if (isManual)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) =>
                    _reorderInAmountTypeGroup(items, oldIndex, newIndex),
                itemBuilder: (context, i) {
                  final s = items[i];
                  return _tile(
                    key: ValueKey('sub-${s.id}'),
                    s: s,
                    dragIndex: i,
                    draggable: true,
                    onEdit: () => _editById(s.id),
                    onDelete: () => _deleteById(s.id),
                  );
                },
              )
            else
              Column(
                children: items
                    .map((s) => _tile(
                          key: ValueKey('sub-${s.id}'),
                          s: s,
                          dragIndex: 0,
                          draggable: false,
                          onEdit: () => _editById(s.id),
                          onDelete: () => _deleteById(s.id),
                        ))
                    .toList(),
              ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 変動費を上に置く（毎月入力が必要なので注意喚起の意味でも先頭）
        section('変動費（毎月入力が必要）', variableItems,
            Icons.swap_vert, const Color(0xFFEA580C)),
        section('定額費', fixedItems,
            Icons.lock_clock, const Color(0xFF1A237E)),
      ],
    );
  }

  /// 定額/変動グループ内での並び替え。
  /// グループをまたぐ移動はしない（同じ amountType 内のみ）。
  Future<void> _reorderInAmountTypeGroup(
      List<Subscription> groupItems, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex < 0 ||
        oldIndex >= groupItems.length ||
        newIndex < 0 ||
        newIndex >= groupItems.length) {
      return;
    }
    final movedId = groupItems[oldIndex].id;
    final beforeId =
        newIndex == 0 ? null : groupItems[newIndex - 1].id;

    // 全 subscriptions の中で movedId を探し、beforeId の直後に挿入する。
    final all = List<Subscription>.from(_config!.subscriptions);
    final movedIdx = all.indexWhere((s) => s.id == movedId);
    if (movedIdx < 0) return;
    final moved = all.removeAt(movedIdx);
    if (beforeId == null) {
      // グループ内の先頭 = 全リストの中での「同 amountType の最初の位置」
      final firstSameTypeIdx =
          all.indexWhere((s) => s.amountType == moved.amountType);
      if (firstSameTypeIdx < 0) {
        all.add(moved);
      } else {
        all.insert(firstSameTypeIdx, moved);
      }
    } else {
      final beforeIdx = all.indexWhere((s) => s.id == beforeId);
      if (beforeIdx < 0) {
        all.add(moved);
      } else {
        all.insert(beforeIdx + 1, moved);
      }
    }
    _update(all);
  }

  /// カテゴリ無視のフラット表示。
  Widget _flatList(SubscriptionConfig config) {
    final items = _applySort(config.subscriptions);
    final isManual = _sortMode == _SortMode.manual;
    if (isManual) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        onReorder: _reorderFlat,
        buildDefaultDragHandles: false,
        itemBuilder: (context, i) {
          final s = items[i];
          return _tile(
            key: ValueKey('sub-${s.id}'),
            s: s,
            dragIndex: i,
            draggable: true,
            onEdit: () => _editById(s.id),
            onDelete: () => _deleteById(s.id),
          );
        },
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final s = items[i];
        return _tile(
          key: ValueKey('sub-${s.id}'),
          s: s,
          dragIndex: 0,
          draggable: false,
          onEdit: () => _editById(s.id),
          onDelete: () => _deleteById(s.id),
        );
      },
    );
  }

  /// フラット表示時のドラッグ並び替え（subscriptions 配列の順序を直接更新）。
  void _reorderFlat(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final list = [..._config!.subscriptions];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _update(list);
  }

  Widget _sectionHeader(String category, int count, int monthlyTotal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            category,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827)),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF1A237E),
                    fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          // 月額換算（強調表示）
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                '月額換算 ',
                style: TextStyle(
                    fontSize: 10, color: Color(0xFF9CA3AF)),
              ),
              Text(
                formatYen(monthlyTotal),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A237E),
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// カテゴリ内の並び替え。subscriptions の全体リストを保ちつつ、
  /// 該当カテゴリのスライスのみを並び替えて元の位置に戻す。
  void _reorderInCategory(String category, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final all = [..._config!.subscriptions];

    bool matches(Subscription s) {
      final c = s.category;
      if (category == SubscriptionConfig.uncategorizedKey) {
        return c == null || c.isEmpty;
      }
      return c == category;
    }

    // カテゴリ内アイテムを集めて並び替え
    final categoryItems = all.where(matches).toList();
    if (oldIndex < 0 ||
        oldIndex >= categoryItems.length ||
        newIndex < 0 ||
        newIndex >= categoryItems.length) {
      return;
    }
    final moved = categoryItems.removeAt(oldIndex);
    categoryItems.insert(newIndex, moved);

    // all を再構築（カテゴリ位置は維持、カテゴリ内のみ並び替え）
    int catIdx = 0;
    final rebuilt = <Subscription>[];
    for (final s in all) {
      if (matches(s)) {
        rebuilt.add(categoryItems[catIdx++]);
      } else {
        rebuilt.add(s);
      }
    }
    _update(rebuilt);
  }

  /// id ベースで編集（カテゴリ別表示時はインデックスがズレるので id で特定）
  Future<void> _editById(String id) async {
    final idx =
        _config!.subscriptions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    await _edit(idx);
  }

  Future<void> _deleteById(String id) async {
    final idx =
        _config!.subscriptions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    await _delete(idx);
  }

  /// 常設の操作バー（追加 / グループ表示 / 並び順）。
  /// 設定ページに埋め込まれた際は AppBar が潰れてボタンが消えるため、
  /// 本体にも同等の操作を常に出しておく。
  Widget _inlineToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      color: Colors.white,
      child: Row(
        children: [
          // グループ表示
          PopupMenuButton<_GroupMode>(
            tooltip: 'グループ表示',
            icon: Icon(
              _groupMode == _GroupMode.none
                  ? Icons.folder_off_outlined
                  : _groupMode == _GroupMode.byAmountType
                      ? Icons.swap_vert
                      : Icons.folder,
              color: const Color(0xFF1A237E),
              size: 20,
            ),
            initialValue: _groupMode,
            onSelected: (v) => setState(() => _groupMode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: _GroupMode.byCategory, child: Text('カテゴリ別')),
              PopupMenuItem(
                  value: _GroupMode.byAmountType, child: Text('定額/変動別')),
              PopupMenuItem(
                  value: _GroupMode.none, child: Text('フラット（分類なし）')),
            ],
          ),
          // 並び順
          PopupMenuButton<_SortMode>(
            tooltip: '並び順',
            icon: const Icon(Icons.sort, color: Color(0xFF1A237E), size: 20),
            initialValue: _sortMode,
            onSelected: (v) => setState(() => _sortMode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: _SortMode.manual, child: Text('手動（ドラッグ並び替え）')),
              PopupMenuItem(
                  value: _SortMode.amountDesc, child: Text('月額の高い順')),
              PopupMenuItem(
                  value: _SortMode.amountAsc, child: Text('月額の安い順')),
            ],
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _config == null ? null : _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('追加'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  /// Summary bar:
  /// - 月額換算（月払い + 年払い÷12）→ 毎月いくらかかってる感覚値
  /// - 年間総コスト（月払い×12 + 年払い）→ 年でいくら払ってるかの強調指標
  Widget _summaryBar(SubscriptionConfig config) {
    if (config.subscriptions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
              child: _sumBlock(
                  '月額換算', formatYen(config.monthlyEquivalentTotal))),
          Container(
              width: 1, height: 36, color: const Color(0xFFE5E7EB)),
          Expanded(
              child: _sumBlock(
                  '年間総コスト', formatYen(config.totalAnnualCost),
                  highlight: true)),
        ],
      ),
    );
  }

  Widget _sumBlock(String label, String value, {bool highlight = false}) =>
      Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFF6B7280))),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: highlight ? 18 : 15,
                  fontWeight: FontWeight.bold,
                  color: highlight
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF111827),
                  fontFamily: 'monospace')),
        ],
      );

  /// 固定費tile（コンパクト版）。
  /// - 左端: ドラッグハンドル（並び替え用、手動モード時のみ表示）
  /// - ロゴ
  /// - 中央: 名前 + 請求日（強調）+ サブメタ
  /// - 右端: 月額/年額 + 換算バッジ
  /// - タップで編集、長押しメニュー的に削除 (実装は IconButton)
  Widget _tile({
    required Key key,
    required Subscription s,
    required int dragIndex,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    bool draggable = true,
  }) {
    final isMonthly = s.cycle == SubscriptionCycle.monthly;
    final cycleColor =
        isMonthly ? const Color(0xFF1A237E) : const Color(0xFF7C3AED);
    final variableColor = const Color(0xFFEA580C);
    final mainLabel = isMonthly ? '月額' : '年額';
    final mainValue = formatYen(s.amount);
    final subLabel = isMonthly ? '年換算' : '月換算';
    final subValue = isMonthly
        ? formatYen(s.annualEquivalent)
        : formatYen(s.monthlyEquivalent);

    // 「毎月◯日」「次回 ◯月◯日」の強調テキスト
    String? scheduleText;
    if (isMonthly && s.billingDay != null) {
      scheduleText = '毎月${s.billingDay}日';
    } else if (!isMonthly && s.nextBillingDate != null) {
      scheduleText =
          '次回 ${s.nextBillingDate!.month}/${s.nextBillingDate!.day}';
    }

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ドラッグハンドル（手動モード時のみ表示）
            if (draggable)
              ReorderableDragStartListener(
                index: dragIndex,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(Icons.drag_indicator,
                      color: Color(0xFFD1D5DB), size: 22),
                ),
              )
            else
              const SizedBox(width: 8),
            // ロゴ
            BrandLogo(
                iconUrl: s.iconUrl, fallbackEmoji: '🔁', size: 36),
            const SizedBox(width: 8),
            // 中央
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF111827)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  // 請求日（強調）+ バッジ群を1行に
                  Row(
                    children: [
                      if (scheduleText != null) ...[
                        Icon(
                          isMonthly
                              ? Icons.event_repeat
                              : Icons.event,
                          size: 13,
                          color: const Color(0xFF1A237E),
                        ),
                        const SizedBox(width: 3),
                        Text(scheduleText,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A237E))),
                        const SizedBox(width: 6),
                      ],
                      // サイクル/タイプ バッジ
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: cycleColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          s.cycleLabel,
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: cycleColor),
                        ),
                      ),
                      if (s.isVariable) ...[
                        const SizedBox(width: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color:
                                variableColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('変動',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: variableColor)),
                        ),
                      ],
                    ],
                  ),
                  if (s.paymentMethod != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.payment,
                            size: 10, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(s.paymentMethod!,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF9CA3AF)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // 右端: 月額/年額 + 換算
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(mainLabel,
                    style: const TextStyle(
                        fontSize: 9, color: Color(0xFF9CA3AF))),
                Text(mainValue,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF111827))),
                const SizedBox(height: 1),
                Text('$subLabel $subValue',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFB45309),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(width: 4),
            // 削除ボタン（編集はカード全体タップ）
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
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
  /// [editing] が false でロゴ設定済みのときは、URLを出さず「ロゴ編集」ボタンだけ。
  Widget _logoUrlField(TextEditingController ctrl, String fallbackEmoji,
      void Function(VoidCallback fn) setLocal,
      {bool editing = true, VoidCallback? onEdit}) {
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

    if (ctrl.text.trim().isNotEmpty && !editing) {
      return Row(
        children: [
          BrandLogo(
              iconUrl: ctrl.text.trim(), fallbackEmoji: fallbackEmoji, size: 40),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('ロゴ設定済み',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ),
          OutlinedButton.icon(
            onPressed: onEdit,
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
            controller: ctrl,
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
            const Icon(Icons.subscriptions,
                size: 64, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('固定費が未登録です',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            const Text('ChatGPT・電気代・家賃などを登録',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('固定費を追加'),
              onPressed: _add,
            ),
          ],
        ),
      );
}
