import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// IMPORTS CORE Y UTILS
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/currency_input_formatter.dart';

// IMPORTS VENTAS
import '../../sales/domain/sale_model.dart';
import '../../sales/data/sales_repository.dart';
import 'pdf_generator.dart';

// IMPORTS TESORERÍA (Para cargar bancos y registrar ingreso)
import '../../finance/presentation/finance_providers.dart';
import '../../finance/domain/finance_model.dart';

// IMPORTS AUTH (Para saber quién registra el pago)
import '../../auth/presentation/user_profile_provider.dart';

import '../../cash/data/cash_repository.dart';
import '../../cash/domain/cash_transaction_model.dart';

class AccountsReceivableScreen extends ConsumerStatefulWidget {
  const AccountsReceivableScreen({super.key});

  @override
  ConsumerState<AccountsReceivableScreen> createState() => _AccountsReceivableScreenState();
}

class _AccountsReceivableScreenState extends ConsumerState<AccountsReceivableScreen> {
  bool _showPaidHistory = false; // Estado para el filtro

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesStreamProvider);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Cuentas por Cobrar"),
        actions: [
          // SWITCH PARA VER HISTORIAL
          Row(
            children: [
              Text(_showPaidHistory ? "Ver Pendientes" : "Ver Pagadas", style: const TextStyle(fontSize: 12)),
              Switch(
                value: _showPaidHistory,
                onChanged: (val) => setState(() => _showPaidHistory = val),
              ),
            ],
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: salesAsync.when(
        data: (allSales) {
          // 1. FILTRADO (Créditos pendientes vs Pagados)
          final receivables = allSales.where((s) {
            // Filtramos solo las que son crédito (tienen fecha límite) O tienen saldo pendiente
            final isCredit = s.initialPayments.any((p) => p.method == 'Crédito');
            if (!isCredit && s.balance <= 0) return false; // Ignorar ventas de contado ya pagadas

            if (_showPaidHistory) {
              return s.balance <= 100; // Consideramos pagado si debe menos de $100 (ajuste por decimales)
            } else {
              return s.balance > 100; // Pendientes
            }
          }).toList();

          if (receivables.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_showPaidHistory ? Icons.history : Icons.check_circle_outline, size: 60, color: Colors.grey),
                  const SizedBox(height: 10),
                  Text(
                    _showPaidHistory ? "No hay historial de créditos pagados." : "¡Excelente! No tienes cuentas por cobrar pendientes.",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // 2. ORDENAMIENTO (Prioridad: Vencidas -> Próximas a Vencer -> Lejanas)
          receivables.sort((a, b) {
            final deadlineA = _getDeadline(a);
            final deadlineB = _getDeadline(b);
            return deadlineA.compareTo(deadlineB);
          });

          // CÁLCULO TOTAL CARTERA
          final totalReceivable = receivables.fold(0.0, (sum, s) => sum + s.balance);

          return Column(
            children: [
              // TARJETA RESUMEN
              if (!_showPaidHistory)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.blue.shade600]),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
                  ),
                  child: Column(
                    children: [
                      const Text('Total Cartera por Cobrar', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 5),
                      Text(CurrencyFormatter.format(totalReceivable), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

              // LISTA
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 100),
                  itemCount: receivables.length,
                  itemBuilder: (context, index) {
                    final sale = receivables[index];
                    final deadline = _getDeadline(sale);
                    final daysUntilDue = deadline.difference(DateTime.now()).inDays;
                    final isOverdue = daysUntilDue < 0;
                    
                    // Color según urgencia
                    Color statusColor;
                    String statusText;
                    
                    if (sale.balance <= 100) {
                      statusColor = Colors.green;
                      statusText = "PAGADO";
                    } else if (isOverdue) {
                      statusColor = Colors.red;
                      statusText = "VENCIDA (${daysUntilDue.abs()} días)";
                    } else if (daysUntilDue <= 3) {
                      statusColor = Colors.orange;
                      statusText = "Vence pronto ($daysUntilDue días)";
                    } else {
                      statusColor = Colors.blue;
                      statusText = "Vence: ${DateFormat('dd/MM').format(deadline)}";
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: statusColor.withOpacity(0.3))),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.1),
                          child: Icon(Icons.calendar_today, color: statusColor, size: 20),
                        ),
                        title: Text(sale.clientName ?? 'Cliente General', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Factura: ${sale.id.substring(0,5).toUpperCase()}'),
                            Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(CurrencyFormatter.format(sale.balance), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                            const Text("Saldo", style: TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                        children: [
                          _buildDetailSection(context, ref, sale),
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
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  // --- OBTENER FECHA LÍMITE (Helper) ---
  DateTime _getDeadline(Sale sale) {
    try {
      final creditPayment = sale.initialPayments.firstWhere((p) => p.method == 'Crédito');
      return creditPayment.paymentDeadline ?? sale.date.add(const Duration(days: 30));
    } catch (_) {
      return sale.date.add(const Duration(days: 30)); // Default 30 días si no encuentra fecha
    }
  }

  Widget _buildDetailSection(BuildContext context, WidgetRef ref, Sale sale) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Factura:'),
              Text(CurrencyFormatter.format(sale.total), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Abonado:'),
              Text(CurrencyFormatter.format(sale.totalPaidReal), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(),
          const Text("Historial de Abonos:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 5),
          
          if (sale.payments.isEmpty)
             const Text("Sin abonos registrados.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12))
          else
             ...sale.payments.map((p) {
               // Intentamos acceder a los nuevos campos si existen, si no, fallbacks
               // NOTA: Esto asume que actualizaste SalePayment en sale_model.dart
               // Si el campo 'method' no existe en tu modelo viejo, dará error de compilación.
               // Asegúrate de agregar los campos al modelo como indiqué arriba.
               String methodInfo = '';
               try { methodInfo = " • ${(p as dynamic).method}"; } catch(_){}
               
               return Padding(
                 padding: const EdgeInsets.symmetric(vertical: 4),
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     Expanded(
                       child: Text(
                         '${DateFormat('dd/MM').format(p.date)} - ${p.note}$methodInfo',
                         style: const TextStyle(fontSize: 12),
                         overflow: TextOverflow.ellipsis,
                       )
                     ),
                     Text(CurrencyFormatter.format(p.amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                   ],
                 ),
               );
             }),
          
          const Divider(),
          
          // BOTONES DE ACCIÓN
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Estado Cuenta'),
                onPressed: () => PdfGenerator.generateAccountStatement(sale),
              ),
              const SizedBox(width: 10),
              
              // Solo mostrar botón Abonar si hay deuda
              if (sale.balance > 100)
                ElevatedButton.icon(
                  icon: const Icon(Icons.payments, size: 18),
                  label: const Text('Abonar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800], 
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                  ),
                  onPressed: () => _showAddPaymentDialog(context, ref, sale),
                ),
            ],
          )
        ],
      ),
    );
  }

  // --- DIÁLOGO DE ABONO MEJORADO ---
  void _showAddPaymentDialog(BuildContext context, WidgetRef ref, Sale sale) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    
    // Variables de estado local del diálogo
    String selectedMethod = 'Efectivo';
    String? selectedBankId;

    // Cargamos cuentas para el dropdown
    final accountsAsync = ref.read(bankAccountsProvider); 

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Registrar Abono'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Saldo pendiente:"),
                        Text(CurrencyFormatter.format(sale.balance), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  // 1. MONTO
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [CurrencyInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Monto a recibir', 
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder()
                    ),
                  ),
                  const SizedBox(height: 15),

                  // 2. MÉTODO DE PAGO
                  const Text("Método de Pago:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    children: ['Efectivo', 'Transferencia', 'Tarjeta'].map((m) {
                      final isSelected = selectedMethod == m;
                      return ChoiceChip(
                        label: Text(m),
                        selected: isSelected,
                        onSelected: (v) => setState(() => selectedMethod = m),
                        selectedColor: Colors.blue[100],
                        labelStyle: TextStyle(color: isSelected ? Colors.blue[900] : Colors.black),
                      );
                    }).toList(),
                  ),

                  // 3. BANCO (Solo si es Transferencia)
                  if (selectedMethod == 'Transferencia') ...[
                    const SizedBox(height: 10),
                    accountsAsync.when(
                      data: (accounts) {
                        final banks = accounts.where((a) => !a.isCash && a.isActive).toList();
                        if (banks.isEmpty) return const Text("⚠️ No hay bancos registrados", style: TextStyle(color: Colors.orange, fontSize: 12));
                        
                        return DropdownButtonFormField<String>(
                          value: selectedBankId,
                          hint: const Text("Seleccionar Banco"),
                          isExpanded: true,
                          items: banks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                          onChanged: (val) => setState(() => selectedBankId = val),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)
                          ),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (_,__) => const SizedBox.shrink(),
                    )
                  ],

                  const SizedBox(height: 15),
                  
                  // 4. NOTA
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nota / Referencia', 
                      prefixIcon: Icon(Icons.comment),
                      border: OutlineInputBorder()
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                onPressed: () async {
                  final cleanAmount = amountCtrl.text.replaceAll(',', '');
                  final amount = double.tryParse(cleanAmount) ?? 0;
                  
                  if (amount <= 0 || amount > sale.balance + 1) { 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monto inválido')));
                    return;
                  }
                  if (selectedMethod == 'Transferencia' && selectedBankId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona el banco destino')));
                    return;
                  }

                  // SALVAVIDAS: Atrapamos errores para cerrar el modal
                  try {
                    final userProfile = ref.read(userProfileProvider).value;
                    final userName = userProfile?.name ?? 'Usuario';

                    final payment = SalePayment(
                      date: DateTime.now(),
                      amount: amount,
                      note: noteCtrl.text.isEmpty ? 'Abono cartera' : noteCtrl.text,
                      method: selectedMethod, 
                      recordedBy: userName,   
                    );

                    await ref.read(salesRepositoryProvider).addPaymentToSale(sale.id, payment);

                    // TESORERÍA BLINDADA
                    final accounts = accountsAsync.value ?? [];
                    String? targetAccountId;

                    if (selectedMethod == 'Efectivo') {
                      final cashAccounts = accounts.where((a) => a.isCash && a.isActive).toList();
                      if (cashAccounts.isNotEmpty) {
                        final defaultCash = cashAccounts.where((a) => a.isDefault).toList();
                        targetAccountId = defaultCash.isNotEmpty ? defaultCash.first.id : cashAccounts.first.id;
                      }
                    } else if (selectedMethod == 'Transferencia') {
                      targetAccountId = selectedBankId;
                    }

                    if (targetAccountId != null) {
                      await ref.read(financeRepositoryProvider).addTransaction(BankTransaction(
                        id: '',
                        accountId: targetAccountId,
                        type: 'INCOME', 
                        amount: amount,
                        description: 'Abono Factura #${sale.id.substring(0,5).toUpperCase()} (${sale.clientName})',
                        date: DateTime.now(),
                        relatedDocId: sale.id,
                      ));
                    }

                    // CAJA
                    if (selectedMethod == 'Efectivo') {
                      final cashTx = CashTransaction(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        amount: amount,
                        type: CashTransactionType.income, 
                        description: 'Abono Cartera: ${sale.clientName} (Fac. ${sale.id.substring(0,5).toUpperCase()})',
                        date: DateTime.now(),
                        userId: userProfile?.id ?? '', 
                      );
                      await ref.read(cashRepositoryProvider).addCashMovement(cashTx);
                    }

                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Abono registrado correctamente'), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                     if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                     }
                  }
                },
                child: const Text('Confirmar Pago'),
              )
            ],
          );
        }
      ),
    );
  }
}