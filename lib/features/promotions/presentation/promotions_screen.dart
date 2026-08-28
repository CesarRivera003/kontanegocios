import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../domain/promotion_model.dart';
import 'promotions_providers.dart';

class PromotionsScreen extends ConsumerWidget {
  const PromotionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promotionsAsync = ref.watch(allPromotionsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Promociones y Ofertas'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/settings/promotions/save'),
        label: const Text('Nueva Promo'),
        icon: const Icon(Icons.add),
      ),
      body: promotionsAsync.when(
        data: (promotions) {
          if (promotions.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_offer_outlined, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("No hay promociones configuradas", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: promotions.length,
            itemBuilder: (context, index) {
              final promo = promotions[index];
              final isExpired = DateTime.now().isAfter(promo.endDate.add(const Duration(days: 1)));
              
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isExpired ? Colors.grey : (promo.isActive ? Colors.green[100] : Colors.orange[100]),
                    child: Icon(
                      _getIconForType(promo.type),
                      color: isExpired ? Colors.white : (promo.isActive ? Colors.green : Colors.orange),
                    ),
                  ),
                  title: Text(promo.name, style: TextStyle(decoration: isExpired ? TextDecoration.lineThrough : null)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_getDescriptionForType(promo), style: const TextStyle(fontSize: 12)),
                      Text(
                        "Vence: ${DateFormat('dd/MM/yyyy').format(promo.endDate)}",
                        style: TextStyle(fontSize: 11, color: isExpired ? Colors.red : Colors.grey),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _confirmDelete(context, ref, promo),
                  ),
                  onTap: () => context.push('/settings/promotions/save', extra: promo),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  IconData _getIconForType(PromotionType type) {
    switch (type) {
      case PromotionType.seasonal: return Icons.calendar_month;
      case PromotionType.volume: return Icons.layers;
      case PromotionType.buyXgetY: return Icons.card_giftcard;
    }
  }

  String _getDescriptionForType(Promotion promo) {
    switch (promo.type) {
      case PromotionType.seasonal:
        return "Desc. Temporada: ${promo.percentage.toStringAsFixed(0)}%";
      case PromotionType.volume:
        return "Mayorista: ${promo.percentage.toStringAsFixed(0)}% (Min ${promo.minQuantity} und)";
      case PromotionType.buyXgetY:
        return "Pague ${promo.buyQuantity} Lleve ${promo.buyQuantity + promo.getQuantity}";
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Promotion promo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Promoción'),
        content: const Text('¿Estás seguro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              ref.read(promotionsRepositoryProvider).deletePromotion(promo.id);
              Navigator.pop(ctx);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}