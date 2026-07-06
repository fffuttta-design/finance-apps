import 'package:flutter/material.dart';
import '../widgets/memo_field.dart';
import 'package:finance_core/finance_core.dart';

import '../data/card_settlement_service.dart';
import '../data/settings_repository.dart';
import '../widgets/brand_logo.dart';
import '../widgets/centered_body.dart';
import 'card_detail_screen.dart';

/// クレジットカードの登録CRUD。
class CardEditorScreen extends StatefulWidget {
  const CardEditorScreen({super.key});

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  final _repo = SettingsRepository();
  PaymentMethodsConfig? _config;
  // 引落明細のカテゴリ選択用（大カテゴリ候補）。
  CategoryConfig? _categories;

  // ブランドカラー選択UIは廃止（ロゴURL指定で代替）。
  // モデル側 brandColorValue は既存データ互換のためフィールドだけ残してある。

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.loadPayments();
    final cats = await _repo.loadCategories();
    if (!mounted) return;
    setState(() {
      _config = c;
      _categories = cats;
    });
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
    // 引き落とし口座（銀行のid）。必須。
    String? selectedSettlementId = initial?.settlementAccountId;
    // 引落明細のカテゴリ（大カテゴリ・任意。未設定なら「振替」で表示）。
    String? selectedSettlementCat = initial?.settlementCategoryMajor;
    bool selectedInactive = initial?.inactive ?? false;
    // ロゴURLの入力欄を開いているか（既にロゴがあれば畳んで「ロゴを編集」だけ）。
    bool logoEditing = (initial?.iconUrl ?? '').trim().isEmpty;

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
          // 引き落とし口座は必須（設定されていないと保存できない）。
          final isValid = nameCtrl.text.trim().isNotEmpty &&
              selectedSettlementId != null;

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
                    settlementAccountId: selectedSettlementId,
                    settlementCategoryMajor: selectedSettlementCat,
                    inactive: selectedInactive,
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
                    settlementAccountId: selectedSettlementId,
                    clearSettlementAccount: selectedSettlementId == null,
                    settlementCategoryMajor: selectedSettlementCat,
                    clearSettlementCategory: selectedSettlementCat == null,
                    inactive: selectedInactive,
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
                          MemoField(controller: memoCtrl),
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
                          // 引き落とし口座（銀行）。引落日にこの口座から自動で引く。
                          DropdownButtonFormField<String?>(
                            initialValue: selectedSettlementId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '引き落とし口座',
                              hintText: '選択してください',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                            items: <DropdownMenuItem<String?>>[
                              for (final b
                                  in (_config?.bankAccounts ?? const [])
                                      .where((b) =>
                                          b.accountType == AccountType.bank))
                                DropdownMenuItem<String?>(
                                  value: b.id,
                                  child: Text(b.name,
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) =>
                                setLocal(() => selectedSettlementId = v),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '※引落日になると、対象月（前月利用）のカード利用額を'
                            'この口座から自動で差し引きます（土日祝は翌営業日）。',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 12),
                          // 引落明細のカテゴリ（自動生成される引落明細に付く大カテゴリ）。
                          DropdownButtonFormField<String>(
                            initialValue: selectedSettlementCat,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '引落明細のカテゴリ',
                              hintText: '未設定（振替として表示）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                            items: <DropdownMenuItem<String>>[
                              const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('— 振替（カテゴリなし）—',
                                      style: TextStyle(
                                          color: Color(0xFF9CA3AF)))),
                              if (selectedSettlementCat != null &&
                                  !(_categories?.majors.any((m) =>
                                          m.name == selectedSettlementCat) ??
                                      false))
                                DropdownMenuItem<String>(
                                    value: selectedSettlementCat,
                                    child: Text(selectedSettlementCat!)),
                              for (final m
                                  in (_categories?.majors ?? const []))
                                DropdownMenuItem<String>(
                                  value: m.name,
                                  child: Text(m.name,
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) =>
                                setLocal(() => selectedSettlementCat = v),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '※自動生成される引落明細は、この大カテゴリ名で表示されます'
                            '（振替扱いなので支出集計・PLには入れず、二重計上しません）。',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 12),
                          _logoUrlField(iconUrlCtrl, '💳', setLocal,
                              editing: logoEditing,
                              onToggleEdit: () =>
                                  setLocal(() => logoEditing = true)),
                          const SizedBox(height: 12),
                          // 未使用フラグ。設定の「未使用を隠す」が ON のとき
                          // ホーム/資産/クレカタブ から除外される。
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: selectedInactive,
                            onChanged: (v) =>
                                setLocal(() => selectedInactive = v),
                            title: const Text('未使用（休眠中）',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827))),
                            subtitle: const Text(
                                '累積額が1円以上ある間は自動で表示されます',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF6B7280))),
                          ),
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
    // 引落カテゴリの変更を、既存の引落明細にも反映する。
    await CardSettlementService.syncCategory(r);
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
    // 休眠中（inactive）は背景を薄いグレー、文字を薄める。
    // ただし完全に隠さず、編集導線として一覧には残す。
    final isInactive = c.inactive;
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isInactive ? const Color(0xFFF3F4F6) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      foregroundDecoration: isInactive
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withValues(alpha: 0.35),
            )
          : null,
      // tile 本体タップで CardDetailScreen に遷移。
      // 編集ボタンは別アクション（既存挙動）。
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CardDetailScreen(card: c),
            ),
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(c.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827))),
                      ),
                      if (isInactive) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '休眠中',
                            style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
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
        ),
      ),
    );
  }

  /// ロゴURL入力欄（共通）。
  /// 既にロゴが設定済み（editing=false）のときは、URLを毎回表示せず
  /// ロゴ＋「ロゴを編集」ボタンだけを出す（onToggleEdit で展開）。
  Widget _logoUrlField(TextEditingController ctrl, String fallbackEmoji,
      void Function(VoidCallback fn) setLocal,
      {bool editing = true, VoidCallback? onToggleEdit}) {
    final hasLogo = ctrl.text.trim().isNotEmpty;
    if (hasLogo && !editing) {
      return Row(
        children: [
          BrandLogo(
            iconUrl: ctrl.text.trim(),
            fallbackEmoji: fallbackEmoji,
            size: 40,
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onToggleEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('ロゴを編集'),
          ),
        ],
      );
    }

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
