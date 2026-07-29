import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../backend/backend_models.dart';

class ExpenseLocationService {
  static const _defaultNominatim = 'https://nominatim.openstreetmap.org';
  static const _nominatimBase = String.fromEnvironment(
    'NOMINATIM_BASE_URL',
    defaultValue: _defaultNominatim,
  );
  static const userAgent = String.fromEnvironment(
    'MAP_USER_AGENT',
    defaultValue: 'Jpay/1.0 (com.example.jpay)',
  );

  final http.Client _client;
  DateTime? _lastRequest;

  ExpenseLocationService({http.Client? client})
    : _client = client ?? http.Client();

  Future<ExpenseLocation> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceDisabledException();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException('Location permission was denied.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return reverse(position.latitude, position.longitude);
  }

  Future<List<ExpenseLocation>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    await _throttle();
    final uri = Uri.parse('$_nominatimBase/search').replace(
      queryParameters: {
        'q': query.trim(),
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '8',
      },
    );
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw StateError('Place search failed (${response.statusCode}).');
    }
    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .map(_fromNominatim)
        .where((place) => place != null)
        .cast<ExpenseLocation>()
        .toList();
  }

  Future<ExpenseLocation> reverse(double latitude, double longitude) async {
    await _throttle();
    final uri = Uri.parse('$_nominatimBase/reverse').replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'format': 'jsonv2',
        'addressdetails': '1',
      },
    );
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      return ExpenseLocation(
        label: 'Pinned location',
        address:
            '${latitude.toStringAsFixed(6)}, '
            '${longitude.toStringAsFixed(6)}',
        latitude: latitude,
        longitude: longitude,
      );
    }
    final row = jsonDecode(response.body) as Map<String, dynamic>;
    return _fromNominatim(row) ??
        ExpenseLocation(
          label: 'Pinned location',
          address:
              '${latitude.toStringAsFixed(6)}, '
              '${longitude.toStringAsFixed(6)}',
          latitude: latitude,
          longitude: longitude,
        );
  }

  Map<String, String> get _headers => {
    'User-Agent': userAgent,
    'Accept-Language': 'en',
  };

  Future<void> _throttle() async {
    final last = _lastRequest;
    if (last != null) {
      final remaining =
          const Duration(seconds: 1) - DateTime.now().difference(last);
      if (!remaining.isNegative) await Future<void>.delayed(remaining);
    }
    _lastRequest = DateTime.now();
  }

  ExpenseLocation? _fromNominatim(Map<String, dynamic> row) {
    final latitude = double.tryParse(row['lat']?.toString() ?? '');
    final longitude = double.tryParse(row['lon']?.toString() ?? '');
    if (latitude == null || longitude == null) return null;
    final address = row['address'] as Map<String, dynamic>?;
    final label =
        address?['shop'] ??
        address?['amenity'] ??
        address?['tourism'] ??
        address?['building'] ??
        row['name'] ??
        (row['display_name'] as String?)?.split(',').first ??
        'Selected place';
    return ExpenseLocation(
      label: label.toString(),
      address: row['display_name'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
      osmType: row['osm_type'] as String?,
      osmId: row['osm_id']?.toString(),
    );
  }

  void dispose() => _client.close();
}
