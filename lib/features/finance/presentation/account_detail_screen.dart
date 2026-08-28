import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/currency_formatter.dart';
import '../domain/finance_model.dart';
import 'finance_providers.dart';
import '../../../core/utils/currency_input_formatter.dart';

class AccountDetailScreen extends ConsumerStatefulWidget {
  final BankAccount account;
  const AccountDetailScreen({super.key, required this.account});

  @override
  ConsumerState<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  DateTimeRange? _selectedRange;

  @override
  Widget build(BuildContext context) {
    // Escuchamos las transacciones
    final transactionsAsync = ref.watch(transactionsProvider(widget.account.id));
    
    // MAGIA DE TIEMPO REAL: Buscamos la cuenta actualizada en el provider global
    final accountsAsync = ref.watch(bankAccountsProvider);
    final currentAccount = accountsAsync.value?.firstWhere(
      (a) => a.id == widget.account.id, 
      orElse: () => widget.account
    ) ?? widget.account;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currentAccount.name, style: const TextStyle(fontSize: 18)),
            if (currentAccount.isCash)
              Text(
                currentAccount.isDefault ? "Cuenta Principal" : "Cuenta Secundaria",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        actions: [
          // BOTÓN DE FILTRO POR FECHA
          IconButton(
            tooltip: 'Filtrar por fecha',
            icon: Icon(
              Icons.calendar_month, 
              color: _selectedRange != null ? Colors.indigo : Colors.grey[800]
            ),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
                initialDateRange: _selectedRange,
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.light().copyWith(
                      primaryColor: Colors.indigo,
                      colorScheme: const ColorScheme.light(primary: Colors.indigo),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() => _selectedRange = picked);
              }
            },
          ),
          // BOTÓN LIMPIAR FILTRO (Solo si hay filtro activo)
          if (_selectedRange != null)
            IconButton(
              icon: const Icon(Icons.filter_alt_off, color: Colors.red),
              tooltip: 'Quitar filtro',
              onPressed: () => setState(() => _selectedRange = null),
            ),

