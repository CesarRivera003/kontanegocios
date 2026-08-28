import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// IMPORTS NECESARIOS
import '../../../core/utils/currency_formatter.dart';
import '../../sales/data/sales_repository.dart';
import '../../settings/data/settings_repository.dart'; // Para el perfil de empresa (si se usa en ticket)
import 'pdf_generator.dart';

// 1. IMPORTAMOS EL PROVIDER DE PERFIL PARA VERIFICAR PERMISOS
import '../../auth/presentation/user_profile_provider.dart';

import '../../finance/presentation/finance_providers.dart'; 

class SalesHistoryTab extends ConsumerStatefulWidget {
  const SalesHistoryTab({super.key});

  @override
  ConsumerState<SalesHistoryTab> createState() => _SalesHistoryTabState();
}

class _SalesHistoryTabState extends ConsumerState<SalesHistoryTab> {
  // --- CONTROLADORES Y ESTADO ---
  final TextEditingController _searchCtrl = TextEditingController();
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDateRange = DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // --- SELECTOR DE FECHAS ---
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final newRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _selectedDateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.blue),
          ),
          child: child!,
        );
      }
    );

    if (newRange != null) {
      setState(() => _selectedDateRange = newRange);
    }
  }

  // --- MÉTODO DE CONFIRMACIÓN DE ANULACIÓN (DEFINITIVO) ---
  void _confirmDeleteSale(BuildContext context, WidgetRef ref, String saleId) {
    // 1. OBTENER LA VENTA PARA VERIFICAR
    final allSales = ref.read(salesStreamProvider).value;
    final saleToDelete = allSales?.firstWhere((s) => s.id == saleId, orElse: () => throw Exception("Venta no encontrada"));

    if (saleToDelete == null) return;

    // 🔒 REGLA DE SEGURIDAD: IMPEDIR BORRAR SI YA TIENE ABONOS POSTERIORES
    if (saleToDelete.payments.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Acción Bloqueada', style: TextStyle(color: Colors.orange)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock, size: 50, color: Colors.orange),
              const SizedBox(height: 10),
              const Text(
                'No se puede anular esta venta porque ya tiene abonos registrados en fechas posteriores.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Esta medida protege la integridad de tu caja y bancos.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return; // <--- AQUÍ SE DETIENE SI HAY ABONOS
    }

    // --- SI PASA LA VALIDACIÓN, MOSTRAMOS LA CONFIRMACIÓN ---
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular Venta'),
        content: const Text(
          '¿Estás seguro de anular esta venta?\n\n'
          '⚠️ Se devolverán los productos al inventario.\n'
          '⚠️ Se restará el dinero de la caja y bancos correspondientes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); 
              
              // Pequeña espera para evitar cualquier congelamiento visual
              await Future.delayed(const Duration(milliseconds: 300));

              try {
                // --- LÓGICA MULTI-BANCO ---
                double cashAmount = 0;
                Map<String, double> bankReversals = {}; 

                void processPaymentList(List<dynamic> payments) {
                  for (var p in payments) {
                    if (p.method == 'Efectivo') {
                      cashAmount += p.amount;
                    } 
                    else if (p.method == 'Transferencia' && p.bankName != null && p.bankName!.isNotEmpty) {
                      final bName = p.bankName!;
                      bankReversals.update(bName, (value) => value + p.amount, ifAbsent: () => p.amount);
                    }
                  }
                }

                // Procesamos solo pagos iniciales (porque los posteriores están vacíos si llegamos aquí)
                processPaymentList(saleToDelete.initialPayments);

                // --- EJECUTAR REVERSIONES ---
                final financeRepo = ref.read(financeRepositoryProvider);
                final desc = 'Anulación Venta #${saleToDelete.id.substring(0,5).toUpperCase()}';

                // A. Efectivo
                if (cashAmount > 0) {
                  await financeRepo.registerReversal(
                    amount: -cashAmount, 
                    isCash: true, 
                    description: desc
                  );
                }

                // B. Bancos (Bucle para reversar cada banco por separado)
                for (var entry in bankReversals.entries) {
                  await financeRepo.registerReversal(
                    amount: -entry.value, 
                    isCash: false,
                    bankName: entry.key, 
                    description: '$desc (${entry.key})'
                  );
                }

                // --- ELIMINAR LA VENTA ---
                await ref.read(salesRepositoryProvider).deleteSale(saleId);

                if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Venta anulada correctamente'), backgroundColor: Colors.green)
                  );
                }
              } catch (e) {
                if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
                  );
                }
              }
            },
            child: const Text('ANULAR', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. OBTENEMOS LAS VENTAS
    final salesAsync = ref.watch(salesStreamProvider);

    // 2. OBTENEMOS LOS PERMISOS DEL USUARIO ACTUAL
    final userProfile = ref.watch(userProfileProvider).value;
    // Solo permitimos borrar si el rol es Admin o Manager (según tu modelo canDeleteItems)
    final bool canAnnullSale = userProfile?.canDeleteItems ?? false; 

    return salesAsync.when(
      data: (allSales) {
        
        // --- LÓGICA DE FILTRADO ---
        final filteredSales = allSales.where((sale) {
          final query = _searchCtrl.text.toLowerCase();
          final clientName = sale.clientName?.toLowerCase() ?? '';
          final saleId = sale.id.toLowerCase();
          
          // Filtro Texto
          final matchesText = clientName.contains(query) || saleId.contains(query);
          if (!matchesText) return false;

          // Filtro Fecha
          if (_selectedDateRange != null) {
            final saleDate = DateTime(sale.date.year, sale.date.month, sale.date.day);
            final start = _selectedDateRange!.start;
            final end = _selectedDateRange!.end;
            
            final normalizedStart = DateTime(start.year, start.month, start.day);
            final normalizedEnd = DateTime(end.year, end.month, end.day);

            return (saleDate.isAtSameMomentAs(normalizedStart) || 
                    saleDate.isAtSameMomentAs(normalizedEnd) || 
                    (saleDate.isAfter(normalizedStart) && saleDate.isBefore(normalizedEnd)));
          }
          return true;
        }).toList();

        if (allSales.isEmpty) return const Center(child: Text("No se encontraron ventas"));

        return Column(
          children: [
            // --- BARRA DE BÚSQUEDA Y FECHAS ---
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar cliente o folio...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 15),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                      onChanged: (_) => setState((){}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.calendar_month),
                    style: IconButton.styleFrom(backgroundColor: Colors.blue[50], foregroundColor: Colors.blue[800]),
                  ),
                ],
              ),
            ),

            // --- LÓGICA INTELIGENTE DEL CHIP DE FECHAS ---
            Builder(
              builder: (context) {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                
                // 1. Detectar si el filtro actual es exactamente "Hoy"
                final isTodayFilter = _selectedDateRange != null && 
                                      _selectedDateRange!.start.isAtSameMomentAs(today) && 
                                      _selectedDateRange!.end.isAtSameMomentAs(today);

                // 2. Mostrar el Chip SOLO si el usuario seleccionó una fecha diferente a "Hoy"
                if (_selectedDateRange != null && !isTodayFilter) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        InputChip(
                          label: Text(
                            _selectedDateRange!.start.isAtSameMomentAs(_selectedDateRange!.end)
                                ? DateFormat('dd/MM/yy').format(_selectedDateRange!.start)
                                : '${DateFormat('dd/MM/yy').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM/yy').format(_selectedDateRange!.end)}',
                            style: TextStyle(color: Colors.blue[900], fontSize: 12)
                          ),
                          backgroundColor: Colors.blue[50],
                          // 3. Al cerrar el filtro de fechas antiguas, regresamos silenciosamente a "Hoy"
                          onDeleted: () => setState(() => _selectedDateRange = DateTimeRange(start: today, end: today)),
                          deleteIcon: const Icon(Icons.close, size: 16, color: Colors.blue),
                        ),
                      ],
                    ),
                  );
                }
                
                // Si el filtro es "Hoy", no mostramos nada y ahorramos espacio en la pantalla
                return const SizedBox.shrink(); 
              }
            ),

            // --- BOTÓN EXPORTAR REPORTE ---
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("Exportar Reporte"),
                  onPressed: () => PdfGenerator.generateReport(filteredSales, null), 
                ),
              ),
            ),

            // --- LISTA DE VENTAS ---
            Expanded(
              child: filteredSales.isEmpty 
              ? const Center(child: Text('No hay ventas con estos filtros'))
              : ListView.builder(
                padding: const EdgeInsets.only(bottom: 150, top: 0, left: 10, right: 10),
                itemCount: filteredSales.length,
                itemBuilder: (context, index) {
                  final sale = filteredSales[index]; 
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    elevation: 2,
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[100],
                        child: const Icon(Icons.receipt, color: Colors.blue),
                      ),
                      title: Row(
                        children: [
                          Text(
                            sale.ticketNumber ?? 'Factura #${sale.id.substring(0, 6).toUpperCase()}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (sale.isElectronicInvoice) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50, 
                                borderRadius: BorderRadius.circular(4), 
                                border: Border.all(color: Colors.indigo.shade200)
                              ),
                              child: const Text('DIAN', style: TextStyle(color: Colors.indigo, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          ]
                        ],
                      ),
                      subtitle: Text(
                        '${DateFormat('dd/MM/yyyy HH:mm').format(sale.date)} - ${sale.clientName ?? 'General'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            CurrencyFormatter.format(sale.total),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14),
                          ),
                          Text(sale.paymentMethodsSummary, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. LISTA DE PRODUCTOS
                              const Text("Productos:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 5),
                              ...sale.items.map((i) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text("${i['quantity']} x ${i['name']}")),
                                    Text(CurrencyFormatter.format((i['total'] as num).toDouble())),
                                  ],
                                ),
                              )),

                              // 2. COSTOS ADICIONALES
                              if (sale.additionalCosts.isNotEmpty) ...[
                                const Divider(),
                                const Text("Adicionales:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                                const SizedBox(height: 5),
                                ...sale.additionalCosts.map((cost) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(cost['reason'] ?? 'Cargo Extra', style: const TextStyle(color: Colors.black87)),
                                      Text(
                                        CurrencyFormatter.format((cost['amount'] as num).toDouble()),
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                                      ),
                                    ],
                                  ),
                                )),
                              ],
                              
                              // Vendedor (Opcional, si quieres mostrar quién vendió)
                              if (sale.sellerName != null) ...[
                                const SizedBox(height: 10),
                                Text("Atendido por: ${sale.sellerName}", style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                              ],

                              const Divider(),

                              // 3. BOTONES DE ACCIÓN
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Botón Ticket (Siempre visible para todos)
                                  TextButton.icon(
                                    icon: const Icon(Icons.print),
                                    label: const Text("Ticket"),
                                    onPressed: () async {
                                      try {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generando...'), duration: Duration(milliseconds: 500)));
                                        final profile = ref.read(companyProfileProvider).value;
                                        await PdfGenerator.printTicket(sale, profile);
                                      } catch (e) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error PDF: $e')));
                                      }
                                    },
                                  ),
                                  
                                  const SizedBox(width: 10),
                                  
                                  // --- PROTECCIÓN DE SEGURIDAD ---
                                  // Solo mostramos "Anular" si el usuario tiene permiso (canDeleteItems/canAnnullSale)
                                  if (canAnnullSale)
                                    if (sale.isElectronicInvoice)
                                      TextButton.icon(
                                        icon: const Icon(Icons.block, color: Colors.grey),
                                        label: const Text("Nota Crédito", style: TextStyle(color: Colors.grey)),
                                        onPressed: () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('⚠️ Esta es una Factura Electrónica. Para anularla, ve a "Configuración > Gestión de Facturas" y emite una Nota Crédito.'),
                                              backgroundColor: Colors.orange,
                                              duration: Duration(seconds: 4),
                                            )
                                          );
                                        },
                                      )
                                    else
                                      TextButton.icon(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        label: const Text("Anular", style: TextStyle(color: Colors.red)),
                                        onPressed: () => _confirmDeleteSale(context, ref, sale.id),
                                      )
                                ],
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text("Error: $e")),
    );
  }
}