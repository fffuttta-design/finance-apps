import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../utils/thousands_separator_input_formatter.dart';
import '../widgets/brand_logo.dart';
import '../widgets/centered_body.dart';

/// ウォレット（銀行口座/現金/電子マネー）の登録CRUD。
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
    final iconUrlCtrl =
        TextEditingController(text: initial?.iconUrl ?? '');
    final memoCtrl = TextEditingController(text: initial?.memo ?? '');
    // 開始残高(任意): 通帳画面の月初/月末残高をユーザーが直したい時用に復活。
    final startingCtrl = NoComposingUnderlineController(
        text: initial?.startingBalance != null
            ? formatAmount(initial!.startingBalance!)
            : '');
    AccountType selectedType = initial?.accountType ?? AccountType.bank;
    bool selectedInactive = initial?.inactive ?? false;
    // last4 は UI 入力廃止。既存値があれば保持して破壊しない。
    final initialLast4 = initial?.last4;

    final result = await showModalBottomSheet<RegisteredBankAccount?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isValid = nameCtrl.text.trim().isNotEmpty;

          void onSave() {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              Navigator.pop(ctx, null);
              return;
            }
            // last4 は UI から入力できないため、initial の値をそのまま維持。
            final last4 = initialLast4;
            final iconUrl = iconUrlCtrl.text.trim().isEmpty
                ? null
                : iconUrlCtrl.text.trim();
            final memo =
                memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
            // 開始残高: 空欄は null（未設定）扱い。
            final startingRaw = startingCtrl.text.trim();
            final starting =
                startingRaw.isEmpty ? null : parseAmount(startingRaw);
            if (initial == null) {
              Navigator.pop(
                  ctx,
                  RegisteredBankAccount(
                    id: _genId(),
                    name: name,
                    last4: last4,
                    startingBalance: starting,
                    accountType: selectedType,
                    iconUrl: iconUrl,
                    memo: memo,
                    inactive: selectedInactive,
                  ));
            } else {
              // copyWith は null 渡し時に既存値が残るため、startingBalance を
              // 明示的にクリア(null)できるよう全フィールド指定で再構築する。
              Navigator.pop(
                  ctx,
                  RegisteredBankAccount(
                    id: initial.id,
                    name: name,
                    last4: last4,
                    startingBalance: starting,
                    currentBalance: initial.currentBalance,
                    accountType: selectedType,
                    iconUrl: iconUrl,
                    memo: memo,
                    inactive: selectedInactive,
                  ));
            }
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: FractionallySizedBox(
              heightFactor: 0.88,
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
                            initial == null ? 'ウォレットを追加' : 'ウォレットを編集',
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
                          const Text('種別',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280))),
                          const SizedBox(height: 4),
                          SegmentedButton<AccountType>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                  value: AccountType.bank,
                                  label: Text('🏦 銀行')),
                              ButtonSegment(
                                  value: AccountType.cash,
                                  label: Text('👛 現金')),
                              ButtonSegment(
                                  value: AccountType.emoney,
                                  label: Text('📱 電子')),
                            ],
                            selected: {selectedType},
                            onSelectionChanged: (s) =>
                                setLocal(() => selectedType = s.first),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                              controller: nameCtrl,
                              autofocus: initial == null,
                              decoration: InputDecoration(
                                labelText: '${selectedType.label}名（必須）',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                              ),
                              onChanged: (_) => setLocal(() {})),
                          const SizedBox(height: 12),
                          // 開始残高(任意)。
                          // 全期間の残高計算の基準値。通帳画面の月初/月末残高が
                          // ズレた時、ここで補正できる。空欄なら 0 として扱う。
                          TextField(
                            controller: startingCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              HalfWidthDigitsFormatter(),
                              ThousandsSeparatorInputFormatter(),
                            ],
                            decoration: const InputDecoration(
                              labelText: '開始残高（任意・円）',
                              prefixText: '¥ ',
                              helperText: '全期間の残高計算の基準値。空欄=0扱い',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 下4桁の入力は UI から廃止（last4 モデルは互換のため残す）。
                          // 備考欄を直接配置。
                          TextField(
                            controller: memoCtrl,
                            maxLines: 1,
                            decoration: const InputDecoration(
                              labelText: '備考（任意）',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _logoUrlField(
                              iconUrlCtrl, selectedType.emoji, setLocal),
                          const SizedBox(height: 12),
                          // 未使用フラグ。ON にすると「未使用を隠す」設定下で
                          // 各画面（ホーム/資産/クレカ）の表示から除外される。
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
                                '残高が1円以上ある間は自動で表示されます',
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
          'ウォレット',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1A237E)),
            tooltip: 'ウォレットを追加',
            onPressed: config == null ? null : _add,
          ),
        ],
      ),
      body: CenteredBody(
        child: config == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: config.bankAccounts.isEmpty
                    ? _empty()
                    : _sectionedList(config.bankAccounts),
              ),
      ),
    );
  }

  /// 種別ごとにセクション分けして表示するリスト。
  /// セクションヘッダーには種別アイコン + 種別名 + 件数。
  Widget _sectionedList(List<RegisteredBankAccount> accounts) {
    // 種別ごとにグルーピング
    final byType = <AccountType, List<RegisteredBankAccount>>{};
    for (final a in accounts) {
      byType.putIfAbsent(a.accountType, () => []).add(a);
    }
    // 表示順: 銀行 → 現金 → 電子マネー
    const order = [
      AccountType.bank,
      AccountType.cash,
      AccountType.emoney,
    ];
    final sections = <Widget>[];
    for (final type in order) {
      final list = byType[type] ?? const [];
      if (list.isEmpty) continue;
      sections.add(_sectionHeader(type, list.length));
      // 各セクションは独立した ReorderableListView。
      // セクション内のみ並び替え可能（セクション間移動は編集ダイアログで種別変更）。
      sections.add(
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: list.length,
          onReorder: (oldIndex, newIndex) =>
              _reorderWithinType(type, oldIndex, newIndex),
          itemBuilder: (context, i) {
            final a = list[i];
            final idx =
                _config!.bankAccounts.indexWhere((x) => x.id == a.id);
            return _tile(
              ValueKey('acc-${a.id}'),
              a,
              i,
              () => _edit(idx),
              () => _delete(idx),
            );
          },
        ),
      );
      sections.add(const SizedBox(height: 12));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: sections,
    );
  }

  /// 指定種別のセクション内の並び替えを反映する。
  /// 全体リスト bankAccounts の中で、その種別のスライスのみを並び替えて元に戻す。
  void _reorderWithinType(
      AccountType type, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final all = [..._config!.bankAccounts];
    final sliceItems = all.where((a) => a.accountType == type).toList();
    if (oldIndex < 0 ||
        oldIndex >= sliceItems.length ||
        newIndex < 0 ||
        newIndex >= sliceItems.length) {
      return;
    }
    final moved = sliceItems.removeAt(oldIndex);
    sliceItems.insert(newIndex, moved);

    int sliceIdx = 0;
    final rebuilt = <RegisteredBankAccount>[];
    for (final a in all) {
      if (a.accountType == type) {
        rebuilt.add(sliceItems[sliceIdx++]);
      } else {
        rebuilt.add(a);
      }
    }
    _update(rebuilt);
  }

  Widget _sectionHeader(AccountType type, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6, top: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(type.emoji,
              style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(type.label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827))),
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
        ],
      ),
    );
  }

  /// ロゴURL入力欄 + プレビュー。
  /// 共通化されたコンポーネント。ドメインを入れて 🔄 タップで favicon URL に変換可能。
  Widget _logoUrlField(TextEditingController ctrl, String fallbackEmoji,
      void Function(VoidCallback fn) setLocal) {
    void convertDomain() {
      final input = ctrl.text.trim();
      if (input.isEmpty) return;
      // 既に画像/favicon URL なら何もしない
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
      crossAxisAlignment: CrossAxisAlignment.center,
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

  Widget _tile(
      Key key,
      RegisteredBankAccount a,
      int dragIndex,
      VoidCallback onEdit,
      VoidCallback onDelete) {
    // 休眠中（inactive）は背景を薄いグレー、文字を薄める。
    final isInactive = a.inactive;
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
      // ListTile では title/subtitle 間に固定パディングが入って間延びするため、
      // 独自レイアウト（Padding + Row + Column）で余白を詰める。
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
            BrandLogo(
                iconUrl: a.iconUrl,
                fallbackEmoji: a.accountType.emoji,
                size: 36),
            const SizedBox(width: 12),
            // 種別バッジはセクションヘッダーで分かるので各 tile からは省略
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(a.name,
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
                  if (a.last4 != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '****${a.last4}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                  if (a.memo != null && a.memo!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      a.memo!,
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
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_balance,
                size: 64, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('ウォレットが未登録です',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            const Text('銀行口座・現金（財布）・電子マネー（PayPay等）を登録',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('ウォレットを追加'),
              onPressed: _add,
            ),
          ],
        ),
      );
}
