import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../domain/report_stats.dart';

class ReportPdfGenerator {
  // Paleta Ejecutiva (Inspirada en el estilo SaaS / Fintech de la app)
  static const PdfColor _primaryIndigo = PdfColor.fromInt(0xFF4F46E5);
  static const PdfColor _darkSlate = PdfColor.fromInt(0xFF0F172A);
  static const PdfColor _textSecondary = PdfColor.fromInt(0xFF64748B);
  static const PdfColor _borderSlate = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor _bgLight = PdfColor.fromInt(0xFFF8FAFC);
  
  static const PdfColor _emerald = PdfColor.fromInt(0xFF047857);
  static const PdfColor _emeraldBg = PdfColor.fromInt(0xFFECFDF5);
  static const PdfColor _rose = PdfColor.fromInt(0xFFBE123C);
  static const PdfColor _roseBg = PdfColor.fromInt(0xFFFFF1F2);
  static const PdfColor _amber = PdfColor.fromInt(0xFFB45309);
  static const PdfColor _amberBg = PdfColor.fromInt(0xFFFEF3C7);

  static final _currencyFormat = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  static Future<void> generateFullReport(ReportStats stats, DateTimeRange range) async {
    final doc = pw.Document();

    final double profitMargin = stats.totalIncome > 0
        ? (stats.totalProfit / stats.totalIncome) * 100
        : 0.0;
    final int estimatedOrders = stats.averageTicket > 0
        ? (stats.totalIncome / stats.averageTicket).round()
        : 0;

    // Nombre de archivo dinámico con fecha
    final String formattedDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final String pdfFileName = 'Reporte_Konta_$formattedDate.pdf';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        header: (context) => _buildExecutiveHeader(range),
        footer: (context) => _buildExecutiveFooter(context),
        build: (pw.Context context) => [
          // ===================================================================
          // 1. RESUMEN EJECUTIVO: 4 KPIs (Tamaño de fuente optimizado)
          // ===================================================================
          pw.Row(
            children: [
              _buildKpiCard(
                title: "VENTAS",
                subtitle: "Facturación consolidada",
                value: _currencyFormat.format(stats.totalIncome),
                badgeText: "$estimatedOrders vtas",
                color: _emerald,
              ),
              pw.SizedBox(width: 8),
              _buildKpiCard(
                title: "GANANCIA",
                subtitle: "Margen de utilidad (mg)",
                value: _currencyFormat.format(stats.totalProfit),
                badgeText: "${profitMargin.toStringAsFixed(1)}% Mg",
                color: stats.totalProfit >= 0 ? _primaryIndigo : _rose,
              ),
              pw.SizedBox(width: 8),
              _buildKpiCard(
                title: "TICKET",
                subtitle: "Gasto medio del cliente",
                value: _currencyFormat.format(stats.averageTicket),
                badgeText: "${stats.averageBasketSize.toStringAsFixed(1)} arts/vta",
                color: _primaryIndigo,
              ),
              pw.SizedBox(width: 8),
              _buildKpiCard(
                title: "BODEGA",
                subtitle: "Costo de invetario",
                value: _currencyFormat.format(stats.totalInventoryCost),
                badgeText: "${stats.inventoryMatrix.deadStock.length} quietos",
                color: stats.immobilizedCapital > 0 ? _rose : _emerald,
              ),
            ],
          ),
          pw.SizedBox(height: 12),

          _buildRecommendationBox(
            title: "Diagnóstico Financiero General",
            recommendation: stats.totalProfit >= 0
                ? "El negocio opera con un margen neto del ${profitMargin.toStringAsFixed(1)}% y flujo positivo. Priorizar la rotación de los ${_currencyFormat.format(stats.immobilizedCapital)} inmovilizados en mercancía estancada para maximizar la liquidez."
                : "Atención: La operación registra déficit en el período evaluado (${_currencyFormat.format(stats.totalProfit)}). Se sugiere auditar costos de reposición y ajustar gastos fijos secundarios.",
            color: stats.totalProfit >= 0 ? _emerald : _rose,
            bgColor: stats.totalProfit >= 0 ? _emeraldBg : _roseBg,
          ),
          pw.SizedBox(height: 18),

          // ===================================================================
          // 2. ALERTAS DE INVENTARIO CRÍTICO (Bloque unificado)
          // ===================================================================
          if (stats.lowStockAlerts.isNotEmpty) ...[
            _buildStockAlertsSection(stats),
            pw.SizedBox(height: 18),
          ],

          // ===================================================================
          // 3. DIAGNÓSTICO ESTRATÉGICO Y MATRIZ (Nunca se separa del título)
          // ===================================================================
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("1. Diagnóstico Estratégico y Comportamiento"),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _buildInfoBox(
                      title: "MAPA DE OPORTUNIDAD",
                      primaryText: "Día Pico: ${stats.peakSalesDay.isNotEmpty ? stats.peakSalesDay : 'N/A'}",
                      secondaryText: "Horario frecuente: ${stats.peakSalesHourRange.isNotEmpty ? stats.peakSalesHourRange : 'N/A'}",
                      note: "Mayor afluencia de compra. Mantener dotación y stock listos.",
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: _buildInfoBox(
                      title: "PROFUNDIDAD DE CARRITO",
                      primaryText: "${stats.averageBasketSize.toStringAsFixed(1)} Arts / Factura",
                      secondaryText: "Ticket medio: ${_currencyFormat.format(stats.averageTicket)}",
                      note: stats.averageBasketSize < 2.0
                          ? "Cesta unitaria. Crear combos sugeridos en caja para subir volumen."
                          : "Excelente profundidad de compra. Fidelizar carritos recurrentes.",
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              _buildMatrixTable(stats.inventoryMatrix),
            ],
          ),
          pw.SizedBox(height: 18),

          // ===================================================================
          // 4. RENDIMIENTO COMERCIAL Y EQUIPO
          // ===================================================================
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("2. Rendimiento Comercial y Equipo"),
              pw.SizedBox(height: 8),
              if (stats.userStats.isNotEmpty)
                _buildCustomTable(
                  headers: ['COLABORADOR / ASESOR', 'VENTAS TOTALES', 'COMISIÓN ESTIMADA'],
                  alignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
                  flexWidths: {0: 3, 1: 2, 2: 2},
                  data: stats.userStats.map((u) => [
                    u.userName.toUpperCase(),
                    _currencyFormat.format(u.totalSales),
                    _currencyFormat.format(u.commissions)
                  ]).toList(),
                )
              else
                _buildEmptyStateText("Sin transacciones registradas por asesores en el período."),
            ],
          ),
          pw.SizedBox(height: 18),

