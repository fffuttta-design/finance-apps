// 回帰テスト：スマホ幅（狭い幅）で支出明細テーブルが灰色(ErrorWidget)になった不具合。
//
// 原因（2026-07-17 修正）: `_NarrowSortBar.build` が `_SortCol.values` を全部回して
// `_labels[c]!` を引いていたが、`_labels` に `custom`（カスタム並び替え）のラベルが無く、
// null に `!` を当てて毎回クラッシュ → 明細が丸ごと灰色になっていた（v1.0.418で custom を
// 列挙に足したとき混入。PCの表は別コードなので無事だった）。
//
// このテストは、狭い幅（<560）でテーブルを組み立てて **例外が出ないこと** を保証する。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_core/finance_core.dart' as core;
import 'package:futa_finance/v2/widgets/expense_detail_table.dart';

Future<void> _noopTxn(core.Transaction _) async {}
Future<void> _noopGroup(List<core.Transaction> _) async {}
Future<void> _noopToggle(core.Transaction _, bool __) async {}

core.Transaction _tx(String id, int amount, String desc,
    {String? receiptId, String store = '店'}) {
  return core.Transaction(
    id: id,
    date: DateTime(2026, 7, 10),
    type: core.TransactionType.expense,
    category: const core.Category(major: '12.通信費', sub: '通信費'),
    paymentMethod: '三井住友カード',
    description: desc,
    amount: amount,
    store: store,
    receiptId: receiptId,
  );
}

void main() {
  testWidgets('狭い幅(380px)で支出明細テーブルが例外なく描画できる', (tester) async {
    final captured = <FlutterErrorDetails>[];
    FlutterError.onError = (d) => captured.add(d);

    // 単発 + receiptId まとめ(2件以上=まとめ行) + マイナス金額(返金) を含む実データ相当。
    final rows = <core.Transaction>[
      _tx('a', 2090, 'GoogleWorkspace'),
      _tx('b', 762, 'ConoHa'),
      _tx('g1', 347, 'スペース使用料', receiptId: 'R1', store: 'スペースマーケット'),
      _tx('g2', 15, 'サービス料', receiptId: 'R1', store: 'スペースマーケット'),
      _tx('g3', -35, 'お得意様割引', receiptId: 'R1', store: 'スペースマーケット'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(size: Size(380, 800)),
          child: SingleChildScrollView(
            child: SizedBox(
              width: 380, // ← テーブルの LayoutBuilder が narrow(<560) を選ぶ幅
              child: ExpenseDetailTable(
                rows: rows,
                accent: Colors.blue,
                onEditTxn: _noopTxn,
                onOpenGroup: _noopGroup,
                showReceiptCheck: true,
                onToggleReceipt: _noopToggle,
                onToggleReviewed: _noopToggle,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    tester.takeException();
    expect(captured, isEmpty,
        reason: '狭い幅の描画で例外: ${captured.map((e) => e.exception)}');
  });
}
