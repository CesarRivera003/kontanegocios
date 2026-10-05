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
  
  // Nuevas Métricas Estratégicas
  final double averageTicket;
  final double averageBasketSize;
  final InventoryMatrix inventoryMatrix;
  final double totalInventoryCost;
  final double immobilizedCapital;
  final String peakSalesDay;
  final String peakSalesHourRange;

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
    this.averageTicket = 0.0,
    this.averageBasketSize = 0.0,
    required this.inventoryMatrix,
    this.totalInventoryCost = 0.0,
    this.immobilizedCapital = 0.0,
    this.peakSalesDay = '',
    this.peakSalesHourRange = '',
  });
}

// Nuevas clases para Inventario Inteligente
class InventoryMatrix {
  final List<MatrixItem> stars; // Alta rotación, alto margen
  final List<MatrixItem> hooks; // Alta rotación, bajo margen
  final List<MatrixItem> opportunities; // Baja rotación, alto margen
  final List<MatrixItem> deadStock; // Cero rotación, con stock

  InventoryMatrix({
    required this.stars,
    required this.hooks,
    required this.opportunities,
    required this.deadStock,
  });
}

class MatrixItem {
  final String name;
  final int stock;
  final double margin;
  final double rotation;

  MatrixItem({
    required this.name,
    required this.stock,
    required this.margin,
    required this.rotation,
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