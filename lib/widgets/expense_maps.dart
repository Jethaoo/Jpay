import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app_theme.dart';
import '../backend/backend_models.dart';
import '../services/expense_location_service.dart';

const _tileUrl = String.fromEnvironment(
  'OSM_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

class ExpenseLocationPickerScreen extends StatefulWidget {
  final ExpenseLocation? initialLocation;

  const ExpenseLocationPickerScreen({super.key, this.initialLocation});

  @override
  State<ExpenseLocationPickerScreen> createState() =>
      _ExpenseLocationPickerScreenState();
}

class _ExpenseLocationPickerScreenState
    extends State<ExpenseLocationPickerScreen> {
  final _service = ExpenseLocationService();
  final _queryController = TextEditingController();
  final _mapController = MapController();
  ExpenseLocation? _selected;
  List<ExpenseLocation> _results = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialLocation;
  }

  @override
  void dispose() {
    _service.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loading = true);
    try {
      final location = await _service.currentLocation();
      if (!mounted) return;
      setState(() => _selected = location);
      _mapController.move(LatLng(location.latitude, location.longitude), 16);
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    if (_queryController.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final results = await _service.search(_queryController.text);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pin(LatLng point) async {
    setState(() {
      _selected = ExpenseLocation(
        label: 'Pinned location',
        address:
            '${point.latitude.toStringAsFixed(6)}, '
            '${point.longitude.toStringAsFixed(6)}',
        latitude: point.latitude,
        longitude: point.longitude,
      );
      _loading = true;
    });
    try {
      final location = await _service.reverse(point.latitude, point.longitude);
      if (mounted) setState(() => _selected = location);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _choose(ExpenseLocation location) {
    setState(() {
      _selected = location;
      _results = const [];
    });
    _mapController.move(LatLng(location.latitude, location.longitude), 16);
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected == null
        ? const LatLng(3.1390, 101.6869)
        : LatLng(_selected!.latitude, _selected!.longitude);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose location'),
        actions: [
          TextButton(
            onPressed: _selected == null
                ? null
                : () => Navigator.pop(context, _selected),
            child: const Text('Use place'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Search shop or place',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _loading ? null : _useCurrentLocation,
                  tooltip: 'Use current location',
                  icon: const Icon(Icons.my_location_rounded),
                ),
              ],
            ),
          ),
          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: _results
                    .map(
                      (place) => ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(place.label),
                        subtitle: Text(
                          place.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _choose(place),
                      ),
                    )
                    .toList(),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: _selected == null ? 11 : 16,
                    onLongPress: (_, point) => _pin(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl,
                      userAgentPackageName: 'com.example.jpay',
                    ),
                    if (_selected != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: center,
                            width: 52,
                            height: 52,
                            child: const Icon(
                              Icons.location_pin,
                              color: AppPalette.red,
                              size: 44,
                            ),
                          ),
                        ],
                      ),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('© OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                if (_loading)
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: CircularProgressIndicator(),
                  ),
                const Positioned(
                  bottom: 34,
                  left: 12,
                  right: 12,
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'Long-press the map to place a pin.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_selected != null)
            ListTile(
              leading: const Icon(Icons.place_rounded, color: AppPalette.blue),
              title: Text(_selected!.label),
              subtitle: Text(
                _selected!.address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class ExpenseHistoryMap extends StatelessWidget {
  final List<ExpenseRecord> expenses;
  final ValueChanged<ExpenseRecord> onSelected;

  const ExpenseHistoryMap({
    super.key,
    required this.expenses,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final located = expenses
        .where((expense) => expense.location != null)
        .toList();
    if (located.isEmpty) {
      return const SizedBox(
        height: 360,
        child: Center(
          child: Text(
            'No matching expenses have a saved location.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppPalette.secondaryLabel),
          ),
        ),
      );
    }
    final first = located.first.location!;
    return SizedBox(
      height: 430,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(first.latitude, first.longitude),
            initialZoom: located.length == 1 ? 16 : 11,
          ),
          children: [
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'com.example.jpay',
            ),
            MarkerLayer(
              markers: located.map((expense) {
                final location = expense.location!;
                return Marker(
                  point: LatLng(location.latitude, location.longitude),
                  width: 52,
                  height: 52,
                  child: Tooltip(
                    message:
                        '${expense.title} · '
                        'RM ${expense.totalWithCharges.toStringAsFixed(2)}',
                    child: IconButton(
                      onPressed: () => onSelected(expense),
                      icon: const Icon(
                        Icons.location_pin,
                        color: AppPalette.red,
                        size: 40,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
