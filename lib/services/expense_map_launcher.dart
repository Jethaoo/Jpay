import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/backend_models.dart';

typedef ExternalUriLauncher =
    Future<bool> Function(Uri uri, {required LaunchMode mode});

Future<bool> _launchExternalUri(Uri uri, {required LaunchMode mode}) =>
    launchUrl(uri, mode: mode);

class ExpenseMapLauncher {
  final ExternalUriLauncher _launchUri;
  final TargetPlatform? _targetPlatform;
  final bool? _isWeb;

  ExpenseMapLauncher({
    ExternalUriLauncher? launchUri,
    TargetPlatform? targetPlatform,
    bool? isWeb,
  }) : _launchUri = launchUri ?? _launchExternalUri,
       _targetPlatform = targetPlatform,
       _isWeb = isWeb;

  Future<bool> openMarker(ExpenseLocation location) async {
    final fallback = _openStreetMapUri(location);
    final preferred = _preferredUri(
      location,
      platform: _targetPlatform ?? defaultTargetPlatform,
      isWeb: _isWeb ?? kIsWeb,
    );
    if (await _tryLaunch(preferred)) return true;
    if (preferred == fallback) return false;
    return _tryLaunch(fallback);
  }

  Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await _launchUri(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Uri _preferredUri(
    ExpenseLocation location, {
    required TargetPlatform platform,
    required bool isWeb,
  }) {
    if (isWeb) return _openStreetMapUri(location);
    final coordinates = _coordinates(location);
    final title = _markerTitle(location);
    switch (platform) {
      case TargetPlatform.android:
        return Uri(
          scheme: 'geo',
          path: coordinates,
          queryParameters: {'q': '$coordinates($title)'},
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return Uri.https('maps.apple.com', '/', {
          'll': coordinates,
          'q': title,
        });
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return _openStreetMapUri(location);
    }
  }

  Uri _openStreetMapUri(ExpenseLocation location) {
    final latitude = location.latitude.toString();
    final longitude = location.longitude.toString();
    return Uri(
      scheme: 'https',
      host: 'www.openstreetmap.org',
      path: '/',
      queryParameters: {'mlat': latitude, 'mlon': longitude},
      fragment: 'map=18/$latitude/$longitude',
    );
  }

  String _coordinates(ExpenseLocation location) =>
      '${location.latitude},${location.longitude}';

  String _markerTitle(ExpenseLocation location) {
    final label = location.label.trim();
    return label.isEmpty ? 'Saved location' : label;
  }
}
