import 'dart:convert';

/// 月末締めチェックリストの1項目。
/// 例: 「三井住友カード明細確認」「PayPay履歴」「源泉徴収確認」等。
///
/// [children] でサブ項目（2階層目）を持てる。サブ項目はさらにネストしない。
class ChecklistItem {
  final String id;
  final String name;

  /// 確認用URL（任意）。タップで外部ブラウザ起動。
  final String? url;

  /// 補足メモ。
  final String? memo;

  /// サブ項目（2階層目）。空ならリーフ。
  final List<ChecklistItem> children;

  /// 動的リンクの種別（任意）。
  /// - "bank_accounts": 表示時に登録されている銀行口座から子要素を動的展開
  /// - "credit_cards": 表示時に登録クレジットカードから子要素を動的展開
  /// - null: 通常の静的項目
  ///
  /// リンク種別が指定された親項目では [children] は表示時に上書きされる。
  /// 編集画面では子要素の手動編集はできない（自動展開のため）。
  final String? linkType;

  const ChecklistItem({
    required this.id,
    required this.name,
    this.url,
    this.memo,
    this.children = const [],
    this.linkType,
  });

  /// 動的リンク（銀行/クレカ）か。
  bool get isLinked => linkType != null && linkType!.isNotEmpty;

  /// 子がいる項目か（=この項目自体はチェック対象ではなく、子のみカウント）。
  bool get hasChildren => children.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'memo': memo,
        'children': children.map((c) => c.toJson()).toList(),
        'linkType': linkType,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String?,
        memo: j['memo'] as String?,
        children: (j['children'] as List?)
                ?.map((c) => ChecklistItem.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
        linkType: j['linkType'] as String?,
      );

  ChecklistItem copyWith({
    String? name,
    String? url,
    String? memo,
    List<ChecklistItem>? children,
    String? linkType,
  }) =>
      ChecklistItem(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        memo: memo ?? this.memo,
        children: children ?? this.children,
        linkType: linkType ?? this.linkType,
      );
}

/// チェックリストの一覧（永続化用）。順序は List のインデックス。
class ChecklistConfig {
  final List<ChecklistItem> items;

  const ChecklistConfig({required this.items});

  factory ChecklistConfig.empty() => const ChecklistConfig(items: []);

  /// FutaFinance 事業モードのデフォルトテンプレート。
  factory ChecklistConfig.businessDefaults() => const ChecklistConfig(items: [
        ChecklistItem(
            id: 'b1',
            name: '銀行口座の入出金を確認',
            url: 'https://www.netbk.co.jp/'),
        ChecklistItem(
            id: 'b2',
            name: 'クレカ明細の確認',
            url: 'https://www.smbc-card.com/'),
        ChecklistItem(
            id: 'b3',
            name: '源泉徴収の確認・記録',
            memo: 'クライアントから引かれた源泉額を集計'),
        ChecklistItem(
            id: 'b4',
            name: '請求書の発行漏れ確認'),
        ChecklistItem(
            id: 'b5',
            name: '入金未済の請求書の追跡'),
      ]);

  /// 個人モードのデフォルトテンプレート。
  factory ChecklistConfig.personalDefaults() =>
      const ChecklistConfig(items: [
        ChecklistItem(
            id: 'p1',
            name: '銀行口座の残高確認',
            url: 'https://www.netbk.co.jp/'),
        ChecklistItem(
            id: 'p2',
            name: 'クレカ明細の確認'),
        ChecklistItem(
            id: 'p3',
            name: 'PayPay/電子マネーの履歴確認',
            url: 'https://paypay.ne.jp/'),
        ChecklistItem(
            id: 'p4',
            name: 'サブスク自動引落の確認'),
      ]);

  /// チェック対象となる leaf 項目の ID 一覧。
  /// - 子を持たない親 → 親自身を leaf として含む
  /// - 子を持つ親 → 子のみを含む（親自身はカウント外）
  List<String> get leafIds {
    final ids = <String>[];
    for (final item in items) {
      if (item.hasChildren) {
        for (final c in item.children) {
          ids.add(c.id);
        }
      } else {
        ids.add(item.id);
      }
    }
    return ids;
  }

  String toJsonString() =>
      jsonEncode({'items': items.map((i) => i.toJson()).toList()});

  factory ChecklistConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return ChecklistConfig(
      items: (json['items'] as List)
          .map((i) => ChecklistItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

  ChecklistConfig copyWith({List<ChecklistItem>? items}) =>
      ChecklistConfig(items: items ?? this.items);
}
