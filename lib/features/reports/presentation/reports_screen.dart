import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/currency_formatter.dart';
import '../data/reports_repository.dart';
import '../domain/report_stats.dart';
import 'report_pdf_generator.dart';
import '../../home/presentation/dashboard_shell.dart';

// Importamos los widgets modulares rediseñados
import 'widgets/kpi_hero_cards.dart';
import 'widgets/actionable_insights.dart';
import 'widgets/financial_charts.dart';
import 'widgets/operational_rankings.dart';
import 'widgets/report_empty_state.dart';

/// Pantalla Principal de Reportes (Business Intelligence Dashboard)
///
/// Arquitectura Visual (SaaS Moderno):
/// Nivel 1: Filtro Temporal & Cabecera (Sticky/Top)
/// Nivel 2: KPIs Estratégicos (KpiHeroGrid) - Salud general del negocio.
/// Nivel 3: Diagnóstico y Recomendaciones (Actionable Insights) - Semáforo de stock y horas pico.
/// Nivel 4: Análisis de Tendencias (Gráficos) - Barras y Donas.
/// Nivel 5: Ranking y Desglose Operativo - Top productos, clientes y rendimiento.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    final reportAsync = ref.watch(reportStatsProvider(_selectedRange));
    
    const backgroundColor = Color(0xFFF8FAFC); // Slate 50 (SaaS style)

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        leading: isMobile ? IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => DashboardShell.scaffoldKey.currentState?.openDrawer(),
        ) : null,
        title: const Text('Inteligencia de Negocio', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          reportAsync.maybeWhen(
            data: (stats) => IconButton(
              tooltip: "Exportar Reporte (PDF)",
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
              onPressed: () => ReportPdfGenerator.generateFullReport(stats, _selectedRange),
            ),
            orElse: () => const SizedBox.shrink(),
          )
        ],
      ),
      body: reportAsync.when(
        data: (stats) {
          if (stats.totalIncome == 0 && stats.totalExpenses == 0 && stats.topProductsByQty.isEmpty) {
             return Column(
               children: [
                 _DateRangeHeader(range: _selectedRange, onTap: _pickDateRange),
                 const Expanded(child: ReportEmptyState()),
               ],
             );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- NIVEL 1: FILTRO TEMPORAL ---
                _DateRangeHeader(range: _selectedRange, onTap: _pickDateRange),
                const SizedBox(height: 24),

                // --- NIVEL 2: MÉTRICAS CLAVE (HERO) ---
                KpiHeroGrid(
                  totalIncome: stats.totalIncome,
                  totalProfit: stats.totalProfit,
                  averageTicket: stats.averageTicket,
                  immobilizedCapital: stats.immobilizedCapital,
                ),
                const SizedBox(height: 32),

                // --- SECCIÓN ALERTAS DE STOCK ---
                if (stats.lowStockAlerts.isNotEmpty)
                  _AlertSection(alerts: stats.lowStockAlerts),

                // --- NIVEL 3: DIAGNÓSTICO Y RECOMENDACIONES ---
                _SectionTitle(title: "Diagnóstico Estratégico", icon: Icons.insights),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 800;
                  final peakDayWidget = InsightActionCard(
                    icon: Icons.access_time_filled,
                    color: Colors.orange.shade700,
                    title: "Mapa de Oportunidad",
                    value: stats.peakSalesDay,
                    insight: "Tu hora pico de ventas es en la ${stats.peakSalesHourRange}. Asegura cobertura de personal y stock en este bloque.",
                  );
                  final basketWidget = InsightActionCard(
                    icon: Icons.shopping_basket_rounded,
                    color: Colors.purple.shade700,
                    title: "Tamaño de Cesta",
                    value: "${stats.averageBasketSize.toStringAsFixed(1)} Unds",
                    insight: "En promedio compran ${stats.averageBasketSize.toStringAsFixed(1)} artículos por factura. Ofrece combos para subir a ${(stats.averageBasketSize + 1).toInt()}.",
                  );

                  return isWide
                    ? Row(children: [Expanded(child: peakDayWidget), const SizedBox(width: 16), Expanded(child: basketWidget)])
                    : Column(children: [peakDayWidget, const SizedBox(height: 16), basketWidget]);
                }),
                const SizedBox(height: 16),

                // Matriz de Inventario
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade100),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Matriz de Inventario Inteligente", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      const Text("Clasificación automática cruzando margen de ganancia y volumen de rotación.", style: TextStyle(fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 20),
                      InventoryQuadrantSection(matrix: stats.inventoryMatrix),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // --- NIVEL 4: TENDENCIAS Y COMPORTAMIENTO FINANCIERO ---
                _SectionTitle(title: "Tendencias Financieras", icon: Icons.trending_up),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    bool isWide = constraints.maxWidth > 900;

                    final barChart = _DashboardCard(
                      title: "Evolución Ingresos vs Gastos",
                      child: SizedBox(height: 250, child: FinancialBarChart(stats: stats)),
                    );

                    final donutChart = _DashboardCard(
                      title: "Distribución por Medio de Pago",
                      child: SizedBox(height: 200, child: ModernDonutChart(data: stats.incomeByMethod)),
                    );

                    return isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: barChart),
                            const SizedBox(width: 24),
                            Expanded(flex: 2, child: donutChart),
                          ]
                        )
                      : Column(
                          children: [barChart, const SizedBox(height: 24), donutChart],
                        );
                  },
                ),

                const SizedBox(height: 32),

                // --- NIVEL 5: RANKINGS Y OPERACIÓN ---
                _SectionTitle(title: "Rendimiento Operativo", icon: Icons.workspace_premium),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    bool isWide = constraints.maxWidth > 900;

                    final rankings = _DashboardCard(
                      title: "Top 5 Líderes",
                      child: Column(
                        children: [
                          TopRankingList(title: "Mayor Facturación", items: stats.topProductsByRevenue.take(5).toList(), icon: Icons.monetization_on, isCurrency: true, accentColor: Colors.blue),
                          const Divider(height: 30),
                          TopRankingList(title: "Mayor Rotación (Volumen)", items: stats.topProductsByQty.take(5).toList(), icon: Icons.inventory_2, isCurrency: false, accentColor: Colors.teal),
                        ],
                      ),
                    );

                    final team = _DashboardCard(
                      title: "Rendimiento del Equipo",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowHeight: 40,
                              columnSpacing: 20,
                              columns: const [
                                DataColumn(label: Text('Usuario', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Ventas', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Comisión', style: TextStyle(fontWeight: FontWeight.bold)))
                              ],
                              rows: stats.userStats.map((u) => DataRow(cells: [
                                DataCell(Text(u.userName)),
                                DataCell(Text(CurrencyFormatter.format(u.totalSales), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600))),
                                DataCell(Text(CurrencyFormatter.format(u.commissions))),
                              ])).toList(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text("Distribución de Gastos", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 16),
                          SizedBox(height: 200, child: ModernDonutChart(data: stats.expensesByCategory)),
                        ],
                      )
                    );

                    return isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: rankings),
                            const SizedBox(width: 24),
                            Expanded(child: team),
                          ]
                        )
                      : Column(children: [rankings, const SizedBox(height: 24), team]);
                  }
                ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Ocurrió un error al cargar: $e')),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedRange,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedRange = picked);
  }
}

// ==========================================
// WIDGETS AUXILIARES
// ==========================================

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey, size: 22),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _DateRangeHeader extends StatelessWidget {
  final DateTimeRange range;
  final VoidCallback onTap;

  const _DateRangeHeader({required this.range, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd MMM, yyyy', 'es_ES');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month_outlined, color: Colors.blueAccent, size: 20),
            const SizedBox(width: 12),
            Text(
              "${format.format(range.start)}  -  ${format.format(range.end)}",
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _DashboardCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _AlertSection extends StatelessWidget {
  final List<ProductAlert> alerts;
  const _AlertSection({required this.alerts});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border(left: BorderSide(color: Colors.red.shade400, width: 4)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Atención Requerida", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                    Text("${alerts.length} productos con bajo stock", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: alerts.length > 5 ? 5 : alerts.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(alert.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: alert.stock == 0 ? Colors.red : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    alert.stock == 0 ? "AGOTADO" : "${alert.stock} Und",
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: FontWeight.bold,
                      color: alert.stock == 0 ? Colors.white : Colors.orange.shade800
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
