import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/cart_item_model.dart';
import '../domain/sale_model.dart';
import '../../clients/domain/client_model.dart';
import 'plemsi_service.dart';
import '../../settings/data/settings_repository.dart';

class SalesRepository {
  final FirebaseFirestore _firestore;
  final String userId; 

  SalesRepository(this._firestore, this.userId);

  // 1. PROCESAR VENTA (HÍBRIDO ONLINE / OFFLINE)
  Future<Sale> processSale({
    required List<CartItem> cartItems,
    required double total,
    required List<PaymentMethodDetail> paymentMethods,
    DateTime? paymentDeadline, 
    String? clientName, 
    String? bankName, 
    String? sellerName,
    List<Map<String, dynamic>>? additionalCosts,
    String? customId,
    bool isElectronicInvoice = false,
    Client? client,
    bool isOnline = true, // <-- NUEVO PARÁMETRO
  }) async {
    try {
      final companyRef = _firestore.collection('companies').doc(userId);
      final profileRef = companyRef.collection('config').doc('profile');
      final countersRef = companyRef.collection('config').doc('counters');
      final salesRef = customId != null 
          ? companyRef.collection('sales').doc(customId) 
          : companyRef.collection('sales').doc();

      // --- PASO 0: VALIDACIÓN DE SUSCRIPCIÓN CON CACHÉ DE RESPALDO ---
      try {
        final profileSnap = await profileRef.get(
          isOnline ? const GetOptions(source: Source.serverAndCache) : const GetOptions(source: Source.cache)
        ).timeout(const Duration(seconds: 2));

        if (profileSnap.exists) {
          final data = profileSnap.data() as Map<String, dynamic>;
          final status = data['subscriptionStatus'] as String? ?? 'trial';
          final referrals = data['referralCount'] as int? ?? 0;
          final currentSales = (data['currentMonthSales'] as num?)?.toDouble() ?? 0.0;
          const maxSalesEmprendedor = 4000000.0; 

          final isPremium = status == 'pro' || status == 'empresarial' || status == 'lifetime';
          if (!isPremium) {
            bool isTrialValid = false;
            if (data['trialEndsAt'] != null) {
              final trialEndsAt = (data['trialEndsAt'] as Timestamp).toDate();
              if (trialEndsAt.isAfter(DateTime.now())) isTrialValid = true;
            }
            final isEmprendedor = (referrals >= 2) || status == 'freemium';
            if (!isTrialValid) {
              if (isEmprendedor) {
                if ((currentSales + total) > maxSalesEmprendedor) throw Exception("Límite de ventas mensual superado.");
              } else {
                throw Exception("Tu periodo de prueba ha expirado.");
              }
            }
          }
        }
      } catch (e) {
        // En offline permitimos continuar si no se pudo consultar el servidor
        if (isOnline && e.toString().contains("Límite") || e.toString().contains("expirado")) rethrow;
      }

      // --- PASO 1: EMISIÓN ELECTRÓNICA O ENCOLADO OFFLINE ---
      String finalDianStatus = 'No Aplica';
      String? finalCufe;
      String? finalPdfUrl;
      String? dianPrefix;
      int? dianNumber;
      bool saleNeedsSync = false;

      if (isElectronicInvoice) {
        if (isOnline && client != null) {
          // ONLINE: Intentamos emitir inmediatamente a la DIAN
          final settingsRepo = SettingsRepository(_firestore, userId);
          final hasBalance = await settingsRepo.hasInvoiceBalance();
          if (!hasBalance) throw Exception("ERROR_SALDO_AGOTADO");

          final safePaymentMethods = paymentMethods.map((p) => PaymentMethodDetail(
            method: p.method,
            amount: p.amount,
            bankName: p.bankName,
            paymentDeadline: null, 
          )).toList();

          final plemsi = PlemsiService(_firestore);
          final feResult = await plemsi.emitInvoice(
            companyId: userId,
            saleId: salesRef.id,
            client: client,
            cartItems: cartItems,
            totalSaleValue: total,
            paymentMethods: safePaymentMethods,
            additionalCosts: additionalCosts ?? [],
            paymentDeadline: paymentDeadline,
          );

          if (feResult != null) {
            finalDianStatus = feResult['status'] ?? 'Pendiente';
            finalCufe = feResult['cufe'];
            finalPdfUrl = feResult['pdfUrl'];
            dianPrefix = feResult['prefix'];
            dianNumber = feResult['number'];
            await settingsRepo.consumeElectronicInvoice();
          } else {
            throw Exception("ERROR_PLEMSI_FALLO");
          }
        } else {
          // OFFLINE: Encolamos para transmitir después
          finalDianStatus = 'Pendiente_Sincronizacion';
          saleNeedsSync = true;
        }
      }

      final saleDate = DateTime.now();
      final currentMonthStr = "${saleDate.year}-${saleDate.month.toString().padLeft(2, '0')}";
      
      // Obtener o calcular número de ticket consecutivo
      int currentSaleCount = 0;
      try {
        final counterSnap = await countersRef.get(const GetOptions(source: Source.cache));
        if (counterSnap.exists && counterSnap.data() != null) {
          currentSaleCount = (counterSnap.data() as Map<String, dynamic>)['salesCount'] ?? 0;
        }
      } catch (_) {}
      
      int nextSaleCount = currentSaleCount + 1;
      String newTicketNumber = isOnline 
          ? "POS-${nextSaleCount.toString().padLeft(5, '0')}"
          : "OFF-${nextSaleCount.toString().padLeft(5, '0')}";

      final saleObj = Sale(
        id: salesRef.id,
        date: saleDate,
        total: total,
        items: Sale.cartItemsToMap(cartItems),
        initialPayments: paymentMethods,
        clientName: clientName,
        clientIdNumber: (client != null && client.idNumber.isNotEmpty) ? client.idNumber : null,
        clientData: client?.toMap(),
        sellerName: sellerName ?? 'Admin',
        additionalCosts: additionalCosts ?? [],
        isElectronicInvoice: isElectronicInvoice,
        dianStatus: finalDianStatus, 
        cufe: finalCufe,             
        pdfUrl: finalPdfUrl,
        ticketNumber: newTicketNumber,
        dianPrefix: dianPrefix,
        dianNumber: dianNumber,
        needsSync: saleNeedsSync || !isOnline,
        isOffline: !isOnline,
      );

      // --- PASO 2: GUARDADO ROBUSTO CON BATCH (COMPATIBLE ONLINE Y OFFLINE) ---
      final batch = _firestore.batch();

      // A. Guardar Venta
      batch.set(salesRef, saleObj.toMap());

      // B. Incrementar Consecutivo
      batch.set(countersRef, {'salesCount': nextSaleCount}, SetOptions(merge: true));

      // C. Descontar Inventario con FieldValue.increment
      for (final item in cartItems) {
        if (item.product.isService) continue;
        final productRef = companyRef.collection('products').doc(item.product.id);
        batch.set(productRef, {'stock': FieldValue.increment(-item.quantity)}, SetOptions(merge: true));
      }

      // D. Termómetro de ventas
      batch.set(profileRef, {
        'currentMonth': currentMonthStr,
        'currentMonthSales': FieldValue.increment(total),
      }, SetOptions(merge: true));

      // Ejecutar el lote de escritura (se guarda en local si estás offline y se sube solo al volver la red)
      await batch.commit();

      return saleObj;
      
    } catch (e) {
      debugPrint("❌ Error crítico en processSale: $e");
      rethrow;
    }
  }

