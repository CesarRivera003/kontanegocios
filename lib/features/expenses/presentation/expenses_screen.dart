import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../home/presentation/dashboard_shell.dart';

// Imports de Utilidades y Modelos
import '../../../core/utils/currency_formatter.dart';
import '../../sales/presentation/pdf_generator.dart';

// Imports del Módulo de Gastos
import '../domain/expense_model.dart'; 
import 'expense_providers.dart';
import 'accounts_payable_screen.dart'; 

import '../../finance/presentation/finance_providers.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  const ExpensesScreen({super.key, this.initialIndex = 0});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2, 
      vsync: this, 
      initialIndex: widget.initialIndex
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    return Scaffold(
      appBar: AppBar(
        leading: isMobile ? IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => DashboardShell.scaffoldKey.currentState?.openDrawer(),
        ): null,
        title: const Text('Control de Gastos'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.red,
          labelColor: Colors.red,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'HISTORIAL', icon: Icon(Icons.history)),
            Tab(text: 'POR PAGAR', icon: Icon(Icons.money_off)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/save-expense'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Gasto'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ExpensesHistoryTab(),
          AccountsPayableScreen(),
        ],
      ),
    );
  }
}

// --- PESTAÑA DE HISTORIAL REDISEÑADA ---
class _ExpensesHistoryTab extends ConsumerStatefulWidget {
  const _ExpensesHistoryTab();

  @override
  ConsumerState<_ExpensesHistoryTab> createState() => _ExpensesHistoryTabState();
}

class _ExpensesHistoryTabState extends ConsumerState<_ExpensesHistoryTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  DateTimeRange? _selectedDateRange;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final newRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _selectedDateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Colors.red)),
        child: child!,
      )
    );

    if (newRange != null) setState(() => _selectedDateRange = newRange);
  }

  void _confirmDeleteExpense(Expense expense) {
    if (expense.isPending && expense.payments.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Acción Bloqueada', style: TextStyle(color: Colors.orange)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.lock_clock, size: 50, color: Colors.orange),
              SizedBox(height: 10),
              Text(
                'No puedes eliminar una Cuenta por Pagar que ya tiene abonos realizados.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                'Esto descuadraría tu caja. Elimina primero los abonos individuales.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Gasto'),
        content: const Text('Esta acción borrará el registro y devolverá el dinero a la tesorería. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              
              await Future.delayed(const Duration(milliseconds: 300));
              
              try {
                if (!expense.isPending) {
                  final financeRepo = ref.read(financeRepositoryProvider);
                  
                  await financeRepo.registerReversal(
                    amount: expense.amount, 
                    isCash: expense.paymentMethod == 'Efectivo',
                    // SALVAVIDAS APLICADO AQUÍ
                    bankName: expense.bankName ?? (expense.paymentMethod == 'Transferencia' ? 'Bancolombia' : null),
                    description: 'Anulación Gasto: ${expense.description}'
                  );
                }

                await ref.read(expenseRepositoryProvider).deleteExpense(expense.id);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Gasto eliminado y saldo restaurado'))
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesStreamProvider);

    return expensesAsync.when(
      data: (allExpenses) {
        // --- LÓGICA DE FILTRADO ---
        final filteredExpenses = allExpenses.where((expense) {
          final query = _searchCtrl.text.toLowerCase();
          final matchesText = expense.description.toLowerCase().contains(query) || expense.category.toLowerCase().contains(query);
          if (!matchesText) return false;

          if (_selectedDateRange != null) {
            final eDate = DateTime(expense.date.year, expense.date.month, expense.date.day);
            final start = _selectedDateRange!.start;
            final end = _selectedDateRange!.end;
            final nStart = DateTime(start.year, start.month, start.day);
            final nEnd = DateTime(end.year, end.month, end.day);
            return eDate.isAtSameMomentAs(nStart) || eDate.isAtSameMomentAs(nEnd) || (eDate.isAfter(nStart) && eDate.isBefore(nEnd));
          }
          return true;
        }).toList();

        // Totales simples (menos ruido visual)
        final totalFiltered = filteredExpenses.fold(0.0, (sum, e) => sum + e.amount); 

        return Column(
          children: [
            // 1. BARRA DE BUSQUEDA LIMPIA
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar...',
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                      onChanged: (_) => setState((){}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _pickDateRange,
                    icon: Icon(Icons.calendar_month, color: _selectedDateRange != null ? Colors.red : Colors.grey),
                    tooltip: "Filtrar Fechas",
                  ),
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.grey),
                    tooltip: "Reporte PDF",
                    onPressed: () => PdfGenerator.generateExpenseReport(filteredExpenses, _selectedDateRange),
                  ),
                ],
              ),
            ),
            
            // Resumen sutil
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: Colors.grey[50],
              child: Text(
                "Total en lista: ${CurrencyFormatter.format(totalFiltered)}",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 13),
                textAlign: TextAlign.end,
              ),
            ),

            // 2. LISTA EXPANDIBLE
            Expanded(
              child: filteredExpenses.isEmpty 
              ? const Center(child: Text("No se encontraron gastos"))
              : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100, top: 5),
                itemCount: filteredExpenses.length,
                itemBuilder: (context, index) {
                  final expense = filteredExpenses[index];
                  // Tarjeta personalizada
                  return _ExpenseCard(
                    expense: expense, 
                    onDelete: () => _confirmDeleteExpense(expense),
                    onEdit: () => context.push('/save-expense', extra: expense),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
    );
  }
}

// --- WIDGET TARJETA EXPANDIBLE (NUEVO DISEÑO) ---
class _ExpenseCard extends StatelessWidget {
  final Expense expense;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ExpenseCard({required this.expense, required this.onDelete, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final bool isPaid = !expense.isPending;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          // Icono principal
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPaid ? Colors.green[50] : Colors.orange[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPaid ? Icons.check : Icons.access_time_filled,
              color: isPaid ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
          // Información Resumida
          title: Text(
            expense.description,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Text(DateFormat('dd/MM').format(expense.date), style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(expense.category, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            ],
          ),
          trailing: Text(
            CurrencyFormatter.format(expense.amount),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          
          // DETALLES AL EXPANDIR
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(thickness: 0.5),
                  _DetailRow(icon: Icons.person_outline, label: "Registrado por:", value: expense.userName.isEmpty ? 'Admin' : expense.userName),
                  if (expense.provider.isNotEmpty)
                    _DetailRow(icon: Icons.store_mall_directory_outlined, label: "Proveedor:", value: expense.provider),
                  _DetailRow(icon: Icons.payment, label: "Método:", value: expense.paymentMethod),
                  if (expense.observations.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text("Nota: ${expense.observations}", style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                    ),
                  
                  const SizedBox(height: 15),
                  
                  // BOTONES DE ACCIÓN (SOLO VISIBLES AL EXPANDIR)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text("Eliminar"),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text("Editar Detalle"),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo, side: const BorderSide(color: Colors.indigo)),
                      ),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(width: 5),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}