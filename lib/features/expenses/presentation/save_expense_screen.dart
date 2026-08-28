import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/currency_formatter.dart';
import '../domain/expense_model.dart';
import 'expense_providers.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../clients/presentation/client_providers.dart'; 
import '../../auth/presentation/user_profile_provider.dart';
import '../../finance/presentation/finance_providers.dart';
import '../../finance/domain/finance_model.dart'; 

class SaveExpenseScreen extends ConsumerStatefulWidget {
  final Expense? expenseToEdit;
  const SaveExpenseScreen({super.key, this.expenseToEdit});

  @override
  ConsumerState<SaveExpenseScreen> createState() => _SaveExpenseScreenState();
}

class _SaveExpenseScreenState extends ConsumerState<SaveExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _descCtrl;
  late TextEditingController _amountCtrl;
  late TextEditingController _providerCtrl;
  late TextEditingController _categoryCtrl;
  
  DateTime _selectedDate = DateTime.now();
  String _paymentMethod = 'Efectivo';
  String? _selectedBankId;
  
  // Lógica de Pendientes
  bool _isPending = false;
  DateTime? _deadlineDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expenseToEdit;
    
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _providerCtrl = TextEditingController(text: e?.provider ?? '');
    _categoryCtrl = TextEditingController(text: e?.category ?? '');
    _amountCtrl = TextEditingController(text: e != null ? CurrencyFormatter.format(e.amount).replaceAll(RegExp(r'[^0-9.]'), '') : ''); // Limpio para editar

    _selectedDate = e?.date ?? DateTime.now();
    _paymentMethod = e?.paymentMethod ?? 'Efectivo';
    _isPending = e?.isPending ?? false;
    _deadlineDate = e?.paymentDeadline;
  }

  Future<void> _pickDate(bool isDeadline) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isDeadline ? (_deadlineDate ?? DateTime.now()) : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isDeadline) {
          _deadlineDate = picked;
        } else {
          _selectedDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_isPending && _deadlineDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona una fecha límite de pago')));
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final userProfile = ref.read(userProfileProvider).value;
      final String currentUserId = userProfile?.id ?? '';
      final String currentUserName = userProfile?.name ?? 'Admin';
      
      final amountClean = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
      
      List<ExpensePayment> existingPayments = [];
      if (widget.expenseToEdit != null) {
        existingPayments = widget.expenseToEdit!.payments;
      }

      // --- LECTURA SEGURA DE CUENTAS (Evita congelamientos) ---
      final accounts = ref.read(bankAccountsProvider).value ?? [];
      
      String? savedBankName;
      if (_paymentMethod == 'Transferencia') {
        if (_selectedBankId != null) {
          try {
            savedBankName = accounts.firstWhere((a) => a.id == _selectedBankId).name;
          } catch (_) {}
        } else if (widget.expenseToEdit != null) {
          savedBankName = widget.expenseToEdit!.bankName;
        }
      }

      final expense = Expense(
        id: widget.expenseToEdit?.id ?? '',
        date: _selectedDate,
        category: _categoryCtrl.text.isEmpty ? 'General' : _categoryCtrl.text,
        description: _descCtrl.text.trim(),
        provider: _providerCtrl.text.trim(),
        amount: amountClean,
        paymentMethod: _paymentMethod,
        isPending: _isPending,
        paymentDeadline: _isPending ? _deadlineDate : null,
        isPaid: !_isPending, 
        userId: widget.expenseToEdit?.userId.isNotEmpty == true ? widget.expenseToEdit!.userId : currentUserId,
        userName: widget.expenseToEdit?.userName.isNotEmpty == true ? widget.expenseToEdit!.userName : currentUserName,
        payments: existingPayments,
        bankName: savedBankName, 
      );

      // 1. GUARDAR EN GASTOS
      await ref.read(expenseRepositoryProvider).saveExpense(expense)
        .timeout(const Duration(seconds: 5), onTimeout: () => throw Exception("Tiempo de espera agotado"));

      // --- NUEVO: GUARDAR CATEGORÍA EN LA LISTA MAESTRA SI ES NUEVA ---
      // Traemos la lista de categorías que está actualmente en memoria
      final currentCategories = ref.read(expenseCategoriesProvider).value ?? [];
      final typedCategory = expense.category;

      // Verificamos si la categoría escrita NO existe en la lista (ignorando mayúsculas)
      final categoryExists = currentCategories.any((c) => c.toLowerCase() == typedCategory.toLowerCase());

      if (!categoryExists && typedCategory.isNotEmpty && typedCategory != 'General') {
        // Hacemos una copia de la lista actual y le agregamos la nueva palabra
        final updatedList = List<String>.from(currentCategories)..add(typedCategory);
        // Guardamos la nueva lista en Firebase usando tu función existente
        await ref.read(expenseRepositoryProvider).saveManagedCategories(updatedList);
      }
      // -----------------------------------------------------------------

      ref.refresh(expenseCategoriesProvider);

      // 2. INTEGRACIÓN CON TESORERÍA
      final financeRepo = ref.read(financeRepositoryProvider);
      
      // A. REVERSIÓN
      if (widget.expenseToEdit != null) {
         final oldExpense = widget.expenseToEdit!;
         if (!oldExpense.isPending) {
            await financeRepo.registerReversal(
              amount: oldExpense.amount, 
              isCash: oldExpense.paymentMethod == 'Efectivo',
              bankName: oldExpense.bankName ?? (oldExpense.paymentMethod == 'Transferencia' ? 'Bancolombia' : null),
              description: 'Corrección Gasto: ${oldExpense.description}'
            );
         }
      }

      // B. NUEVO MOVIMIENTO (Búsqueda de caja a prueba de fallos)
      if (!_isPending) {
        String? targetAccountId;

        if (_paymentMethod == 'Efectivo') {
          final cashAccounts = accounts.where((a) => a.isCash && a.isActive).toList();
          if (cashAccounts.isNotEmpty) {
             final defaultCash = cashAccounts.where((a) => a.isDefault).toList();
             targetAccountId = defaultCash.isNotEmpty ? defaultCash.first.id : cashAccounts.first.id;
          }
        } 
        else if (_paymentMethod == 'Transferencia') {
          targetAccountId = _selectedBankId; 
        }
        
        if (targetAccountId != null) {
          await financeRepo.addTransaction(BankTransaction(
            id: '',
            accountId: targetAccountId,
            type: 'EXPENSE', 
            amount: amountClean,
            description: 'Gasto: ${_descCtrl.text} (${_categoryCtrl.text})',
            date: _selectedDate,
            relatedDocId: expense.id.isNotEmpty ? expense.id : 'nuevo_gasto',
          ));
        }
      }

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gasto guardado correctamente'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.expenseToEdit != null ? 'Editar Gasto' : 'Nuevo Gasto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. FECHA y MONTO
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(false),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Fecha del Gasto', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                        child: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(labelText: 'Valor', prefixIcon: Icon(Icons.attach_money), border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? 'Requerido' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),

              // 2. CATEGORÍA (Mejorada con DropdownMenu)
              categoriesAsync.when(
                data: (categories) {
                  // Filtramos duplicados y ordenamos para que se vea limpio
                  final uniqueCategories = categories.toSet().toList()..sort();
                  
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return DropdownMenu<String>(
                        width: constraints.maxWidth, // Ocupa todo el ancho disponible
                        controller: _categoryCtrl, // Usamos tu mismo controlador
                        enableFilter: true, // ¡Esto permite escribir y filtrar!
                        requestFocusOnTap: true, // Abre la lista apenas tocas
                        label: const Text('Categoría'),
                        leadingIcon: const Icon(Icons.category),
                        helperText: 'Selecciona una o escribe una nueva para guardarla',
                        
                        // Configuración visual del menú
                        menuHeight: 300,
                        inputDecorationTheme: const InputDecorationTheme(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        
                        // Convertimos tus strings en opciones del menú
                        dropdownMenuEntries: uniqueCategories.map((cat) {
                          return DropdownMenuEntry<String>(
                            value: cat,
                            label: cat,
                          );
                        }).toList(),
                        
                        // Si selecciona de la lista, actualizamos el controlador
                        onSelected: (String? value) {
                          if (value != null) {
                            _categoryCtrl.text = value;
                          }
                        },
                      );
                    }
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (_,__) => const SizedBox(),
              ),
              const SizedBox(height: 15),

              // 3. DESCRIPCIÓN
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción del Gasto', prefixIcon: Icon(Icons.description), border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 15),

              // 4. PROVEEDOR (Selector desde BD)
              // Usamos Consumer para escuchar el stream de proveedores
              Consumer(
                builder: (context, ref, child) {
                  // Asumo que tienes un provider llamado 'providersStreamProvider' o similar
                  // que devuelve List<ProviderModel>. Si no, ajusta el nombre.
                  final providersAsync = ref.watch(providersStreamProvider);

                  return providersAsync.when(
                    data: (providers) {
                      // Validación: Si estamos editando y el proveedor guardado ya no existe en la lista,
                      // manejamos el valor para evitar error en el Dropdown.
                      final existingProvider = providers.any((p) => p.name == _providerCtrl.text);
                      final currentValue = existingProvider ? _providerCtrl.text : null;

                      return DropdownButtonFormField<String>(
                        value: currentValue,
                        decoration: const InputDecoration(
                          labelText: 'Proveedor (opcional)',
                          prefixIcon: Icon(Icons.store),
                          border: OutlineInputBorder(),
                          helperText: 'Selecciona un proveedor registrado'
                        ),
                        items: providers.map((p) {
                          return DropdownMenuItem<String>(
                            value: p.name, // Guardamos el Nombre para mantener compatibilidad con tu modelo actual
                            child: Text(
                              p.name, 
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _providerCtrl.text = value;
                              // Opcional: Si seleccionan proveedor, el gasto suele ser pendiente
                              // _isPending = true; 
                            });
                          }
                        },
                        // Validación opcional: Obligar a seleccionar si es cuenta por pagar
                        validator: (value) {
                          if (_isPending && (value == null || value.isEmpty)) {
                            return 'Si es cuenta por pagar, debes seleccionar un proveedor';
                          }
                          return null;
                        },
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (err, stack) => Text('Error cargando proveedores: $err'),
                  );
                },
              ),
              
              // Botón rápido para crear proveedor si no existe (Mejora de UX)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    // Navegar a crear proveedor y luego volver
                    context.push('/save-provider'); 
                    // Asegúrate que tu ruta sea correcta, o usa:
                    // Navigator.push(context, MaterialPageRoute(builder: (_) => const SaveProviderScreen()));
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Crear nuevo proveedor"),
                ),
              ),

              const SizedBox(height: 15),

              // 5. MÉTODO DE PAGO
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Método de Pago', border: OutlineInputBorder(), prefixIcon: Icon(Icons.payment)),
                items: ['Efectivo', 'Transferencia', 'Otros'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() {
                  _paymentMethod = v!;
                  // Si cambia el método y no es transferencia, limpiamos el banco
                  if (_paymentMethod != 'Transferencia') _selectedBankId = null;
                }),
              ),
              
              // --- SELECTOR DE BANCO (NUEVO) ---
              if (_paymentMethod == 'Transferencia') ...[
                const SizedBox(height: 15),
                Consumer(
                  builder: (context, ref, child) {
                    final accountsAsync = ref.watch(bankAccountsProvider);
                    
                    return accountsAsync.when(
                      data: (accounts) {
                        // Filtramos solo bancos activos (no efectivo)
                        final banks = accounts.where((a) => !a.isCash && a.isActive).toList();
                        
                        if (banks.isEmpty) {
                          return const Text("⚠️ No tienes bancos registrados en Tesorería", style: TextStyle(color: Colors.orange));
                        }

                        return DropdownButtonFormField<String>(
                          value: _selectedBankId,
                          decoration: const InputDecoration(
                            labelText: 'Banco', 
                            border: OutlineInputBorder(), 
                            prefixIcon: Icon(Icons.account_balance)
                          ),
                          items: banks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                          onChanged: (val) => setState(() => _selectedBankId = val),
                          validator: (v) => v == null ? 'Debes seleccionar un banco' : null,
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (_,__) => const SizedBox(),
                    );
                  }
                ),
              ],
              // ---------------------------------
              
              const SizedBox(height: 25),

              // 6. SECCIÓN PENDIENTE DE PAGO
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isPending ? Colors.orange[50] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _isPending ? Colors.orange : Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('¿Es una Cuenta por Pagar?', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Marca si el dinero aún no ha salido de caja'),
                      value: _isPending,
                      activeColor: Colors.orange,
                      onChanged: (val) => setState(() => _isPending = val),
                    ),
                    if (_isPending)
                      InkWell(
                        onTap: () => _pickDate(true),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Fecha Límite de Pago', 
                            border: OutlineInputBorder(), 
                            prefixIcon: Icon(Icons.event_busy, color: Colors.red),
                            filled: true,
                            fillColor: Colors.white
                          ),
                          child: Text(_deadlineDate != null ? DateFormat('dd/MM/yyyy').format(_deadlineDate!) : 'Seleccionar Fecha'),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.red[800], foregroundColor: Colors.white),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('REGISTRAR GASTO'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}