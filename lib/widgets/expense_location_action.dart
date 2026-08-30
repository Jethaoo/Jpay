import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../backend/backend_models.dart';

typedef ExpenseLocationOpener = Future<bool> Function(ExpenseLocation location);

class ExpenseLocationAction extends StatelessWidget {
  final ExpenseLocation location;
  final ExpenseLocationOpener openLocation;

  const ExpenseLocationAction({
    super.key,
    required this.location,
    required this.openLocation,
  });

  String get _title {
    final label = location.label.trim();
    return label.isEmpty ? 'Saved location' : label;
  }

  String get _address {
    final address = location.address.trim();
    if (address.isNotEmpty) return address;
    return '${location.latitude.toStringAsFixed(6)}, '
        '${location.longitude.toStringAsFixed(6)}';
  }

  Future<void> _open(BuildContext context) async {
    var opened = false;
    try {
      opened = await openLocation(location);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Couldn't open this location in a maps app."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppRadius.medium);
    return Semantics(
      button: true,
      label: 'Open $_title in maps',
      child: Material(
        color: AppPalette.surfaceElevated,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.place_outlined,
                    size: 20,
                    color: AppPalette.blue,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _address,
                        style: const TextStyle(
                          color: AppPalette.secondaryLabel,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Tooltip(
                    message: 'Open in maps',
                    child: Icon(
                      Icons.open_in_new_rounded,
                      size: 19,
                      color: AppPalette.secondaryLabel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