  // 2. OBTENER VENTAS (STREAM - HISTORIAL)
  Stream<List<Sale>> getSales() {
    return _firestore.collection('companies').doc(userId).collection('sales')
        .orderBy('date', descending: true).snapshots(includeMetadataChanges: true)
        .map((snapshot) => snapshot.docs.map((doc) => Sale.fromMap(doc.data(), doc.id)).toList());
  }

  // 3. ELIMINAR LA VENTA (BLINDADO)
  Future<void> deleteSale(String saleId) async {
    final companyRef = _firestore.collection('companies').doc(userId);
    final saleRef = companyRef.collection('sales').doc(saleId);
    final saleSnapshot = await saleRef.get(); 
    if (!saleSnapshot.exists) throw Exception("La venta no existe localmente ni en red");

    final data = saleSnapshot.data()!;
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final double amountToSubtract = (data['total'] as num?)?.toDouble() ?? 0.0;
    final Timestamp? saleTimestamp = data['date'] as Timestamp?;
    final batch = _firestore.batch();

    for (final item in items) {
      final productId = item['productId'];
      final quantityToReturn = (item['quantity'] as num).toDouble();
      final isService = item['isService'] ?? false;
      if (productId != null && !isService) {
        final productRef = companyRef.collection('products').doc(productId);
        // Usamos set con merge para evitar fallos si el producto fue alterado
        batch.set(productRef, {'stock': FieldValue.increment(quantityToReturn)}, SetOptions(merge: true));
      }
    }
    batch.delete(saleRef);
    await batch.commit();

    if (saleTimestamp != null && amountToSubtract > 0) {
      try {
        final profileRef = companyRef.collection('config').doc('profile');
        final now = DateTime.now();
        final currentMonthStr = "${now.year}-${now.month.toString().padLeft(2, '0')}";
        final saleDate = saleTimestamp.toDate();
        final saleMonthStr = "${saleDate.year}-${saleDate.month.toString().padLeft(2, '0')}";

        await _firestore.runTransaction((transaction) async {
          final snap = await transaction.get(profileRef);
          if (!snap.exists) return;
          
          final profileData = snap.data() as Map<String, dynamic>;
          final dbMonth = profileData['currentMonth'] as String?; // <-- Extraemos el dato primero
          
          if (dbMonth == currentMonthStr && saleMonthStr == currentMonthStr) {
            double currentSales = (profileData['currentMonthSales'] as num?)?.toDouble() ?? 0.0;
            double newSales = currentSales - amountToSubtract;
            transaction.set(profileRef, {'currentMonthSales': newSales < 0 ? 0.0 : newSales}, SetOptions(merge: true));
          }
        });
      } catch (e) {
        debugPrint("Error reversando termómetro de ventas: $e");
      }
    }
  }

