import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:konta_gestor/main.dart';
import 'package:konta_gestor/core/router/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:konta_gestor/features/auth/data/auth_repository.dart';

// Mock Router Provider para el test
final mockRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Center(child: Text('Mock Home')))),
    ],
  );
});

void main() {
  testWidgets('App structural smoke test', (WidgetTester tester) async {
    // Override del router
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routerProvider.overrideWith((ref) => ref.watch(mockRouterProvider)),
        ],
        child: const MyApp(),
      ),
    );

    // Verificamos que el MaterialApp se dibuja
    expect(find.byType(MaterialApp), findsOneWidget);

    // Verificamos que el router funciona y dibuja nuestra pantalla inicial de mock
    await tester.pumpAndSettle();
    expect(find.text('Mock Home'), findsOneWidget);
  });
}
