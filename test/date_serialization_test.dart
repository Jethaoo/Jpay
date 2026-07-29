import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/backend/date_serialization.dart';

void main() {
  test('timestamptz values are serialized with an explicit UTC offset', () {
    final localDate = DateTime(2026, 7, 28, 23, 30);

    final serialized = serializeTimestamptz(localDate);

    expect(serialized, localDate.toUtc().toIso8601String());
    expect(serialized, endsWith('Z'));
    expect(DateTime.parse(serialized!).isUtc, isTrue);
  });

  test('null timestamptz values remain null', () {
    expect(serializeTimestamptz(null), isNull);
  });
}
