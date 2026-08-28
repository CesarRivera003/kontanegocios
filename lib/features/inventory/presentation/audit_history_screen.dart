import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../domain/audit_model.dart';
import 'inventory_providers.dart';

// Provider simple para leer el historial
final auditHistoryProvider = StreamProvider<List<AuditLog>>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.getAuditHistory();
});

class AuditHistoryScreen extends ConsumerWidget {
  const AuditHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(auditHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Historial de Auditorías")),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text("Error: $e")),
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(child: Text("No hay auditorías registradas aún."));
          }
          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo[50],
                    child: const Icon(Icons.assignment, color: Colors.indigo),
                  ),
                  title: Text(DateFormat('dd/MM/yyyy HH:mm').format(log.date)),
                  subtitle: Text("${log.itemsAdjusted} productos ajustados"),
                  children: [
                    // RESUMEN FINANCIERO (Igual que antes)
                    Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // ... tus columnas de Pérdida y Sobrante ...
                        ],
                      ),
                    ),
                    const Divider(),
                    
                    // TÍTULO DE LA LISTA
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        "Detalle de Productos (${log.details.length})",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
                      ),
                    ),

                    // DETALLE MEJORADO
                    ...log.details.map((detail) {
                      final diff = detail.newStock - detail.oldStock;
                      final isPerfect = diff == 0;

                      return ListTile(
                        dense: true,
                        // Icono visual: Check azul si está perfecto, Alerta si hubo cambio
                        leading: isPerfect 
                            ? const Icon(Icons.check_circle_outline, color: Colors.blueGrey, size: 20)
                            : Icon(diff > 0 ? Icons.arrow_circle_up : Icons.arrow_circle_down, 
                                  color: diff > 0 ? Colors.green : Colors.red, size: 20),
                        
                        title: Text(
                          detail.productName,
                          style: TextStyle(
                            fontWeight: isPerfect ? FontWeight.normal : FontWeight.bold,
                            color: isPerfect ? Colors.black87 : Colors.black
                          ),
                        ),
                        
                        subtitle: isPerfect
                            ? Text("Stock verificado: ${detail.newStock}") // Mensaje para los correctos
                            : Text("Ajustado: ${detail.oldStock} ➔ ${detail.newStock}"), // Mensaje para cambios
                        
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPerfect ? Colors.grey[100] : (diff > 0 ? Colors.green[50] : Colors.red[50]),
                            borderRadius: BorderRadius.circular(8),
                            border: isPerfect ? Border.all(color: Colors.grey.shade300) : null,
                          ),
                          child: Text(
                            isPerfect ? "OK" : (diff > 0 ? "+$diff" : "$diff"),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isPerfect ? Colors.grey[700] : (diff > 0 ? Colors.green[800] : Colors.red[800]),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 10),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}