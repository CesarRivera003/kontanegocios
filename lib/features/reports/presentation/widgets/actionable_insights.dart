import 'package:flutter/material.dart';
import '../../domain/report_stats.dart';

/// Tarjeta de Insight (Nivel 3). Muestra una recomendación estratégica de forma amigable.
class InsightActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String insight;
  final Color color;

  const InsightActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.insight,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))
              ],
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                    Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: color)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(insight, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
              ],
            ),
          )
        ],
      ),
    );
  }
}

/// Contenedor de la Matriz de Inventario Inteligente (Estrellas, Ganchos, Oportunidad, Estancados)
class InventoryQuadrantSection extends StatelessWidget {
  final InventoryMatrix matrix;

  const InventoryQuadrantSection({super.key, required this.matrix});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWide = constraints.maxWidth > 700;

        final stars = _QuadrantCard(
          title: "Estrellas ⭐",
          description: "¡Nunca te quedes sin stock!",
          items: matrix.stars,
          color: Colors.amber.shade700,
          bgColor: Colors.amber.shade50,
        );

        final hooks = _QuadrantCard(
          title: "Ganchos 🎯",
          description: "Atraen clientes. Sugiere otros productos.",
          items: matrix.hooks,
          color: Colors.blue.shade700,
          bgColor: Colors.blue.shade50,
        );

        final ops = _QuadrantCard(
          title: "Oportunidad 💎",
          description: "Dales más visibilidad y promociones.",
          items: matrix.opportunities,
          color: Colors.purple.shade700,
          bgColor: Colors.purple.shade50,
        );

        final dead = _QuadrantCard(
          title: "Estancados ⚠️",
          description: "Liquídalos para recuperar dinero.",
          items: matrix.deadStock,
          color: Colors.red.shade700,
          bgColor: Colors.red.shade50,
        );

        if (isWide) {
          return Column(
            children: [
              Row(children: [Expanded(child: stars), const SizedBox(width: 16), Expanded(child: hooks)]),
              const SizedBox(height: 16),
              Row(children: [Expanded(child: ops), const SizedBox(width: 16), Expanded(child: dead)]),
            ],
          );
        } else {
          return Column(
            children: [stars, const SizedBox(height: 16), hooks, const SizedBox(height: 16), ops, const SizedBox(height: 16), dead],
          );
        }
      },
    );
  }
}

class _QuadrantCard extends StatelessWidget {
  final String title;
  final String description;
  final List<MatrixItem> items;
  final Color color;
  final Color bgColor;

  const _QuadrantCard({
    required this.title,
    required this.description,
    required this.items,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Text("${items.length}", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              )
            ],
          ),
          const SizedBox(height: 4),
          Text(description, style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(8)),
              child: const Text("Ningún producto aquí.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54), textAlign: TextAlign.center),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items.take(8).map((item) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text("${item.name} (${item.stock})", style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
              )).toList(),
            ),
            if (items.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text("+ ${items.length - 8} más...", style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              )
        ],
      ),
    );
  }
}