          // ===================================================================
          // 5. GASTOS Y MEDIOS DE PAGO
          // ===================================================================
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("3. Control de Costos y Medios de Pago"),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Recaudo por Medio de Pago", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _primaryIndigo)),
                        pw.SizedBox(height: 4),
                        _buildCustomTable(
                          headers: ['MÉTODO', 'TOTAL'],
                          alignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
                          flexWidths: {0: 2, 1: 2},
                          data: stats.incomeByMethod.entries.map((e) => [e.key, _currencyFormat.format(e.value)]).toList(),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Gastos por Categoría", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _rose)),
                        pw.SizedBox(height: 4),
                        _buildCustomTable(
                          headers: ['CATEGORÍA', 'TOTAL EJECUTADO'],
                          alignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
                          flexWidths: {0: 3, 1: 2},
                          data: stats.expensesByCategory.entries.map((e) => [e.key.toUpperCase(), _currencyFormat.format(e.value)]).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          // ===================================================================
          // 6. RANKINGS: CLIENTES Y PRODUCTOS
          // ===================================================================
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("4. Rankings Estratégicos (Clientes y Artículos)"),
              pw.SizedBox(height: 8),
              if (stats.topClients.isNotEmpty) ...[
                pw.Text("Top 5 Clientes con Mayor Aporte (VIP)", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _darkSlate)),
                pw.SizedBox(height: 4),
                _buildCustomTable(
                  headers: ['POS.', 'CLIENTE', 'TOTAL COMPRADO'],
                  alignments: {0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight},
                  flexWidths: {0: 1, 1: 5, 2: 3},
                  data: stats.topClients.take(5).toList().asMap().entries.map((e) => [
                    '#${e.key + 1}',
                    e.value.name,
                    _currencyFormat.format(e.value.value),
                  ]).toList(),
                ),
                pw.SizedBox(height: 12),
              ],
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Top 5 Mayor Facturación", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _emerald)),
                        pw.SizedBox(height: 4),
                        _buildCustomTable(
                          headers: ['PRODUCTO', 'TOTAL'],
                          alignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
                          flexWidths: {0: 3, 1: 2},
                          data: stats.topProductsByRevenue.take(5).map((e) => [e.name, _currencyFormat.format(e.value)]).toList(),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Top 5 Mayor Rotación", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _primaryIndigo)),
                        pw.SizedBox(height: 4),
                        _buildCustomTable(
                          headers: ['PRODUCTO', 'UNIDADES'],
                          alignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
                          flexWidths: {0: 3, 1: 2},
                          data: stats.topProductsByQty.take(5).map((e) => [e.name, "${e.value.toInt()} Und"]).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          _buildRecommendationBox(
            title: "Conclusiones Ejecutivas y Plan de Acción",
            recommendation: "1. Mantener abastecimiento constante de los productos 'Estrella' para blindar el flujo principal.\n2. Crear combos promocionales con los productos de 'Alto Margen' para impulsar su salida.\n3. Liquidar los ${stats.inventoryMatrix.deadStock.length} SKUs inactivos para liberar ${_currencyFormat.format(stats.immobilizedCapital)} en liquidez inmediata.\n4. Establecer fidelización preferencial con los 5 mejores clientes registrados en el período.",
            color: _primaryIndigo,
            bgColor: const PdfColor.fromInt(0xFFEEF2FF),
          ),
        ],
      ),
    );

