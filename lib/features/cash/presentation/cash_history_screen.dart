import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/currency_formatter.dart';
import 'cash_providers.dart';
import '../domain/cash_count_model.dart';

class CashHistoryScreen extends ConsumerWidget {
  const CashHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Leemos el historial del proveedor
    final historyAsync = ref.watch(cashHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Historial de Cierres'),
        elevation: 0,
      ),
      // Manejamos los estados de carga, error y datos
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text("Error al cargar: $e")),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text("No hay cierres registrados.", style: TextStyle(color: Colors.grey)),
            );
          }

          // USAMOS UNA LISTA SIMPLE (Sin ExpansionTile para evitar errores de GlobalKey)
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = list[index];
              return _HistoryCard(item: item);
            },
          );
        },
      ),
    );
  }
}

// Tarjeta visual simple para la lista
class _HistoryCard extends StatelessWidget {
  final CashCountModel item;
  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final bool isBalanced = item.difference == 0;
    final bool isSurplus = item.difference > 0;
    
    // Colores según estado
    final Color color = isBalanced ? Colors.green : (isSurplus ? Colors.blue : Colors.red);
    final IconData icon = isBalanced ? Icons.check_circle : (isSurplus ? Icons.trending_up : Icons.trending_down);
    final String statusText = isBalanced ? "Cuadrado" : (isSurplus ? "Sobra" : "Falta");

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // AL TOCAR: Abrimos el detalle en una ventana modal segura
        onTap: () => _showDetailModal(context, item, color),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('dd/MM/yyyy - hh:mm a').format(item.date),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      "Cajero: ${item.userName}",
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(item.realBalance),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    statusText,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  // Ventana modal con los detalles (Reemplaza al ExpansionTile)
  void _showDetailModal(BuildContext context, CashCountModel item, Color color) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, color: Colors.grey[300]),
            const SizedBox(height: 20),
            Text("Detalle del Cierre", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            _DetailRow("Base Inicial", item.baseAmount),
            _DetailRow("Entradas / Provisiones", item.provisions, color: Colors.blue),
            _DetailRow("Ventas Efectivo", item.cashSales, color: Colors.green),
            _DetailRow("Salidas", item.cashExpenses, color: Colors.red),
            if (item.movementsDetail.isNotEmpty) ...[
              const SizedBox(height: 15),
              const Text("Detalle de Movimientos Manuales:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 5),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Column(
                  children: item.movementsDetail.map((d) {
                    final isInc = d['type'] == 'income';
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(isInc ? Icons.arrow_downward : Icons.arrow_upward, size: 14, color: isInc ? Colors.green : Colors.red),
                      title: Text(d['description'] ?? '', style: const TextStyle(fontSize: 12)),
                      trailing: Text(CurrencyFormatter.format((d['amount'] ?? 0).toDouble()), style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 15),
            ],
            const Divider(height: 30),
            _DetailRow("Esperado", item.theoreticalBalance, isBold: true),
            _DetailRow("Real (Contado)", item.realBalance, isBold: true, scale: 1.2),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Diferencia", style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                  Text(CurrencyFormatter.format(item.difference), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;
  final Color? color;
  final double scale;
  const _DetailRow(this.label, this.value, {this.isBold = false, this.color, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14 * scale, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(CurrencyFormatter.format(value), style: TextStyle(fontSize: 14 * scale, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
        ],
      ),
    );
  }
}