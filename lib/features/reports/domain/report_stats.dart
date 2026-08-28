class ReportStats {
  final double totalIncome;
  final double totalExpenses;
  final double totalProfit;
  
  // Mapas para gráficos
  final Map<String, double> incomeByMethod; // Ej: {'Efectivo': 1000, 'Nequi': 500}
  final Map<String, double> incomeByBank;   // Ej: {'Bancolombia': 2000}
  final Map<String, double> expensesByCategory;
  
  // Listas Top
  final List<TopItem> topProductsByQty;
  final List<TopItem> topProductsByRevenue;
  final List<TopItem> topClients;
  
  // Gestión
  final List<UserStat> userStats; // Ventas y comisiones por usuario
  final List<ProductAlert> lowStockAlerts;
  
  // Gráfico Anual (Mes a Mes)
  final List<MonthlyStat> monthlyStats;

  ReportStats({
    required this.totalIncome,
    required this.totalExpenses,
    required this.totalProfit,
    required this.incomeByMethod,
    required this.incomeByBank,
    required this.expensesByCategory,
    required this.topProductsByQty,
    required this.topProductsByRevenue,
    required this.topClients,
    required this.userStats,
    required this.lowStockAlerts,
    required this.monthlyStats,
  });
}

// Clases auxiliares
class TopItem {
  final String name;
  final double value; // Puede ser cantidad o dinero
  final String? subtitle;
  TopItem(this.name, this.value, {this.subtitle});
}

class UserStat {
  final String userName;
  final double totalSales;
  final double commissions;
  UserStat(this.userName, this.totalSales, this.commissions);
}

class ProductAlert {
  final String name;
  final int stock;
  ProductAlert(this.name, this.stock);
}

class MonthlyStat {
  final String month; // Ene, Feb...
  final double income;
  final double expense;
  MonthlyStat(this.month, this.income, this.expense);
}