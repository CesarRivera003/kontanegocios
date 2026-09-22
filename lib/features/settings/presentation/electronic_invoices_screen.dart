import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale_model.dart';
import '../../auth/presentation/auth_providers.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/credit_note_model.dart';
import '../domain/debit_note_model.dart';
import '../../finance/presentation/finance_providers.dart';

// ===========================================================================
// PROVIDER DE RIVERPOD PARA LAS NOTAS CRÉDITO
// ===========================================================================
final creditNotesStreamProvider = StreamProvider.autoDispose<List<CreditNote>>((ref) {
  final companyId = ref.watch(companyIdProvider).value;
  if (companyId == null || companyId.isEmpty) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('companies')
      .doc(companyId)
      .collection('credit_notes')
      .orderBy('date', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => CreditNote.fromMap(doc.data(), doc.id))
          .toList());
});


// ===========================================================================
// PROVIDER DE RIVERPOD PARA NOTAS DÉBITO
// ===========================================================================
final debitNotesStreamProvider = StreamProvider.autoDispose<List<DebitNote>>((ref) {
  final companyId = ref.watch(companyIdProvider).value;
  if (companyId == null || companyId.isEmpty) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('companies')
      .doc(companyId)
      .collection('debit_notes')
      .orderBy('date', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => DebitNote.fromMap(doc.data(), doc.id))
          .toList());
});

class ElectronicInvoicesScreen extends ConsumerStatefulWidget {
  const ElectronicInvoicesScreen({super.key});

  @override
  ConsumerState<ElectronicInvoicesScreen> createState() => _ElectronicInvoicesScreenState();
}

class _ElectronicInvoicesScreenState extends ConsumerState<ElectronicInvoicesScreen> {
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  // ===========================================================================
  // FUNCIONES DE UTILIDAD Y LLAMADAS A CLOUD FUNCTIONS (Mantenidas Intactas)
  // ===========================================================================