    // ✅ DESCARGA DIRECTA CON NOMBRE PERSONALIZADO
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: pdfFileName,
    );
  }

  // ===========================================================================
  // COMPONENTES VISUALES
  // ===========================================================================

  static pw.Widget _buildExecutiveHeader(DateTimeRange range) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _borderSlate, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 32,
                height: 32,
                decoration: pw.BoxDecoration(
                  color: _primaryIndigo,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Center(
                  child: pw.Text('K', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 18)),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('KONTA NEGOCIOS', style: pw.TextStyle(color: _darkSlate, fontWeight: pw.FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
                  pw.Text('Informe de Inteligencia y Toma de Decisiones', style: const pw.TextStyle(color: _textSecondary, fontSize: 8)),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: _bgLight,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: _borderSlate),
                ),
                child: pw.Text(
                  'PERIODO: ${_dateFormat.format(range.start)} - ${_dateFormat.format(range.end)}',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _darkSlate),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text('Generado: ${_dateFormat.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7, color: _textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildExecutiveFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderSlate, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Konta Negocios - Confidencial para uso interno', style: const pw.TextStyle(fontSize: 8, color: _textSecondary)),
          pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _darkSlate)),
        ],
      ),
    );
  }

  static pw.Widget _buildKpiCard({
    required String title,
    required String subtitle,
    required String value,
    required String badgeText,
    required PdfColor color,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: _borderSlate),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    title,
                    style: pw.TextStyle(fontSize: 8, color: _textSecondary, fontWeight: pw.FontWeight.bold),
                    maxLines: 1,
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: pw.BoxDecoration(
                    color: _bgLight,
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: _borderSlate),
                  ),
                  child: pw.Text(badgeText, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: color)),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _darkSlate)),
            pw.SizedBox(height: 2),
            pw.Text(subtitle, style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary), maxLines: 1),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: _bgLight,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: _borderSlate),
      ),
      child: pw.Text(
        title.toUpperCase(),
        style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _darkSlate),
      ),
    );
  }

  static pw.Widget _buildRecommendationBox({
    required String title,
    required String recommendation,
    required PdfColor color,
    required PdfColor bgColor,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: color, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("[ACCION RECOMENDADA] $title", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: color)),
          pw.SizedBox(height: 3),
          pw.Text(recommendation, style: pw.TextStyle(fontSize: 8, color: _darkSlate, lineSpacing: 1.3)),
        ],
      ),
    );
  }

  static pw.Widget _buildStockAlertsSection(ReportStats stats) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _roseBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _rose, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("[ALERTA] RIESGO DE QUIEBRE DE STOCK", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _rose)),
              pw.Text("${stats.lowStockAlerts.length} productos criticos", style: const pw.TextStyle(fontSize: 8, color: _rose)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 12,
            runSpacing: 4,
            children: stats.lowStockAlerts.take(12).map((a) {
              final isZero = a.stock == 0;
              return pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: isZero ? _rose : _amber),
                ),
                child: pw.Text(
                  "${a.name}: ${isZero ? 'AGOTADO' : '${a.stock} Und'}",
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: isZero ? _rose : _amber),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoBox({
    required String title,
    required String primaryText,
    required String secondaryText,
    required String note,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _borderSlate),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 8.5, color: _textSecondary, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(primaryText, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _darkSlate)),
          pw.SizedBox(height: 2),
          pw.Text(secondaryText, style: const pw.TextStyle(fontSize: 8, color: _textSecondary)),
          pw.SizedBox(height: 4),
          pw.Text("Nota: $note", style: pw.TextStyle(fontSize: 8, color: _textSecondary, fontStyle: pw.FontStyle.italic)),
        ],
      ),
    );
  }

  static pw.Widget _buildMatrixTable(InventoryMatrix matrix) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _borderSlate),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                "MATRIZ DE INVENTARIO INTELIGENTE (BCG)",
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _darkSlate),
              ),
              pw.Text(
                "Clasificacion segun rotacion y margen neto",
                style: const pw.TextStyle(fontSize: 8, color: _textSecondary),
              ),
            ],
          ),
          pw.SizedBox(height: 8),

          // 4 Cuadrantes de la Matriz
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildMatrixQuadrantSummary("ESTRELLAS", "Alta rotacion / Alto margen", matrix.stars, _emerald, _emeraldBg),
              pw.SizedBox(width: 6),
              _buildMatrixQuadrantSummary("OPORTUNIDAD", "Baja rotacion / Alto margen", matrix.opportunities, _primaryIndigo, const PdfColor.fromInt(0xFFEEF2FF)),
              pw.SizedBox(width: 6),
              _buildMatrixQuadrantSummary("CABALLOS DE BATALLA", "Alta rotacion / Bajo margen", matrix.hooks, _amber, _amberBg),
              pw.SizedBox(width: 6),
              _buildMatrixQuadrantSummary("INACTIVOS / HUESO", "Sin rotacion / Capital quieto", matrix.deadStock, _rose, _roseBg),
            ],
          ),
          pw.SizedBox(height: 10),

          // GUÍA ESTRATÉGICA Y ACCIONES DETALLADAS POR CUADRANTE
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: _bgLight,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: _borderSlate, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "DIRECTRICES DE ACCION POR CUADRANTE:",
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _darkSlate),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  "1. Estrellas: Son el motor de ganancia. Establecer alertas tempranas de stock y compras prioritarias para evitar roturas de inventario.",
                  style: pw.TextStyle(fontSize: 8, color: _darkSlate),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  "2. Oportunidades: Tienen margen excelente pero bajo volumen. Aumentar su exhibicion, colocarlos cerca de caja o recomendarlos activamente para estimular la prueba.",
                  style: pw.TextStyle(fontSize: 8, color: _darkSlate),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  "3. Caballos de Batalla: Generan alto trafico pero poco margen. Negociar mejores costos por volumen con proveedores o asociarlos en paquetes (combos) junto a productos de alto margen.",
                  style: pw.TextStyle(fontSize: 8, color: _darkSlate),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  "4. Inactivos / Hueso: Inmovilizan liquidez en bodega. Implementar promociones de descuento, ventas 2x1 o combos de salida inmediata para recuperar el capital atrapado.",
                  style: pw.TextStyle(fontSize: 8, color: _darkSlate),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMatrixQuadrantSummary(
    String title,
    String desc,
    List<MatrixItem> items,
    PdfColor color,
    PdfColor bgColor,
  ) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          color: bgColor,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(color: color, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    title,
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: color),
                    maxLines: 1,
                  ),
                ),
                pw.Text(
                  "${items.length}",
                  style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: color),
                ),
              ],
            ),
            pw.Text(desc, style: const pw.TextStyle(fontSize: 6.5, color: _textSecondary), maxLines: 1),
            pw.SizedBox(height: 4),
            if (items.isEmpty)
              pw.Text(
                "Sin productos",
                style: pw.TextStyle(fontSize: 7, color: _textSecondary, fontStyle: pw.FontStyle.italic),
              )
            else
              // Numeración limpia (1. 2. 3.) sin símbolos especiales
              ...items.take(3).toList().asMap().entries.map(
                (entry) => pw.Text(
                  "${entry.key + 1}. ${entry.value.name}",
                  style: pw.TextStyle(fontSize: 7, color: _darkSlate, fontWeight: pw.FontWeight.bold),
                  maxLines: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildCustomTable({
    required List<String> headers,
    required List<List<String>> data,
    required Map<int, pw.Alignment> alignments,
    required Map<int, int> flexWidths,
  }) {
    if (data.isEmpty) return _buildEmptyStateText("Sin datos registrados");

    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _borderSlate, width: 0.5),
      ),
      columnWidths: flexWidths.map((k, v) => MapEntry(k, pw.FlexColumnWidth(v.toDouble()))),
      children: [
        // Fila de encabezado
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _bgLight),
          children: headers.asMap().entries.map((h) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: pw.Align(
                alignment: alignments[h.key] ?? pw.Alignment.centerLeft,
                child: pw.Text(
                  h.value,
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _textSecondary),
                ),
              ),
            );
          }).toList(),
        ),
        // Filas de datos
        ...data.map((row) {
          return pw.TableRow(
            children: row.asMap().entries.map((cell) {
              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                child: pw.Align(
                  alignment: alignments[cell.key] ?? pw.Alignment.centerLeft,
                  child: pw.Text(
                    cell.value,
                    style: pw.TextStyle(fontSize: 9, color: _darkSlate, fontWeight: pw.FontWeight.normal),
                  ),
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  static pw.Widget _buildEmptyStateText(String msg) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: _bgLight,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Center(
        child: pw.Text(msg, style: pw.TextStyle(fontSize: 8, color: _textSecondary, fontStyle: pw.FontStyle.italic)),
      ),
    );
  }
}