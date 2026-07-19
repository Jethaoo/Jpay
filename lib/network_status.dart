import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

abstract final class NetworkStatus {
  static final ValueNotifier<bool> isOffline = ValueNotifier(false);

  static bool isOfflineResult(List<ConnectivityResult> results) {
    return results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);
  }

  static void update(List<ConnectivityResult> results) {
    final nextValue = isOfflineResult(results);
    if (isOffline.value != nextValue) isOffline.value = nextValue;
  }
}

String networkAwareErrorMessage(Object error, {required String action}) {
  final normalizedError = error.toString().toLowerCase();
  final firebaseCode = error is FirebaseException
      ? error.code.toLowerCase()
      : '';
  final isNetworkFailure =
      NetworkStatus.isOffline.value ||
      firebaseCode == 'unavailable' ||
      firebaseCode == 'network-request-failed' ||
      normalizedError.contains('network is unreachable') ||
      normalizedError.contains('failed host lookup') ||
      normalizedError.contains('socketexception');

  if (isNetworkFailure) {
    return "You're offline. Connect to the internet to $action.";
  }
  return "Unable to $action. Please try again.";
}

class ConnectivityBannerHost extends StatefulWidget {
  final Widget child;

  const ConnectivityBannerHost({super.key, required this.child});

  @override
  State<ConnectivityBannerHost> createState() => _ConnectivityBannerHostState();
}

class _ConnectivityBannerHostState extends State<ConnectivityBannerHost>
    with WidgetsBindingObserver {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _subscription = _connectivity.onConnectivityChanged.listen(
      NetworkStatus.update,
      onError: (_) {},
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      NetworkStatus.update(await _connectivity.checkConnectivity());
    } catch (_) {
      // Keep the last known state if the platform check is unavailable.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: NetworkStatus.isOffline,
      child: widget.child,
      builder: (context, isOffline, child) {
        final mediaQuery = MediaQuery.of(context);
        final childMediaQuery = isOffline
            ? mediaQuery.copyWith(padding: mediaQuery.padding.copyWith(top: 0))
            : mediaQuery;

        return Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: isOffline
                  ? Material(
                      color: AppPalette.orange,
                      child: SafeArea(
                        bottom: false,
                        child: const SizedBox(
                          height: 40,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                size: 18,
                                color: Colors.black,
                              ),
                              SizedBox(width: 8),
                              Text(
                                "You're offline • Showing saved data",
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: MediaQuery(data: childMediaQuery, child: child!),
            ),
          ],
        );
      },
    );
  }
}
