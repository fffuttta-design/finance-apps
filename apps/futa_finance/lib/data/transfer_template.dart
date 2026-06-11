import 'dart:convert';

/// 振替の「よく使うパターン」テンプレート（移動元→移動先）。
class TransferTemplate {
  final String id;
  final String fromAccount;
  final String toAccount;

  const TransferTemplate({
    required this.id,
    required this.fromAccount,
    required this.toAccount,
  });

  String get label => '$fromAccount → $toAccount';

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': fromAccount,
        'to': toAccount,
      };

  factory TransferTemplate.fromJson(Map<String, dynamic> j) => TransferTemplate(
        id: (j['id'] ?? '') as String,
        fromAccount: (j['from'] ?? '') as String,
        toAccount: (j['to'] ?? '') as String,
      );

  TransferTemplate copyWith({String? fromAccount, String? toAccount}) =>
      TransferTemplate(
        id: id,
        fromAccount: fromAccount ?? this.fromAccount,
        toAccount: toAccount ?? this.toAccount,
      );
}

/// 振替テンプレートの集合（モード別に保存）。
class TransferTemplatesConfig {
  final List<TransferTemplate> templates;
  const TransferTemplatesConfig({this.templates = const []});

  factory TransferTemplatesConfig.empty() =>
      const TransferTemplatesConfig(templates: []);

  String toJsonString() => jsonEncode({
        'templates': templates.map((t) => t.toJson()).toList(),
      });

  factory TransferTemplatesConfig.fromJsonString(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    final list = (j['templates'] as List? ?? [])
        .map((e) =>
            TransferTemplate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return TransferTemplatesConfig(templates: list);
  }
}