  // 4. REGISTRAR ABONO
  Future<void> addPaymentToSale(String saleId, SalePayment payment) async {
    await _firestore.collection('companies').doc(userId).collection('sales').doc(saleId)
        .set({'payments': FieldValue.arrayUnion([payment.toMap()])}, SetOptions(merge: true));
  }

  // 5. OBTENER VENTAS POR FECHA
  Future<List<Sale>> getSalesByDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final query = _firestore.collection('companies').doc(userId).collection('sales')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end)).orderBy('date', descending: true);
    final snapshot = await query.get();
    return snapshot.docs.map((doc) => Sale.fromMap(doc.data(), doc.id)).toList();
  }

  // 6. ANULAR FACTURA ELECTRÓNICA (NOTA CRÉDITO)
  Future<void> annulElectronicSale(String saleId, List<Map<String, dynamic>> items) async {
    final companyRef = _firestore.collection('companies').doc(userId);
    final saleRef = companyRef.collection('sales').doc(saleId);
    final saleSnapshot = await saleRef.get();
    if (!saleSnapshot.exists) throw Exception("La venta no existe localmente ni en red");

    final data = saleSnapshot.data()!;
    final double amountToSubtract = (data['total'] as num?)?.toDouble() ?? 0.0;
    final Timestamp? saleTimestamp = data['date'] as Timestamp?;
    
    final batch = _firestore.batch();

    // 1. Marcar la factura electrónica como Anulada (sin borrar el documento)
    batch.update(saleRef, {'dianStatus': 'Anulada'});

    // 2. Devolver las cantidades al inventario (respetando servicios)
    for (final item in items) {
      final productId = item['productId'];
      final quantityToReturn = (item['quantity'] as num).toDouble();
      final isService = item['isService'] ?? false;
      
      if (productId != null && !isService) {
        final productRef = companyRef.collection('products').doc(productId);
        batch.set(productRef, {'stock': FieldValue.increment(quantityToReturn)}, SetOptions(merge: true));
      }
    }
    
    await batch.commit();

    // 3. Reversar el termómetro de ventas del mes si la venta corresponde al periodo actual
    if (saleTimestamp != null && amountToSubtract > 0) {
      try {
        final profileRef = companyRef.collection('config').doc('profile');
        final now = DateTime.now();
        final currentMonthStr = "${now.year}-${now.month.toString().padLeft(2, '0')}";
        final saleDate = saleTimestamp.toDate();
        final saleMonthStr = "${saleDate.year}-${saleDate.month.toString().padLeft(2, '0')}";

        await _firestore.runTransaction((transaction) async {
          final snap = await transaction.get(profileRef);
          if (!snap.exists) return;
          
          final profileData = snap.data() as Map<String, dynamic>;
          final dbMonth = profileData['currentMonth'] as String?;
          
          if (dbMonth == currentMonthStr && saleMonthStr == currentMonthStr) {
            double currentSales = (profileData['currentMonthSales'] as num?)?.toDouble() ?? 0.0;
            double newSales = currentSales - amountToSubtract;
            transaction.set(profileRef, {'currentMonthSales': newSales < 0 ? 0.0 : newSales}, SetOptions(merge: true));
          }
        });
      } catch (e) {
        debugPrint("Error reversando termómetro de ventas en anulación FE: $e");
      }
    }
  }
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  final companyIdAsync = ref.watch(companyIdProvider);
  final String? companyId = companyIdAsync.value;
  if (companyId == null) throw Exception('Cargando empresa...');
  return SalesRepository(FirebaseFirestore.instance, companyId);
});

final salesStreamProvider = StreamProvider<List<Sale>>((ref) {
  return ref.watch(salesRepositoryProvider).getSales();
});