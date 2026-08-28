import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/company_model.dart';

class SettingsRepository {
  final FirebaseFirestore _firestore;
  final String userId;

  SettingsRepository(this._firestore, this.userId);

  DocumentReference get _profileRef => 
      _firestore.collection('companies').doc(userId).collection('config').doc('profile');

  // NUEVO: Referencia directa a la configuración de la DIAN
  DocumentReference get _feConfigRef => 
      _firestore.collection('companies').doc(userId).collection('config').doc('fe_config');

  // Obtener Perfil (Stream)
  Stream<CompanyProfile> getCompanyProfile() {
    return _profileRef.snapshots().map((doc) {
      return CompanyProfile.fromMap(doc.data() as Map<String, dynamic>?, doc.id);
    });
  }

  // --- ACTUALIZACIÓN SEGURA DE PERFIL ---
  Future<void> updateCompanyProfileData(Map<String, dynamic> data) async {
    await _profileRef.set(data, SetOptions(merge: true));
  }

  // =================================================================
  // NUEVO: LÓGICA DE CONSUMO DE FACTURAS (TRANSACCIÓN SEGURA)
  // =================================================================
  Future<bool> hasInvoiceBalance() async {
    try {
      final snapshot = await _feConfigRef.get();
      if (!snapshot.exists) return false;

      final data = snapshot.data() as Map<String, dynamic>;
      int monthlyUsed = data['monthlyUsed'] ?? 0;
      int extraBalance = data['extraBalance'] ?? 0;
      const int monthlyLimit = 100;

      final now = DateTime.now();
      final currentMonthStr = "${now.year}-${now.month.toString().padLeft(2, '0')}";
      final lastResetMonth = data['lastResetMonth'] ?? "";

      // Si cambió el mes, el consumo real será 0, por lo que sí tiene saldo
      if (lastResetMonth != currentMonthStr) {
        return true;
      }

      return (monthlyUsed < monthlyLimit) || (extraBalance > 0);
    } catch (e) {
      debugPrint("Error verificando saldo de facturas: $e");
      return false;
    }
  }
  
  Future<bool> consumeElectronicInvoice() async {
    try {
      // runTransaction bloquea el documento para evitar dobles cobros accidentales
      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(_feConfigRef);
        
        if (!snapshot.exists) {
          return false; // No ha configurado la DIAN aún
        }

        final data = snapshot.data() as Map<String, dynamic>;
        
        int monthlyUsed = data['monthlyUsed'] ?? 0;
        int extraBalance = data['extraBalance'] ?? 0;
        final int monthlyLimit = 100; // El límite de tu plan por defecto

        // 1. REINICIO PEREZOSO (LAZY RESET)
        final now = DateTime.now();
        // Formato: "2026-05" (Año y mes actual)
        final currentMonthStr = "${now.year}-${now.month.toString().padLeft(2, '0')}";
        final lastResetMonth = data['lastResetMonth'] ?? "";

        // Si el mes registrado no es el mes actual, se reinicia el consumo
        if (lastResetMonth != currentMonthStr) {
          monthlyUsed = 0;
        }

        // 2. LÓGICA DE DESCUENTO (Primero Plan, luego Prepago)
        bool canEmit = false;

        if (monthlyUsed < monthlyLimit) {
          // Aún tiene facturas gratuitas del mes
          monthlyUsed++;
          canEmit = true;
        } else if (extraBalance > 0) {
          // Se agotaron las del mes, usamos del saldo extra comprado
          extraBalance--;
          canEmit = true;
        }

        // 3. GUARDAR LOS CAMBIOS
        if (canEmit) {
          transaction.update(_feConfigRef, {
            'monthlyUsed': monthlyUsed,
            'extraBalance': extraBalance,
            'lastResetMonth': currentMonthStr,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return true; // ✅ Se descontó con éxito, puede emitir
        } else {
          return false; // ❌ No tiene saldo en ningún lado
        }
      });
    } catch (e) {
      debugPrint("Error crítico descontando factura: $e");
      return false; 
    }
  }
}

// --- PROVIDERS SEGUROS (ANTI-CRASH) ---

final settingsRepositoryProvider = Provider<SettingsRepository?>((ref) {
  final companyId = ref.watch(companyIdProvider).value; 
  
  if (companyId == null || companyId.isEmpty) {
    return null;
  }
  
  return SettingsRepository(FirebaseFirestore.instance, companyId);
});

final companyProfileProvider = StreamProvider<CompanyProfile>((ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  
  if (repository == null) {
    return Stream.value(CompanyProfile(name: 'Configurando cuenta...'));
  }
  
  return repository.getCompanyProfile();
});