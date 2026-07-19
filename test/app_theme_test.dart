import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the lightweight iOS-style transition on Android', () {
    final transitionBuilder =
        AppTheme.dark.pageTransitionsTheme.builders[TargetPlatform.android];

    expect(transitionBuilder, isA<CupertinoPageTransitionsBuilder>());
  });
}
