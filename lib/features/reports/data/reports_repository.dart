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

    // --- NUEVAS MÉTRICAS ESTRATÉGICAS ---

    // 1. Ticket Promedio y Tamaño de Cesta
    double averageTicket = 0.0;
    double averageBasketSize = 0.0;
    double totalUnitsSold = 0.0;

    for (var sale in sales) {
      for (var item in sale.items) {
        totalUnitsSold += (item['quantity'] as num).toDouble();
      }
    }

    if (sales.isNotEmpty) {
      averageTicket = totalIncome / sales.length;
      averageBasketSize = totalUnitsSold / sales.length;
    }

    // 2. Matriz de Inventario Inteligente y Capital en Bodega
    final stars = <MatrixItem>[];
    final hooks = <MatrixItem>[];
    final opportunities = <MatrixItem>[];
    final deadStock = <MatrixItem>[];
    
    double immobilizedCapital = 0.0;
    double totalInventoryCost = 0.0;

    double avgRotation = 0.0;
    double avgMargin = 0.0;
    int productsWithSales = 0;

    // PASO 1: Sumar total de bodega y calcular promedios de los que sí rotaron
    for (var p in products) {
      if (p.isService) continue;

      // Suma de todo el valor del inventario real en bodega a precio de costo
      if (p.stock > 0 && p.cost > 0) {
        totalInventoryCost += (p.stock * p.cost);
      }

      // Buscamos rotación por nombre o aseguramos comparación limpia
      final rotation = productQtyMap[p.name] ?? 
                       productQtyMap[p.name.trim()] ?? 
                       0.0;

      final marginPercent = p.price > 0 ? ((p.price - p.cost) / p.price) * 100 : 0.0;

      if (rotation > 0) {
        avgRotation += rotation;
        avgMargin += marginPercent;
        productsWithSales++;
      }
    }

    if (productsWithSales > 0) {
      avgRotation /= productsWithSales;
      avgMargin /= productsWithSales;
    }

    // PASO 2: Clasificar a cada producto en su cuadrante correspondiente
    for (var p in products) {
      if (p.isService) continue;

      final rotation = productQtyMap[p.name] ?? 
                       productQtyMap[p.name.trim()] ?? 
                       0.0;

      final marginPercent = p.price > 0 ? ((p.price - p.cost) / p.price) * 100 : 0.0;

      // SOLO es inmovilizado si tiene stock disponible pero 0 ventas en el período
      if (rotation == 0 && p.stock > 0) {
        deadStock.add(MatrixItem(
          name: p.name,
          stock: p.stock,
          margin: marginPercent,
          rotation: rotation,
        ));
        immobilizedCapital += (p.stock * p.cost);
      } else if (rotation > 0) {
        final item = MatrixItem(
          name: p.name,
          stock: p.stock,
          margin: marginPercent,
          rotation: rotation,
        );

        if (rotation >= avgRotation && marginPercent >= avgMargin) {
          stars.add(item);
        } else if (rotation >= avgRotation && marginPercent < avgMargin) {
          hooks.add(item);
        } else if (rotation < avgRotation && marginPercent >= avgMargin) {
          opportunities.add(item);
        } else {
          opportunities.add(item);
        }
      }
    }

    // 3. Horas y Días Pico de Venta
    final dayCounts = <int, int>{}; // 1 = Lunes, 7 = Domingo
    final hourBlocks = <String, int>{}; // 'Mañana' (6-12), 'Tarde' (12-18), 'Noche' (18-24)

    for (var s in sales) {
      final h = s.date.hour;
      final d = s.date.weekday;

      dayCounts.update(d, (v) => v + 1, ifAbsent: () => 1);

      String block = 'Noche'; // 18-5
      if (h >= 6 && h < 12) block = 'Mañana';
      else if (h >= 12 && h < 18) block = 'Tarde';

      hourBlocks.update(block, (v) => v + 1, ifAbsent: () => 1);
    }

    String peakSalesDay = 'N/A';
    if (dayCounts.isNotEmpty) {
      final bestDayIndex = dayCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      peakSalesDay = _getWeekdayName(bestDayIndex);
    }

    String peakSalesHourRange = 'N/A';
    if (hourBlocks.isNotEmpty) {
      peakSalesHourRange = hourBlocks.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }


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

    // Ordenamiento estratégico de cada cuadrante
    stars.sort((a, b) => b.margin.compareTo(a.margin));
    opportunities.sort((a, b) => b.margin.compareTo(a.margin));
    hooks.sort((a, b) => b.rotation.compareTo(a.rotation));
    deadStock.sort((a, b) => b.stock.compareTo(a.stock));
    
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
      averageTicket: averageTicket,
      averageBasketSize: averageBasketSize,
      inventoryMatrix: InventoryMatrix(
        stars: stars,
        hooks: hooks,
        opportunities: opportunities,
        deadStock: deadStock,
      ),
      totalInventoryCost: totalInventoryCost,
      immobilizedCapital: immobilizedCapital,
      peakSalesDay: peakSalesDay,
      peakSalesHourRange: peakSalesHourRange,
    );
  }

  String _getMonthName(int m) => ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][m-1];
  int _getMonthIndex(String m) => ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'].indexOf(m);
  String _getWeekdayName(int d) => ['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'][d-1];
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