import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/debt_calculations.dart';

void main() {
  group('outstandingExpenseTotal', () {
    test('includes charges and excludes paid debts', () {
      final expense = <String, dynamic>{
        'debts': [
          {
            'baseAmount': 10.0,
            'taxAmount': 0.6,
            'serviceAmount': 1.0,
            'paid': false,
          },
          {'amount': 20.0, 'paid': true},
        ],
      };

      expect(outstandingExpenseTotal(expense), 11.6);
    });

    test('supports legacy proportional charges', () {
      final expense = <String, dynamic>{
        'totalAmount': 100.0,
        'taxAmount': 6.0,
        'serviceAmount': 10.0,
        'debts': [
          {'amount': 25.0, 'paid': false},
          {'amount': 75.0, 'paid': false},
        ],
      };

      expect(outstandingExpenseTotal(expense), 116.0);
    });

    test('rounds currency to two decimal places', () {
      expect(roundCurrency(10.005), 10.01);
    });
  });

  group('splitCurrencyTotal', () {
    test('splits evenly without changing the total', () {
      final shares = splitCurrencyTotal(30, 3);

      expect(shares, [10.0, 10.0, 10.0]);
      expect(shares.fold<double>(0, (sum, share) => sum + share), 30.0);
    });

    test('distributes remainder cents deterministically', () {
      final shares = splitCurrencyTotal(10, 3);

      expect(shares, [3.34, 3.33, 3.33]);
      expect(roundCurrency(shares.reduce((a, b) => a + b)), 10.0);
    });

    test('returns no shares when there are no participants', () {
      expect(splitCurrencyTotal(10, 0), isEmpty);
    });
  });
}
