import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/app_mode.dart';
import '../../data/auth_service.dart';
import '../../data/desktop_bridge.dart' as desktop;
import '../../data/ui_preferences.dart';
import '../../data/update_flow.dart';
import '../../data/windows_update.dart';
import '../../screens/account_editor_screen.dart';
import '../../screens/balance_adjust_screen.dart';
import '../../screens/card_editor_screen.dart';
import '../../screens/category_editor_screen.dart';
import '../../screens/checklist_editor_screen.dart';
import '../../screens/subscription_list_screen.dart';
import 'v2_devlab.dart';
import 'panels/v2_backup_panel.dart';
import 'panels/v2_income_master_panel.dart';
import 'panels/v2_replacement_panel.dart';
import 'panels/v2_sidebar_order_panel.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/v2_card.dart';

/// v2.1 ネイティブ設定タブ。
/// 左メニュー（カテゴリ別） + 右コンテンツのマスター/ディテール構成。
///
/// - 表示設定 / サイドバー並び順 / UI バージョン / 未使用フラグ は v2.1 ネイティブ
/// - カテゴリ / ウォレット / クレカ / 収入マスタ / 固定費 / チェックリスト / バックアップ
///   は v1 画面を右パネルに埋め込み（AppBar を潰す）
/// - 各 v1 エディタは将来順次 v2.1 ネイティブで書き直す
class V2SettingsScreen extends StatefulWidget {
  final Color accent;
  const V2SettingsScreen({super.key, required this.accent});

  @override
  State<V2SettingsScreen> createState() => _V2SettingsScreenState();
}

class _V2SettingsScreenState extends State<V2SettingsScreen> {
  String _currentId = 'display';

  @override
  void initState() {
    super.initState();
    // 事業/個人モードの切替を購読。設定パネルはモード別データを持つため、
    // モードが変わったら再描画してパネルを作り直す（下の _buildPanel の key）。
    AppModeManager.instance.addListener(_onModeChanged);
  }

  @override
  void dispose() {
    AppModeManager.instance.removeListener(_onModeChanged);
    super.dispose();
  }

  void _onModeChanged() {
    if (mounted) setState(() {});
  }

  static const _menus = <_MenuGroup>[
    _MenuGroup(title: '表示・UI', items: [
      _MenuItem('display', '表示設定', Icons.tune,
          desc: 'UI の見た目や挙動を切替'),
      _MenuItem('sidebarOrder', 'サイドバー並び順', Icons.view_sidebar_outlined,
          desc: 'メニューの並び順を変更'),
    ]),
    _MenuGroup(title: 'マスタデータ', items: [
      _MenuItem('category', '支出カテゴリ', Icons.label_outline,
          desc: '大分類・小分類を編集'),
      _MenuItem('wallet', '支払方法マスタ',
          Icons.account_balance_wallet_outlined,
          desc: '口座・クレジットカードを登録'),
      _MenuItem('balanceAdjust', '残高調整', Icons.tune_outlined,
          desc: 'ウォレット残高を実際に合わせる（差は営業外に記録）'),
      _MenuItem('incomeMaster', '収入マスタ', Icons.savings_outlined,
          desc: '収入源（売上）を登録'),
      _MenuItem('subscription', '固定費・サブスク', Icons.event_repeat,
          desc: '毎月・毎年の固定支払を管理'),
      _MenuItem('replacements', '変換マスタ', Icons.find_replace,
          desc: 'レシートの表記ゆれを置換'),
      _MenuItem('checklist', '月末締めチェックリスト', Icons.checklist,
          desc: '月末の確認項目を編集'),
    ]),
    _MenuGroup(title: 'データ管理', items: [
      _MenuItem('backup', 'バックアップ / 取り込み',
          Icons.cloud_upload_outlined,
          desc: 'データの書き出し・取り込み'),
      _MenuItem('devLab', '明細の貼り付け取込・開発ラボ',
          Icons.upload_file_outlined,
          desc: '明細を貼り付けて一括取込ほか'),
    ]),
    _MenuGroup(title: 'アプリ情報', items: [
      _MenuItem('about', 'バージョン・更新確認', Icons.info_outline,
          desc: '現在の版・最新版を確認'),
    ]),
    _MenuGroup(title: 'アカウント', items: [
      _MenuItem('account', 'アカウント / サインアウト',
          Icons.account_circle_outlined,
          desc: 'ログイン中のアカウント'),
    ]),
  ];

  String _titleFor(String id) {
    for (final g in _menus) {
      for (final it in g.items) {
        if (it.id == id) return it.label;
      }
    }
    return '設定';
  }

