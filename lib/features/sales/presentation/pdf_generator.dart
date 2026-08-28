import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart'; // [NUEVO] Para agrupar
import 'package:flutter/material.dart' show DateTimeRange; // Solo para tipos

// --- TUS MODELOS ---
import '../domain/sale_model.dart';
import '../../expenses/domain/expense_model.dart';
import '../../settings/domain/company_model.dart';
import '../../clients/domain/provider_model.dart'; // [NUEVO] Importar modelo de proveedor

class PdfGenerator {
  // --- CONFIGURACIÓN DE ESTILO CORPORATIVO ---
  static const PdfColor _primaryColor = PdfColor.fromInt(0xFF1565C0);
  static const PdfColor _accentColor = PdfColor.fromInt(0xFFE3F2FD);
  static const PdfColor _textColor = PdfColor.fromInt(0xFF212121);
  static const PdfColor _greyColor = PdfColor.fromInt(0xFF757575);

  static final _currencyFormat = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  // Estilos de texto reutilizables
  static pw.TextStyle get _titleStyle => pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _primaryColor);
  static pw.TextStyle get _subTitleStyle => pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _textColor);
  static pw.TextStyle get _normalStyle => const pw.TextStyle(fontSize: 10, color: _textColor);
  static pw.TextStyle get _smallStyle => const pw.TextStyle(fontSize: 8, color: _greyColor);

  // -----------------------------------------------------------------------------
  // 1. TICKET POS (Térmico) - GENERADOR DEL DISEÑO RESTAURADO
  // -----------------------------------------------------------------------------
  static Future<pw.Document> _buildTicketDocument(Sale sale, CompanyProfile? profile) async {
    final doc = pw.Document();
    
    final _smallStyle = pw.TextStyle(fontSize: 8);
    final _normalStyle = pw.TextStyle(fontSize: 9);
    final _boldStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final _titleStyle = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);

    // Separamos los costos adicionales en Cargos (+) y Descuentos (-)
    final charges = sale.additionalCosts.where((c) => (c['amount'] as num) > 0).toList();
    final discounts = sale.additionalCosts.where((c) => (c['amount'] as num) < 0).toList();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80.copyWith(
          marginLeft: 2 * PdfPageFormat.mm,
          marginRight: 2 * PdfPageFormat.mm,
          marginTop: 5 * PdfPageFormat.mm,
          marginBottom: 5 * PdfPageFormat.mm,
        ),
        build: (pw.Context context) {
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // --- CABECERA (PERSONALIZADA) ---
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Column(
                  children: [
                    pw.Text(profile?.name ?? 'KONTA GESTOR', style: _titleStyle, textAlign: pw.TextAlign.center),
                    if (profile?.nit.isNotEmpty == true) pw.Text('NIT: ${profile!.nit}', style: _normalStyle),
                    if (profile?.address.isNotEmpty == true) pw.Text(profile!.address, style: _normalStyle, textAlign: pw.TextAlign.center),
                    if (profile?.phone.isNotEmpty == true) pw.Text('Tel: ${profile!.phone}', style: _normalStyle),
                  ]
                ),
              ),
              
              pw.SizedBox(height: 5),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // --- INFO FACTURA ---
              _buildRow('Recibo POS:', sale.ticketNumber ?? sale.id.substring(0, 6).toUpperCase(), _boldStyle),
              _buildRow('Fecha:', DateFormat('dd/MM/yyyy HH:mm').format(sale.date), _normalStyle),
              _buildRow('Atendido por:', sale.sellerName ?? 'Admin', _normalStyle),
              pw.SizedBox(height: 2),
              pw.Text('Cliente: ${sale.clientName ?? "Cliente General"}', style: _normalStyle),
              
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // --- ENCABEZADOS TABLA ---
              pw.Row(children: [
                pw.SizedBox(width: 20, child: pw.Text('Cant', style: _boldStyle)),
                pw.SizedBox(width: 20, child: pw.Text('Und', style: _boldStyle)), 
                pw.Expanded(child: pw.Text('Descripción', style: _boldStyle)),
                pw.SizedBox(width: 55, child: pw.Text('Total', style: _boldStyle, textAlign: pw.TextAlign.right)),
              ]),
              pw.SizedBox(height: 4),

              // --- PRODUCTOS ---
              ...sale.items.map((item) {
                final qty = item['quantity'] ?? 0;
                final unit = item['unit'] ?? 'UND';
                final name = item['name'] ?? 'Producto';
                final total = (item['total'] as num?)?.toDouble() ?? 0.0;
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(width: 20, child: pw.Text('$qty', style: _normalStyle)),
                      pw.SizedBox(width: 20, child: pw.Text('$unit', style: _normalStyle)), 
                      pw.Expanded(child: pw.Text('$name', style: _normalStyle)),
                      pw.SizedBox(width: 55, child: pw.Text(_currencyFormat.format(total), style: _normalStyle, textAlign: pw.TextAlign.right)),
                    ]
                  )
                );
              }),

              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // --- CARGOS ADICIONALES ---
              if (charges.isNotEmpty) ...[
                 ...charges.map((cost) => _buildRow(cost['reason'] ?? 'Adicional', _currencyFormat.format((cost['amount'] as num).toDouble()), _normalStyle)),
                pw.SizedBox(height: 2),
              ],

              // --- DESCUENTOS ---
              if (discounts.isNotEmpty) ...[
                 ...discounts.map((disc) => _buildRow(disc['reason'] ?? 'Descuento', _currencyFormat.format((disc['amount'] as num).toDouble()), _normalStyle.copyWith(fontStyle: pw.FontStyle.italic))),
                 pw.Divider(borderStyle: pw.BorderStyle.dashed),
              ],

              // --- DESGLOSE TRIBUTARIO (RESTAURADO) ---
              pw.Builder(
                builder: (context) {
                  double baseTotal = 0.0;
                  Map<String, double> taxSummary = {};
                  for (var item in sale.items) {
                    final total = (item['total'] as num?)?.toDouble() ?? 0.0;
                    final taxRate = (item['taxRate'] as num?)?.toDouble() ?? 0.0;
                    final taxType = item['taxType'] as String? ?? 'EXCLUIDO';
                    if (taxRate > 0) {
                      final base = total / (1 + (taxRate / 100));
                      final tax = total - base;
                      baseTotal += base;
                      final key = '$taxType ${taxRate.toInt()}%';
                      taxSummary[key] = (taxSummary[key] ?? 0) + tax;
                    } else { baseTotal += total; }
                  }

                  if (taxSummary.isNotEmpty) {
                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8, top: 4),
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Text("Desglose Tributario", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                          pw.SizedBox(height: 2),
                          _buildRow("Base Total:", _currencyFormat.format(baseTotal), _smallStyle),
                          ...taxSummary.entries.map((e) => _buildRow(e.key, _currencyFormat.format(e.value), _smallStyle)),
                        ]
                      )
                    );
                  }
                  return pw.SizedBox.shrink();
                }
              ),

              // --- TOTAL FINAL ---
              _buildRow('TOTAL A PAGAR', _currencyFormat.format(sale.total), pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              
              pw.SizedBox(height: 10),
              pw.Text('Medios de Pago:', style: _boldStyle),
              ...sale.initialPayments.map((p) => _buildRow(' - ${p.method}${p.bankName != null ? " (${p.bankName})" : ""}', _currencyFormat.format(p.amount), _normalStyle)),
              
              if (sale.totalPaidReal > sale.total)
                 _buildRow('Cambio:', _currencyFormat.format(sale.totalPaidReal - sale.total), _boldStyle),

              // --- SECCIÓN LEGAL DIAN ---
              if (sale.isElectronicInvoice && sale.dianPrefix != null) ...[
                pw.SizedBox(height: 10),
                pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 1),
                pw.SizedBox(height: 5),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(5),
                  decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Column(
                    children: [
                      pw.Text('FACTURA ELECTRÓNICA DE VENTA', style: _boldStyle, textAlign: pw.TextAlign.center),
                      pw.SizedBox(height: 3),
                      pw.Text('${sale.dianPrefix}-${sale.dianNumber}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900), textAlign: pw.TextAlign.center),
                      pw.SizedBox(height: 3),
                      pw.Text('Este documento fue transmitido a la DIAN. Puede descargar el PDF oficial con firma digital desde su correo electrónico.', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
                    ]
                  )
                ),
              ],

              // --- PIE DE PÁGINA ---
              pw.SizedBox(height: 15),
              if (profile?.slogan.isNotEmpty == true)
                 pw.Container(width: double.infinity, child: pw.Text(profile!.slogan, style: _normalStyle.copyWith(fontStyle: pw.FontStyle.italic), textAlign: pw.TextAlign.center)),
              pw.SizedBox(height: 5),
              pw.Container(width: double.infinity, child: pw.Text('¡Gracias por su compra!', style: _boldStyle, textAlign: pw.TextAlign.center)),
              pw.SizedBox(height: 10),
            ]
          );
        },
      ),
    );
    return doc;
  }

  static Future<void> printTicket(Sale sale, CompanyProfile? profile) async {
    final doc = await _buildTicketDocument(sale, profile);
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  static Future<void> shareTicket(Sale sale, CompanyProfile? profile) async {
    final doc = await _buildTicketDocument(sale, profile);
    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Ticket_${sale.ticketNumber ?? sale.id}.pdf');
  }

  static pw.Widget _buildRow(String label, String value, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(value, style: style)],
      ),
    );
  }

  // -----------------------------------------------------------------------------
  // 2. REPORTE DE VENTAS (A4)
  // -----------------------------------------------------------------------------
  static Future<void> generateReport(List<Sale> sales, DateTimeRange? range) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader(
          title: 'Reporte de Ventas',
          subtitle: range != null 
            ? 'Periodo: ${DateFormat('dd MM yyyy').format(range.start)} - ${DateFormat('dd MM yyyy').format(range.end)}'
            : 'Histórico Completo'
        ),
        footer: _buildFooter,
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryCard('Total Ventas', _currencyFormat.format(sales.fold<double>(0, (sum, i) => sum + i.total)), PdfColors.blue50),
              _buildSummaryCard('Cantidad Trx', '${sales.length}', PdfColors.green50),
              _buildSummaryCard('Promedio Ticket', _currencyFormat.format(sales.isEmpty ? 0 : sales.fold<double>(0, (sum, i) => sum + i.total) / sales.length), PdfColors.orange50),
            ]
          ),
          pw.SizedBox(height: 20),
          pw.Table.fromTextArray(
            context: context,
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: _primaryColor),
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.centerRight,
            },
            cellPadding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 5),
            headers: ['FECHA', 'FACTURA', 'CLIENTE', 'MÉTODO', 'TOTAL'],
            data: sales.map((sale) => [
              DateFormat('dd/MM/yy HH:mm').format(sale.date),
              sale.id.substring(0, 6).toUpperCase(),
              sale.clientName ?? 'Mostrador',
              sale.paymentMethodsSummary,
              _currencyFormat.format(sale.total),
            ]).toList(),
          ),
          pw.SizedBox(height: 10),
          pw.Divider(color: _primaryColor),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'TOTAL GENERAL: ${_currencyFormat.format(sales.fold<double>(0, (sum, item) => sum + item.total))}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)
            ),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Reporte_Ventas_Konta.pdf');
  }

  // -----------------------------------------------------------------------------
  // 3. REPORTE DE GASTOS (A4) - ESTILO PROFESIONAL (CORREGIDO)
  // -----------------------------------------------------------------------------
  static Future<void> generateExpenseReport(List<Expense> expenses, DateTimeRange? range) async {
    final doc = pw.Document();

    // Colores corporativos
    final PdfColor primaryColor = PdfColors.red800;
    final PdfColor accentColor = PdfColors.red50;
    final PdfColor greyColor = PdfColors.grey200;

    // Cálculo de totales
    final double totalAmount = expenses.fold(0, (sum, e) => sum + e.amount);
    final int totalCount = expenses.length;
    final double totalPending = expenses.where((e) => e.isPending).fold(0, (sum, e) => sum + e.amount);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        
        header: (context) => _buildHeader(
          title: 'Reporte de Egresos',
          subtitle: range != null 
              ? '${DateFormat('dd/MM/yy').format(range.start)} - ${DateFormat('dd/MM/yy').format(range.end)}' 
              : 'Histórico Completo',
        ),
        
        footer: (context) => _buildFooter(context),
        
        build: (context) => [
          
          // --- 1. SECCIÓN DE RESUMEN (TARJETAS) ---
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Tarjeta 1: Total Gastado
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: accentColor,
                    borderRadius: pw.BorderRadius.circular(5),
                    border: pw.Border.all(color: primaryColor, width: 0.5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('TOTAL EGRESOS', style: pw.TextStyle(color: primaryColor, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 5),
                      pw.Text(_currencyFormat.format(totalAmount), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 15),
              // Tarjeta 2: Registros
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('CANTIDAD REGISTROS', style: pw.TextStyle(color: PdfColors.grey700, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 5),
                      pw.Text(totalCount.toString(), style: pw.TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 15),
               // Tarjeta 3: Deuda
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('DEUDA PENDIENTE', style: pw.TextStyle(color: PdfColors.grey700, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 5),
                      pw.Text(_currencyFormat.format(totalPending), style: pw.TextStyle(fontSize: 16, color: totalPending > 0 ? PdfColors.orange800 : PdfColors.black)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 25),

          // --- 2. TABLA DE DATOS (CORREGIDA) ---
          pw.Table.fromTextArray(
            headers: ['FECHA', 'CATEGORÍA', 'DESCRIPCIÓN', 'ESTADO', 'VALOR'],
            
            // Estilo del Encabezado
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            headerDecoration: pw.BoxDecoration(
              color: primaryColor,
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
            ),
            
            // Estilo de las Celdas y Padding General (Aplica a encabezado y celdas)
            cellStyle: const pw.TextStyle(fontSize: 9, color: PdfColors.grey900),
            cellPadding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            
            // Zebra Striping (Filas alternas grises)
            oddRowDecoration: pw.BoxDecoration(color: greyColor),
            
            // Alineaciones
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.centerRight,
            },

            // Datos
            data: expenses.map((e) => [
              DateFormat('dd/MM/yy').format(e.date),
              e.category.toUpperCase(),
              e.description.length > 25 ? '${e.description.substring(0, 25)}...' : e.description,
              e.isPending ? 'PENDIENTE' : 'PAGADO',
              _currencyFormat.format(e.amount),
            ]).toList(),
          ),

          // --- 3. SECCIÓN FINAL Y FIRMAS ---
          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey400, thickness: 0.5),
          pw.SizedBox(height: 10),
          
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generado por Konta App', 
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)
              ),
              // Total Final Grande
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Total Final:  ", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_currencyFormat.format(totalAmount), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Reporte_Gastos_Konta.pdf');
  }

  // -----------------------------------------------------------------------------
  // 4. ORDEN DE PAGO (A4 - NUEVA VERSIÓN GERENCIAL)
  // -----------------------------------------------------------------------------
  static Future<void> generatePaymentOrder({
    required List<Expense> selectedExpenses,
    required List<ProviderModel> providers,
    required CompanyProfile? profile,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();

    // 1. Agrupar gastos por proveedor
    final expensesByProvider = groupBy(selectedExpenses, (Expense e) => e.provider.trim());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        // Usamos un margen estándar
        margin: const pw.EdgeInsets.all(40),
        // Cabecera personalizada para este reporte
        header: (context) => _buildPaymentOrderHeader(profile, now),
        footer: _buildFooter,
        build: (context) => [
          // Mensaje informativo
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            margin: const pw.EdgeInsets.only(bottom: 20),
            decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(5)),
            child: pw.Row(children: [
              pw.Container(
                width: 20, height: 20,
                alignment: pw.Alignment.center,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.indigo, 
                  shape: pw.BoxShape.circle
                ),
                // Usamos una letra 'i' normal, que sí soportan todas las fuentes PDF
                child: pw.Text('i', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14, fontStyle: pw.FontStyle.italic))
              ),
              pw.SizedBox(width: 10),
              pw.Text(
                'Se han seleccionado ${selectedExpenses.length} cuentas pendientes para procesar pago.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.indigo900),
              ),
            ]),
          ),

          // Lista de proveedores y sus gastos
          ...expensesByProvider.entries.map((entry) {
            final providerName = entry.key;
            final expenses = entry.value;
            
            // Buscar datos del proveedor (banco, nit, etc)
            final providerData = providers.firstWhereOrNull(
              (p) => p.name.trim().toLowerCase() == providerName.toLowerCase()
            );

            // Calcular total del proveedor
            final totalProvider = expenses.fold<double>(0, (sum, e) => sum + e.balance);

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 25),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // A. Cabecera del Proveedor
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    color: PdfColors.indigo50,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(providerName.isEmpty ? 'PROVEEDOR GENERAL' : providerName, 
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                            if (providerData != null)
                              pw.Text("NIT/CC: ${providerData.nit}", style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                          ]
                        ),
                        // Datos Bancarios
                        if (providerData != null && providerData.accountNumber.isNotEmpty)
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text("DATOS PARA TRANSFERENCIA", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                              pw.Text("${providerData.bank} - ${providerData.accountType}", style: const pw.TextStyle(fontSize: 9)),
                              pw.Text("No. ${providerData.accountNumber}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                            ]
                          )
                        else
                          pw.Text("Sin datos bancarios registrados", style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.red)),
                      ]
                    )
                  ),
                  
                  pw.SizedBox(height: 5),

                  // B. Tabla de facturas
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2), // Concepto
                      1: const pw.FlexColumnWidth(2), // Observaciones
                      2: const pw.FlexColumnWidth(1), // Vence
                      3: const pw.FlexColumnWidth(1), // Saldo
                    },
                    children: [
                      // Encabezados
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          _buildCell('Concepto / Categoría', isBold: true),
                          _buildCell('Observaciones', isBold: true),
                          _buildCell('Vence', align: pw.Alignment.center, isBold: true),
                          _buildCell('Saldo', align: pw.Alignment.centerRight, isBold: true),
                        ]
                      ),
                      // Filas
                      ...expenses.map((e) => pw.TableRow(
                        children: [
                          _buildCell(e.description.isNotEmpty ? e.description : e.category),
                          _buildCell(e.observations, isItalic: true, fontSize: 8),
                          _buildCell(e.paymentDeadline != null ? _dateFormat.format(e.paymentDeadline!) : '-', align: pw.Alignment.center),
                          _buildCell(_currencyFormat.format(e.balance), align: pw.Alignment.centerRight, color: PdfColors.red900),
                        ]
                      )).toList(),
                    ]
                  ),

                  // C. Subtotal Proveedor
                  pw.Container(
                    alignment: pw.Alignment.centerRight,
                    padding: const pw.EdgeInsets.only(top: 5),
                    child: pw.Text(
                      "Total a pagar a $providerName: ${_currencyFormat.format(totalProvider)}",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)
                    ),
                  )
                ],
              ),
            );
          }).toList(),

          pw.Divider(thickness: 2, color: PdfColors.grey400),
          
          // Total General
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 10),
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text("TOTAL GENERAL A DISPERSAR", style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                pw.Text(
                  _currencyFormat.format(selectedExpenses.fold<double>(0, (sum, e) => sum + e.balance)), 
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)
                ),
              ]
            )
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Orden_Pago.pdf');
  }

  // -----------------------------------------------------------------------------
  // 5. ESTADO DE CUENTA
  // -----------------------------------------------------------------------------
  static Future<void> generateAccountStatement(Sale sale) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader(title: 'Estado de Cuenta', subtitle: 'Ref: ${sale.id.substring(0,8).toUpperCase()}'),
        footer: _buildFooter,
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(5),
                color: _accentColor
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('CLIENTE', style: _smallStyle),
                    pw.Text(sale.clientName ?? 'General', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 5),
                    if(sale.earliestDeadline != null)
                      pw.Text('FECHA LÍMITE PAGO', style: _smallStyle),
                    if(sale.earliestDeadline != null)
                      pw.Text(DateFormat('dd MMMM yyyy').format(sale.earliestDeadline!), style: pw.TextStyle(color: PdfColors.red, fontWeight: pw.FontWeight.bold)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text('SALDO PENDIENTE', style: _smallStyle),
                    pw.Text(_currencyFormat.format(sale.balance), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
                  ])
                ]
              )
            ),
            pw.SizedBox(height: 30),
            pw.Text('DETALLE DE MOVIMIENTOS', style: _subTitleStyle),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['FECHA', 'DESCRIPCIÓN', 'CARGO', 'ABONO'],
              headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: _greyColor),
              cellAlignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
              data: [
                [
                  DateFormat('dd/MM/yyyy').format(sale.date),
                  'Compra Factura #${sale.id.substring(0,6)}',
                  _currencyFormat.format(sale.total),
                  ''
                ],
                ...sale.payments.map((p) => [
                   DateFormat('dd/MM/yyyy').format(p.date),
                   'Abono: ${p.note.isEmpty ? "Pago Parcial" : p.note}',
                   '',
                   _currencyFormat.format(p.amount)
                ]),
              ]
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
               pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                 pw.Text('Total Facturado:   ${_currencyFormat.format(sale.total)}'),
                 pw.Text('Total Abonado:   -${_currencyFormat.format(sale.totalPaidReal)}'),
                 pw.SizedBox(width: 150, child: pw.Divider()),
                 pw.Text('SALDO FINAL:   ${_currencyFormat.format(sale.balance)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))
               ])
            ]),
            pw.Spacer(),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              color: PdfColors.grey100,
              child: pw.Center(child: pw.Text('Gracias por su preferencia.\nPor favor realice sus pagos antes de la fecha límite.', style: _smallStyle))
            )
          ];
        }
      )
    );
    await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Estado_Cuenta_${sale.clientName}.pdf');
  }

  // ===========================================================================
  // WIDGETS AUXILIARES
  // ===========================================================================

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
              pw.Text('Soluciones Contables', style: const pw.TextStyle(color: _greyColor, fontSize: 8)),
            ])
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(title, style: _titleStyle),
            pw.Text(subtitle, style: _normalStyle),
          ])
        ]
      )
    );
  }

  // [NUEVO] Header especial para la orden de pago (Muestra datos de TU empresa)
  static pw.Widget _buildPaymentOrderHeader(CompanyProfile? profile, DateTime date) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Columna Izquierda: Datos de TU Empresa
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(profile?.name.toUpperCase() ?? 'MI EMPRESA', 
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                if (profile != null) ...[
                  pw.Text("NIT: ${profile.nit}", style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(profile.address, style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(profile.phone, style: const pw.TextStyle(fontSize: 10)),
                ]
              ],
            ),
            // Columna Derecha: Datos del Reporte
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text("ORDEN DE PAGO", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                pw.Text("Fecha: ${_dateFormat.format(date)}", style: const pw.TextStyle(fontSize: 12)),
                pw.Text("Hora: ${DateFormat('HH:mm').format(date)}", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              ]
            )
          ]
        ),
        pw.SizedBox(height: 20),
        pw.Divider(color: PdfColors.indigo900, thickness: 1),
        pw.SizedBox(height: 10),
      ]
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
          pw.Text('Generado por Konta App', style: _smallStyle),
          pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: _smallStyle),
        ]
      )
    );
  }

  static pw.Widget _buildSummaryCard(String label, String value, PdfColor color) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.grey200)
      ),
      child: pw.Column(children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _greyColor)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _textColor)),
      ])
    );
  }

  // Helper para celdas de tabla
  static pw.Widget _buildCell(String text, {
    pw.Alignment align = pw.Alignment.centerLeft, 
    bool isBold = false, 
    bool isItalic = false,
    double fontSize = 9,
    PdfColor color = PdfColors.black
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text, 
          style: pw.TextStyle(
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, 
            fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
            fontSize: fontSize,
            color: color
          )
        ),
      )
    );
  }
}