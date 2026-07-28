import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/services/receipt_scanner.dart';

void main() {
  group('ReceiptParser', () {
    test('extracts merchant, labelled total, date, and purchased items', () {
      final result = ReceiptParser.parse('''
MY FRIENDS CAFE
12 Jalan Example
Nasi Lemak             8.50
Teh Tarik              3.20
SUBTOTAL              11.70
SERVICE                1.17
GRAND TOTAL RM         12.87
28/07/2026
Cash                   20.00
Change                  7.13
''');

      expect(result.merchant, 'MY FRIENDS CAFE');
      expect(result.total, 12.87);
      expect(result.date, DateTime(2026, 7, 28));
      expect(
        result.items.map((item) => item.description),
        containsAll(['Nasi Lemak', 'Teh Tarik']),
      );
      expect(
        result.items.any((item) => item.description == 'SUBTOTAL'),
        isFalse,
      );
    });

    test('does not select change or subtotal as the total', () {
      final result = ReceiptParser.parse('''
KEDAI RUNCIT
ITEM A 4.00
SUBTOTAL 4.00
TOTAL 4.24
CASH 10.00
CHANGE 5.76
''');

      expect(result.total, 4.24);
    });

    test('accepts ISO receipt dates and Chinese merchant text', () {
      final result = ReceiptParser.parse('''
快乐超市
2026-07-28
牛奶 6.50
TOTAL RM 6.50
''', script: 'chinese');

      expect(result.merchant, '快乐超市');
      expect(result.date, DateTime(2026, 7, 28));
      expect(result.script, 'chinese');
    });
  });
}