  /// 狭い画面（スマホ）：メニュー項目タップで該当パネルをフルスクリーンで開く。
  void _openPanelScreen(String id) {
    setState(() => _currentId = id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(
          data: V2Theme.light(),
          child: Scaffold(
            backgroundColor: V2Colors.surfaceMuted,
            appBar: AppBar(
              title: Text(_titleFor(id),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.lg),
                child: _buildPanel(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // 広い画面：左メニュー＋右パネルのマスター/ディテール。
      if (c.maxWidth >= 900) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: V2Spacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 240,
                child: _SettingsMenu(
                  groups: _menus,
                  currentId: _currentId,
                  accent: widget.accent,
                  onSelect: (id) => setState(() => _currentId = id),
                ),
              ),
              const SizedBox(width: V2Spacing.lg),
              Expanded(child: _buildPanel()),
            ],
          ),
        );
      }
      // 狭い画面（スマホ）：カテゴリごとのカードに大きめタイルで縦並び。
      // 各タイルはアイコン＋名前＋説明＋「›」で、タップでフルスクリーンを開く。
      return _MobileSettingsList(
        groups: _menus,
        onSelect: _openPanelScreen,
      );
    });
  }

  Widget _buildPanel() {
    // モードをキーに含め、事業/個人を切り替えたらパネルを作り直して
    // （initState/_load を再実行）現モードのデータを読み直させる。
    final modeKey = AppModeManager.instance.current.name;
    return KeyedSubtree(
      key: ValueKey('$_currentId-$modeKey'),
      child: _buildPanelInner(),
    );
  }

  Widget _buildPanelInner() {
    switch (_currentId) {
      case 'display':
        return const _DisplayPanel();
      case 'sidebarOrder':
        return const V2SidebarOrderPanel();
      case 'category':
        return _embedV1(const CategoryEditorScreen(),
            title: '支出カテゴリ',
            note: '支出のカテゴリ（大分類・小分類）を編集します。会計科目のセクションごとに表示されます。',
            icon: Icons.label_outline,
            iconColor: V2Colors.badgePurple);
      case 'wallet':
        return const _PaymentMethodMasterPanel();
      case 'balanceAdjust':
        return _embedV1(const BalanceAdjustScreen(),
            title: '残高調整',
            note: 'ウォレットの残高を実際の金額に合わせます。ズレ分は「残高調整」として記録し、'
                '収支に含めます（事業モードのPLでは営業外）。',
            icon: Icons.tune_outlined,
            iconColor: V2Colors.info);
      case 'incomeMaster':
        return const V2IncomeMasterPanel();
      case 'subscription':
        return _embedV1(const SubscriptionListScreen(),
            title: '固定費・サブスク',
            note: '毎月・毎年の固定支払（家賃・サブスク等）を管理します。',
            icon: Icons.event_repeat,
            iconColor: V2Colors.warning);
      case 'checklist':
        return _embedV1(const ChecklistEditorScreen(),
            title: '月末締めチェックリスト',
            note: '月末締めの確認項目（2階層）を編集。動的リンクで銀行/クレカと自動紐付け。',
            icon: Icons.checklist,
            iconColor: V2Colors.info);
      case 'replacements':
        return const V2ReplacementPanel();
      case 'backup':
        return const V2BackupPanel();
      // タブから移設した「取込（個人）／開発ラボ（事業）」。画面自身がバナー付き。
      case 'devLab':
        return V2DevLabScreen(accent: widget.accent);
      case 'about':
        return const _AboutPanel();
      case 'account':
        return const _AccountPanel();
      default:
        return const _DisplayPanel();
    }
  }

  /// v1 編集画面を v2.1 風ヘッダー付きで右パネルに埋め込む共通ラッパー。
  /// AppBar は Theme で潰し、ClipRRect で V2Card の角丸に合わせる。
  Widget _embedV1(Widget child, {
    required String title,
    String? note,
    IconData? icon,
    Color? iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeaderWithIcon(
          title: title,
          note: note,
          icon: icon,
          iconColor: iconColor,
        ),
        const SizedBox(height: V2Spacing.sm),
        Expanded(
          child: V2Card(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(V2Spacing.radiusLg),
              child: Theme(
                data: Theme.of(context).copyWith(
                  appBarTheme: const AppBarTheme(
                    toolbarHeight: 0,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// v2.1 風のパネルヘッダー（アイコンバッジ + タイトル + 説明）。
/// 設定タブの各エディタ panel で共通使用。
class _PanelHeaderWithIcon extends StatelessWidget {
  final String title;
  final String? note;
  final IconData? icon;
  final Color? iconColor;
  const _PanelHeaderWithIcon({
    required this.title,
    this.note,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          V2Spacing.sm, 0, V2Spacing.sm, V2Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (iconColor ?? V2Colors.accent)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(
                    V2Spacing.radiusSm),
              ),
              alignment: Alignment.center,
              child: Icon(icon,
                  size: 20,
                  color: iconColor ?? V2Colors.accent),
            ),
            const SizedBox(width: V2Spacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: V2Typography.h1),
                if (note != null) ...[
                  const SizedBox(height: V2Spacing.xs),
                  Text(note!,
                      style: V2Typography.caption.copyWith(
                          color: V2Colors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 支払方法マスタ（口座 / クレジットカードを1画面に統合）
// ═════════════════════════════════════════════════

/// 旧「ウォレット」＋「クレジットカード」を統合した支払方法マスタ。
/// 上部トグルで「口座（銀行/現金/電子マネー）」と「クレジットカード」を切替え、
/// それぞれ既存の v1 エディタを右パネルに埋め込む。
class _PaymentMethodMasterPanel extends StatefulWidget {
  const _PaymentMethodMasterPanel();

  @override
  State<_PaymentMethodMasterPanel> createState() =>
      _PaymentMethodMasterPanelState();
}

class _PaymentMethodMasterPanelState
    extends State<_PaymentMethodMasterPanel> {
  int _tab = 0; // 0=口座, 1=クレジットカード

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PanelHeaderWithIcon(
          title: '支払方法マスタ',
          note: '銀行 / 現金 / 電子マネー と クレジットカードを登録・編集します。'
              '事業 / 個人モードで別管理。',
          icon: Icons.account_balance_wallet_outlined,
          iconColor: V2Colors.badgeBlue,
        ),
        const SizedBox(height: V2Spacing.sm),
        // ── 口座 / カード トグル ──
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('口座'),
                icon: Icon(Icons.account_balance, size: 16),
              ),
              ButtonSegment(
                value: 1,
                label: Text('クレジットカード'),
                icon: Icon(Icons.credit_card, size: 16),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(V2Typography.caption),
            ),
          ),
        ),
        const SizedBox(height: V2Spacing.sm),
        Expanded(
          child: V2Card(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(V2Spacing.radiusLg),
              child: Theme(
                data: Theme.of(context).copyWith(
                  appBarTheme: const AppBarTheme(
                    toolbarHeight: 0,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                  ),
                ),
                child: _tab == 0
                    ? const AccountEditorScreen()
                    : const CardEditorScreen(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════
// 左メニュー
// ═════════════════════════════════════════════════

class _MenuGroup {
  final String title;
  final List<_MenuItem> items;
  const _MenuGroup({required this.title, required this.items});
}

class _MenuItem {
  final String id;
  final String label;
  final IconData icon;

  /// スマホの縦並び一覧で名前の下に出す短い説明（PC サイドバーでは未使用）。
  final String? desc;
  const _MenuItem(this.id, this.label, this.icon, {this.desc});
}

// ═════════════════════════════════════════════════
// スマホ用: カテゴリごとのカードに大きめタイルで縦並び
// ═════════════════════════════════════════════════

class _MobileSettingsList extends StatelessWidget {
  final List<_MenuGroup> groups;
  final ValueChanged<String> onSelect;
  const _MobileSettingsList({
    required this.groups,
    required this.onSelect,
  });

  /// グループごとのアクセント色（アイコンバッジ用）。見分けやすさのため色分け。
  static const _groupColors = <Color>[
    V2Colors.badgeBlue,
    V2Colors.badgePurple,
    V2Colors.info,
    V2Colors.warning,
    V2Colors.accent,
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
          primary: false,
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var gi = 0; gi < groups.length; gi++) ...[
            if (gi > 0) const SizedBox(height: V2Spacing.lg),
            // カテゴリ見出し
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  V2Spacing.xs, 0, V2Spacing.xs, V2Spacing.sm),
              child: Text(groups[gi].title,
                  style: V2Typography.micro.copyWith(
                      color: V2Colors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
            // カテゴリのカード（中に項目行）
            V2Card(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var ii = 0; ii < groups[gi].items.length; ii++) ...[
                    if (ii > 0)
                      const Divider(
                          height: 1,
                          thickness: 1,
                          indent: 60,
                          color: V2Colors.divider),
                    _MobileSettingTile(
                      item: groups[gi].items[ii],
                      color: _groupColors[gi % _groupColors.length],
                      onTap: () => onSelect(groups[gi].items[ii].id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileSettingTile extends StatelessWidget {
  final _MenuItem item;
  final Color color;
  final VoidCallback onTap;
  const _MobileSettingTile({
    required this.item,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.md, vertical: V2Spacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(V2Spacing.radiusSm),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, size: 19, color: color),
            ),
            const SizedBox(width: V2Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label, style: V2Typography.bodyStrong),
                  if (item.desc != null) ...[
                    const SizedBox(height: 2),
                    Text(item.desc!,
                        style: V2Typography.micro.copyWith(
                            color: V2Colors.textSecondary)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.sm),
            const Icon(Icons.chevron_right,
                size: 20, color: V2Colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  final List<_MenuGroup> groups;
  final String currentId;
  final Color accent;
  final ValueChanged<String> onSelect;

  const _SettingsMenu({
    required this.groups,
    required this.currentId,
    required this.accent,
    required this.onSelect,
  });

  /// 1グループ分の見出し + 項目タイル列。
  Widget _groupBody(_MenuGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              V2Spacing.sm, 0, V2Spacing.sm, V2Spacing.xs),
          child: Text(group.title,
              style: V2Typography.micro.copyWith(
                  color: V2Colors.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ),
        for (final item in group.items)
          _MenuTile(
            item: item,
            selected: item.id == currentId,
            accent: accent,
            onTap: () => onSelect(item.id),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return V2Card(
      padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.sm, vertical: V2Spacing.md),
      // 項目が多いと下（アカウント/サインアウト）が見切れるため内部スクロール可に。
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var gi = 0; gi < groups.length; gi++) ...[
              if (gi > 0) const SizedBox(height: V2Spacing.md),
              _groupBody(groups[gi]),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatefulWidget {
  final _MenuItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _MenuTile({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? V2Colors.accentSoft
        : (_hover ? V2Colors.hover : Colors.transparent);
    final fg = selected ? widget.accent : V2Colors.textBody;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.sm, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  BorderRadius.circular(V2Spacing.radiusSm),
            ),
            child: Row(
              children: [
                Icon(widget.item.icon, size: 14, color: fg),
                const SizedBox(width: V2Spacing.sm),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: V2Typography.caption.copyWith(
                        color: fg,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500),
                    // 狭いレールでも長いラベルが読めるよう2行まで折り返す。
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 右パネル: 共通ヘッダー
// ═════════════════════════════════════════════════

class _PanelHeader extends StatelessWidget {
  final String title;
  final String? note;
  const _PanelHeader({required this.title, this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          V2Spacing.sm, 0, V2Spacing.sm, V2Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.h1),
          if (note != null) ...[
            const SizedBox(height: V2Spacing.xs),
            Text(note!,
                style: V2Typography.caption.copyWith(
                    color: V2Colors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// 表示設定パネル（v2.1 ネイティブ）
// ═════════════════════════════════════════════════

class _DisplayPanel extends StatelessWidget {
  const _DisplayPanel();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UiPreferences.instance,
      builder: (_, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PanelHeader(
                title: '表示設定',
                note: 'UI のバージョンや見た目の細かい挙動を切替えます。'),
            const SizedBox(height: V2Spacing.sm),
            Expanded(
              child: SingleChildScrollView(
          primary: false,
                child: Column(
                  children: [
                    _SettingTile(
                      icon: Icons.auto_awesome,
                      iconColor: V2Colors.accent,
                      title: '新デザイン（ベータ・スマホ向け）',
                      subtitle:
                          'スマホ表示をリッチな新デザインに切替えます。PCは従来のまま。OFFで元通り。',
                      trailing: Switch.adaptive(
                        value: UiPreferences.instance.richUi,
                        onChanged: (v) =>
                            UiPreferences.instance.setRichUi(v),
                        activeThumbColor: V2Colors.accent,
                      ),
                    ),
                    _SettingTile(
                      icon: Icons.visibility_off_outlined,
                      iconColor: V2Colors.textSecondary,
                      title: '未使用のウォレット/カードを隠す',
                      subtitle:
                          '各ウォレット/クレカ編集で「未使用」フラグを立てた項目を非表示にする',
                      trailing: Switch.adaptive(
                        value:
                            UiPreferences.instance.hideInactive,
                        onChanged: (v) => UiPreferences.instance
                            .setHideInactive(v),
                        activeThumbColor: V2Colors.accent,
                      ),
                    ),
                    const SizedBox(height: V2Spacing.md),
                    _ModeIndicator(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.sm),
      child: V2Card(
        padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.lg, vertical: V2Spacing.md),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius:
                    BorderRadius.circular(V2Spacing.radiusSm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: V2Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: V2Typography.bodyStrong),
                  Text(subtitle,
                      style: V2Typography.micro.copyWith(
                          color: V2Colors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.md),
            trailing,
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// アプリ情報パネル（v2.1 ネイティブ）: バージョン表示 + 更新確認
// ═════════════════════════════════════════════════

class _AboutPanel extends StatefulWidget {
  const _AboutPanel();

  @override
  State<_AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends State<_AboutPanel> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
      });
    } catch (_) {/* ignore */}
  }

  @override
  Widget build(BuildContext context) {
    final versionText =
        _version == null ? '読み込み中...' : 'v$_version';
    const buildText = '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PanelHeader(
          title: 'アプリ情報',
          note: '現在のバージョンの確認と、最新版へのアップデートができます。',
        ),
        const SizedBox(height: V2Spacing.sm),
        Expanded(
          child: SingleChildScrollView(
          primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                V2Card(
                  padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.lg, vertical: V2Spacing.lg),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: V2Colors.accent.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(V2Spacing.radiusSm),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.smartphone,
                            size: 20, color: V2Colors.accent),
                      ),
                      const SizedBox(width: V2Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('現在のバージョン',
                                style: V2Typography.micro.copyWith(
                                    color: V2Colors.textSecondary)),
                            const SizedBox(height: 2),
                            Text('$versionText$buildText',
                                style: V2Typography.bodyStrong.copyWith(
                                    fontFeatures:
                                        V2Typography.tabularNums)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: V2Spacing.md),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: () {
                      // Electronデスクトップ版はElectronの自己更新へ。
                      if (desktop.isDesktopShell) {
                        desktop.desktopCheckUpdate();
                      } else if (WindowsUpdateService.isTarget) {
                        WindowsUpdateService.instance.checkManually(context);
                      } else {
                        UpdateFlow.checkManually(context);
                      }
                    },
                    icon: const Icon(Icons.system_update, size: 18),
                    label: const Text('最新バージョンを確認'),
                    style: FilledButton.styleFrom(
                      backgroundColor: V2Colors.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(V2Spacing.radiusMd),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: V2Spacing.sm),
                Text(
                  desktop.isDesktopShell
                      ? 'デスクトップ版は起動時に自動で更新を確認します。'
                          'このボタンでも手動で確認できます。'
                      : 'Android では最新版があればこの場でダウンロードしてインストールできます。'
                          'Web は再読み込みで最新になります。',
                  style: V2Typography.micro
                      .copyWith(color: V2Colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModeManager.instance,
      builder: (_, _) {
        final isBusiness =
            AppModeManager.instance.current == AppMode.business;
        return V2Card(
          background: V2Colors.surfaceMuted,
          padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.lg, vertical: V2Spacing.md),
          child: Row(
            children: [
              Icon(
                  isBusiness
                      ? Icons.business_center_outlined
                      : Icons.person_outline,
                  size: 16,
                  color: V2Colors.textSecondary),
              const SizedBox(width: V2Spacing.sm),
              Expanded(
                child: Text(
                  '現在のモード: ${isBusiness ? '事業' : '個人'}（ヘッダー右上のスイッチで切替）',
                  style: V2Typography.caption.copyWith(
                      color: V2Colors.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// アカウント情報＋サインアウト。
class _AccountPanel extends StatefulWidget {
  const _AccountPanel();
  @override
  State<_AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<_AccountPanel> {
  bool _busy = false;

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('サインアウト'),
        content: const Text(
            'サインアウトすると、サインインするまでアプリが使えなくなります。\n'
            '別アカウント（例: contact@…）でログインし直す時に使います。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('サインアウト')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.signOut();
      // authStateChanges によりログイン画面へ自動遷移する。
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('サインアウトに失敗: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final email = user?.email ?? '(未ログイン)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PanelHeaderWithIcon(
          title: 'アカウント',
          note: 'ログイン中のGoogleアカウント。別アカウントに切り替えるにはサインアウトします。',
          icon: Icons.account_circle_outlined,
          iconColor: V2Colors.accent,
        ),
        const SizedBox(height: V2Spacing.sm),
        V2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.email_outlined,
                      size: 18, color: V2Colors.textSecondary),
                  const SizedBox(width: V2Spacing.sm),
                  Expanded(
                    child: Text(email,
                        style: V2Typography.bodyStrong
                            .copyWith(color: V2Colors.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _signOut,
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text(_busy ? '処理中…' : 'サインアウト'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(height: V2Spacing.sm),
              Text(
                'アカウント移行の手順: ①このアカウントでバックアップを書き出す → '
                '②サインアウト → ③移行先アカウントでログイン → ④取り込み。',
                style: V2Typography.caption
                    .copyWith(color: V2Colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
