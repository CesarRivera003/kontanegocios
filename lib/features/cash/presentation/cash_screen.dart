import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../auth/presentation/user_profile_provider.dart';
import '../data/cash_repository.dart';
import '../domain/cash_count_model.dart';
import '../domain/cash_transaction_model.dart';
import 'cash_providers.dart';
import 'denomination_calculator_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../home/presentation/dashboard_shell.dart';

class CashScreen extends ConsumerStatefulWidget {
  const CashScreen({super.key});

  @override
  ConsumerState<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends ConsumerState<CashScreen> {
  final _baseCtrl = TextEditingController();
  final _realCtrl = TextEditingController();
  
  double _sales = 0;
  double _expenses = 0;
  double _manualIn = 0;
  double _manualOut = 0;
  double _receivables = 0;
  
  // Guardamos la lista actual de movimientos para poder enviarla al historial
  List<CashTransaction> _currentMovements = [];
  
  bool _isSavingBase = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _loadInitialData();
      _initialized = true;
    }
  }

  Future<void> _loadInitialData() async {
    try {
      final totals = await ref.read(systemTotalsProvider.future);
      // ¡SALVAVIDAS! Si el usuario se salió de la pantalla rápido, cancela el dibujo
      if (!mounted) return; 

      final savedBase = await ref.read(savedBaseProvider.future);
      if (!mounted) return; // ¡SALVAVIDAS 2!

      setState(() {
        _sales = totals['sales'] ?? 0;
        _expenses = totals['expenses'] ?? 0;
        if (savedBase > 0) {
          _baseCtrl.text = savedBase.toStringAsFixed(0);
        }
      });
    } catch (e) {
      debugPrint("Error cargando caja: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    
    // 1. Verificar si YA se cerró caja hoy para bloquear
    final historyAsync = ref.watch(cashHistoryProvider);
    bool isClosedToday = false;
    double nextDayBaseAmount = 0;
    
    // Revisamos en el historial si hay un cierre con fecha de hoy
    historyAsync.whenData((list) {
      final now = DateTime.now();
      final todayStr = "${now.year}-${now.month}-${now.day}";
      
      final found = list.where((item) {
        final itemDateStr = "${item.date.year}-${item.date.month}-${item.date.day}";
        return itemDateStr == todayStr;
      });
      
      if (found.isNotEmpty) {
        isClosedToday = true;
        nextDayBaseAmount = found.first.nextDayBase;
      }
    });

    final movementsAsync = ref.watch(dailyMovementsProvider);
    
    // Lógica para actualizar totales y guardar la lista localmente
    movementsAsync.whenData((movements) {
      _currentMovements = movements;
      Future.microtask(() {
        // FILTRO: Separamos los que son "Abono Cartera" del resto de entradas manuales
        final incomeMovements = movements.where((m) => m.type == CashTransactionType.income);
        
        // A. Abonos de Cartera (Identificados por la descripción que pusimos en el paso 1)
        final newReceivables = incomeMovements
            .where((m) => m.description.startsWith('Abono Cartera'))
            .fold(0.0, (sum, m) => sum + m.amount);

        // B. Otras Entradas (Base, Préstamos, etc.)
        final newManualIn = incomeMovements
            .where((m) => !m.description.startsWith('Abono Cartera'))
            .fold(0.0, (sum, m) => sum + m.amount);

        final newOut = movements
            .where((m) => m.type == CashTransactionType.expense)
            .fold(0.0, (sum, m) => sum + m.amount);
        
        // Actualizamos estado si hubo cambios
        if (newManualIn != _manualIn || newOut != _manualOut || newReceivables != _receivables) {
          if (mounted) {
            setState(() { 
              _manualIn = newManualIn; 
              _manualOut = newOut;
              _receivables = newReceivables; // <--- Actualizamos
            });
          }
        }
      });
    });

    final base = double.tryParse(_baseCtrl.text.replaceAll(',', '')) ?? 0;
    final real = double.tryParse(_realCtrl.text.replaceAll(',', '')) ?? 0;
    
    // --- MAGIA: Si está cerrada, el saldo es la base para mañana ---
    final theoretical = isClosedToday 
        ? nextDayBaseAmount 
        : (base + _manualIn + _sales + _receivables) - (_manualOut + _expenses);
        
    final difference = real - theoretical;

    return Scaffold(
      appBar: AppBar(
        leading: isMobile ? IconButton(
            icon: const Icon(Icons.menu),
            // Llamamos al drawer global
            onPressed: () => DashboardShell.scaffoldKey.currentState?.openDrawer(),
        ) : null,
        title: const Text('Arqueo de Caja'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.indigo),
            tooltip: 'Historial',
            onPressed: () => context.push('/cash/history'),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // AVISO DE CIERRE
            // AVISO DE CIERRE Y REAPERTURA
            if (isClosedToday)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade300)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock, color: Colors.orange),
                        SizedBox(width: 10),
                        Expanded(child: Text("La caja ya fue cerrada hoy. Ventas y movimientos están bloqueados.", style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.deepOrange),
                        icon: const Icon(Icons.lock_open),
                        label: const Text("Reabrir Caja (Requiere PIN)"),
                        onPressed: () async {
                          // Pedimos el PIN de admin
                          final isAuthorized = await _requestAdminAuthorization(context);
                          if (!isAuthorized) return; 
                          
                          final userProfile = ref.read(userProfileProvider).value;
                          if (userProfile != null) {
                             // NUEVO: Salvavidas Try-Catch para evitar congelamientos
                             try {
                               await ref.read(cashRepositoryProvider).reopenShift(userProfile.id!);
                               await _loadInitialData();
                               if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Caja reabierta con éxito. Ya puedes vender.'), backgroundColor: Colors.green));
                               }
                             } catch (e) {
                               // Si algo falla, mostramos el error rojo en vez de congelar la app
                               if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al reabrir: $e'), backgroundColor: Colors.red));
                               }
                             }
                          }
                        }
                      ),
                    )
                  ],
                ),
              ),

            // 1. BASE
            _SectionTitle("1. INICIO DEL DÍA"),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _baseCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CurrencyInputFormatter()],
                    // Bloqueamos edición si ya cerró
                    enabled: !isClosedToday, 
                    decoration: const InputDecoration(
                      labelText: 'Base Inicial',
                      prefixIcon: Icon(Icons.account_balance_wallet),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                       setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: isClosedToday ? null : _saveBase, 
                  icon: _isSavingBase 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.save),
                )
              ],
            ),

            const SizedBox(height: 25),

            // 2. MOVIMIENTOS
            _SectionTitle("2. MOVIMIENTOS DEL TURNO"),
            // Bloqueamos botones si ya cerró
            IgnorePointer(
              ignoring: isClosedToday,
              child: Opacity(
                opacity: isClosedToday ? 0.5 : 1.0,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showTransactionDialog(context, CashTransactionType.income),
                        icon: const Icon(Icons.add, color: Colors.green),
                        label: const Text("Entrada / Provisión", style: TextStyle(color: Colors.green)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showTransactionDialog(context, CashTransactionType.expense),
                        icon: const Icon(Icons.remove, color: Colors.red),
                        label: const Text("Salida / Entrega", style: TextStyle(color: Colors.red)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 10),
            movementsAsync.when(
              data: (movements) => _MovementsList(
                movements: movements, 
                ref: ref, 
                readOnly: isClosedToday // Pasamos el estado de bloqueo
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, s) => Text("Error: $e"),
            ),

            // ... RESUMEN ...
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  _SummaryRow("Ventas Efectivo (+)", _sales, Colors.green[700]!),
                  if (_receivables > 0) 
                    _SummaryRow("Recaudos Cartera (+)", _receivables, Colors.blue[700]!), // <--- NUEVA FILA
                  if (_expenses > 0) 
                    _SummaryRow("Gastos Sistema (-)", _expenses, Colors.red[700]!),
                  if (_manualIn > 0) 
                    _SummaryRow("Otras Entradas (+)", _manualIn, Colors.green[700]!),
                  if (_manualOut > 0) 
                    _SummaryRow("Salidas Manuales (-)", _manualOut, Colors.red[700]!),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // 3. CIERRE FINAL O ESTADO ACTUAL
            _SectionTitle(isClosedToday ? "3. ESTADO ACTUAL DE LA CAJA" : "3. CIERRE FINAL"),
            
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isClosedToday ? Colors.green[50] : Colors.blue[50], 
                borderRadius: BorderRadius.circular(10),
                border: isClosedToday ? Border.all(color: Colors.green.shade300) : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isClosedToday ? "Base para próximo turno:" : "Saldo efectivo:", 
                    style: TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold, 
                      color: isClosedToday ? Colors.green[800] : Colors.blue
                    )
                  ),
                  Text(
                    CurrencyFormatter.format(theoretical), 
                    style: TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.bold, 
                      color: isClosedToday ? Colors.green[800] : Colors.blue
                    )
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            
            // --- OCULTAMOS TODO ESTO SI LA CAJA ESTÁ CERRADA ---
            if (!isClosedToday) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _realCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Total Efectivo Contado',
                        prefixIcon: Icon(Icons.money),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // BOTÓN DE CALCULADORA DE BILLETES
                  IconButton.filled(
                    onPressed: () => _showDenominationCalculator(context),
                    icon: const Icon(Icons.calculate),
                    tooltip: "Calculadora de Billetes",
                    style: IconButton.styleFrom(backgroundColor: Colors.indigo),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              if (_realCtrl.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: difference == 0 ? Colors.green[50] : (difference > 0 ? Colors.blue[50] : Colors.red[50]),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: difference == 0 ? Colors.green : (difference > 0 ? Colors.blue : Colors.red))
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        difference == 0 ? "¡CUADRADO!" : (difference > 0 ? "SOBRANTE" : "FALTANTE"),
                        style: TextStyle(fontWeight: FontWeight.bold, color: difference == 0 ? Colors.green : (difference > 0 ? Colors.blue : Colors.red))
                      ),
                      Text(
                        CurrencyFormatter.format(difference),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: difference == 0 ? Colors.green : (difference > 0 ? Colors.blue : Colors.red))
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 30),

              ElevatedButton.icon(
                onPressed: () => _saveClosure(base, _manualIn, _sales, _expenses + _manualOut, theoretical, real, difference),
                icon: const Icon(Icons.lock),
                label: const Text("CERRAR CAJA Y GUARDAR ARQUEO"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white
                ),
              ),
            ], // FIN DEL BLOQUE OCULTO
          ],
        ),
      ),
    );
  }

  // --- CALCULADORA DE BILLETES ---
  void _showDenominationCalculator(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => DenominationCalculatorDialog( 
        onConfirm: (total) {
          setState(() {
            _realCtrl.text = total.toStringAsFixed(0); 
          });
        },
      ),
    );
  }

  // --- GUARDADO CON BASE DE MAÑANA Y DETALLES ---
  Future<void> _saveClosure(double base, double provisions, double sales, double expenses, double theoretical, double real, double diff) async {
    final userProfile = ref.read(userProfileProvider).value;
    if (userProfile == null) return;
    
    // Controlador para la base de mañana
    final nextDayBaseCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Cerrar Caja?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Esta acción bloqueará los movimientos de hoy."),
            const SizedBox(height: 20),
            const Text("¿Cuánto dinero dejas para la base de MAÑANA?", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: nextDayBaseCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [CurrencyInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Base Próximo Turno',
                prefixIcon: Icon(Icons.next_plan),
                border: OutlineInputBorder(),
                hintText: '0 si se retira todo',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Confirmar Cierre")),
        ],
      )
    );

    if (confirm == true) {
      try {
        final nextBaseVal = double.tryParse(nextDayBaseCtrl.text.replaceAll(',', '')) ?? 0.0;
        
        // 1. Convertimos los movimientos actuales en una lista de Mapas
        // para guardarlos eternamente en el historial
        final detailsList = _currentMovements.map((tx) => {
          'description': tx.description,
          'amount': tx.amount,
          'type': tx.type.name, // 'income' o 'expense'
          'time': DateFormat('HH:mm').format(tx.date),
        }).toList();

        final newId = DateTime.now().millisecondsSinceEpoch.toString();
        final closure = CashCountModel(
          id: newId,
          date: DateTime.now(),
          userId: userProfile.id ?? '',
          userName: userProfile.name,
          userRole: userProfile.role.name,
          baseAmount: base,
          provisions: provisions,
          cashSales: sales,
          cashExpenses: expenses,
          theoreticalBalance: theoretical,
          realBalance: real,
          difference: diff,
          movementsDetail: detailsList, // <--- AQUÍ GUARDAMOS EL DETALLE
          nextDayBase: nextBaseVal,     // <--- AQUÍ GUARDAMOS LO QUE QUEDA
        );

        await ref.read(cashRepositoryProvider).saveCashCount(closure);
        
        // 2. Guardamos AUTOMÁTICAMENTE la base para mañana
        if (nextBaseVal > 0) {
           await ref.read(cashRepositoryProvider).saveBaseDraft(userProfile.id!, nextBaseVal);
        }

        if (mounted) {
          _baseCtrl.clear();
          _realCtrl.clear();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Caja cerrada y base de mañana guardada"), backgroundColor: Colors.green));
          context.go('/dashboard');
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // --- MÉTODOS DE ACCIÓN (BASE Y DIALOGOS) ---

  Future<void> _saveBase() async {
    final userProfile = ref.read(userProfileProvider).value;
    if (userProfile == null) return;
    
    setState(() => _isSavingBase = true);
    final base = double.tryParse(_baseCtrl.text.replaceAll(',', '')) ?? 0;
    
    try {
      await ref.read(cashRepositoryProvider).saveBaseDraft(userProfile.id!, base);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Base guardada"), backgroundColor: Colors.green));
    } finally {
      if (mounted) setState(() => _isSavingBase = false);
    }
  }

  // --- MÉTODO DE AUTORIZACIÓN (CONECTADO A BD) ---
  Future<bool> _requestAdminAuthorization(BuildContext context) async {
    final pinCtrl = TextEditingController();
    bool isAuthorized = false;
    bool isVerifying = false;

    await showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.lock, color: Colors.red),
                SizedBox(width: 10),
                Text('Autorización Requerida'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Un administrador debe autorizar este movimiento con su PIN.'),
                const SizedBox(height: 15),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  enabled: !isVerifying,
                  decoration: const InputDecoration(
                    labelText: 'PIN de Administrador',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.password),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(ctx), 
                child: const Text('Cancelar')
              ),
              FilledButton(
                onPressed: isVerifying ? null : () async {
                  final inputPin = pinCtrl.text.trim();
                  if (inputPin.isEmpty) return;

                  setState(() => isVerifying = true);

                  try {
                    // 1. Obtener el ID de la empresa
                    final companyId = ref.read(companyIdProvider).value;
                    if (companyId == null) throw Exception("Empresa no identificada");

                    // 2. Leer el PIN guardado en la BD
                    final securityDoc = await FirebaseFirestore.instance
                        .collection('companies')
                        .doc(companyId)
                        .collection('config')
                        .doc('security')
                        .get();
                        
                    final realPin = securityDoc.data()?['adminPin'] as String?;

                    // 3. Validar
                    if (realPin != null && inputPin == realPin) {
                      isAuthorized = true;
                      if (context.mounted) Navigator.pop(ctx);
                    } else {
                      setState(() {
                        isVerifying = false;
                        pinCtrl.clear(); // Limpiamos el campo para que intente de nuevo
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PIN incorrecto o no configurado'), backgroundColor: Colors.red)
                        );
                      }
                    }
                  } catch (e) {
                     setState(() => isVerifying = false);
                     if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                     }
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: isVerifying 
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Text('Autorizar'),
              ),
            ],
          );
        }
      ),
    );

    return isAuthorized;
  }

  // --- 2. DIÁLOGO DE MOVIMIENTO MODIFICADO (CON VALIDACIONES) ---
  void _showTransactionDialog(BuildContext context, CashTransactionType type) {
    final formKey = GlobalKey<FormState>(); // NUEVO: Llave para controlar errores
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == CashTransactionType.income ? "Nueva Entrada" : "Nueva Salida"),
        content: Form(
          key: formKey, // Asignamos la llave al formulario
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField( // Cambiado a TextFormField
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                decoration: const InputDecoration(labelText: 'Monto *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                autofocus: true,
                validator: (val) => val == null || val.isEmpty ? '* Requerido' : null, // Validación roja
              ),
              const SizedBox(height: 10),
              TextFormField( // Cambiado a TextFormField
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Motivo / Comentario *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.comment)),
                validator: (val) => val == null || val.isEmpty ? '* Requerido' : null, // Validación roja
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          FilledButton(
            onPressed: () async {
              // NUEVO: Verificamos si los campos están llenos ANTES de continuar
              if (!formKey.currentState!.validate()) return; 

              final amount = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0.0;
              final desc = reasonCtrl.text.trim();
              
              if (amount > 0 && desc.isNotEmpty) {
                final userProfile = ref.read(userProfileProvider).value;
                
                // Si NO es administrador, pedimos el PIN
                if (userProfile?.role.name != 'admin') {
                  final isAuthorized = await _requestAdminAuthorization(context);
                  if (!isAuthorized) return; 
                }

                Navigator.pop(ctx); 
                
                final newTx = CashTransaction(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  amount: amount,
                  type: type,
                  description: desc,
                  date: DateTime.now(),
                  userId: userProfile?.id ?? '',
                );
                
                try {
                  await ref.read(cashRepositoryProvider).addCashMovement(newTx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Movimiento manual guardado con éxito"), backgroundColor: Colors.green)
                    );
                  }
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text("Guardar"),
          )
        ],
      ),
    );
  }
} // <--- FIN DE LA CLASE STATE

