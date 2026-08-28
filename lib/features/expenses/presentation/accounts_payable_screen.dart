import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/currency_input_formatter.dart';

import '../../sales/presentation/pdf_generator.dart';
import '../domain/expense_model.dart';
import 'expense_providers.dart';
import '../../clients/presentation/client_providers.dart'; 
import '../../settings/data/settings_repository.dart'; 
import '../../auth/presentation/user_profile_provider.dart';
import '../../finance/presentation/finance_providers.dart';
import '../../finance/domain/finance_model.dart';

class AccountsPayableScreen extends ConsumerStatefulWidget {
  const AccountsPayableScreen({super.key});

  @override
  ConsumerState<AccountsPayableScreen> createState() => _AccountsPayableScreenState();
}

class _AccountsPayableScreenState extends ConsumerState<AccountsPayableScreen> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesStreamProvider);
    final providersAsync = ref.watch(providersStreamProvider);
    final profileAsync = ref.watch(companyProfileProvider);

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: _selectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () async {
                final allExpenses = expensesAsync.asData?.value;
                if (allExpenses == null) return; 
                final selected = allExpenses.where((e) => _selectedIds.contains(e.id)).toList();
                final providers = providersAsync.asData?.value ?? []; 
                final profile = profileAsync.asData?.value; 
                await PdfGenerator.generatePaymentOrder(selectedExpenses: selected, providers: providers, profile: profile);
              },
              icon: const Icon(Icons.print),
              label: Text('Generar Orden (${_selectedIds.length})'),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            )
          : null,
      body: expensesAsync.when(
        data: (allExpenses) {
          var payables = allExpenses.where((e) => e.isPending && !e.isFullyPaid).toList();
          payables.sort((a, b) {
            if (a.paymentDeadline == null) return 1;
            if (b.paymentDeadline == null) return -1;
            return a.paymentDeadline!.compareTo(b.paymentDeadline!);
          });

          if (payables.isEmpty) return const Center(child: Text("¡Excelente! No tienes cuentas por pagar."));

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 100, top: 10, left: 10, right: 10),
            itemCount: payables.length,
            itemBuilder: (context, index) {
              final expense = payables[index];
              final isSelected = _selectedIds.contains(expense.id);
              
              final daysLeft = expense.paymentDeadline != null ? expense.paymentDeadline!.difference(DateTime.now()).inDays : 0;
              final isOverdue = daysLeft < 0;
              final statusColor = isOverdue ? Colors.red : (daysLeft <= 3 ? Colors.orange : Colors.green);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                shape: RoundedRectangleBorder(side: BorderSide(color: statusColor, width: 1.5), borderRadius: BorderRadius.circular(10)),
                child: ExpansionTile(
                  leading: Checkbox(
                    value: isSelected, 
                    activeColor: Colors.indigo,
                    onChanged: (val) => setState(() => val == true ? _selectedIds.add(expense.id) : _selectedIds.remove(expense.id)),
                  ),
                  title: Text(expense.provider.isNotEmpty ? expense.provider : expense.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    expense.paymentDeadline != null ? (isOverdue ? "VENCIDA" : "Vence en $daysLeft días") : "Sin fecha", 
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)
                  ),
                  trailing: Text(CurrencyFormatter.format(expense.balance), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: statusColor)),
                  children: [_buildDetailSection(expense)],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildDetailSection(Expense expense) {
    final obsCtrl = TextEditingController(text: expense.observations);

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Observaciones (Igual que antes)
          TextField(
            controller: obsCtrl,
            decoration: InputDecoration(
              labelText: 'Observaciones', 
              isDense: true, 
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.save, color: Colors.blue),
                onPressed: () {
                  ref.read(expenseRepositoryProvider).updateObservation(expense.id, obsCtrl.text);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado')));
                }
              )
            ),
          ),
          const SizedBox(height: 15),

          // --- HISTORIAL DE ABONOS MEJORADO ---
          const Text("Historial de Abonos:", style: TextStyle(fontWeight: FontWeight.bold)),
          if (expense.payments.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text("Sin abonos.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)))
          else
            ...expense.payments.map((p) {
              // Determinamos info del método para mostrar
              final methodInfo = p.paymentMethod == 'Transf. - Tarjeta Db' && p.bankName != null 
                  ? 'Transf. (${p.bankName})' 
                  : p.paymentMethod;

              return Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.green[50], shape: BoxShape.circle),
                      child: const Icon(Icons.attach_money, size: 16, color: Colors.green),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(CurrencyFormatter.format(p.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            "${DateFormat('dd/MM/yyyy').format(p.date)} • ${p.userName}", 
                            style: const TextStyle(fontSize: 11, color: Colors.grey)
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(methodInfo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.indigo)),
                        if(p.note.isNotEmpty)
                          Text(p.note, style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
                      ],
                    )
                  ],
                ),
              );
            }),

          const Divider(height: 20),
          
          // BOTONES DE ACCIÓN
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add_card),
                label: const Text("Registrar Abono"),
                onPressed: () => _showAddPaymentDialog(expense, initialAmount: 0),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                icon: const Icon(Icons.check_circle),
                label: const Text("Pagar Todo"),
                // "Pagar Todo" ahora abre el diálogo con el monto lleno
                onPressed: () => _showAddPaymentDialog(expense, initialAmount: expense.balance, isFullPayment: true),
              ),
            ],
          )
        ],
      ),
    );
  }

  // --- DIÁLOGO CONECTADO A TESORERÍA ---
  void _showAddPaymentDialog(Expense expense, {double initialAmount = 0, bool isFullPayment = false}) {
    final amountCtrl = TextEditingController(text: initialAmount > 0 ? initialAmount.toStringAsFixed(0) : '');
    final noteCtrl = TextEditingController(text: isFullPayment ? 'Pago Total / Saldado' : '');
    
    // Variables de estado
    String selectedMethod = 'Efectivo'; 
    String? selectedBankId; // Guardamos el ID de la cuenta real

    // Leemos las cuentas de tesorería
    final accountsAsync = ref.read(bankAccountsProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFullPayment ? 'Saldar Deuda Total' : 'Registrar Abono'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Saldo actual: ${CurrencyFormatter.format(expense.balance)}'),
                  const SizedBox(height: 10),
                  
                  // 1. MONTO
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [CurrencyInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Monto', prefixIcon: Icon(Icons.attach_money)),
                  ),
                  const SizedBox(height: 10),
                  
                  // 2. MÉTODO
                  DropdownButtonFormField<String>(
                    value: selectedMethod,
                    decoration: const InputDecoration(labelText: 'Medio de Pago', prefixIcon: Icon(Icons.payment)),
                    items: ['Efectivo', 'Transferencia', 'Otros'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) => setState(() {
                      selectedMethod = val!;
                      if (selectedMethod != 'Transferencia') selectedBankId = null;
                    }),
                  ),

                  // 3. SELECTOR DE BANCO (Solo si es Transferencia)
                  if (selectedMethod == 'Transferencia') ...[
                    const SizedBox(height: 10),
                    accountsAsync.when(
                      data: (accounts) {
                        // Filtramos solo bancos activos
                        final banks = accounts.where((a) => !a.isCash && a.isActive).toList();
                        return DropdownButtonFormField<String>(
                          value: selectedBankId,
                          decoration: const InputDecoration(labelText: 'Banco', prefixIcon: Icon(Icons.account_balance)),
                          items: banks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                          onChanged: (val) => setState(() => selectedBankId = val!),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (_,__) => const SizedBox(),
                    )
                  ],

                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Nota', prefixIcon: Icon(Icons.comment)),
                  ),
                ],
              ),
            );
          }
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final cleanAmount = amountCtrl.text.replaceAll(',', '');
              final amount = double.tryParse(cleanAmount) ?? 0;
              
              if (amount <= 0 || amount > expense.balance + 100) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monto inválido')));
                return;
              }
              
              // SALVAVIDAS: Atrapamos cualquier error para que el modal no se quede trabado
              try {
                final userProfile = ref.read(userProfileProvider).value;
                
                final payment = ExpensePayment(
                  date: DateTime.now(),
                  amount: amount,
                  note: noteCtrl.text,
                  paymentMethod: selectedMethod, 
                  userId: userProfile?.id ?? '', 
                  userName: userProfile?.name ?? 'Admin', 
                  bankName: selectedBankId != null ? accountsAsync.asData?.value.firstWhere((a) => a.id == selectedBankId).name : null, 
                );

                await ref.read(expenseRepositoryProvider).addPayment(expense.id, payment);

                // INTEGRACIÓN TESORERÍA BLINDADA
                final financeRepo = ref.read(financeRepositoryProvider);
                final accounts = accountsAsync.asData?.value ?? [];
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
                  await financeRepo.addTransaction(BankTransaction(
                    id: '',
                    accountId: targetAccountId,
                    type: 'EXPENSE',
                    amount: amount,
                    description: 'Pago Gasto: ${expense.provider} - ${expense.category}',
                    date: DateTime.now(),
                    relatedDocId: expense.id,
                  ));
                }

                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abono registrado y descontado de caja'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Registrar'),
          )
        ],
      ),
    );
  }
}