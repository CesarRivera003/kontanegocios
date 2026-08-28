import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Este provider mantiene la ÚNICA llave del Scaffold del Dashboard en toda la app.
// Al usar 'keepAlive: true' (por defecto en Provider), evitamos que se destruya y recree,
// solucionando el error de "Duplicate GlobalKey".
final dashboardScaffoldKeyProvider = Provider<GlobalKey<ScaffoldState>>((ref) {
  return GlobalKey<ScaffoldState>();
});

// Función auxiliar segura para abrir el Drawer desde cualquier lado
void openDashboardDrawer(WidgetRef ref) {
  final key = ref.read(dashboardScaffoldKeyProvider);
  // Verificamos si la llave está atada a un widget actual
  if (key.currentState != null) {
    key.currentState!.openDrawer();
  }
}