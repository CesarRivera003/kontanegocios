import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/currency_formatter.dart'; // Asegúrate de que esta ruta sea correcta
import '../data/reports_repository.dart';
import '../domain/report_stats.dart';
import 'report_pdf_generator.dart';
import '../../home/presentation/dashboard_shell.dart';

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
    
    // Color de fondo suave para que resalten las tarjetas blancas
    const backgroundColor = Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        leading: isMobile ?IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            // Usamos el "Control Remoto" para abrir el menú principal
            DashboardShell.scaffoldKey.currentState?.openDrawer();
          },
        ): null,
        title: const Text('Tablero de Control', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          // Botón PDF minimalista
          reportAsync.maybeWhen(
            data: (stats) => IconButton(
              tooltip: "Descargar PDF",
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
              onPressed: () => ReportPdfGenerator.generateFullReport(stats, _selectedRange),
            ),
            orElse: () => const SizedBox.shrink(),
          )
        ],
      ),
      body: reportAsync.when(
        data: (stats) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER: FECHAS ---
              _DateRangeHeader(
                range: _selectedRange,
                onTap: _pickDateRange,
              ),
              const SizedBox(height: 20),

              // --- SECCIÓN 1: KPIS PRINCIPALES ---
              Row(
                children: [
                  Expanded(child: _KpiCard(title: "Ingresos", amount: stats.totalIncome, color: Colors.green, icon: Icons.arrow_upward)),
                  const SizedBox(width: 12),
                  Expanded(child: _KpiCard(title: "Gastos", amount: stats.totalExpenses, color: Colors.redAccent, icon: Icons.arrow_downward)),
                ],
              ),
              const SizedBox(height: 12),
              _KpiCard(
                title: "Rentabilidad Neta", 
                amount: stats.totalProfit, 
                color: stats.totalProfit >= 0 ? Colors.blueAccent : Colors.orange, 
                icon: Icons.account_balance_wallet,
                isWide: true
              ),

              const SizedBox(height: 20),

              // --- SECCIÓN 2: ALERTAS (Solo si existen) ---
              if (stats.lowStockAlerts.isNotEmpty)
                _AlertSection(alerts: stats.lowStockAlerts),

              // --- SECCIÓN 3: GRÁFICO DE EVOLUCIÓN ---
              DashboardCard(
                title: "Evolución Financiera",
                subtitle: "Comparativa mensual de ingresos vs gastos",
                child: SizedBox(height: 250, child: _BarChartWidget(stats: stats)),
              ),

              // --- SECCIÓN 4: MEDIOS DE PAGO Y BANCOS (CORREGIDO) ---
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, 
                children: [
                  
                  // --- A. TARJETA DE GRÁFICO TORTA ---
                  DashboardCard(
                    title: "Métodos de Pago",
                    child: SizedBox(
                      height: 220, 
                      child: _PieChartWidget(data: stats.incomeByMethod),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- B. TARJETA DE BANCOS (ANIMADA) ---
                  if (stats.incomeByBank.isNotEmpty)
                    DashboardCard(
                      title: "Ingresos por Banco",
                      child: Column(
                        children: stats.incomeByBank.entries.map((e) {
                          // CORRECCIÓN: Calculamos el total aquí dentro para evitar el error
                          final double totalBanks = stats.incomeByBank.values.fold(0.0, (sum, item) => sum + item);
                          final double percentage = totalBanks == 0 ? 0.0 : (e.value / totalBanks);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Fila: Nombre del Banco y Valor
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.account_balance, size: 16, color: Colors.blue),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    Text(
                                      CurrencyFormatter.format(e.value),
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                // BARRA ANIMADA
                                TweenAnimationBuilder<double>(
                                  duration: const Duration(seconds: 1),
                                  curve: Curves.easeOutExpo,
                                  tween: Tween<double>(begin: 0, end: percentage),
                                  builder: (context, value, _) {
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: value,
                                        backgroundColor: Colors.grey[200],
                                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent), 
                                        minHeight: 8,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
              // --- SECCIÓN 5: TOP LISTS (Clientes y Productos) ---
              // Usamos PageView o Tabs si son muchos, o columnas si es desktop. Aquí Columnas.
              DashboardCard(
                title: "Top Rendimiento",
                child: Column(
                  children: [
                    _RankingSection(title: "Mejores Clientes", items: stats.topClients.take(5).toList(), icon: Icons.person),
                    const Divider(height: 30),
                    _RankingSection(title: "Productos Más Vendidos", items: stats.topProductsByQty.take(5).toList(), icon: Icons.inventory_2, isCurrency: false),
                    // [NUEVO] Productos por Ingresos (Valor)
                    _RankingSection(
                      title: "Líderes en Facturación",  // Nombre profesional
                      items: stats.topProductsByRevenue.take(5).toList(), 
                      icon: Icons.monetization_on, 
                      isCurrency: true
                    ),
                  ],
                ),
              ),

              // --- SECCIÓN 6: EQUIPO Y GASTOS ---
              DashboardCard(
                title: "Desglose Operativo",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Rendimiento de Equipo", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 10),
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
                          DataCell(Text(CurrencyFormatter.format(u.totalSales), style: const TextStyle(color: Colors.green))),
                          DataCell(Text(CurrencyFormatter.format(u.commissions))),
                        ])).toList(),
                      ),
                    ),
                    // [NUEVO] GRÁFICO DE GASTOS POR CATEGORÍA
                    const Text("Distribución de Gastos", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200, // Altura para el gráfico
                      child: _PieChartWidget(data: stats.expensesByCategory), // Reutilizamos el widget de torta
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Ocurrió un error: $e')),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.blueAccent),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedRange = picked);
  }
}

// ==========================================
// WIDGETS DE DISEÑO (ESTILO PROFESIONAL)
// ==========================================

// HEADER DE FECHA (Estilo Pill)
class _DateRangeHeader extends StatelessWidget {
  final DateTimeRange range;
  final VoidCallback onTap;

  const _DateRangeHeader({required this.range, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 16, color: Colors.blueGrey),
            const SizedBox(width: 10),
            Text(
              '${DateFormat('dd/MM/yyyy').format(range.start)}  -  ${DateFormat('dd/MM/yyyy',).format(range.end)}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.blueGrey),
          ],
        ),
      ),
    );
  }
}

// TARJETA CONTENEDORA GENÉRICA (Base del diseño)
class DashboardCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const DashboardCard({super.key, required this.title, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
          if (subtitle != null) ...[
             const SizedBox(height: 4),
             Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

// TARJETA KPI (Ingresos/Gastos)
class _KpiCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;
  final bool isWide;

  const _KpiCard({required this.title, required this.amount, required this.color, required this.icon, this.isWide = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isWide ? double.infinity : null,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 5))],
        border: Border.all(color: color.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w600, fontSize: 13)),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            CurrencyFormatter.format(amount),
            style: TextStyle(fontSize: isWide ? 26 : 22, fontWeight: FontWeight.w800, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

// SECCIÓN DE ALERTAS DE STOCK
class _AlertSection extends StatelessWidget {
  final List<ProductAlert> alerts;
  const _AlertSection({required this.alerts});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      // Diseño limpio: Fondo blanco, sombra suave y borde lateral rojo
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border(
          left: BorderSide(color: Colors.red.shade400, width: 4), // Línea de acento
        ),
      ),
      child: Column(
        children: [
          // CABECERA
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Atención Requerida",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                    ),
                    Text(
                      "${alerts.length} productos con bajo stock",
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),

          // LISTA DE PRODUCTOS (Reemplazamos los Chips por una lista limpia)
          ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 5),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: alerts.length > 5 ? 5 : alerts.length, // Mostramos máx 5 para no saturar
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 20, endIndent: 20),
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(alert.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
          
          // BOTÓN "VER TODOS" (Opcional, si hay muchos)
          if (alerts.length > 5)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton(
                onPressed: () {
                  // Acción para ver todo el inventario filtrado (opcional)
                  // context.push('/inventory'); 
                },
                child: const Text("Ver todos las alertas", style: TextStyle(fontSize: 12)),
              ),
            )
        ],
      ),
    );
  }
}

