import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

enum NetworkStatus {
  online,
  offline,
  restored,
}

class NetworkConnectivityNotifier extends Notifier<NetworkStatus> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _restoredTimer;
  bool _wasOffline = false;

  @override
  NetworkStatus build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _restoredTimer?.cancel();
    });

    _initConnectivity();
    return NetworkStatus.online;
  }

  Future<void> _initConnectivity() async {
    try {
      final List<ConnectivityResult> initialResults =
          await _connectivity.checkConnectivity();
      await _handleConnectivityChange(initialResults);
    } catch (e) {
      debugPrint("⚠️ [ConnectivityService] Error en chequeo inicial: $e");
    }

    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _handleConnectivityChange(results);
      },
      onError: (error) {
        debugPrint("⚠️ [ConnectivityService] Error en stream de red: $error");
      },
    );
  }

  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) async {
    final bool hasNoNetwork =
        results.isEmpty || results.contains(ConnectivityResult.none);

    if (hasNoNetwork) {
      _setOffline();
      return;
    }

    // Comprobamos salida real
    final bool hasRealInternet = await _checkRealInternetAccess(results);

    if (!hasRealInternet) {
      _setOffline();
    } else {
      _setOnline();
    }
  }

  void _setOffline() {
    _restoredTimer?.cancel();
    _wasOffline = true;
    if (state != NetworkStatus.offline) {
      state = NetworkStatus.offline;
    }
  }

  void _setOnline() {
    if (_wasOffline) {
      _wasOffline = false;
      state = NetworkStatus.restored;

      _restoredTimer?.cancel();
      _restoredTimer = Timer(const Duration(seconds: 4), () {
        if (state == NetworkStatus.restored) {
          state = NetworkStatus.online;
        }
      });
    } else {
      state = NetworkStatus.online;
    }
  }

  /// Verificación de conectividad real diferenciada por plataforma
  Future<bool> _checkRealInternetAccess(List<ConnectivityResult> results) async {
    // EN WEB:
    // 1. ConnectivityResult.none ya descartó si el navegador no tiene red.
    // 2. No hacemos http.get a dominios de terceros para evitar bloqueo CORS.
    // Si connectivity_plus detecta wifi/ethernet/mobile en web, estamos online.
    if (kIsWeb) {
      return !results.contains(ConnectivityResult.none);
    }

    // EN MÓVIL Y DESKTOP:
    // Aquí sí podemos hacer el ping ligero sin problemas de CORS.
    try {
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(milliseconds: 2500));
      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<void> checkConnectionNow() async {
    final results = await _connectivity.checkConnectivity();
    await _handleConnectivityChange(results);
  }
}

final networkConnectivityProvider =
    NotifierProvider<NetworkConnectivityNotifier, NetworkStatus>(
  NetworkConnectivityNotifier.new,
);