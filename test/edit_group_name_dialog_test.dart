import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/edit_group_name_dialog.dart';

void main() {
  group('validateGroupName', () {
    test('rejects empty and whitespace-only names', () {
      expect(validateGroupName(''), 'Enter a group name');
      expect(validateGroupName('   '), 'Enter a group name');
    });

    test('accepts a trimmed name within the limit', () {
      expect(validateGroupName('  Penang trip  '), isNull);
      expect(validateGroupName('a' * maximumGroupNameLength), isNull);
    });

    test('rejects a name over the character limit', () {
      expect(
        validateGroupName('a' * (maximumGroupNameLength + 1)),
        'Use $maximumGroupNameLength characters or fewer',
      );
    });
  });
}