// LISTA DE TOP (Clientes/Productos)
class _RankingSection extends StatelessWidget {
  final String title;
  final List<TopItem> items;
  final IconData icon;
  final bool isCurrency;

  const _RankingSection({required this.title, required this.items, required this.icon, this.isCurrency = true});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.blueGrey),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.blueGrey)),
          ],
        ),
        const SizedBox(height: 12),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                // Número de ranking
                Container(
                  width: 24, 
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index < 3 ? const Color(0xFFFFD700).withOpacity(0.2) : Colors.grey[100],
                    shape: BoxShape.circle
                  ),
                  child: Text("${index + 1}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: index < 3 ? Colors.orange[800] : Colors.grey)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w500))),
                Text(
                  isCurrency ? CurrencyFormatter.format(item.value) : item.value.toInt().toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// FILA ESTADÍSTICA COMPACTA (Para bancos/categorías)
class _StatRowCompact extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatRowCompact({required this.label, required this.value, this.color = Colors.black87});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ==========================================
// GRÁFICOS (MEJORADOS)
// ==========================================

class _BarChartWidget extends StatelessWidget {
  final ReportStats stats;
  const _BarChartWidget({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.monthlyStats.isEmpty) return const Center(child: Text("Sin datos suficientes"));
    
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _getMaxY(),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
             getTooltipColor: (_) => Colors.blueGrey,
             getTooltipItem: (group, groupIndex, rod, rodIndex) {
               return BarTooltipItem(
                 CurrencyFormatter.format(rod.toY),
                 const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
               );
             }
          ),
        ),
        gridData: FlGridData(
          show: true, 
          drawVerticalLine: false, 
          horizontalInterval: _getMaxY() / 5,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey[200], strokeWidth: 1)
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Limpio, sin números laterales
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < 0 || value.toInt() >= stats.monthlyStats.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    stats.monthlyStats[value.toInt()].month.substring(0, 3), 
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: stats.monthlyStats.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(toY: e.value.income, color: const Color(0xFF4CAF50), width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              BarChartRodData(toY: e.value.expense, color: const Color(0xFFEF5350), width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
            ],
          );
        }).toList(),
      ),
    );
  }

  double _getMaxY() {
    double max = 0;
    for (var m in stats.monthlyStats) {
      if (m.income > max) max = m.income;
      if (m.expense > max) max = m.expense;
    }
    return max == 0 ? 100 : max * 1.1; 
  }
}