            // --- NUEVO MENÚ DE OPCIONES (EDITAR / ELIMINAR) ---
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _showEditNameDialog();
                if (value == 'delete') _attemptDeleteAccount(ref); // Pasamos ref para leer transacciones
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [Icon(Icons.edit, color: Colors.blue), SizedBox(width: 10), Text("Cambiar Nombre")]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(currentAccount.isActive ? Icons.delete : Icons.restore, color: Colors.red), 
                    const SizedBox(width: 10), 
                    Text(currentAccount.isActive ? "Eliminar Cuenta" : "Restaurar Cuenta")
                  ]),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // 1. CABECERA DE SALDO Y ACCIONES DE CUENTA
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              children: [
                const Text("Saldo Disponible", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 5),
                Text(
                  CurrencyFormatter.format(currentAccount.balance),
                  style: TextStyle(
                    fontSize: 32, 
                    fontWeight: FontWeight.bold, 
                    color: currentAccount.balance < 0 ? Colors.red : Colors.black87
                  ),
                ),
                
                const SizedBox(height: 15),

                // LÓGICA DE CUENTA PRINCIPAL (Solo para Efectivo)
                if (currentAccount.isCash)
                  if (currentAccount.isDefault)
                    // YA ES PRINCIPAL
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber[100],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.shade300)
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, size: 16, color: Colors.amber[900]),
                          const SizedBox(width: 5),
                          Text(
                            "Cuenta Principal de Efectivo", 
                            style: TextStyle(
                              color: Colors.amber[900], 
                              fontSize: 12, 
                              fontWeight: FontWeight.bold
                            )
                          ),
                        ],
                      ),
                    )
                  else
                    // NO ES PRINCIPAL -> MOSTRAR BOTÓN PARA MARCARLA
                    OutlinedButton.icon(
                      onPressed: () async {
                        // Llamamos al repositorio para actualizar
                        await ref.read(financeRepositoryProvider).setAsDefaultAccount(currentAccount.id, true);
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("¡Cuenta marcada como principal! Las ventas en efectivo llegarán aquí."),
                              backgroundColor: Colors.green,
                            )
                          );
                          Navigator.pop(context); // Salimos para refrescar la lista anterior
                        }
                      },
                      icon: const Icon(Icons.star_border, size: 18),
                      label: const Text("Marcar como Principal"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber[800],
                        side: BorderSide(color: Colors.amber.shade800),
                      ),
                    ),
              ],
            ),
          ),

          // 2. BOTONES DE ACCIÓN RÁPIDA
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.add_circle_outline, 
                  label: "Ingreso Manual", 
                  color: Colors.green,
                  onTap: () => _showTransactionDialog(context, ref, 'DEPOSIT'),
                ),
                _ActionButton(
                  icon: Icons.remove_circle_outline, 
                  label: "Retiro / Gasto", 
                  color: Colors.red,
                  onTap: () => _showTransactionDialog(context, ref, 'WITHDRAWAL'),
                ),
              ],
            ),
          ),

          // 3. TÍTULO DE LISTA
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Row(
              children: [
                const Text("Movimientos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                if (_selectedRange != null)
                  Text(
                    "${DateFormat('dd/MM').format(_selectedRange!.start)} - ${DateFormat('dd/MM').format(_selectedRange!.end)}",
                    style: const TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 4. LISTA DE TRANSACCIONES
          Expanded(
            child: transactionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e')),
              data: (transactions) {
                // APLICAR FILTRO DE FECHA
                final filteredList = _selectedRange == null 
                  ? transactions 
                  : transactions.where((tx) {
                      // Normalizamos la fecha de la tx para comparar solo días
                      final txDate = DateTime(tx.date.year, tx.date.month, tx.date.day);
                      return !txDate.isBefore(_selectedRange!.start) && !txDate.isAfter(_selectedRange!.end);
                    }).toList();

                if (filteredList.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 10),
                        Text(
                          _selectedRange != null ? "Sin movimientos en estas fechas" : "No hay movimientos recientes",
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filteredList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
                  itemBuilder: (context, index) {
                    final tx = filteredList[index];
                    final isPositive = ['DEPOSIT', 'SALE', 'INCOME', 'TRANSFER_IN'].contains(tx.type);
                    
                    // Icono según tipo
                    IconData icon;
                    if (tx.type == 'SALE') icon = Icons.shopping_cart;
                    else if (tx.type.contains('TRANSFER')) icon = Icons.compare_arrows;
                    else icon = isPositive ? Icons.arrow_downward : Icons.arrow_upward;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      leading: CircleAvatar(
                        backgroundColor: isPositive ? Colors.green[50] : Colors.red[50],
                        child: Icon(
                          icon,
                          color: isPositive ? Colors.green : Colors.red,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        tx.description, 
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 2, 
                        overflow: TextOverflow.ellipsis
                      ),
                      subtitle: Text(
                        DateFormat('dd MMM yyyy - HH:mm').format(tx.date),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: Text(
                        "${isPositive ? '+' : '-'} ${CurrencyFormatter.format(tx.amount)}",
                        style: TextStyle(
                          color: isPositive ? Colors.green[700] : Colors.red[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
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

  // DIALOGO PARA INGRESOS/GASTOS MANUALES
  void _showTransactionDialog(BuildContext context, WidgetRef ref, String type) {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final isDeposit = type == 'DEPOSIT';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDeposit ? 'Registrar Ingreso Manual' : 'Registrar Retiro Manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [CurrencyInputFormatter()], // <--- Formateador
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Monto', 
                prefixText: '\$ ', 
                border: OutlineInputBorder()
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo', 
                hintText: 'Ej: Base inicial, Pago taxi, etc.',
                border: OutlineInputBorder()
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDeposit ? Colors.green : Colors.red,
              foregroundColor: Colors.white
            ),
            onPressed: () async {
              // Limpiar formato de miles
              final amount = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0.0;
              final desc = descCtrl.text.trim();

              // --- ALERTA DE VALIDACIÓN ---
              if (amount <= 0 || desc.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Ingresa un monto válido y un motivo."), backgroundColor: Colors.orange)
                );
                return; // Detenemos
              }

              final tx = BankTransaction(
                id: '',
                accountId: widget.account.id,
                type: type,
                amount: amount,
                description: desc,
                date: DateTime.now(),
              );

              try {
                await ref.read(financeRepositoryProvider).addTransaction(tx);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Movimiento registrado: $desc"), 
                      backgroundColor: isDeposit ? Colors.green : Colors.red
                    )
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red)
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // --- LÓGICA DE EDICIÓN DE NOMBRE ---
  void _showEditNameDialog() {
    final nameCtrl = TextEditingController(text: widget.account.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Editar Nombre"),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nuevo Nombre")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                // Creamos copia actualizada
                final updated = BankAccount(
                  id: widget.account.id,
                  name: nameCtrl.text.trim(),
                  balance: widget.account.balance,
                  isCash: widget.account.isCash,
                  isDefault: widget.account.isDefault,
                  isActive: widget.account.isActive,
                );
                await ref.read(financeRepositoryProvider).updateAccount(updated);
                if (mounted) {
                  Navigator.pop(ctx);
                  Navigator.pop(context); // Salir para refrescar titulo
                }
              }
            },
            child: const Text("Guardar"),
          )
        ],
      ),
    );
  }

  // --- LÓGICA DE ELIMINACIÓN SEGURA ---
  Future<void> _attemptDeleteAccount(WidgetRef ref) async {
    // 1. SI ESTÁ INACTIVA, LA RESTAURAMOS (Lógica inversa simple)
    if (!widget.account.isActive) {
      final updated = BankAccount(
        id: widget.account.id, name: widget.account.name, balance: widget.account.balance,
        isCash: widget.account.isCash, isDefault: widget.account.isDefault,
        isActive: true, // REACTIVAR
      );
      await ref.read(financeRepositoryProvider).updateAccount(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cuenta restaurada")));
        Navigator.pop(context);
      }
      return;
    }

    // 2. VALIDACIÓN: SALDO EN 0
    if (widget.account.balance != 0) {
      _showErrorDialog("No se puede eliminar", "La cuenta debe tener un saldo de \$0. Por favor transfiere o retira el dinero restante antes de borrarla.");
      return;
    }

    // 3. VALIDACIÓN: NO SER PRINCIPAL
    if (widget.account.isDefault) {
      _showErrorDialog("No se puede eliminar", "Esta es tu cuenta principal para efectivo. Debes marcar otra cuenta de efectivo como 'Principal' antes de eliminar esta.");
      return;
    }

    // 4. VERIFICAR SI TIENE HISTORIAL (Consultamos la lista de transacciones actual)
    // Leemos el provider que ya está cargado en esta pantalla
    final transactions = ref.read(transactionsProvider(widget.account.id)).asData?.value ?? [];
    
    bool hasHistory = transactions.isNotEmpty;

    // 5. CONFIRMACIÓN FINAL
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Eliminar Cuenta?"),
        content: Text(hasHistory 
          ? "Esta cuenta tiene movimientos históricos. No se borrará permanentemente, pero se ARCHIVARÁ y dejará de aparecer en las opciones de venta."
          : "Esta cuenta está vacía y sin uso. Se eliminará permanentemente."
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx); // Cerrar dialogo
              
              if (hasHistory) {
                // SOFT DELETE (Archivar)
                final updated = BankAccount(
                  id: widget.account.id, name: widget.account.name, balance: widget.account.balance,
                  isCash: widget.account.isCash, isDefault: widget.account.isDefault,
                  isActive: false, // <--- DESACTIVAR
                );
                await ref.read(financeRepositoryProvider).updateAccount(updated);
              } else {
                // HARD DELETE (Borrar BD)
                await ref.read(financeRepositoryProvider).deleteAccountPermanent(widget.account.id);
              }

              if (mounted) {
                Navigator.pop(context); // Volver a la lista
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hasHistory ? "Cuenta archivada" : "Cuenta eliminada")));
              }
            },
            child: const Text("Confirmar"),
          )
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String content) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(title), content: Text(content),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Entendido"))],
    ));
  }
}

// Widget auxiliar para los botones redondos grandes
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 140, // Ancho fijo para uniformidad
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
          ]
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(color: color.withOpacity(0.8), fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}