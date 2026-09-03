import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale_model.dart';
import '../../auth/presentation/auth_providers.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ElectronicInvoicesScreen extends ConsumerStatefulWidget {
  const ElectronicInvoicesScreen({super.key});

  @override
  ConsumerState<ElectronicInvoicesScreen> createState() => _ElectronicInvoicesScreenState();
}

class _ElectronicInvoicesScreenState extends ConsumerState<ElectronicInvoicesScreen> {
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  Future<void> _launchPdf(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace')));
    }
  }

  // Función para procesar y descargar archivos en Web, Android y Windows
  Future<void> _downloadWebFile(String base64String, String fileName, String mimeType) async {
    final bytes = base64Decode(base64String);

    if (kIsWeb) {
      // 1. Lógica nativa para navegadores WEB
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
      // 2. Lógica nativa para ANDROID y WINDOWS
      try {
        Directory? directory;
        if (Platform.isAndroid) {
          // Usa descargas o almacenamiento externo en Android
          directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        } else if (Platform.isWindows) {
          // Usa la carpeta de descargas en Windows
          directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        final String filePath = '${directory!.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        // Muestra una notificación con la ruta donde se guardó
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Archivo guardado en: $filePath'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('⚠️ Error al guardar: $e')),
          );
        }
      }
    }
  }

  Future<void> _downloadPlemsiPdf(String companyId, String cufe) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('obtenerPdfPlemsi');
      final resp = await callable.call({'companyId': companyId, 'cufe': cufe});
      
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // Cierre forzado del dialog
      
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
              Navigator.pop(ctx); // Cierra el input de correo
              
              showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
              try {
                final callable = FirebaseFunctions.instance.httpsCallable('reenviarCorreoPlemsi');
                await callable.call({'companyId': companyId, 'cufe': sale.cufe, 'email': ctrl.text.trim()});
                
                if (mounted) Navigator.of(context, rootNavigator: true).pop(); // Cierra el indicador de carga
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
              Navigator.pop(ctx); // 1. Cierra el cuadro de diálogo de confirmación
              
              // 2. Abre el loader y le pasa su PROPIO contexto a la función que hace el llamado
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

  // 3. Función aislada que maneja la llamada y usa el loaderCtx para cerrarse a sí misma
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Nota Crédito Emitida y Aceptada'), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Rechazo DIAN: ${resp.data['error']}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (loaderCtx.mounted) Navigator.pop(loaderCtx); // Cierra el loader si hay fallo crítico
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error crítico anulando: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesStreamProvider);
    final companyId = ref.watch(companyIdProvider).value ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text("Gestión de Facturas (DIAN)")),
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
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
                    hintText: "Buscar por cliente...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ""); }) : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ],
            ),
          ),

          Expanded(
            child: salesAsync.when(
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
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.search_off, size: 80, color: Colors.grey[400]), const SizedBox(height: 15), const Text("No hay facturas para esta fecha.", style: TextStyle(color: Colors.grey))]));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: filteredSales.length,
                  itemBuilder: (context, index) {
                    final sale = filteredSales[index];
                    
                    Color statusColor = sale.cufe != null ? Colors.green : (sale.dianStatus == 'Rechazada' ? Colors.red : Colors.orange);
                    IconData statusIcon = sale.cufe != null ? Icons.check_circle : (sale.dianStatus == 'Rechazada' ? Icons.error : Icons.sync);
                    
                    String displayId = sale.ticketNumber ?? "ID: ${sale.id.substring(0, 8).toUpperCase()}";

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: statusColor.withOpacity(0.1), child: Icon(statusIcon, color: statusColor)),
                        title: Text(sale.clientName ?? 'Desconocido', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                            const PopupMenuItem(value: 'anular', child: Row(children: [Icon(Icons.cancel_presentation, color: Colors.black54, size: 20), SizedBox(width: 10), Text("Emitir Nota Crédito")])),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}