class _PieChartWidget extends StatelessWidget {
  final Map<String, double> data;
  const _PieChartWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text("Sin datos"));

    final total = data.values.fold(0.0, (a, b) => a + b);
    int colorIndex = 0;
    // Paleta de colores profesional
    final colors = [
      const Color(0xFF5C6BC0), // Indigo
      const Color(0xFF26A69A), // Teal
      const Color(0xFFFFA726), // Orange
      const Color(0xFFEC407A), // Pink
      const Color(0xFF78909C), // Blue Grey
    ];

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sectionsSpace: 0,
              centerSpaceRadius: 30,
              sections: data.entries.map((e) {
                final color = colors[colorIndex++ % colors.length];
                final percentage = (e.value / total) * 100;
                return PieChartSectionData(
                  color: color,
                  value: e.value,
                  title: percentage > 10 ? '${percentage.toStringAsFixed(0)}%' : '',
                  radius: 45,
                  titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data.entries.toList().asMap().entries.map((e) {
               final color = colors[e.key % colors.length];
               return Padding(
                 padding: const EdgeInsets.only(bottom: 4),
                 child: Row(children: [
                   Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                   const SizedBox(width: 6),
                   Expanded(child: Text(e.value.key, style: const TextStyle(fontSize: 11, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                 ]),
               );
            }).toList(),
          ),
        )
      ],
    );
  }
}