import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../domain/report_stats.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Gráfico de barras estilizado (SaaS) para la evolución financiera mensual.
class FinancialBarChart extends StatelessWidget {
  final ReportStats stats;

  const FinancialBarChart({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.monthlyStats.isEmpty) {
      return const Center(child: Text("Sin datos suficientes para graficar", style: TextStyle(color: Colors.grey)));
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _getMaxY(),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
             getTooltipColor: (_) => Colors.black87,

             getTooltipItem: (group, groupIndex, rod, rodIndex) {
               return BarTooltipItem(
                 CurrencyFormatter.format(rod.toY),
                 const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)
               );
             }
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _getMaxY() / 4,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1, dashArray: [5, 5])
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < 0 || value.toInt() >= stats.monthlyStats.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    stats.monthlyStats[value.toInt()].month.substring(0, 3),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)
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
              BarChartRodData(
                toY: e.value.income,
                color: Colors.blueAccent,
                width: 14,
                borderRadius: BorderRadius.circular(4)
              ),
              BarChartRodData(
                toY: e.value.expense,
                color: Colors.redAccent.withOpacity(0.8),
                width: 14,
                borderRadius: BorderRadius.circular(4)
              ),
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
    return max == 0 ? 100 : max * 1.2;
  }
}

/// Gráfico de Dona moderno para Distribución (Métodos de pago, bancos, gastos).
class ModernDonutChart extends StatelessWidget {
  final Map<String, double> data;

  const ModernDonutChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text("Sin datos", style: TextStyle(color: Colors.grey)));

    final total = data.values.fold(0.0, (a, b) => a + b);
    int colorIndex = 0;

    // Paleta SaaS moderna y accesible
    final colors = [
      const Color(0xFF3B82F6), // Blue
      const Color(0xFF10B981), // Emerald
      const Color(0xFFF59E0B), // Amber
      const Color(0xFF8B5CF6), // Violet
      const Color(0xFFEC4899), // Pink
      const Color(0xFF64748B), // Slate
    ];

    return Row(
      children: [
        Expanded(
          flex: 1,
          child: AspectRatio(
            aspectRatio: 1,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2, // Pequeño espacio para estilo anillo moderno
                centerSpaceRadius: 40,
                sections: data.entries.map((e) {
                  final color = colors[colorIndex++ % colors.length];
                  final percentage = (e.value / total) * 100;
                  return PieChartSectionData(
                    color: color,
                    value: e.value,
                    title: percentage > 5 ? '${percentage.toStringAsFixed(0)}%' : '',
                    radius: 30, // Grosor del anillo
                    titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data.entries.toList().asMap().entries.map((e) {
               final color = colors[e.key % colors.length];
               final percentage = (e.value.value / total) * 100;
               return Padding(
                 padding: const EdgeInsets.only(bottom: 8),
                 child: Row(
                   children: [
                     Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                     const SizedBox(width: 8),
                     Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text(e.value.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87), overflow: TextOverflow.ellipsis),
                           Text("${percentage.toStringAsFixed(1)}% (${CurrencyFormatter.format(e.value.value)})", style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                         ],
                       )
                     ),
                   ]
                 ),
               );
            }).toList(),
          ),
        )
      ],
    );
  }
}
