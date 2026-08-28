import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sales/data/sales_repository.dart'; 
import '../../expenses/presentation/expense_providers.dart'; 
import '../../inventory/presentation/inventory_providers.dart';


class DashboardStats {
  final double salesToday;
  final double salesMonth;
  final double accountsReceivable; // Por cobrar
  final double accountsPayable;    // Por pagar
  final int lowStockCount;         // Alertas
  
  // --- NUEVO: Datos para el gráfico ---
  final List<Map<String, dynamic>> weeklySales;

  DashboardStats({
    required this.salesToday,
    required this.salesMonth,
    required this.accountsReceivable,
    required this.accountsPayable,
    required this.lowStockCount,
    required this.weeklySales, // Nuevo campo
  });
}

final dashboardStreamProvider = StreamProvider<DashboardStats>((ref) {
  final salesStream = ref.watch(salesRepositoryProvider).getSales();
  final expensesStream = ref.watch(expenseRepositoryProvider).getExpenses();
  final productsStream = ref.watch(inventoryRepositoryProvider).getProducts(); 

  return salesStream.asyncMap((sales) async {
    final expenses = await expensesStream.first;
    final products = await productsStream.first; 

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    
    // Preparar el arreglo para los últimos 7 días
    List<double> dailyAmounts = List.filled(7, 0.0);
    List<DateTime> dailyDates = List.generate(7, (index) => todayStart.subtract(Duration(days: 6 - index)));

    // --- A. Cálculos de Ventas ---
    double today = 0;
    double month = 0;
    double receivable = 0;

    for (var s in sales) {
      final saleDateStart = DateTime(s.date.year, s.date.month, s.date.day);

      // Hoy
      if (saleDateStart.isAtSameMomentAs(todayStart)) {
        today += s.total;
      }
      // Este Mes
      if (s.date.month == now.month && s.date.year == now.year) {
        month += s.total;
      }
      // Por Cobrar (Cartera)
      if (s.balance > 0.5) { 
        receivable += s.balance;
      }

      // --- NUEVO: Lógica Semanal (Gráfico) ---
      final differenceInDays = todayStart.difference(saleDateStart).inDays;
      if (differenceInDays >= 0 && differenceInDays < 7) {
        // index 6 = hoy, index 0 = hace 6 días
        final index = 6 - differenceInDays; 
        dailyAmounts[index] += s.total;
      }
    }

    // Calcular proporciones para las barras (0.0 a 1.0)
    double maxAmount = 0.0;
    for (var amt in dailyAmounts) {
      if (amt > maxAmount) maxAmount = amt;
    }

    const dayNames = {1: 'L', 2: 'M', 3: 'X', 4: 'J', 5: 'V', 6: 'S', 7: 'D'};
    List<Map<String, dynamic>> finalWeeklySales = [];

    for (int i = 0; i < 7; i++) {
      double amt = dailyAmounts[i];
      // Escalar al 100% de la barra más alta
      double val = maxAmount > 0 ? amt / maxAmount : 0.0; 
      
      finalWeeklySales.add({
        'day': dayNames[dailyDates[i].weekday] ?? '',
        'amount': amt,
        'value': val,
        'isToday': i == 6, // Identifica fácil cuál es el día actual
      });
    }

    // --- B. Cálculos de Gastos ---
    double payable = 0;
    for (var e in expenses) {
      if (e.isPending && !e.isFullyPaid) {
        payable += e.balance;
      }
    }

    // --- C. Cálculos de Inventario ---
    final lowStock = products.where((p) {
      if (p.isService) return false;
      return p.stock <= p.minStock;
    }).length;
    
    // Retornar objeto con datos reales
    return DashboardStats(
      salesToday: today,
      salesMonth: month,
      accountsReceivable: receivable,
      accountsPayable: payable,
      lowStockCount: lowStock, 
      weeklySales: finalWeeklySales, // <--- Pasamos los datos al UI
    );
  });
});