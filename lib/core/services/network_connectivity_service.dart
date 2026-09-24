import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Estados posibles de la conexión a internet en la aplicación.
enum NetworkStatus {
  online,   // Hay conexión funcional a internet.
  offline,  // No hay red o no hay salida real a internet.
  restored, // La conexión se acaba de restablecer (feedback visual temporal).
}

/// Notifier que monitoriza en tiempo real el estado de la red.
/// 
/// Diseñado para Riverpod 3.x y compatible de forma nativa con Android, Windows y Web.
class NetworkConnectivityNotifier extends Notifier<NetworkStatus> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _restoredTimer;
  bool _wasOffline = false;

  @override
  NetworkStatus build() {
    // Liberación segura de memoria cuando el provider se destruye
    ref.onDispose(() {
      _subscription?.cancel();
      _restoredTimer?.cancel();
    });

    // Iniciar la verificación en segundo plano
    _initConnectivity();

    // Estado inicial por defecto
    return NetworkStatus.online;
  }

  /// Inicializa la verificación al arrancar y suscribe el Stream de cambios.
  Future<void> _initConnectivity() async {
    try {
      // 1. Verificación inicial de adaptadores de red
      final List<ConnectivityResult> initialResults =
          await _connectivity.checkConnectivity();
      await _handleConnectivityChange(initialResults);
    } catch (e) {
      debugPrint("⚠️ [ConnectivityService] Error en chequeo inicial: $e");
    }

    // 2. Escuchar cambios de red en tiempo real (Wi-Fi, Datos, Ethernet o desconexión)
    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _handleConnectivityChange(results);
      },
      onError: (error) {
        debugPrint("⚠️ [ConnectivityService] Error en stream de red: $error");
      },
    );
  }

  /// Evalúa la lista de conexiones devueltas por connectivity_plus 7.x
  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) async {
    // Si no hay adaptadores activos o la lista indica desconexión total
    final bool hasNoNetwork =
        results.isEmpty || results.contains(ConnectivityResult.none);

    if (hasNoNetwork) {
      _setOffline();
      return;
    }

    // Si hay adaptador activo (Wi-Fi, Datos, Ethernet), verificamos si hay acceso real
    final bool hasRealInternet = await _checkRealInternetAccess();

    if (!hasRealInternet) {
      _setOffline();
    } else {
      _setOnline();
    }
  }

  /// Marca el estado como desconectado
  void _setOffline() {
    _restoredTimer?.cancel();
    _wasOffline = true;
    if (state != NetworkStatus.offline) {
      state = NetworkStatus.offline;
    }
  }

  /// Marca el estado como conectado y gestiona la transición visual "restored"
  void _setOnline() {
    if (_wasOffline) {
      // Estaba offline y acaba de regresar la señal
      _wasOffline = false;
      state = NetworkStatus.restored;

      // Mantener el aviso verde durante 4 segundos antes de ocultarlo
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

  /// Comprueba si realmente existe salida a internet hacia el exterior.
  Future<bool> _checkRealInternetAccess() async {
    // En Flutter Web, el navegador gestiona los sockets y aplicar un ping manual
    // puede arrojar bloqueos de CORS (XMLHttpRequest).
    if (kIsWeb) return true;

    try {
      // Petición ultra ligera con timeout estricto de 2.5 segundos
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(milliseconds: 2500));
      return response.statusCode == 204;
    } catch (_) {
      return false; // Error de timeout, DNS caído o Wi-Fi sin salida a internet
    }
  }

  /// Método público para forzar un re-chequeo manual en cualquier momento
  Future<void> checkConnectionNow() async {
    final results = await _connectivity.checkConnectivity();
    await _handleConnectivityChange(results);
  }
}

/// Provider global accesible desde cualquier widget o servicio de la app
final networkConnectivityProvider =
    NotifierProvider<NetworkConnectivityNotifier, NetworkStatus>(
  NetworkConnectivityNotifier.new,
);