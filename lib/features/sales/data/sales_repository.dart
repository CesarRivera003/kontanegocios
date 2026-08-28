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

  // 1. PROCESAR VENTA (TRANSACCIÓN ATÓMICA BLINDADA)
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
  }) async {
    try {
      final companyRef = _firestore.collection('companies').doc(userId);
      final profileRef = companyRef.collection('config').doc('profile');
      
      // --- PASO 0: VALIDACIÓN DE SUSCRIPCIÓN ---
      final profileSnap = await profileRef.get();
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

      // --- PASO 1: EMITIR FACTURA ELECTRÓNICA ---
      String finalDianStatus = isElectronicInvoice ? 'Pendiente' : 'No Aplica';
      String? finalCufe;
      String? finalPdfUrl;
      String? dianPrefix;
      int? dianNumber;

      final salesRef = customId != null ? companyRef.collection('sales').doc(customId) : companyRef.collection('sales').doc();

      if (isElectronicInvoice && client != null) {

        // 1. PRIMERO VERIFICAMOS: ¿Tiene saldo disponible? (No descuenta nada aún)
        final settingsRepo = SettingsRepository(_firestore, userId);
        final hasBalance = await settingsRepo.hasInvoiceBalance();

        if (!hasBalance) {
          throw Exception("ERROR_SALDO_AGOTADO");
        }

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

        // 2. COMPROBAMOS EL ÉXITO DE LA EMISIÓN
        if (feResult != null) {
          finalDianStatus = feResult['status'] ?? 'Pendiente';
          finalCufe = feResult['cufe'];
          finalPdfUrl = feResult['pdfUrl'];
          dianPrefix = feResult['prefix'];
          dianNumber = feResult['number'];

          // 🔥 ¡EL CAMBIO CRÍTICO AQUÍ! 🔥
          // Solo si la factura fue creada exitosamente en Plemsi, la descontamos de su saldo
          await settingsRepo.consumeElectronicInvoice();
          
        } else {
          // Si Plemsi devuelve null es porque la DIAN rechazó los datos o hubo un error técnico
          throw Exception("ERROR_PLEMSI_FALLO");
        }
      }

      final saleDate = DateTime.now();
      final currentMonthStr = "${saleDate.year}-${saleDate.month.toString().padLeft(2, '0')}";
      Sale? createdSale;

      // --- PASO 2: TRANSACCIÓN ATÓMICA MAESTRA ---
      await _firestore.runTransaction((transaction) async {
        final countersRef = companyRef.collection('config').doc('counters');
        
        // A. Lecturas Obligatorias
        DocumentSnapshot counterSnap = await transaction.get(countersRef);
        DocumentSnapshot termSnap = await transaction.get(profileRef);
        
        // B. Calcular el nuevo Número POS
        int currentSaleCount = 0;
        if (counterSnap.exists && counterSnap.data() != null) {
          currentSaleCount = (counterSnap.data() as Map<String, dynamic>)['salesCount'] ?? 0;
        }
        int nextSaleCount = currentSaleCount + 1;
        String newTicketNumber = "POS-${nextSaleCount.toString().padLeft(5, '0')}";

        // C. Preparar objeto de Venta
        final saleObj = Sale(
          id: salesRef.id,
          date: saleDate,
          total: total,
          items: Sale.cartItemsToMap(cartItems),
          initialPayments: paymentMethods,
          clientName: clientName,
          sellerName: sellerName ?? 'Admin',
          additionalCosts: additionalCosts ?? [],
          isElectronicInvoice: isElectronicInvoice,
          dianStatus: finalDianStatus, 
          cufe: finalCufe,             
          pdfUrl: finalPdfUrl,
          ticketNumber: newTicketNumber,
          dianPrefix: dianPrefix,
          dianNumber: dianNumber,
        );

        createdSale = saleObj;

        // D. ESCRITURAS SEGURAS (Usamos SetOptions(merge: true) para evitar cuelgues)
        transaction.set(salesRef, saleObj.toMap());
        transaction.set(countersRef, {'salesCount': nextSaleCount}, SetOptions(merge: true));

        // Descontar Inventario
        for (final item in cartItems) {
          if (item.product.isService) continue;
          final productRef = companyRef.collection('products').doc(item.product.id);
          transaction.set(productRef, {'stock': FieldValue.increment(-item.quantity)}, SetOptions(merge: true));
        }

        // Actualizar Termómetro de Ventas
        if (termSnap.exists) {
          final termData = termSnap.data() as Map<String, dynamic>;
          final dbMonth = termData['currentMonth'] as String?;
          if (dbMonth != currentMonthStr) {
            transaction.set(profileRef, {'currentMonth': currentMonthStr, 'currentMonthSales': total}, SetOptions(merge: true));
          } else {
            transaction.set(profileRef, {'currentMonthSales': FieldValue.increment(total)}, SetOptions(merge: true));
          }
        }
      });

      return createdSale!;
      
    } catch (e) {
      debugPrint("❌ Error crítico en processSale: $e");
      throw Exception("Hubo un error al procesar la venta: $e");
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