  Future<void> _launchPdf(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace')));
    }
  }

  Future<void> _downloadWebFile(String base64String, String fileName, String mimeType) async {
    final bytes = base64Decode(base64String);

    if (kIsWeb) {
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..style.display = 'none';
      
      html.document.body?.children.add(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    } else {
      try {
        Directory? directory;
        if (Platform.isAndroid) {
          directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        } else if (Platform.isWindows) {
          directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        final String filePath = '${directory!.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Archivo guardado en: $filePath'), duration: const Duration(seconds: 5)),
          );
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ Error al guardar: $e')));
      }
    }
  }

  Future<void> _downloadPlemsiPdf(String companyId, String cufe) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('obtenerPdfPlemsi');
      final resp = await callable.call({'companyId': companyId, 'cufe': cufe});
      
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); 
      
      if (resp.data['success'] == true) {
        final String base64String = resp.data['base64'];
        await _downloadWebFile(base64String, "Factura_$cufe.pdf", "application/pdf");
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error obteniendo PDF: $e')));
    }
  }

  void _showEmailDialog(String companyId, Sale sale) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reenviar Correo"),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: "ejemplo@correo.com", prefixIcon: Icon(Icons.email)),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.isEmpty || !ctrl.text.contains('@')) return;
              Navigator.pop(ctx); 
              
              showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
              try {
                final callable = FirebaseFunctions.instance.httpsCallable('reenviarCorreoPlemsi');
                await callable.call({'companyId': companyId, 'cufe': sale.cufe, 'email': ctrl.text.trim()});
                
                if (mounted) Navigator.of(context, rootNavigator: true).pop(); 
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📧 Correo enviado con éxito'), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) Navigator.of(context, rootNavigator: true).pop();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text("Enviar"),
          )
        ],
      ),
    );
  }

  void _showCreditNoteDialog(BuildContext context, Sale sale, String companyId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Emitir Nota Crédito", style: TextStyle(color: Colors.red)),
        content: const Text("¿Estás seguro de anular esta Factura?\n\nEsta acción informará a la DIAN y generará una Nota Crédito electrónica irreparable."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx); 
              showDialog(
                context: context, 
                barrierDismissible: false, 
                builder: (loaderCtx) {
                  _procesarAnulacion(loaderCtx, sale, companyId);
                  return const Center(child: CircularProgressIndicator());
                }
              );
            },
            child: const Text("Anular Factura", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Future<void> _procesarAnulacion(BuildContext loaderCtx, Sale sale, String companyId) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('emitirNotaCreditoPlemsi');
      final resp = await callable.call({
        'companyId': companyId,
        'saleId': sale.id, 
        'originalPrefix': sale.dianPrefix,
        'originalNumber': sale.dianNumber,
        'originalCufe': sale.cufe,
        'reason': 'Devolución de mercancía / Anulación de servicio',
      });
      
      if (loaderCtx.mounted) Navigator.pop(loaderCtx); // Cierra el loader de forma exacta
      
      if (resp.data['status'] == 'Aceptada') {
        // ===================================================================
        // 1. REVERSIÓN FINANCIERA (Efectivo y Bancos - Idéntico a ventas normales)
        // ===================================================================
        double cashAmount = 0;
        Map<String, double> bankReversals = {}; 

        for (var p in sale.initialPayments) {
          if (p.method == 'Efectivo') {
            cashAmount += p.amount;
          } 
          else if (p.method == 'Transferencia' && p.bankName != null && p.bankName!.isNotEmpty) {
            final bName = p.bankName!;
            bankReversals.update(bName, (value) => value + p.amount, ifAbsent: () => p.amount);
          }
        }

        final financeRepo = ref.read(financeRepositoryProvider);
        final desc = 'Anulación FE #${sale.dianPrefix}-${sale.dianNumber}';

        // A. Reversar Efectivo en Caja
        if (cashAmount > 0) {
          await financeRepo.registerReversal(
            amount: -cashAmount, 
            isCash: true, 
            description: desc
          );
        }

        // B. Reversar Bancos
        for (var entry in bankReversals.entries) {
          await financeRepo.registerReversal(
            amount: -entry.value, 
            isCash: false,
            bankName: entry.key, 
            description: '$desc (${entry.key})'
          );
        }

        // ===================================================================
        // 2. DEVOLVER PRODUCTOS AL INVENTARIO Y MARCAR COMO ANULADA
        // ===================================================================
        // Usamos el repositorio de ventas para devolver stock y cambiar el estado sin borrar el documento
        await ref.read(salesRepositoryProvider).annulElectronicSale(sale.id, sale.items);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Nota Crédito Aceptada: Inventario devuelto y caja actualizada'), 
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            )
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Rechazo DIAN: ${resp.data['error']}'), backgroundColor: Colors.red)
          );
        }
      }
    } catch (e) {
      if (loaderCtx.mounted) Navigator.pop(loaderCtx); 
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error crítico anulando: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  // ===========================================================================
  // CONSTRUCCIÓN DE LA INTERFAZ PRINCIPAL CON TABS
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesStreamProvider);
    final companyId = ref.watch(companyIdProvider).value ?? '';

    return DefaultTabController(
      length: 4, // 1. Facturas, 2. Notas Crédito, 3. Notas Débito, 4. Doc. Soporte
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Documentos Electrónicos DIAN"),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: "Facturas"),
              Tab(icon: Icon(Icons.assignment_return), text: "Notas Crédito"),
              Tab(icon: Icon(Icons.assignment_late), text: "Notas Débito"),
              Tab(icon: Icon(Icons.contact_mail), text: "Doc. Soporte"),
            ],
          ),
        ),
        backgroundColor: Colors.grey[100],
        body: Column(
          children: [
            // Filtros Globales (Afectarán al Tab activo)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Fecha: ${DateFormat('dd MMM yyyy').format(_selectedDate)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: const Text("Cambiar"),
                        onPressed: () async {
                          final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2030));
                          if (picked != null) setState(() => _selectedDate = picked);
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Buscar por cliente o ID...",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ""); }) : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ],
              ),
            ),

            // Vistas de los Tabs
            Expanded(
              child: TabBarView(
                children: [
                  _buildInvoicesList(salesAsync, companyId), // Tab 1: Facturas
                  _buildCreditNotesList(ref), // Tab 2: Notas Crédito
                  _buildDebitNotesList(),  // Tab 3: Notas Débito
                  _buildPlaceholder("Documentos Soporte\nPróximamente..."),       // Tab 4: Documento Soporte
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // WIDGETS EXTRAÍDOS PARA MANTENER EL CÓDIGO LIMPIO
  // ===========================================================================

  Widget _buildInvoicesList(AsyncValue<List<Sale>> salesAsync, String companyId) {
    return salesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text("Error: $e")),
      data: (allSales) {
        final filteredSales = allSales.where((s) {
          if (!s.isElectronicInvoice) return false;
          bool matchesDate = s.date.year == _selectedDate.year && s.date.month == _selectedDate.month && s.date.day == _selectedDate.day;
          bool matchesSearch = _searchQuery.isEmpty || (s.clientName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
          return matchesDate && matchesSearch;
        }).toList();

        if (filteredSales.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, 
              children: [
                Icon(Icons.search_off, size: 80, color: Colors.grey[400]), 
                const SizedBox(height: 15), 
                const Text("No hay facturas para esta fecha.", style: TextStyle(color: Colors.grey))
              ]
            )
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: filteredSales.length,
          itemBuilder: (context, index) {
            final sale = filteredSales[index];
            // 1. Validar si la factura está anulada (Ajusta 'sale.status' según tu modelo real en Firebase)
            bool isAnnulled = sale.dianStatus.toUpperCase() == 'ANULADA';

            Color statusColor = isAnnulled 
                ? Colors.red 
                : (sale.cufe != null ? Colors.green : (sale.dianStatus == 'Rechazada' ? Colors.red : Colors.orange));
            IconData statusIcon = isAnnulled 
                ? Icons.block 
                : (sale.cufe != null ? Icons.check_circle : (sale.dianStatus == 'Rechazada' ? Icons.error : Icons.sync));
            String displayId = sale.ticketNumber ?? "ID: ${sale.id.substring(0, 8).toUpperCase()}";

            return Card(
              elevation: isAnnulled ? 0 : 2, // Quitar relieve si está anulada
              color: isAnnulled ? Colors.red[50] : Colors.white, // Fondo rojizo tenue
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isAnnulled ? BorderSide(color: Colors.red.shade200, width: 1.5) : BorderSide.none, // Borde rojo
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: statusColor.withOpacity(0.1), 
                  child: Icon(statusIcon, color: statusColor)
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sale.clientName ?? 'Desconocido', 
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration: isAnnulled ? TextDecoration.lineThrough : null, // Tachado si está anulada
                          color: isAnnulled ? Colors.red[800] : Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isAnnulled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                        child: const Text("ANULADA", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayId, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                    if (sale.dianPrefix != null && sale.dianNumber != null)
                      Text("DIAN: ${sale.dianPrefix}-${sale.dianNumber}", style: const TextStyle(color: Colors.indigo, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text("Total: ${CurrencyFormatter.format(sale.total)}"),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (sale.cufe == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Factura pendiente, no tiene CUFE registrado')));
                      return;
                    }
                    if (value == 'dian' && sale.pdfUrl != null) _launchPdf(sale.pdfUrl!);
                    if (value == 'plemsi') _downloadPlemsiPdf(companyId, sale.cufe!);
                    if (value == 'correo') _showEmailDialog(companyId, sale);
                    if (value == 'anular') _showCreditNoteDialog(context, sale, companyId);
                  },
                  itemBuilder: (context) => [
                    if (sale.pdfUrl != null) const PopupMenuItem(value: 'dian', child: Row(children: [Icon(Icons.verified, color: Colors.blue, size: 20), SizedBox(width: 10), Text("Ver Validación DIAN")])),
                    const PopupMenuItem(value: 'plemsi', child: Row(children: [Icon(Icons.picture_as_pdf, color: Colors.red, size: 20), SizedBox(width: 10), Text("Descargar PDF Oficial")])),
                    const PopupMenuItem(value: 'correo', child: Row(children: [Icon(Icons.email, color: Colors.orange, size: 20), SizedBox(width: 10), Text("Reenviar por Correo")])),
                    // 2. Ocultar el botón de anular si ya está anulada
                    if (!isAnnulled)
                      const PopupMenuItem(value: 'anular', child: Row(children: [Icon(Icons.cancel_presentation, color: Colors.black54, size: 20), SizedBox(width: 10), Text("Emitir Nota Crédito")])),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Widget temporal para las pestañas en desarrollo
  Widget _buildPlaceholder(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildCreditNotesList(WidgetRef ref) {
    final creditNotesAsync = ref.watch(creditNotesStreamProvider);

    return creditNotesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text("Error: $e")),
      data: (allNotes) {
        final filteredNotes = allNotes.where((nc) {
          bool matchesDate = nc.date.year == _selectedDate.year && 
                            nc.date.month == _selectedDate.month && 
                            nc.date.day == _selectedDate.day;
          bool matchesSearch = _searchQuery.isEmpty || 
                              nc.originalFactura.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                              nc.ncNumber.toString().contains(_searchQuery);
          return matchesDate && matchesSearch;
        }).toList();

        if (filteredNotes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_return, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 15),
                const Text("No hay notas crédito para esta fecha.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: filteredNotes.length,
          itemBuilder: (context, index) {
            final nc = filteredNotes[index];
            String formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(nc.date);

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.redAccent,
                  child: Icon(Icons.receipt, color: Colors.white),
                ),
                title: Text("${nc.ncPrefix}-${nc.ncNumber}", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Factura Afectada: ${nc.originalFactura}", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                    Text("Fecha: $formattedDate", style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                  ],
                ),
                trailing: const Chip(
                  label: Text("DIAN Aceptada", style: TextStyle(color: Color.fromARGB(255, 6, 7, 6), fontSize: 11)),
                  backgroundColor: Color.fromARGB(117, 76, 175, 79),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDebitNotesList() {
    final debitNotesAsync = ref.watch(debitNotesStreamProvider);

    return debitNotesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text("Error: $e")),
      data: (allNotes) {
        final filteredNotes = allNotes.where((nd) {
          bool matchesDate = nd.date.year == _selectedDate.year && 
                            nd.date.month == _selectedDate.month && 
                            nd.date.day == _selectedDate.day;
          bool matchesSearch = _searchQuery.isEmpty || 
                              nd.originalFactura.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                              nd.ndNumber.toString().contains(_searchQuery);
          return matchesDate && matchesSearch;
        }).toList();

        if (filteredNotes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_late, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 15),
                const Text("No hay notas débito para esta fecha.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: filteredNotes.length,
          itemBuilder: (context, index) {
            final nd = filteredNotes[index];
            String formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(nd.date);

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: Icon(Icons.add_card, color: Colors.white),
                ),
                title: Text("${nd.ndPrefix}-${nd.ndNumber}", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Factura Afectada: ${nd.originalFactura}", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                    Text("Valor Adicional: ${CurrencyFormatter.format(nd.totalAdded)}", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
                    if (nd.reason.isNotEmpty) Text("Motivo: ${nd.reason}", style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                    Text("Fecha: $formattedDate", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                  ],
                ),
                trailing: Chip(
                  label: const Text("DIAN Aceptada", style: TextStyle(color: Colors.green, fontSize: 11)),
                  backgroundColor: Colors.green[100],
                ),
              ),
            );
          },
        );
      },
    );
  }
}