import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../inventory/domain/product_model.dart';
import '../../sales/domain/sale_model.dart';
import '../../expenses/domain/expense_model.dart';
import '../domain/report_stats.dart';

class ReportsRepository {
  final FirebaseFirestore _firestore;
  final String userId;

  ReportsRepository(this._firestore, this.userId);

  Future<ReportStats> generateReport(DateTimeRange range) async {
    // 1. VENTAS (Filtradas por fecha)
    final salesSnap = await _firestore.collection('companies').doc(userId).collection('sales')
        .where('date', isGreaterThanOrEqualTo: range.start)
        .where('date', isLessThanOrEqualTo: range.end.add(const Duration(days: 1)))
        .get();

    // 2. GASTOS (Filtrados por fecha)
    final expensesSnap = await _firestore.collection('companies').doc(userId).collection('expenses')
        .where('date', isGreaterThanOrEqualTo: range.start)
        .where('date', isLessThanOrEqualTo: range.end.add(const Duration(days: 1)))
        .get();

    // 3. INVENTARIO (Completo para alertas)
    final productsSnap = await _firestore.collection('companies').doc(userId).collection('products').get();

    final sales = salesSnap.docs.map((d) => Sale.fromMap(d.data(), d.id)).toList();
    final expenses = expensesSnap.docs.map((d) => Expense.fromMap(d.data(), d.id)).toList();
    final products = productsSnap.docs.map((d) => Product.fromMap(d.data(), d.id)).toList();

    // (1) TOTALES
    double totalIncome = sales.fold(0, (sum, s) => sum + s.total);
    double totalExpenses = expenses.fold(0, (sum, e) => sum + e.amount);
    
    // VARIABLES PARA ACUMULAR DATOS
    final incomeByMethod = <String, double>{};
    final incomeByBank = <String, double>{}; 
    final userSalesMap = <String, double>{};
    final userCommissionsMap = <String, double>{}; // <--- NUEVO MAPA PARA COMISIONES REALES
    
    final productQtyMap = <String, double>{};
    final productRevMap = <String, double>{};
    final clientMap = <String, double>{};

    // --- BUCLE PRINCIPAL DE VENTAS ---
    for (var sale in sales) {
      
      // 1. Pagos y Bancos
      for (var payment in sale.initialPayments) {
        incomeByMethod.update(payment.method, (v) => v + payment.amount, ifAbsent: () => payment.amount);

        if (payment.method == 'Transferencia' && payment.bankName != null) {
          incomeByBank.update(payment.bankName!, (v) => v + payment.amount, ifAbsent: () => payment.amount);
        }
      }  

      // 2. Ventas por Vendedor
      final seller = sale.sellerName ?? 'Desconocido';
      userSalesMap.update(seller, (v) => v + sale.total, ifAbsent: () => sale.total);

      // 3. Top Clientes
      final client = sale.clientName ?? 'Mostrador';
      clientMap.update(client, (v) => v + sale.total, ifAbsent: () => sale.total);

      // 4. Productos y Comisiones
      for (var item in sale.items) {
        final pName = item['name'] as String;
        final qty = (item['quantity'] as num).toDouble();
        final total = (item['total'] as num).toDouble();
        
        // Acumular Top Productos
        productQtyMap.update(pName, (v) => v + qty, ifAbsent: () => qty);
        productRevMap.update(pName, (v) => v + total, ifAbsent: () => total);

        // --- CÁLCULO DE COMISIÓN CORREGIDO ---
        // Sumamos el valor real guardado en la venta
        double itemCommission = 0.0;
        if (item.containsKey('commission')) {
          itemCommission = (item['commission'] as num).toDouble();
        }

        // Acumulamos la comisión al vendedor correspondiente
        userCommissionsMap.update(seller, (v) => v + itemCommission, ifAbsent: () => itemCommission);
      }
    }

    // 6. Gastos por Categoría
    final expenseMap = <String, double>{};
    for (var expense in expenses) {
      expenseMap.update(expense.category, (v) => v + expense.amount, ifAbsent: () => expense.amount);
    }

    // 7. Alerta Inventario (CORREGIDO)
    // Filtramos para que SOLO los productos físicos entren en alerta
    final alerts = products
        .where((p) => !p.isService && p.stock <= p.minStock) // <--- AQUÍ ESTÁ EL CAMBIO
        .map((p) => ProductAlert(p.name, p.stock))
        .toList();
        
    // Ordenamientos
    final topQty = productQtyMap.entries.map((e) => TopItem(e.key, e.value)).toList()..sort((a, b) => b.value.compareTo(a.value));
    final topRev = productRevMap.entries.map((e) => TopItem(e.key, e.value)).toList()..sort((a, b) => b.value.compareTo(a.value));
    final topCli = clientMap.entries.map((e) => TopItem(e.key, e.value)).toList()..sort((a, b) => b.value.compareTo(a.value));

    // 5. Estructura de Usuarios con Comisión REAL
    final userStatsList = userSalesMap.entries.map((e) {
      final sellerName = e.key;
      final totalSold = e.value;
      // Buscamos la comisión real acumulada, si no existe es 0
      final totalCommission = userCommissionsMap[sellerName] ?? 0.0; 
      
      return UserStat(sellerName, totalSold, totalCommission);
    }).toList();

    // 11. Resumen Anual (Mes a Mes)
    final monthlyData = <int, MonthlyStat>{}; 
    for (var s in sales) {
      final m = s.date.month;
      if (!monthlyData.containsKey(m)) monthlyData[m] = MonthlyStat(_getMonthName(m), 0, 0);
      monthlyData[m] = MonthlyStat(monthlyData[m]!.month, monthlyData[m]!.income + s.total, monthlyData[m]!.expense);
    }
    for (var e in expenses) {
      final m = e.date.month;
      if (!monthlyData.containsKey(m)) monthlyData[m] = MonthlyStat(_getMonthName(m), 0, 0);
      monthlyData[m] = MonthlyStat(monthlyData[m]!.month, monthlyData[m]!.income, monthlyData[m]!.expense + e.amount);
    }
    final monthlyStatsList = monthlyData.values.toList()..sort((a,b) => _getMonthIndex(a.month).compareTo(_getMonthIndex(b.month)));

    return ReportStats(
      totalIncome: totalIncome,
      totalExpenses: totalExpenses,
      totalProfit: totalIncome - totalExpenses,
      incomeByMethod: incomeByMethod,
      incomeByBank: incomeByBank,
      expensesByCategory: expenseMap,
      topProductsByQty: topQty,
      topProductsByRevenue: topRev,
      topClients: topCli,
      userStats: userStatsList, // Ahora envía comisiones reales
      lowStockAlerts: alerts,
      monthlyStats: monthlyStatsList,
    );
  }

  String _getMonthName(int m) => ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][m-1];
  int _getMonthIndex(String m) => ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'].indexOf(m);
}

// ... providers igual ...

// PROVIDER
final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) throw Exception('No autenticado');
  return ReportsRepository(FirebaseFirestore.instance, user.uid);
});

final reportStatsProvider = FutureProvider.family<ReportStats, DateTimeRange>((ref, range) {
  return ref.watch(reportsRepositoryProvider).generateReport(range);
});