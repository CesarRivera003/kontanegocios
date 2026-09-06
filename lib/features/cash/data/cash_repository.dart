import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/cash_count_model.dart';
import '../domain/cash_transaction_model.dart'; 
import '../../sales/domain/sale_model.dart';

class CashRepository {
  final FirebaseFirestore _firestore;
  final String companyId;

  CashRepository(this._firestore, this.companyId);

  // --- 1. GESTIÓN DE MOVIMIENTOS ---

  Future<void> addCashMovement(CashTransaction transaction) async {
    await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_movements')
        .doc(transaction.id)
        .set(transaction.toMap());
  }

  Future<void> deleteCashMovement(String movementId) async {
    await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_movements')
        .doc(movementId)
        .delete();
  }

  // Filtro Cliente-Side para evitar Índice Compuesto y bloqueos
  Stream<List<CashTransaction>> getDailyMovements(String userId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_movements')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .snapshots()
        .map((snapshot) {
          final all = snapshot.docs.map((doc) => CashTransaction.fromMap(doc.data()));
          return all.where((tx) => tx.userId == userId).toList();
        });
  }

  // --- 2. CÁLCULO DE TOTALES (LÓGICA ACTUALIZADA GASTOS) ---
  
  Future<Map<String, double>> getUserDailyTotals({
    required String userName, 
    required bool canHaveExpenses,
  }) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // A. VENTAS (Ingresos)
    final salesQuery = await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('sales')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .get();

    double totalCashSales = 0;

    for (var doc in salesQuery.docs) {
      final sale = Sale.fromMap(doc.data(), doc.id);
      
      // 🔥 NUEVO FILTRO: Ignorar completamente las facturas anuladas (Notas Crédito)
      if (sale.dianStatus.toUpperCase() == 'ANULADA') continue;

      final seller = sale.sellerName ?? ''; 
      if (seller.toLowerCase() != userName.toLowerCase()) continue;

      double cashPayment = 0;
      double totalPaidWithAllMethods = 0;

      for (var payment in sale.initialPayments) {
        totalPaidWithAllMethods += payment.amount;
        if (payment.method == 'Efectivo') {
          cashPayment += payment.amount;
        }
      }

      if (cashPayment > 0) {
        // Cálculo de Vueltas/Cambio
        double change = 0;
        if (totalPaidWithAllMethods > sale.total) {
          change = totalPaidWithAllMethods - sale.total;
        }
        double realCashIn = cashPayment - change;
        if (realCashIn < 0) realCashIn = 0;

        totalCashSales += realCashIn;
      }
    }

    // B. GASTOS (Salidas) - Lógica Blindada
    double totalCashExpenses = 0;
    
    if (canHaveExpenses) {
      // 1. Buscamos gastos creados HOY
      final todayExpensesQuery = await _firestore
          .collection('companies')
          .doc(companyId)
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      // 2. Buscamos gastos PENDIENTES (pueden ser antiguos pagados hoy)
      final pendingExpensesQuery = await _firestore
          .collection('companies')
          .doc(companyId)
          .collection('expenses')
          .where('isPending', isEqualTo: true)
          .get();

      // 3. Unificamos para no procesar doble (Usamos un Map por ID)
      Map<String, Map<String, dynamic>> uniqueExpenses = {};

      for (var doc in todayExpensesQuery.docs) {
        uniqueExpenses[doc.id] = doc.data();
      }
      for (var doc in pendingExpensesQuery.docs) {
        uniqueExpenses[doc.id] = doc.data(); // Si ya existe, se sobrescribe (es el mismo dato)
      }

      // 4. Procesamos cada gasto único
      for (var data in uniqueExpenses.values) {
        final expenseUser = data['userName']?.toString() ?? ''; 
        final initialMethod = data['paymentMethod']?.toString() ?? '';
        final initialAmount = (data['amount'] ?? 0).toDouble();
        final isPending = data['isPending'] ?? false;
        
        // Lista de abonos (Payments)
        final List<dynamic> paymentsList = data['payments'] ?? [];

        // CASO 1: PAGO TOTAL AL CREAR (Gasto de contado)
        // Solo cuenta si: NO es pendiente, NO tiene abonos (es directo), fue HOY, es EFECTIVO y es MI GASTO.
        // Verificamos la fecha del gasto para no sumar viejos "pagados de contado"
        final Timestamp? dateTs = data['date'];
        bool isCreatedToday = false;
        if (dateTs != null) {
          final date = dateTs.toDate();
          isCreatedToday = date.isAfter(startOfDay) && date.isBefore(endOfDay);
        }

        if (isCreatedToday && !isPending && paymentsList.isEmpty) {
          if (expenseUser.toLowerCase() == userName.toLowerCase() && initialMethod == 'Efectivo') {
            totalCashExpenses += initialAmount;
          }
        }

        // CASO 2: ABONOS (Pagos parciales o totales registrados en la lista)
        // Iteramos todos los abonos para buscar los de HOY
        for (var p in paymentsList) {
          final pAmount = (p['amount'] ?? 0).toDouble();
          final pMethod = p['paymentMethod']?.toString() ?? 'Efectivo'; // Default a Efectivo si es antiguo
          final pUser = p['userName']?.toString() ?? ''; // Quien registró el abono
          final Timestamp? pDateTs = p['date'];

          if (pDateTs != null) {
            final pDate = pDateTs.toDate();
            // Filtro: Abono de HOY
            final isPaymentToday = pDate.year == now.year && pDate.month == now.month && pDate.day == now.day;

            if (isPaymentToday && pMethod == 'Efectivo' && pUser.toLowerCase() == userName.toLowerCase()) {
              totalCashExpenses += pAmount;
            }
          }
        }
      }
    }

