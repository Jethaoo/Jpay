double roundCurrency(num value) => (value.toDouble() * 100).round() / 100;

List<double> splitCurrencyTotal(num total, int participantCount) {
  if (participantCount <= 0) return const [];

  final totalCents = (total.toDouble() * 100).round();
  final baseCents = totalCents ~/ participantCount;
  final remainder = totalCents.remainder(participantCount);

  return List<double>.generate(
    participantCount,
    (index) => (baseCents + (index < remainder ? 1 : 0)) / 100,
  );
}

double effectiveDebtAmount(
  Map<String, dynamic> debt, {
  Map<String, dynamic>? expense,
}) {
  final baseAmount = (debt['baseAmount'] as num?)?.toDouble();
  if (baseAmount != null) {
    return roundCurrency(
      baseAmount +
          ((debt['taxAmount'] as num?)?.toDouble() ?? 0) +
          ((debt['serviceAmount'] as num?)?.toDouble() ?? 0),
    );
  }

  var amount = (debt['amount'] as num?)?.toDouble() ?? 0;
  final baseTotal = (expense?['totalAmount'] as num?)?.toDouble() ?? 0;
  final tax = (expense?['taxAmount'] as num?)?.toDouble() ?? 0;
  final service = (expense?['serviceAmount'] as num?)?.toDouble() ?? 0;
  if (baseTotal > 0 && (tax != 0 || service != 0)) {
    final ratio = amount / baseTotal;
    amount += (tax + service) * ratio;
  }
  return roundCurrency(amount);
}

double outstandingExpenseTotal(Map<String, dynamic> expense) {
  final debts = expense['debts'];
  if (debts is List) {
    return roundCurrency(
      debts.whereType<Map>().fold<double>(0, (total, rawDebt) {
        final debt = Map<String, dynamic>.from(rawDebt);
        if (debt['paid'] == true) return total;
        return total + effectiveDebtAmount(debt, expense: expense);
      }),
    );
  }

  if (expense['paid'] == true) return 0;
  return roundCurrency((expense['amount'] as num?)?.toDouble() ?? 0);
}

double expenseDeletionBalanceDelta(Map<String, dynamic> expense) {
  final outstanding = outstandingExpenseTotal(expense);
  return outstanding == 0 ? 0 : -outstanding;
}
