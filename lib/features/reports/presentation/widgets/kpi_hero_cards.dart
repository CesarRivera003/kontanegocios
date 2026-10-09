import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Tarjeta individual para mostrar un KPI (Key Performance Indicator).
/// Diseñada con un estilo SaaS moderno, con fondo limpio, icono destacado y sombra suave.
class KpiCard extends StatelessWidget {
  final String title;
  final String amountText;
  final Color color;
  final IconData icon;
  final String? subtitle;

  const KpiCard({
    super.key,
    required this.title,
    required this.amountText,
    required this.color,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            amountText,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            )
          ]
        ],
      ),
    );
  }
}

/// Contenedor responsivo para agrupar los KPIs principales (Nivel 2 de jerarquía).
/// En pantallas anchas (desktop/web) se muestra como un grid horizontal (Wrap).
/// En pantallas pequeñas (móvil) se apilan en pares o en una sola columna.
class KpiHeroGrid extends StatelessWidget {
  final double totalIncome;
  final double totalProfit;
  final double averageTicket;
  final double immobilizedCapital;

  const KpiHeroGrid({
    super.key,
    required this.totalIncome,
    required this.totalProfit,
    required this.averageTicket,
    required this.immobilizedCapital,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determinamos el número de columnas basado en el ancho disponible
        int columns = 1;
        if (constraints.maxWidth > 800) {
          columns = 4;
        } else if (constraints.maxWidth > 500) {
          columns = 2;
        }

        final double spacing = 16.0;
        // Calculamos el ancho de cada tarjeta restando los espacios entre ellas
        final double itemWidth = (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: itemWidth,
              child: KpiCard(
                title: "Ventas Totales",
                amountText: CurrencyFormatter.format(totalIncome),
                color: Colors.blueAccent,
                icon: Icons.payments_outlined,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: KpiCard(
                title: "Ganancia Neta",
                amountText: CurrencyFormatter.format(totalProfit),
                color: totalProfit >= 0 ? Colors.green : Colors.orange,
                icon: Icons.account_balance_wallet_outlined,
                subtitle: totalIncome > 0
                  ? "Margen: ${((totalProfit / totalIncome) * 100).toStringAsFixed(1)}%"
                  : "Margen: 0%",
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: KpiCard(
                title: "Ticket Promedio",
                amountText: CurrencyFormatter.format(averageTicket),
                color: Colors.purpleAccent,
                icon: Icons.receipt_long_outlined,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: KpiCard(
                title: "Dinero Inmovilizado",
                amountText: CurrencyFormatter.format(immobilizedCapital),
                color: Colors.redAccent,
                icon: Icons.inventory_2_outlined,
                subtitle: "En inventario sin rotación",
              ),
            ),
          ],
        );
      },
    );
  }
}
