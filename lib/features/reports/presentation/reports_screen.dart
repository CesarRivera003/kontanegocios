import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/currency_formatter.dart';
import '../data/reports_repository.dart';
import '../domain/report_stats.dart';
import 'report_pdf_generator.dart';
import '../../home/presentation/dashboard_shell.dart';
import 'package:go_router/go_router.dart';
import '../../inventory/domain/product_model.dart';
import '../../inventory/presentation/inventory_providers.dart';

// Widgets modulares existentes
import 'widgets/financial_charts.dart';
import 'widgets/report_empty_state.dart';

/// Pantalla Principal de Reportes - Estilo Ultramoderno (SaaS / Fintech Stitch)
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

  String _activePreset = '30D';

  void _applyPreset(String preset) {
    final now = DateTime.now();
    DateTime start;
    switch (preset) {
      case 'Hoy':
        start = DateTime(now.year, now.month, now.day);
        break;
      case '7D':
        start = now.subtract(const Duration(days: 7));
        break;
      case '30D':
        start = now.subtract(const Duration(days: 30));
        break;
      case 'Este Mes':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'Año':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = now.subtract(const Duration(days: 30));
    }
    setState(() {
      _activePreset = preset;
      _selectedRange = DateTimeRange(start: start, end: now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    final reportAsync = ref.watch(reportStatsProvider(_selectedRange));
    const backgroundColor = Color(0xFFF8FAFC); // Slate 50 de la maqueta

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF0F172A)),
                onPressed: () => DashboardShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              'Konta',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A)),
            ),
            const Text(
              ' Negocios',
              style: TextStyle(fontWeight: FontWeight.normal, fontSize: 18, color: Color(0xFF4F46E5)),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
        actions: [
          reportAsync.maybeWhen(
            data: (stats) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('Exportar PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                onPressed: () => ReportPdfGenerator.generateFullReport(stats, _selectedRange),
              ),
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
                _buildHeaderSection(),
                const Expanded(child: ReportEmptyState()),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==========================================
                    // NIVEL 1: ENCABEZADO Y FILTRO TEMPORAL
                    // ==========================================
                    _buildHeaderSection(),
                    const SizedBox(height: 24),

                    // ==========================================
                    // NIVEL 2: MÉTRICAS CLAVE (HERO 4 KPIs)
                    // ==========================================
                    _buildKpiHeroGrid(stats),
                    const SizedBox(height: 24),

                    // ==========================================
                    // BANNER DE ALERTAS DE STOCK (CRÍTICO)
                    // ==========================================
                    if (stats.lowStockAlerts.isNotEmpty) ...[
                      _buildStockAlertBanner(stats.lowStockAlerts),
                      const SizedBox(height: 28),
                    ],

                    // ==========================================
                    // NIVEL 3: DIAGNÓSTICO & MATRIZ INTELIGENTE
                    // ==========================================
                    _buildSectionHeader(
                      icon: Icons.psychology_outlined,
                      title: 'Diagnóstico Estratégico & Matriz Inteligente',
                      subtitle: 'Patrones detectados por el modelo de rotación automática',
                    ),
                    const SizedBox(height: 16),
                    _buildDiagnosticsAndMatrixSection(stats),
                    const SizedBox(height: 32),

                    // ==========================================
                    // NIVEL 4: TENDENCIAS FINANCIERAS
                    // ==========================================
                    _buildSectionHeader(
                      icon: Icons.show_chart,
                      title: 'Tendencias Financieras',
                      subtitle: 'Flujo consolidado de caja, márgenes netos y dispersión por canal de cobro',
                    ),
                    const SizedBox(height: 16),
                    _buildFinancialTrendsSection(stats),
                    const SizedBox(height: 32),

                    // ==========================================
                    // NIVEL 5: RENDIMIENTO OPERATIVO & RANKINGS
                    // ==========================================
                    _buildSectionHeader(
                      icon: Icons.leaderboard_outlined,
                      title: 'Rendimiento Operativo & Rankings',
                      subtitle: 'Líderes de facturación, velocidad de producto y balance de costos operativos',
                    ),
                    const SizedBox(height: 16),
                    _buildOperationalRankingsSection(stats),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5))),
        error: (e, _) => Center(child: Text('Error al cargar datos: $e', style: const TextStyle(color: Colors.red))),
      ),
    );
  }

  // =========================================================================
  // SECCIÓN 1: HEADER & SELECTOR DE TIEMPO ESTILO MAQUETA
  // =========================================================================
  Widget _buildHeaderSection() {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 850;
      final headerInfo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'MOTOR ANALÍTICO',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF047857),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              const Text('•', style: TextStyle(color: Color(0xFFCBD5E1))),
              const SizedBox(width: 8),
              const Text(
                'Sincronizado en tiempo real',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Inteligencia de Negocio',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: const Text(
                  'Empresarial',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Visibilidad algorítmica de márgenes, rotación de activos y flujo operacional.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ],
      );

      final datePill = Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF4F46E5)),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatDateSafe(_selectedRange.start)} — ${_formatDateSafe(_selectedRange.end)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.expand_more, size: 16, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
            ...['Hoy', '7D', '30D', 'Este Mes', 'Año'].map((preset) {
              final isSelected = _activePreset == preset;
              return InkWell(
                onTap: () => _applyPreset(preset),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFEEF2FF) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected ? Border.all(color: const Color(0xFFC7D2FE)) : null,
                  ),
                  child: Text(
                    preset,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      );

      return isWide
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: headerInfo),
                datePill,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headerInfo,
                const SizedBox(height: 16),
                datePill,
              ],
            );
    });
  }

  // =========================================================================
  // SECCIÓN 2: HERO CARDS EN UN SOLO RENGLÓN HORIZONTAL (4 EN LÍNEA)
  // =========================================================================
  Widget _buildKpiHeroGrid(ReportStats stats) {
    // Cálculos reales de margen y ratios
    final double profitMargin = stats.totalIncome > 0
        ? (stats.totalProfit / stats.totalIncome) * 100
        : 0.0;

    final int estimatedOrders = stats.averageTicket > 0
        ? (stats.totalIncome / stats.averageTicket).round()
        : 0;

    final List<double> incomeTrend = stats.monthlyStats.isNotEmpty
        ? stats.monthlyStats.map((m) => m.income).toList()
        : [0.0, stats.totalIncome];

    final List<double> profitTrend = stats.monthlyStats.isNotEmpty
        ? stats.monthlyStats.map((m) => (m.income - m.expense)).toList()
        : [0.0, stats.totalProfit];

    final cards = [
      // 1. VENTAS TOTALES
      _buildCompactKpiCard(
        title: 'Ventas Totales / Ingresos',
        subtitle: 'Facturación neta',
        value: CurrencyFormatter.format(stats.totalIncome),
        badgeLabel: '$estimatedOrders vtas',
        badgePositive: true,
        sparklineData: incomeTrend,
        accentColor: const Color(0xFF10B981),
        footerLeading: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 11, color: Color(0xFF64748B)),
            const SizedBox(width: 3),
            Text('$estimatedOrders pedidos', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
          ],
        ),
      ),

      // 2. GANANCIA NETA REAL
      _buildCompactKpiCard(
        title: 'Ganancia Neta Real',
        subtitle: 'Ingresos - costos y gastos',
        value: CurrencyFormatter.format(stats.totalProfit),
        badgeLabel: '${profitMargin.toStringAsFixed(1)}% Margen',
        badgePositive: stats.totalProfit >= 0,
        sparklineData: profitTrend,
        accentColor: const Color(0xFF4F46E5),
        footerLeading: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: stats.totalProfit >= 0 ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              stats.totalProfit >= 0 ? 'Rentabilidad Positiva' : 'Déficit',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: stats.totalProfit >= 0 ? const Color(0xFF047857) : const Color(0xFFBE123C),
              ),
            ),
          ],
        ),
      ),

      // 3. TICKET PROMEDIO
      _buildCompactKpiCard(
        title: 'Ticket Promedio',
        subtitle: 'Gasto medio por cliente',
        value: CurrencyFormatter.format(stats.averageTicket),
        badgeLabel: '${stats.averageBasketSize.toStringAsFixed(1)} arts/vta',
        badgePositive: stats.averageBasketSize >= 1.0,
        progressRatio: (stats.averageBasketSize / 5.0).clamp(0.05, 1.0),
        accentColor: const Color(0xFF6366F1),
        footerLeading: Row(
          children: [
            const Icon(Icons.shopping_basket_outlined, size: 11, color: Color(0xFF64748B)),
            const SizedBox(width: 3),
            Text('Cesta: ${stats.averageBasketSize.toStringAsFixed(1)} arts.', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
          ],
        ),
      ),

      // 4. CAPITAL EN BODEGA
      _buildCompactKpiCard(
        title: 'Capital en Bodega',
        subtitle: 'Stock estancado',
        value: CurrencyFormatter.format(stats.immobilizedCapital),
        badgeLabel: '${stats.inventoryMatrix.deadStock.length} sin rotación',
        badgePositive: stats.immobilizedCapital == 0,
        accentColor: const Color(0xFFF43F5E),
        footerLeading: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, size: 11, color: Color(0xFFE11D48)),
            const SizedBox(width: 3),
            Text(
              '${stats.inventoryMatrix.deadStock.length} SKUs inactivos',
              style: const TextStyle(fontSize: 10, color: Color(0xFFBE123C), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // Si la pantalla es amplia (web / desktop), mostramos exactamente 1 renglón con 4 columnas
      if (constraints.maxWidth > 950) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
            const SizedBox(width: 12),
            Expanded(child: cards[2]),
            const SizedBox(width: 12),
            Expanded(child: cards[3]),
          ],
        );
      }

      // Si la ventana es más estrecha (tablet o ventana pequeña), permitimos deslizar en una sola fila horizontal
      // evitando que se apilen en 2x2 y preservando el diseño de 1 solo renglón
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            SizedBox(width: 260, child: cards[0]),
            const SizedBox(width: 12),
            SizedBox(width: 260, child: cards[1]),
            const SizedBox(width: 12),
            SizedBox(width: 260, child: cards[2]),
            const SizedBox(width: 12),
            SizedBox(width: 260, child: cards[3]),
          ],
        ),
      );
    });
  }

  Widget _buildCompactKpiCard({
    required String title,
    required String subtitle,
    required String value,
    required String badgeLabel,
    required bool badgePositive,
    required Color accentColor,
    required Widget footerLeading,
    List<double>? sparklineData,
    double? progressRatio,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Fila superior: Título y Badge Real
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgePositive ? const Color(0xFFECFDF5) : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: badgePositive ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3),
                  ),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: badgePositive ? const Color(0xFF047857) : const Color(0xFFBE123C),
                  ),
                ),
              ),
            ],
          ),

          // Valor Numérico
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'COP',
                style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: Color(0xFF94A3B8)),
              ),
            ],
          ),

          // Fila Inferior: Micro-gráfico Sparkline real y footer
          Container(
            padding: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Gráfica de línea Sparkline o mini barra de progreso
                if (sparklineData != null && sparklineData.length >= 2)
                  SizedBox(
                    width: 55,
                    height: 16,
                    child: CustomPaint(
                      painter: _MiniSparklinePainter(
                        data: sparklineData,
                        lineColor: accentColor,
                      ),
                    ),
                  )
                else if (progressRatio != null)
                  Container(
                    width: 55,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progressRatio,
                      child: Container(
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                footerLeading,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // BANNER DE ALERTAS DE STOCK (RESPONSIVO Y CON EDICIÓN AL CLIC)
  // =========================================================================
  Widget _buildStockAlertBanner(List<ProductAlert> alerts) {
    // Obtenemos el listado de productos de inventario para enviar el objeto completo al editar
    final allProducts = ref.watch(productsStreamProvider).asData?.value ?? [];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2).withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFFF43F5E), width: 5)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado Responsivo: Evita desbordamientos
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE4E6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.crisis_alert, color: Color(0xFFE11D48), size: 20),
                  ),
                  const SizedBox(width: 12),
                  // Expanded previene que los textos se salgan de la pantalla
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text(
                              'Alertas de Stock: Atención Inmediata',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE11D48),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${alerts.length} Críticos',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Existencias bajas detectadas. Toca un producto para editarlo o reabastecerlo.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Chips de productos interactivos
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: alerts.take(8).map((alert) {
                  final isZero = alert.stock == 0;

                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        // Buscamos el producto correspondiente en el inventario
                        final matchingProduct = allProducts.cast<Product?>().firstWhere(
                              (p) => p?.name.trim().toLowerCase() == alert.name.trim().toLowerCase(),
                              orElse: () => null,
                            );

                        // Navegamos al formulario de edición pasando el producto
                        if (matchingProduct != null) {
                          context.push('/inventory/save', extra: matchingProduct);
                        } else {
                          // Si no se encuentra en memoria, abre la pantalla general de inventario
                          context.push('/inventory');
                        }
                      },
                      hoverColor: const Color(0xFFFFF1F2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECDD3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                alert.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isZero ? const Color(0xFFE11D48) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isZero ? 'AGOTADO' : '${alert.stock} Und',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isZero ? Colors.white : const Color(0xFFB45309),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_outlined, size: 12, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // SECCIÓN 3: DIAGNÓSTICO ESTRATÉGICO & MATRIZ INTELIGENTE (DATOS REALES)
  // =========================================================================
  Widget _buildDiagnosticsAndMatrixSection(ReportStats stats) {
    // 1. Lógica dinámica para la Cesta Promedio (evita textos y badges inventados)
    final double basket = stats.averageBasketSize;
    final String basketBadge;
    final Color basketBadgeColor;
    final Color basketBadgeBg;
    final Color basketBadgeBorder;
    final String basketDescription;
    final String basketTip;

    if (basket <= 0) {
      basketBadge = 'Sin Datos';
      basketBadgeColor = const Color(0xFF64748B);
      basketBadgeBg = const Color(0xFFF1F5F9);
      basketBadgeBorder = const Color(0xFFE2E8F0);
      basketDescription = 'No hay ventas con unidades registradas en el período seleccionado.';
      basketTip = 'Registra ventas con múltiples ítems para calcular la profundidad de compra.';
    } else if (basket < 1.5) {
      basketBadge = 'Cesta Unitaria';
      basketBadgeColor = const Color(0xFFB45309);
      basketBadgeBg = const Color(0xFFFEF3C7);
      basketBadgeBorder = const Color(0xFFFDE68A);
      basketDescription = 'La mayoría de clientes solo compran 1 artículo por visita (compras rápidas o de paso).';
      basketTip = 'Estrategia Cross-Selling: Sugiere complementos económicos o artículos de impulso en caja para subir a 2 unidades.';
    } else if (basket < 2.5) {
      basketBadge = 'Cesta Media';
      basketBadgeColor = const Color(0xFF4F46E5);
      basketBadgeBg = const Color(0xFFEEF2FF);
      basketBadgeBorder = const Color(0xFFC7D2FE);
      basketDescription = 'Los clientes llevan en promedio ${basket.toStringAsFixed(1)} productos por factura.';
      basketTip = 'Estrategia Bundle: Crea combos o paquetes con descuento sugerido para incentivar compras de ${(basket + 1).toInt()} artículos.';
    } else {
      basketBadge = 'Cesta Óptima';
      basketBadgeColor = const Color(0xFF047857);
      basketBadgeBg = const Color(0xFFECFDF5);
      basketBadgeBorder = const Color(0xFFA7F3D0);
      basketDescription = 'Excelente profundidad: los clientes llevan en promedio ${basket.toStringAsFixed(1)} artículos por transacción.';
      basketTip = 'Estrategia de Fidelización: Premia carritos de gran volumen con descuentos o beneficios en su próxima compra.';
    }

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 950;

      // Columna Izquierda: 2 Tarjetas de Acción Rápida
      final leftInsights = Column(
        children: [
          // 1. MAPA DE OPORTUNIDAD CON DÍAS DE LA SEMANA
          _buildActionCard(
            title: 'MAPA DE OPORTUNIDAD TEMPORAL',
            badge: stats.peakSalesDay.isNotEmpty && stats.peakSalesDay != 'N/A' ? 'Día ${stats.peakSalesDay}' : 'Sin datos',
            badgeBg: const Color(0xFFF1F5F9),
            badgeColor: const Color(0xFF475569),
            icon: Icons.schedule,
            iconColor: const Color(0xFF4F46E5),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('DÍA PICO', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF94A3B8))),
                            const SizedBox(height: 2),
                            Text(
                              stats.peakSalesDay.isNotEmpty ? stats.peakSalesDay : 'N/A',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text('Mayor concentración', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('HORARIO FRECUENTE', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF94A3B8))),
                            const SizedBox(height: 2),
                            Text(
                              stats.peakSalesHourRange.isNotEmpty ? stats.peakSalesHourRange : 'N/A',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text('Bloque de mayor afluencia', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Micro-heatmap de los 7 días de la semana
                _buildWeekdaysHeatmap(stats.peakSalesDay),
              ],
            ),
            tip: stats.peakSalesDay != 'N/A'
                ? 'Optimización de turnos: Refuerza personal y stock en el horario ${stats.peakSalesHourRange} del ${stats.peakSalesDay}.'
                : 'Registra ventas con fecha y hora para que el sistema identifique tu día pico.',
            tipIcon: Icons.lightbulb_outline,
            tipColor: const Color(0xFF4F46E5),
            tipBg: const Color(0xFFEEF2FF),
          ),
          const SizedBox(height: 16),

          // 2. PROFUNDIDAD DE CARRITO (CON DATOS REALES)
          _buildActionCard(
            title: 'PROFUNDIDAD DE CARRITO',
            badge: basketBadge,
            badgeBg: basketBadgeBg,
            badgeColor: basketBadgeColor,
            badgeBorder: basketBadgeBorder,
            icon: Icons.shopping_cart_checkout,
            iconColor: const Color(0xFF10B981),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      basket.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 8),
                    const Text('unidades / factura en promedio', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  basketDescription,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            tip: basketTip,
            tipIcon: Icons.auto_awesome_outlined,
            tipColor: basketBadgeColor,
            tipBg: basketBadgeBg,
          ),
        ],
      );

      // Columna Derecha: Matriz con productos visibles
      final rightMatrix = _buildInventoryMatrixCard(stats.inventoryMatrix);

      return isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: leftInsights),
                const SizedBox(width: 16),
                Expanded(flex: 7, child: rightMatrix),
              ],
            )
          : Column(
              children: [
                leftInsights,
                const SizedBox(height: 16),
                rightMatrix,
              ],
            );
    });
  }

  // Micro-heatmap de los 7 días de la semana
  Widget _buildWeekdaysHeatmap(String peakDay) {
    const days = [
      {'short': 'Lun', 'name': 'Lunes'},
      {'short': 'Mar', 'name': 'Martes'},
      {'short': 'Mié', 'name': 'Miércoles'},
      {'short': 'Jue', 'name': 'Jueves'},
      {'short': 'Vie', 'name': 'Viernes'},
      {'short': 'Sáb', 'name': 'Sábado'},
      {'short': 'Dom', 'name': 'Domingo'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: days.map((d) {
            final isPeak = peakDay.toLowerCase().startsWith(d['name']!.toLowerCase().substring(0, 3));
            return Expanded(
              child: Text(
                d['short']!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: isPeak ? FontWeight.bold : FontWeight.w500,
                  color: isPeak ? const Color(0xFF047857) : const Color(0xFF94A3B8),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Row(
          children: days.map((d) {
            final isPeak = peakDay.toLowerCase().startsWith(d['name']!.toLowerCase().substring(0, 3));
            return Expanded(
              child: Container(
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isPeak ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required String badge,
    required IconData icon,
    required Color iconColor,
    required Widget content,
    required String tip,
    required IconData tipIcon,
    required Color tipColor,
    required Color tipBg,
    Color? badgeBg,
    Color? badgeColor,
    Color? badgeBorder,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg ?? const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: badgeBorder != null ? Border.all(color: badgeBorder) : null,
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor ?? const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          content,
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tipBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(tipIcon, size: 16, color: tipColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tip,
                    style: TextStyle(fontSize: 11, color: tipColor, fontWeight: FontWeight.w500, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Matriz de Inventario mostrando productos reales en 2x2
  Widget _buildInventoryMatrixCard(InventoryMatrix matrix) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Matriz de Inventario Inteligente (BCG)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                  SizedBox(height: 2),
                  Text('Clasificación cruzando rotación y margen unitario (mg)', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('4 Cuadrantes', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF475569))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Cuadrícula flexible que muestra los productos sin desbordamientos
          LayoutBuilder(builder: (context, constraints) {
            final isMini = constraints.maxWidth < 500;

            final starsBox = _buildQuadrantBox(
              emoji: '⭐',
              title: 'PRODUCTOS ESTRELLA',
              subtitle: 'Alto Vol. / Alto Margen',
              bgColor: const Color(0xFFF0FDF4),
              borderColor: const Color(0xFFBBF7D0),
              textColor: const Color(0xFF166534),
              items: matrix.stars,
              valueType: 'margin',
              actionText: 'Mantener stock continuo siempre',
            );

            final opsBox = _buildQuadrantBox(
              emoji: '💎',
              title: 'ALTO MARGEN',
              subtitle: 'Bajo Vol. / Alto Margen',
              bgColor: const Color(0xFFEEF2FF),
              borderColor: const Color(0xFFC7D2FE),
              textColor: const Color(0xFF3730A3),
              items: matrix.opportunities,
              valueType: 'margin',
              actionText: 'Mayor visibilidad y ofertas',
            );

            final hooksBox = _buildQuadrantBox(
              emoji: '🎯',
              title: 'CABALLOS DE BATALLA',
              subtitle: 'Alto Vol. / Bajo Margen',
              bgColor: const Color(0xFFF8FAFC),
              borderColor: const Color(0xFFE2E8F0),
              textColor: const Color(0xFF1E293B),
              items: matrix.hooks,
              valueType: 'rotation',
              actionText: 'Optimizar costos con mayoristas',
            );

            final deadBox = _buildQuadrantBox(
              emoji: '⚠️️',
              title: 'INACTIVOS / HUESO',
              subtitle: 'Bajo Vol. / Bajo Margen',
              bgColor: const Color(0xFFFFF1F2),
              borderColor: const Color(0xFFFECDD3),
              textColor: const Color(0xFF9F1239),
              items: matrix.deadStock,
              valueType: 'stock',
              actionText: 'Liquidar para liberar liquidez',
            );

            if (isMini) {
              return Column(
                children: [
                  starsBox,
                  const SizedBox(height: 10),
                  opsBox,
                  const SizedBox(height: 10),
                  hooksBox,
                  const SizedBox(height: 10),
                  deadBox,
                ],
              );
            }

            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: starsBox),
                    const SizedBox(width: 10),
                    Expanded(child: opsBox),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: hooksBox),
                    const SizedBox(width: 10),
                    Expanded(child: deadBox),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildQuadrantBox({
    required String emoji,
    required String title,
    required String subtitle,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
    required List<MatrixItem> items,
    required String valueType,
    required String actionText,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 15)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${items.length} items', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
          Text(subtitle, style: TextStyle(fontSize: 9, color: textColor.withOpacity(0.8), fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),

          // LISTADO DE PRODUCTOS REALES
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sin productos en esta categoría',
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: textColor.withOpacity(0.6)),
              ),
            )
          else ...[
            ...items.take(3).map((item) {
              final String detail;
              if (valueType == 'stock') {
                detail = '${item.stock} und';
              } else if (valueType == 'rotation') {
                detail = '${item.rotation.toInt()} vtas';
              } else {
                detail = '${item.margin.toStringAsFixed(0)}% mg';
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      detail,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold, color: textColor),
                    ),
                  ],
                ),
              );
            }),
            if (items.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+ ${items.length - 3} más...',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.7)),
                ),
              ),
          ],

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: borderColor.withOpacity(0.6)))),
            child: Row(
              children: [
                Icon(Icons.arrow_right_alt, size: 14, color: textColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(actionText, style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.85), fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SECCIÓN 4: TENDENCIAS FINANCIERAS (BARRAS & MEDIOS DE PAGO)
  // =========================================================================
  Widget _buildFinancialTrendsSection(ReportStats stats) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;

      final barCard = Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Evolución Ingresos vs Gastos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                    Text('Comparativa periódica con margen neto', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
                Row(
                  children: [
                    _buildLegendItem('Ingresos', const Color(0xFF4F46E5)),
                    const SizedBox(width: 12),
                    _buildLegendItem('Gastos', const Color(0xFFF43F5E)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: FinancialBarChart(stats: stats),
            ),
          ],
        ),
      );

      final paymentMethodsCard = Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Medios de Pago', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                Text('100% Auditado', style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF047857))),
              ],
            ),
            const Text('Canales de liquidación preferidos', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: ModernDonutChart(data: stats.incomeByMethod),
            ),
            const SizedBox(height: 12),
            ...stats.incomeByMethod.entries.map((entry) {
              final total = stats.totalIncome > 0 ? stats.totalIncome : 1.0;
              final pct = ((entry.value / total) * 100).toStringAsFixed(0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key, style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w500)),
                    Row(
                      children: [
                        Text('$pct%', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        const SizedBox(width: 6),
                        Text('(${CurrencyFormatter.format(entry.value)})', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      );

      return isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: barCard),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: paymentMethodsCard),
              ],
            )
          : Column(
              children: [
                barCard,
                const SizedBox(height: 16),
                paymentMethodsCard,
              ],
            );
    });
  }

  // =========================================================================
  // SECCIÓN 5: RANKINGS Y RENDIMIENTO OPERATIVO (ESTILO MAQUETA)
  // =========================================================================
  Widget _buildOperationalRankingsSection(ReportStats stats) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;

      // Card de Top Líderes con barras de progreso delgadas
      final leadersCard = Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Top 5 Productos Líderes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                Text('Últimos 30D', style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF4F46E5))),
              ],
            ),
            const Text('Facturación monetaria vs. unidades despachadas', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildProgressRankingColumn(
                    title: 'MAYOR FACTURACIÓN',
                    items: stats.topProductsByRevenue.take(5).toList(),
                    isCurrency: true,
                    accentColor: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildProgressRankingColumn(
                    title: 'MAYOR ROTACIÓN (VOL)',
                    items: stats.topProductsByQty.take(5).toList(),
                    isCurrency: false,
                    accentColor: const Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      // Card de Rendimiento del Equipo & Gastos Operativos
      final teamCard = Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Rendimiento del Equipo & Gastos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10)),
                  child: Text('${stats.userStats.length} Asesores', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                ),
              ],
            ),
            const Text('Control de ventas por usuario y gastos por categoría', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            // Tabla de Asesores
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 34,
                dataRowHeight: 44,
                horizontalMargin: 8,
                columnSpacing: 16,
                headingTextStyle: const TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                columns: const [
                  DataColumn(label: Text('USUARIO')),
                  DataColumn(label: Text('VENTAS')),
                  DataColumn(label: Text('COMISIÓN')),
                ],
                rows: stats.userStats.map((u) {
                  final initials = u.userName.isNotEmpty
                      ? u.userName.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
                      : 'US';
                  return DataRow(cells: [
                    DataCell(
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFC7D2FE)),
                            ),
                            child: Center(
                              child: Text(
                                initials,
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(u.userName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                        ],
                      ),
                    ),
                    DataCell(Text(CurrencyFormatter.format(u.totalSales), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))),
                    DataCell(Text(CurrencyFormatter.format(u.commissions), style: const TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.w600))),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            // Donut de Gastos Operativos
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('DISTRIBUCIÓN DE GASTOS', style: TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                      Text(CurrencyFormatter.format(stats.totalExpenses), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 140,
                    child: ModernDonutChart(data: stats.expensesByCategory),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      return isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: leadersCard),
                const SizedBox(width: 16),
                Expanded(child: teamCard),
              ],
            )
          : Column(
              children: [
                leadersCard,
                const SizedBox(height: 16),
                teamCard,
              ],
            );
    });
  }

  Widget _buildProgressRankingColumn({
    required String title,
    required List<TopItem> items,
    required bool isCurrency,
    required Color accentColor,
  }) {
    double maxValue = 1.0;
    for (var it in items) {
      if (it.value > maxValue) maxValue = it.value;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
        ),
        const SizedBox(height: 12),
        ...items.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final it = entry.value;
          final progress = (it.value / maxValue).clamp(0.05, 1.0);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$idx. ${it.name}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      isCurrency ? CurrencyFormatter.format(it.value) : '${it.value.toInt()} und',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // =========================================================================
  // AUXILIARES
  // =========================================================================
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Icon(icon, color: const Color(0xFF4F46E5), size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: -0.3),
                ),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ],
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(badge, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
      ],
    );
  }

  String _formatDateSafe(DateTime dt) {
    try {
      return DateFormat('dd MMM, yyyy', 'es').format(dt);
    } catch (_) {
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    }
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
              primary: Color(0xFF4F46E5),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _activePreset = 'Custom';
        _selectedRange = picked;
      });
    }
  }
}

/// Pintor para dibujar micro-gráficos sparkline con datos reales
class _MiniSparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;

  _MiniSparklinePainter({required this.data, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double minVal = data.reduce((a, b) => a < b ? a : b);
    final double maxVal = data.reduce((a, b) => a > b ? a : b);
    final double range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final normalized = (data[i] - minVal) / range;
      final y = size.height - (normalized * (size.height - 4)) - 2;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      if (i == data.length - 1) {
        fillPath.lineTo(x, size.height);
        fillPath.close();
      }
    }

    // Área translúcida debajo de la línea
    final fillPaint = Paint()
      ..color = lineColor.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Línea de tendencia
    final strokePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.lineColor != lineColor;
}