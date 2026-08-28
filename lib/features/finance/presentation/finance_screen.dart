import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// Imports Core
import '../../../core/utils/currency_formatter.dart';

// Imports Finanzas
import '../domain/finance_model.dart';
import 'finance_providers.dart';
import 'account_detail_screen.dart';

// Imports Ventas (Para el Datáfono)
import '../../sales/data/sales_repository.dart';
import '../../../core/utils/currency_input_formatter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../cash/data/cash_repository.dart';
import '../../auth/presentation/user_profile_provider.dart';
import '../../home/presentation/dashboard_shell.dart';

// =============================================================================
// CEREBRO: CÁLCULO EN VIVO DE CAJAS (A PRUEBA DE FALLOS Y CIERRES)
// =============================================================================
final liveCashRegistersProvider = FutureProvider<Map<String, double>>((ref) async {
  final companyId = ref.watch(companyIdProvider).value;
  final currentUser = ref.watch(userProfileProvider).value; 
  if (companyId == null) return {};

  final firestore = FirebaseFirestore.instance;
  final cashRepo = ref.read(cashRepositoryProvider); 

  Map<String, double> balances = {};

  final usersSnap = await firestore.collection('companies').doc(companyId).collection('users').get();
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  // --- 1. NUEVO: BUSCAR QUIÉNES YA CERRARON CAJA HOY ---
  final closuresSnap = await firestore.collection('companies').doc(companyId).collection('cash_closures')
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
      .where('date', isLessThan: Timestamp.fromDate(endOfDay)).get();

  // Guardamos a los que cerraron y su base de mañana en un mapa {userId: baseParaMañana}
  Map<String, double> closedUsers = {};
  for (var doc in closuresSnap.docs) {
    final data = doc.data();
    final uid = data['userId'] as String?;
    final nextBase = (data['nextDayBase'] ?? 0).toDouble();
    if (uid != null) closedUsers[uid] = nextBase;
  }

  // Traer entradas y salidas manuales
  final moveSnap = await firestore.collection('companies').doc(companyId).collection('cash_movements')
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
      .where('date', isLessThan: Timestamp.fromDate(endOfDay)).get();

  // --- 2. CREAMOS UNA LISTA CON TODOS ---
  List<Map<String, dynamic>> allUsersToEvaluate = [];
  if (currentUser != null) {
    allUsersToEvaluate.add({
      'id': currentUser.id ?? companyId,
      'name': currentUser.name,
      'role': currentUser.role.name,
    });
  }
  // B. Agregamos a los empleados
  for (var doc in usersSnap.docs) {
    // ¡LA SOLUCIÓN! Si el empleado de la BD es el mismo dueño que ya agregamos arriba, lo saltamos
    if (currentUser != null && doc.id == currentUser.id) continue;
    
    allUsersToEvaluate.add({
      'id': doc.id,
      'name': doc.data()['name'] ?? 'Usuario',
      'role': doc.data()['role'] ?? 'cashier',
    });
  }

  // --- 3. REVISAMOS LA CAJA DE CADA UNO ---
  for (var u in allUsersToEvaluate) {
    final userId = u['id'];
    final userName = u['name'];
    final role = u['role'];

    // Verificamos si este usuario está en la lista de cajas cerradas
    final isClosed = closedUsers.containsKey(userId);
    
    double balance = 0;
    double salesTotal = 0;
    double baseTotal = 0;

    if (isClosed) {
      // ¡MAGIA! Si está cerrada, ignoramos las ventas y solo mostramos la base de mañana
      balance = closedUsers[userId]!;
    } else {
      // Si está abierta, hacemos la matemática normal
      final totals = await cashRepo.getUserDailyTotals(userName: userName, canHaveExpenses: true);
      final base = await cashRepo.getBaseDraft(userId);
      salesTotal = totals['sales']!;
      baseTotal = base;

      double manualIn = 0;
      double manualOut = 0;

      for (var m in moveSnap.docs) {
        if (m.data()['userId'] == userId) {
          final amt = (m.data()['amount'] ?? 0).toDouble();
          final typeStr = m.data()['type'].toString().trim().toLowerCase();
          
          if (typeStr == 'income' || typeStr == '0' || typeStr.contains('ingreso') || typeStr == 'in') {
            manualIn += amt;
          } else {
            manualOut += amt;
          }
        }
      }
      balance = (base + salesTotal + manualIn) - (totals['expenses']! + manualOut);
    }

    // Filtro para mostrar solo a quienes tienen movimiento o dejaron caja cerrada
    if (balance > 0 || salesTotal > 0 || baseTotal > 0 || isClosed) {
      String displayName = (role == 'admin' || role == 'Dueño') ? 'Admin ($userName)' : userName;
      
      // Le agregamos la etiqueta visual para que el Administrador sepa que ya terminaron turno
      if (isClosed) displayName += ' (Cerrada)'; 
      
      if (!balances.containsKey(displayName)) {
         balances[displayName] = balance;
      }
    }
  }

  return balances;
});

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Usamos DefaultTabController para las pestañas (Cuentas | Datáfono)
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          // --- NUEVO: BOTÓN HAMBURGUESA PARA MÓVIL ---
          leading: MediaQuery.of(context).size.width <= 900 ? IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => DashboardShell.scaffoldKey.currentState?.openDrawer(),
          ) : null,
          title: const Text('Tesorería y Cuentas'),
          elevation: 0,
          actions: [
            // Botón rápido para Nueva Transferencia (Solo visible en la primera pestaña idealmente, 
            // pero lo dejamos aquí para acceso rápido)
            Consumer(
              builder: (context, ref, _) {
                final accountsAsync = ref.watch(bankAccountsProvider);
                return IconButton(
                  icon: const Icon(Icons.compare_arrows),
                  tooltip: 'Nueva Transferencia',
                  onPressed: () => _showTransferDialog(context, ref, accountsAsync.value ?? []),
                );
              },
            )
          ],
          bottom: const TabBar(
            labelColor: Colors.indigo,
            indicatorColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: "Cuentas y Efectivo", icon: Icon(Icons.account_balance_wallet)),
              Tab(text: "Datáfono / Tarjetas", icon: Icon(Icons.credit_card)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AccountsListTab(),     // Pestaña 1: Cajas y Bancos
            _CardsSummaryTab(),     // Pestaña 2: Datáfono
          ],
        ),
      ),
    );
  }

  // --- DIALOGO TRANSFERENCIAS (Provisiones / Recogidas) ---
  void _showTransferDialog(BuildContext context, WidgetRef ref, List<BankAccount> accounts) {
    if (accounts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Necesitas al menos 2 cuentas para transferir.")));
      return;
    }

    String? sourceId;
    String? destId;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Transferencia de Fondos"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Sirve para: Provisiones a cajeros, Recogida de dinero, Consignaciones, etc.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 15),
                  
                  // ORIGEN
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Origen (Sale el dinero)', border: OutlineInputBorder()),
                    value: sourceId,
                    items: accounts.map((a) => DropdownMenuItem(
                      value: a.id, 
                      child: Text("${a.name} (\$${CurrencyFormatter.format(a.balance)})", style: const TextStyle(fontSize: 13))
                    )).toList(),
                    onChanged: (val) => setState(() => sourceId = val),
                  ),
                  const SizedBox(height: 10),
                  
                  // ICONO FLECHA
                  const Icon(Icons.arrow_downward, color: Colors.grey),
                  const SizedBox(height: 10),

                  // DESTINO
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Destino (Entra el dinero)', border: OutlineInputBorder()),
                    value: destId,
                    items: accounts.where((a) => a.id != sourceId).map((a) => DropdownMenuItem( // Excluir origen
                      value: a.id, 
                      child: Text(a.name, style: const TextStyle(fontSize: 13))
                    )).toList(),
                    onChanged: (val) => setState(() => destId = val),
                  ),
                  const SizedBox(height: 15),

                  // MONTO
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [CurrencyInputFormatter()], // <--- Formateador
                    decoration: const InputDecoration(labelText: 'Monto a Transferir', prefixText: '\$ ', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  
                  // NOTA
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Nota (Opcional)', hintText: 'Ej: Provisión fin de semana', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: () async {
                  // CORRECCIÓN: Expresión regular para ignorar letras, comas o símbolos del teclado móvil
                  final String cleanText = amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                  final amount = double.tryParse(cleanText) ?? 0.0;
                  
                  // --- ALERTA DE VALIDACIÓN ---
                  if (sourceId == null || destId == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Por favor selecciona origen, destino y un monto mayor a 0."), backgroundColor: Colors.orange)
                    );
                    return; // Detenemos el guardado
                  }
                  if (sourceId == destId) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("El origen y destino no pueden ser la misma cuenta."), backgroundColor: Colors.orange)
                    );
                    return;
                  }

                  final sourceAccount = accounts.firstWhere((a) => a.id == sourceId);
                  final destAccount = accounts.firstWhere((a) => a.id == destId);

                  await ref.read(financeRepositoryProvider).transferFunds(
                    sourceAccountId: sourceId!,
                    destinationAccountId: destId!,
                    amount: amount,
                    description: "${sourceAccount.name} -> ${destAccount.name} (${noteCtrl.text})",
                  );
                  
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transferencia exitosa"), backgroundColor: Colors.green));
                  }
                },
                child: const Text('Transferir', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      ),
    );
  }
}