// --- WIDGETS AUXILIARES (FUERA DE LA CLASE STATE) ---

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _SummaryRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(CurrencyFormatter.format(value), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _MovementsList extends StatelessWidget {
  final List<CashTransaction> movements;
  final WidgetRef ref;
  final bool readOnly;

  const _MovementsList({
    super.key, 
    required this.movements, 
    required this.ref, 
    required this.readOnly
  });

  @override
  Widget build(BuildContext context) {
    if (movements.isEmpty) {
      return Container(
         padding: const EdgeInsets.all(15),
         alignment: Alignment.center,
         decoration: BoxDecoration(
           border: Border.all(color: Colors.grey.shade200),
           borderRadius: BorderRadius.circular(10),
           color: Colors.grey[50],
         ),
         child: const Text("Sin movimientos manuales hoy", style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: movements.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final m = movements[i];
          final isInc = m.type == CashTransactionType.income;
          
          return ListTile(
            dense: true,
            leading: Icon(
              isInc ? Icons.arrow_downward : Icons.arrow_upward, 
              color: isInc ? Colors.green : Colors.red, 
              size: 18
            ),
            title: Text(m.description),
            subtitle: Text(DateFormat('hh:mm a').format(m.date)),
            
            // CAMBIO AQUÍ: Ya no usamos un Row con botón de borrar.
            // Solo mostramos el monto. El historial es sagrado.
            trailing: Text(
              CurrencyFormatter.format(m.amount), 
              style: TextStyle(
                color: isInc ? Colors.green : Colors.red, 
                fontWeight: FontWeight.bold
              )
            ),
          );
        }
      ),
    );
  }
}
