import 'package:flutter/material.dart';
import '../../domain/report_stats.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Lista de ranking (Top N) estilizada con barras de progreso relativas
class TopRankingList extends StatelessWidget {
  final String title;
  final List<TopItem> items;
  final IconData icon;
  final bool isCurrency;
  final Color accentColor;

  const TopRankingList({
    super.key,
    required this.title,
    required this.items,
    required this.icon,
    this.isCurrency = true,
    this.accentColor = Colors.blueAccent,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    // Encontramos el valor máximo para calcular la proporción de la barra
    final maxValue = items.isEmpty ? 1.0 : items.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
          ],
        ),
        const SizedBox(height: 16),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final fillPercentage = maxValue > 0 ? (item.value / maxValue) : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                // Número de ranking
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index < 3 ? accentColor.withOpacity(0.15) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6)
                  ),
                  child: Text(
                    "${index + 1}",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: index < 3 ? accentColor : Colors.grey.shade600
                    )
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            isCurrency ? CurrencyFormatter.format(item.value) : item.value.toInt().toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Barra relativa sutil
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: fillPercentage,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(index < 3 ? accentColor : Colors.grey.shade400),
                          minHeight: 4,
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
