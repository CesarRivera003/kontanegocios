import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../domain/report_stats.dart'; // Asegúrate que esta ruta sea correcta
import 'package:flutter/material.dart';

class ReportPdfGenerator {
  // --- ESTILOS CORPORATIVOS ---
  static const PdfColor _primaryColor = PdfColor.fromInt(0xFF1565C0);
  static const PdfColor _accentColor = PdfColor.fromInt(0xFFF5F5F5);
  static const PdfColor _textColor = PdfColor.fromInt(0xFF212121);
  
  static final _currencyFormat = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  static Future<void> generateFullReport(ReportStats stats, DateTimeRange range) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        // CAMBIO IMPORTANTE: Orientación Horizontal (Landscape)
        pageFormat: PdfPageFormat.a4, 
        margin: const pw.EdgeInsets.all(40),
        
        header: (context) => _buildHeader(
          title: 'Informe Gerencial Detallado', 
          subtitle: 'Periodo: ${_dateFormat.format(range.start)} - ${_dateFormat.format(range.end)}'
        ),
        footer: _buildFooter,
        
        build: (pw.Context context) => [
          
          // 1. RESUMEN EJECUTIVO (KPIs)
          // Aquí sí usamos Row porque son tarjetas fijas que no crecen infinitamente
          pw.Row(
            children: [
              _buildKpiCard("INGRESOS TOTALES", stats.totalIncome, PdfColors.green700),
              pw.SizedBox(width: 15),
              _buildKpiCard("GASTOS TOTALES", stats.totalExpenses, PdfColors.red700),
              pw.SizedBox(width: 15),
              _buildKpiCard("UTILIDAD NETA", stats.totalProfit, stats.totalProfit >= 0 ? _primaryColor : PdfColors.orange700),
            ]
          ),
          pw.SizedBox(height: 20),

          // 2. ALERTAS DE INVENTARIO
          if (stats.lowStockAlerts.isNotEmpty) ...[
            _buildAlertSection(stats),
            pw.SizedBox(height: 20),
          ],

          // A PARTIR DE AQUÍ, TODO ES SECUENCIAL (Uno debajo del otro)
          // Esto garantiza que el PDF nunca se congele al calcular saltos de página.

          // 3. DESGLOSE DE INGRESOS
          _buildSectionHeader("Detalle de Ingresos"),
          pw.SizedBox(height: 10),
          
          _buildTableSection(
            title: "Ingresos por Medio de Pago",
            headers: ['MÉTODO DE PAGO', 'TOTAL RECAUDADO'],
            data: stats.incomeByMethod.entries.map((e) => [e.key, _currencyFormat.format(e.value)]).toList()
          ),
          pw.SizedBox(height: 15),

          _buildTableSection(
            title: "Ingresos por Entidad Bancaria",
            headers: ['BANCO / CUENTA', 'TOTAL RECAUDADO'],
            data: stats.incomeByBank.entries.map((e) => [e.key, _currencyFormat.format(e.value)]).toList()
          ),
          pw.SizedBox(height: 25),

          // 4. RENDIMIENTO COMERCIAL
          _buildSectionHeader("Rendimiento Comercial y Equipo"),
          pw.SizedBox(height: 10),
          
          pw.Table.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: _primaryColor),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight, 
              2: pw.Alignment.centerRight
            },
            // En landscape damos más espacio a las columnas
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1.5),
            },
            headers: ['COLABORADOR', 'VENTAS TOTALES', 'COMISIÓN ESTIMADA'],
            data: stats.userStats.map((u) => [
              u.userName.toUpperCase(),
              _currencyFormat.format(u.totalSales),
              _currencyFormat.format(u.commissions)
            ]).toList(),
          ),
          pw.SizedBox(height: 25),

          // 5. GASTOS
          _buildSectionHeader("Control de Gastos"),
          pw.SizedBox(height: 10),
          
          pw.Table.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red800),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
            columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1)},
            headers: ['CATEGORÍA DE GASTO', 'VALOR EJECUTADO'],
            data: stats.expensesByCategory.entries.map((e) => [
              e.key.toUpperCase(),
              _currencyFormat.format(e.value)
            ]).toList(),
          ),
          pw.SizedBox(height: 25),

          // 6. RANKINGS (Top Clientes y Productos)
          _buildSectionHeader("Rankings y Tendencias"),
          pw.SizedBox(height: 10),

          _buildTableSection(
            title: "Top 10 Mejores Clientes",
            headers: ['CLIENTE', 'TOTAL COMPRADO'],
            data: stats.topClients.take(10).map((e) => [e.name, _currencyFormat.format(e.value)]).toList()
          ),
          pw.SizedBox(height: 15),

          _buildTableSection(
            title: "Productos Más Vendidos (Por Cantidad)",
            headers: ['PRODUCTO', 'UNIDADES VENDIDAS'],
            data: stats.topProductsByQty.take(10).map((e) => [e.name, "${e.value.toInt()} Unidades"]).toList()
          ),
          pw.SizedBox(height: 15),

          _buildTableSection(
            title: "Productos Más Rentables (Por Ingreso)",
            headers: ['PRODUCTO', 'INGRESOS GENERADOS'],
            data: stats.topProductsByRevenue.take(10).map((e) => [e.name, _currencyFormat.format(e.value)]).toList()
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) => doc.save(), 
      name: 'Reporte_Gerencial_Konta.pdf'
    );
  }

  // ===========================================================================
  // WIDGETS AUXILIARES
  // ===========================================================================

  static pw.Widget _buildAlertSection(ReportStats stats) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.red50,
        border: pw.Border.all(color: PdfColors.red200),
        borderRadius: pw.BorderRadius.circular(4)
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Text("ATENCIÓN: INVENTARIO CRÍTICO", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red900, fontSize: 10)),
          ]),
          pw.SizedBox(height: 5),
          pw.Wrap(
            spacing: 15, // Más espacio horizontal
            runSpacing: 5,
            children: stats.lowStockAlerts.map((a) => 
              pw.Text("• ${a.name} (Quedan: ${a.stock})", style: const pw.TextStyle(fontSize: 10, color: PdfColors.red900))
            ).toList()
          )
        ]
      )
    );
  }

  static pw.Widget _buildHeader({required String title, required String subtitle}) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _primaryColor, width: 2))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(children: [
            pw.Container(
              width: 35, height: 35,
              decoration: const pw.BoxDecoration(color: _primaryColor, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Center(child: pw.Text('K', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 20)))
            ),
            pw.SizedBox(width: 10),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('KONTA', style: pw.TextStyle(color: _primaryColor, fontWeight: pw.FontWeight.bold, fontSize: 18)),
              pw.Text('Sistema Contable', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9)),
            ])
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(title.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
            pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: _textColor)),
          ])
        ]
      )
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 20),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generado automáticamente por Konta App', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ]
      )
    );
  }

  static pw.Widget _buildKpiCard(String title, double value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 15),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(color: PdfColors.grey300),
          boxShadow: const [pw.BoxShadow(color: PdfColors.grey200, blurRadius: 2, offset: PdfPoint(1, 1))]
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 9, color: color, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text(_currencyFormat.format(value), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _textColor)),
          ]
        )
      )
    );
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
      decoration: const pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
      child: pw.Text(title.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _textColor))
    );
  }

  static pw.Widget _buildTableSection({
    required String title, 
    required List<String> headers, 
    required List<List<String>> data,
  }) {
    if (data.isEmpty) return pw.Container();
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
        pw.SizedBox(height: 6),
        pw.Table.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: _accentColor),
          headerStyle: pw.TextStyle(color: _textColor, fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
          // Ajustamos anchos para Landscape (más espacio para nombre)
          columnWidths: {
            0: const pw.FlexColumnWidth(4), 
            1: const pw.FlexColumnWidth(1), 
          },
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
          },
          headers: headers,
          data: data,
        )
      ]
    );
  }
}