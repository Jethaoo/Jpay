import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/network_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => NetworkStatus.isOffline.value = false);
  tearDown(() => NetworkStatus.isOffline.value = false);

  test('reports offline only when no network interface is available', () {
    expect(NetworkStatus.isOfflineResult(const []), isTrue);
    expect(
      NetworkStatus.isOfflineResult(const [ConnectivityResult.none]),
      isTrue,
    );
    expect(
      NetworkStatus.isOfflineResult(const [ConnectivityResult.wifi]),
      isFalse,
    );
  });

  test('turns Firebase unavailable errors into an offline action message', () {
    final message = networkAwareErrorMessage(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      action: 'save this expense',
    );

    expect(
      message,
      "You're offline. Connect to the internet to save this expense.",
    );
  });

  testWidgets('shows a persistent saved-data banner while offline', (
    tester,
  ) async {
    NetworkStatus.isOffline.value = true;

    await tester.pumpWidget(
      const MaterialApp(
        home: ConnectivityBannerHost(child: Scaffold(body: SizedBox())),
      ),
    );
    await tester.pump();

    expect(find.text("You're offline • Showing saved data"), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });
}