    return {'sales': totalCashSales, 'expenses': totalCashExpenses};
  }

  // --- 3. PERSISTENCIA BASE (VERSIÓN DEFINITIVA) ---
  
  // Guarda el saldo que el usuario dejó al irse (su nueva base)
  Future<void> saveBaseDraft(String userId, double base) async {
    // Usamos SOLO el ID del usuario. Este documento se sobrescribirá cada vez que cierre caja
    // guardando siempre el último valor que dejó para su próximo turno, sin importar qué día sea.
    final docId = '${userId}_next_base'; 
    
    await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_drafts')
        .doc(docId)
        .set({'base': base, 'lastUpdated': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  // Trae el último saldo que dejó en la caja
  Future<double> getBaseDraft(String userId) async {
    final docId = '${userId}_next_base';
    
    final doc = await _firestore.collection('companies').doc(companyId).collection('cash_drafts').doc(docId).get();
    if (doc.exists) return (doc.data()?['base'] ?? 0).toDouble();
    return 0;
  }

  // --- 4. GUARDAR ARQUEO ---
  Future<void> saveCashCount(CashCountModel count) async {
    await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_closures')
        .doc(count.id)
        .set(count.toMap());
  }

  // --- 5. HISTORIAL ---
  Stream<List<CashCountModel>> getClosureHistory(String userId, bool isAdmin) {
    Query query = _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_closures')
        .orderBy('date', descending: true);

    if (!isAdmin) {
      query = query.where('userId', isEqualTo: userId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>?; 
        if (data == null) return null; 
        return CashCountModel.fromMap(data);
      }).whereType<CashCountModel>().toList(); 
    });
  }

  // --- NUEVO: REABRIR CAJA (A PRUEBA DE ÍNDICES DE FIREBASE) ---
  Future<void> reopenShift(String userId) async {
    final now = DateTime.now();

    // 1. Buscamos TODOS los cierres del usuario (Esto no requiere índice compuesto)
    final query = await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_closures')
        .where('userId', isEqualTo: userId)
        .get();

    // 2. Filtramos "a mano" en la memoria del celular
    for (var doc in query.docs) {
      final data = doc.data();
      final dateTs = data['date'] as Timestamp?;
      
      if (dateTs != null) {
        final docDate = dateTs.toDate();
        // Si el cierre fue hecho exactamente hoy, lo borramos
        if (docDate.year == now.year && docDate.month == now.month && docDate.day == now.day) {
          await doc.reference.delete();
        }
      }
    }
  }

}

final cashRepositoryProvider = Provider<CashRepository>((ref) {
  final companyId = ref.watch(companyIdProvider).value;
  if (companyId == null) throw Exception("Empresa no cargada");
  return CashRepository(FirebaseFirestore.instance, companyId);
});