// =============================================================================
// PESTAÑA 1: LISTA DE CUENTAS (CAJAS Y BANCOS)
// =============================================================================
class _AccountsListTab extends ConsumerStatefulWidget {
  const _AccountsListTab();

  @override
  ConsumerState<_AccountsListTab> createState() => _AccountsListTabState();
}

class _AccountsListTabState extends ConsumerState<_AccountsListTab> {
  bool _showArchived = false; // Estado del filtro

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(bankAccountsProvider);

    return accountsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
      data: (accounts) {
        // Filtramos según si queremos ver archivadas o no
        final visibleAccounts = accounts.where((a) => _showArchived ? !a.isActive : a.isActive).toList();

        final cashAccounts = visibleAccounts.where((a) => a.isCash).toList();
        final bankAccounts = visibleAccounts.where((a) => !a.isCash).toList();

        // Calculamos totales SIEMPRE con las activas (para no falsear la realidad financiera actual)
        final activeAccounts = accounts.where((a) => a.isActive).toList();
        final double totalCash = activeAccounts.where((a) => a.isCash).fold(0, (sum, item) => sum + item.balance);
        final double totalBank = activeAccounts.where((a) => !a.isCash).fold(0, (sum, item) => sum + item.balance);
        
        final liveRegistersAsync = ref.watch(liveCashRegistersProvider);
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // =========================================================
              // 1. PANEL AVANZADO: DISTRIBUCIÓN DE EFECTIVO
              // =========================================================
              
              liveRegistersAsync.when(
                data: (cashierBalances) {
                  // SUMAMOS LA PLATA DE LOS CAJEROS Y CALCULAMOS LA CAJA FUERTE
                  double sumCashiers = cashierBalances.values.fold(0.0, (a, b) => a + b);
                  double mainSafe = totalCash - sumCashiers;

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade700, Colors.green.shade900],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("DISTRIBUCIÓN DE EFECTIVO", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),                            
                            InkWell(
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Actualizando saldos...'), duration: Duration(seconds: 1)));
                                // ref.invalidate obliga a recalcular todo desde la base de datos
                                ref.invalidate(liveCashRegistersProvider);
                              },
                              child: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                            )
                          ],
                        ),
                        const SizedBox(height: 10),
                        
                        // GLOBAL TESORERÍA
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Total General (Tesorería):", style: TextStyle(color: Colors.white, fontSize: 16)),
                            Text(CurrencyFormatter.format(totalCash), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Divider(color: Colors.white30, height: 25),
                        
                        // CAJA FUERTE (Resta Matemática)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.shield, color: Colors.amber, size: 18),
                                SizedBox(width: 8),
                                Text("Caja Principal (Fuerte):", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Text(CurrencyFormatter.format(mainSafe), style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        
                        // LISTA DE CAJEROS EN CURSO
                        if (cashierBalances.isNotEmpty) ...[
                          const SizedBox(height: 15),
                          ...cashierBalances.entries.map((e) => Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.point_of_sale, color: Colors.white70, size: 16),
                                    const SizedBox(width: 8),
                                    Text("Turno: ${e.key}", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                  ],
                                ),
                                Text(CurrencyFormatter.format(e.value), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ))
                        ],
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
                error: (e, _) => Text("Error cargando cajas: $e"),
              ),
              
              const SizedBox(height: 15),

              // TARJETA DE BANCOS (Queda debajo para equilibrar el diseño)
              _TotalCard(title: 'Total en Bancos', amount: totalBank, color: Colors.indigo, icon: Icons.account_balance),
              
              const SizedBox(height: 15),
              // =========================================================
              
              // TOGGLE VER ARCHIVADAS
              if (_showArchived || accounts.any((a) => !a.isActive)) 
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showArchived = !_showArchived),
                    icon: Icon(_showArchived ? Icons.visibility_off : Icons.visibility, size: 16, color: Colors.grey),
                    label: Text(_showArchived ? "Ocultar cuentas eliminadas" : "Ver cuentas eliminadas", style: const TextStyle(color: Colors.grey)),
                  ),
                ),

              const SizedBox(height: 10),

              if (_showArchived)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange[50],
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text("Estás viendo el historial de cuentas eliminadas. Restauralas para usarlas.", style: TextStyle(fontSize: 11, color: Colors.orange))),
                    ],
                  ),
                ),
              
              const SizedBox(height: 10),

              // 2. SECCIÓN CAJAS

              // 2. SECCIÓN CAJAS
              _SectionHeader(title: 'Cajas y Efectivo', icon: Icons.point_of_sale, onAdd: () => _showAddAccountDialog(context, ref, isCash: true)),
              if (cashAccounts.isEmpty) _EmptyState(text: "No tienes cajas registradas"),
              ...cashAccounts.map((acc) => _AccountTile(account: acc)),

              const SizedBox(height: 25),

              // 3. SECCIÓN BANCOS
              _SectionHeader(title: 'Cuentas Bancarias', icon: Icons.account_balance, onAdd: () => _showAddAccountDialog(context, ref, isCash: false)),
              if (bankAccounts.isEmpty) _EmptyState(text: "No tienes bancos registrados."),
              ...bankAccounts.map((acc) => _AccountTile(account: acc)),
              
              const SizedBox(height: 50), // Espacio extra abajo
            ],
          ),
        );
      },
    );
  }

  void _showAddAccountDialog(BuildContext context, WidgetRef ref, {required bool isCash}) {
    final nameCtrl = TextEditingController();
    final balanceCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCash ? 'Nueva Caja de Efectivo' : 'Nueva Cuenta Bancaria'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Nombre', 
                hintText: isCash ? 'Ej: Caja Menor, Caja Principal' : 'Ej: Nequi, Bancolombia',
                border: const OutlineInputBorder()
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: balanceCtrl,
              keyboardType: TextInputType.number,
              // --- NUEVO: FORMATEADOR DE MILES ---
              inputFormatters: [CurrencyInputFormatter()], 
              decoration: const InputDecoration(labelText: 'Saldo Inicial', border: OutlineInputBorder(), prefixText: '\$ '),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              // --- CORRECCIÓN: Limpiar el formato antes de guardar ---
              final cleanBalance = balanceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
              final balance = double.tryParse(cleanBalance) ?? 0.0;
              
              if (name.isNotEmpty) {
                final newAccount = BankAccount(
                  id: '', 
                  name: name, 
                  balance: balance,
                  isCash: isCash,
                  isDefault: false // Por defecto no es la principal al crearla
                );
                await ref.read(financeRepositoryProvider).createAccount(newAccount);
                if (context.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PESTAÑA 2: DATÁFONO / TARJETAS 
// =============================================================================
class _CardsSummaryTab extends ConsumerWidget {
  const _CardsSummaryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Usamos el stream global para tener acceso a ventas viejas (por si pagan un abono hoy)
    final salesAsync = ref.watch(salesStreamProvider);

    return salesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text("Error cargando ventas: $e")),
      data: (allSales) {
        
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final todayEnd = todayStart.add(const Duration(days: 1));

        // Lista temporal para recolectar todos los movimientos de tarjeta de hoy
        List<Map<String, dynamic>> cardMovements = [];
        double totalCards = 0;

        for (var sale in allSales) {
          // A. REVISAR PAGO INICIAL (Si la venta fue HOY)
          if (sale.date.isAfter(todayStart) && sale.date.isBefore(todayEnd)) {
            for (var payment in sale.initialPayments) {
              // FILTRO ESTRICTO: Solo 'Tarjeta'. 
              // Quitamos 'Crédito' para que no tome las ventas fiadas.
              if (payment.method == 'Tarjeta') {
                totalCards += payment.amount;
                cardMovements.add({
                  'type': 'Venta',
                  'docId': sale.id,
                  'amount': payment.amount,
                  'date': sale.date,
                  'info': 'Venta Directa',
                });
              }
            }
          }

          // B. REVISAR ABONOS (Sale.payments)
          // Estos pueden ser de hoy, incluso si la venta es vieja
          for (var payment in sale.payments) {
            if (payment.date.isAfter(todayStart) && payment.date.isBefore(todayEnd)) {
              // Verificamos si el abono se hizo con Tarjeta
              if (payment.method == 'Tarjeta') {
                totalCards += payment.amount;
                cardMovements.add({
                  'type': 'Abono',
                  'docId': sale.id,
                  'amount': payment.amount,
                  'date': payment.date,
                  'info': 'Abono Cartera',
                });
              }
            }
          }
        }

        // Ordenamos por hora (del más reciente al más antiguo)
        cardMovements.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Movimientos de Datáfono (Hoy)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              // Tarjetas Resumen
              Row(
                children: [
                  Expanded(
                    child: _TotalCard(
                      title: "Transacciones", 
                      amount: cardMovements.length.toDouble(), 
                      icon: Icons.receipt_long, 
                      color: Colors.orange
                    )
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _TotalCard(
                      title: "Total Datáfono", 
                      amount: totalCards, 
                      icon: Icons.credit_card, 
                      color: Colors.blue
                    )
                  ),
                ],
              ),
              
              const SizedBox(height: 30),
              
              if (cardMovements.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.credit_card_off, size: 40, color: Colors.grey),
                        SizedBox(height: 10),
                        Text("No hay cobros con tarjeta hoy.", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: cardMovements.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = cardMovements[index];
                      final isSale = item['type'] == 'Venta';
                      
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[50],
                          child: Icon(isSale ? Icons.shopping_bag : Icons.account_balance_wallet, color: Colors.blue, size: 20),
                        ),
                        title: Text(
                          "${item['type']} #${item['docId'].toString().substring(0,5).toUpperCase()}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "${DateFormat('HH:mm').format(item['date'])} • ${item['info']}",
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Text(
                          CurrencyFormatter.format(item['amount']), 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// WIDGETS AUXILIARES
// =============================================================================

class _TotalCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;

  const _TotalCard({required this.title, required this.amount, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    // Si el titulo es "Transacciones", mostramos entero, si no, moneda
    final valueStr = title == 'Transacciones' ? amount.toStringAsFixed(0) : CurrencyFormatter.format(amount);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 20, color: color), const SizedBox(width: 8), Expanded(child: Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)))]),
          const SizedBox(height: 8),
          Text(valueStr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final BankAccount account;
  const _AccountTile({required this.account});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: account.isCash ? Colors.green[50] : Colors.blue[50],
          child: Icon(account.isCash ? Icons.money : Icons.account_balance, color: account.isCash ? Colors.green : Colors.blue, size: 20),
        ),
        title: Row(
          children: [
            Text(account.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            // ESTRELLA SI ES PRINCIPAL (DEFAULT)
            if (account.isDefault) 
              const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.star, size: 16, color: Colors.amber)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(CurrencyFormatter.format(account.balance), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: account.balance < 0 ? Colors.red : Colors.black87)),
            const SizedBox(width: 5),
            const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
          ],
        ),
        onTap: () {
          // --- AQUÍ ESTÁ LA MAGIA PARA PANTALLA COMPLETA ---
          // rootNavigator: true le dice a Flutter "Salte del Shell (menú) y monta esto encima de todo"
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => AccountDetailScreen(account: account)),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onAdd;
  const _SectionHeader({required this.title, required this.icon, required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [Icon(icon, color: Colors.grey[700]), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
        TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_circle, size: 16), label: const Text("Crear"))
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(20), alignment: Alignment.center, child: Text(text, style: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic)));
  }
}