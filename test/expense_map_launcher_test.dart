import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/backend/backend_models.dart';
import 'package:jpay/services/expense_map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  const location = ExpenseLocation(
    label: 'Central Market & Annexe',
    address: 'Jalan Hang Kasturi, Kuala Lumpur, Malaysia',
    latitude: 3.1453,
    longitude: 101.6955,
  );

  test('Android opens an exact labeled geo marker', () async {
    final launched = <Uri>[];
    final modes = <LaunchMode>[];
    final launcher = ExpenseMapLauncher(
      targetPlatform: TargetPlatform.android,
      isWeb: false,
      launchUri: (uri, {required mode}) async {
        launched.add(uri);
        modes.add(mode);
        return true;
      },
    );

    expect(await launcher.openMarker(location), isTrue);
    expect(launched, hasLength(1));
    expect(launched.single.scheme, 'geo');
    expect(launched.single.path, '3.1453,101.6955');
    expect(
      launched.single.queryParameters['q'],
      '3.1453,101.6955(Central Market & Annexe)',
    );
    expect(modes.single, LaunchMode.externalApplication);
  });

  test('Apple platforms open a labeled Apple Maps marker', () async {
    final launched = <Uri>[];
    final launcher = ExpenseMapLauncher(
      targetPlatform: TargetPlatform.iOS,
      isWeb: false,
      launchUri: (uri, {required mode}) async {
        launched.add(uri);
        return true;
      },
    );

    expect(await launcher.openMarker(location), isTrue);
    expect(launched.single.scheme, 'https');
    expect(launched.single.host, 'maps.apple.com');
    expect(launched.single.queryParameters, {
      'll': '3.1453,101.6955',
      'q': 'Central Market & Annexe',
    });
  });

  test('web and desktop use an OpenStreetMap marker', () async {
    final launched = <Uri>[];
    final launcher = ExpenseMapLauncher(
      targetPlatform: TargetPlatform.windows,
      isWeb: true,
      launchUri: (uri, {required mode}) async {
        launched.add(uri);
        return true;
      },
    );

    expect(await launcher.openMarker(location), isTrue);
    expect(launched.single.host, 'www.openstreetmap.org');
    expect(launched.single.queryParameters, {
      'mlat': '3.1453',
      'mlon': '101.6955',
    });
    expect(launched.single.fragment, 'map=18/3.1453/101.6955');
  });

  test('a failed native launch falls back to OpenStreetMap', () async {
    final launched = <Uri>[];
    final launcher = ExpenseMapLauncher(
      targetPlatform: TargetPlatform.android,
      isWeb: false,
      launchUri: (uri, {required mode}) async {
        launched.add(uri);
        if (launched.length == 1) throw StateError('No maps app');
        return true;
      },
    );

    expect(await launcher.openMarker(location), isTrue);
    expect(launched, hasLength(2));
    expect(launched.first.scheme, 'geo');
    expect(launched.last.host, 'www.openstreetmap.org');
  });

  test('returns false when neither map destination can open', () async {
    final launched = <Uri>[];
    final launcher = ExpenseMapLauncher(
      targetPlatform: TargetPlatform.android,
      isWeb: false,
      launchUri: (uri, {required mode}) async {
        launched.add(uri);
        return false;
      },
    );

    expect(await launcher.openMarker(location), isFalse);
    expect(launched, hasLength(2));
  });
}
