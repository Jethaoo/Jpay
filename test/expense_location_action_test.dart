import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/app_theme.dart';
import 'package:jpay/backend/backend_models.dart';
import 'package:jpay/widgets/expense_location_action.dart';

Widget _app({
  required ExpenseLocation location,
  required ExpenseLocationOpener openLocation,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: Center(
        child: ExpenseLocationAction(
          location: location,
          openLocation: openLocation,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the full address and opens the saved location', (
    tester,
  ) async {
    const location = ExpenseLocation(
      label: 'Central Market',
      address:
          'Lot 3.04-3.06, Central Market, Jalan Hang Kasturi, City Centre, '
          '50050 Kuala Lumpur, Malaysia',
      latitude: 3.1453,
      longitude: 101.6955,
    );
    ExpenseLocation? openedLocation;

    await tester.pumpWidget(
      _app(
        location: location,
        openLocation: (location) async {
          openedLocation = location;
          return true;
        },
      ),
    );

    expect(find.text('Central Market'), findsOneWidget);
    expect(find.text(location.address), findsOneWidget);
    expect(find.byTooltip('Open in maps'), findsOneWidget);
    final addressText = tester.widget<Text>(find.text(location.address));
    expect(addressText.maxLines, isNull);
    expect(addressText.overflow, isNull);

    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(openedLocation, same(location));
  });

  testWidgets('uses useful fallbacks for sparse saved locations', (
    tester,
  ) async {
    const location = ExpenseLocation(
      label: '  ',
      address: '',
      latitude: 3.139,
      longitude: 101.6869,
    );

    await tester.pumpWidget(
      _app(location: location, openLocation: (_) async => true),
    );

    expect(find.text('Saved location'), findsOneWidget);
    expect(find.text('3.139000, 101.686900'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Open Saved location in maps',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reports when no maps destination can be opened', (tester) async {
    const location = ExpenseLocation(
      label: 'Central Market',
      address: 'Kuala Lumpur',
      latitude: 3.1453,
      longitude: 101.6955,
    );

    await tester.pumpWidget(
      _app(location: location, openLocation: (_) async => false),
    );
    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(
      find.text("Couldn't open this location in a maps app."),
      findsOneWidget,
    );
  });
}
