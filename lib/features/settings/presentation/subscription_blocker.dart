import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/settings_repository.dart';
import '../../auth/presentation/user_profile_provider.dart';
import '../../auth/domain/user_model.dart';

class SubscriptionBlocker extends ConsumerWidget {
  final Widget child;

  const SubscriptionBlocker({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyProfileAsync = ref.watch(companyProfileProvider);
    final userProfileAsync = ref.watch(userProfileProvider);

    // 1. ESPERAR A QUE TERMINE DE CARGAR FIREBASE
    if (companyProfileAsync.isLoading || userProfileAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 2. ASEGURARSE DE QUE EXISTAN LOS DATOS
    if (!companyProfileAsync.hasValue || !userProfileAsync.hasValue || 
        companyProfileAsync.value == null || userProfileAsync.value == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final companyProfile = companyProfileAsync.value!;
    final userProfile = userProfileAsync.value!;

    // 3. EL TRUCO ANTI-PARPADEO (Ignorar el perfil temporal)
    // Si el nombre es el que pusimos por defecto en el repositorio mientras carga, seguimos esperando.
    if (companyProfile.name == 'Configurando cuenta...') {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    final bool isAdmin = userProfile.role == UserRole.admin;
    bool isExpired = false;
    int daysLeft = 999;
    
    // --- LÓGICA DE VALIDACIÓN ---
    final status = companyProfile.subscriptionStatus;
    final isEmprendedor = (companyProfile.referralCount >= 2) || status == 'freemium';
    
    if (status != 'lifetime' && !isEmprendedor) {
      if (companyProfile.trialEndsAt != null) {
        final now = DateTime.now();
        daysLeft = companyProfile.trialEndsAt!.difference(now).inDays;

        if (companyProfile.trialEndsAt!.isBefore(now)) {
          isExpired = true;
        }
      } else {
        isExpired = true; 
      }
    }

    // --- 1. SI ESTÁ VENCIDO, BLOQUEA LA PANTALLA ---
    if (isExpired) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.credit_card_off, size: 80, color: isAdmin ? Colors.red : Colors.grey[600]),
              const SizedBox(height: 20),
              Text(isAdmin ? "PLAN VENCIDO" : "LICENCIA EXPIRADA", 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isAdmin ? Colors.red : Colors.grey[800])
              ),
              const SizedBox(height: 10),
              Text(
                isAdmin 
                  ? "Tu suscripción ha expirado.\nRealiza el pago para reactivar todas las funciones."
                  : "La licencia de uso de este sistema ha expirado.\nPor favor, comunícate con el administrador.", 
                textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.grey[700], fontSize: 16)
              ),
              const SizedBox(height: 25),
              if (isAdmin)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: () => context.push('/subscription'), 
                  icon: const Icon(Icons.workspace_premium),
                  label: const Text("Renovar Plan"),
                )
            ],
          ),
        ),
      );
    }

    // --- 2. SI FALTAN 5 DÍAS (MUESTRA ALERTA GLOBAL SOLO AL ADMIN) ---
    if (isAdmin && daysLeft <= 5 && daysLeft >= 0) {
      return Column(
        children: [
          // Barra de advertencia global en la parte superior
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: daysLeft <= 2 ? Colors.red.shade100 : Colors.orange.shade100,
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: daysLeft <= 2 ? Colors.red : Colors.orange),
                  const SizedBox(width: 10),
                  Text(
                    daysLeft == 0 ? "¡Tu plan vence HOY! Renueva pronto para evitar interrupciones." : "Tu plan vence en $daysLeft días. Renueva pronto.", 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: daysLeft <= 2 ? Colors.red.shade900 : Colors.orange.shade900)
                  ),
                ],
              ),
            ),
          ),
          // El resto de la aplicación abajo de la alerta
          Expanded(child: child), 
        ],
      );
    }

    // --- 3. SI ESTÁ TODO BIEN, LO DEJA PASAR NORMALMENTE ---
    return child; 
  }
}