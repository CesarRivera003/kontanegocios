import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'firebase_options.dart'; 
import 'package:konta_gestor/core/router/app_router.dart';
import 'package:konta_gestor/core/theme/app_theme.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart';

Future<void> main() async {
  // 1. INICIALIZAMOS SENTRY PRIMERO Y ENVOLVEMOS TODA LA APP EN SU ZONA
  await SentryFlutter.init(
    (options) {
      // Usamos kReleaseMode para silenciar Sentry en desarrollo y evitar los errores de "dwds"
      options.dsn = kReleaseMode 
          ? 'https://c01004bd121db10ca0bb5a40c41760d5@o4511844637868032.ingest.us.sentry.io/4511844647239680' 
          : ''; 
      options.tracesSampleRate = 1.0; 
    },
    // 2. CONVERTIMOS EL APPRUNNER EN ASYNC Y METEMOS TODA LA INICIALIZACIÓN AQUÍ
    appRunner: () async {
      // ESTA LÍNEA DEBE SER LA PRIMERA DENTRO DEL APPRUNNER (Soluciona el Zone mismatch)
      WidgetsFlutterBinding.ensureInitialized();

      // ACTIVAMOS RUTAS LIMPIAS (Sin el #) AQUÍ
      usePathUrlStrategy(); 

      // Inicialización de Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Configuración de Firestore
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true, 
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED
      );

      // Inicializamos RevenueCat
      await _configureRevenueCat();

      // Arrancamos la app
      runApp(
        const ProviderScope(
          child: MyApp(),
        ),
      );
    },
  );
}

// --- FUNCIÓN DE CONFIGURACIÓN DE PAGOS ---
Future<void> _configureRevenueCat() async {
  try {
    if (kIsWeb) {
      debugPrint("📱 MODO WEB DETECTADO: Saltando inicialización de RevenueCat.");
      return; 
    }

    await Purchases.setLogLevel(LogLevel.debug);
    String apiKey = "goog_iIXDwhwuojahguSeiJXjQzkXtbu"; 

    if (defaultTargetPlatform == TargetPlatform.android) {
      PurchasesConfiguration configuration = PurchasesConfiguration(apiKey);
      await Purchases.configure(configuration);
    }
  } catch (e) {
    debugPrint("Error inicializando RevenueCat: $e");
  }
}

class MyApp extends ConsumerWidget { 
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Konta Negocios',
      theme: AppTheme.getTheme(),
      routerConfig: router, 
      debugShowCheckedModeBanner: false, 
    );
  }
}