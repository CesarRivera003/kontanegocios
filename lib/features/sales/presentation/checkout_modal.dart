import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../core/utils/currency_formatter_no_decimal.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale_model.dart';
import 'cart_provider.dart';
import '../presentation/pdf_generator.dart';
import '../../auth/presentation/user_profile_provider.dart';
import '../../../../features/settings/data/settings_repository.dart';
import '../../finance/presentation/finance_providers.dart';
import '../../finance/domain/finance_model.dart';
import '../../clients/presentation/client_providers.dart';
import '../../clients/domain/client_model.dart';

class CheckoutModal extends ConsumerStatefulWidget {
  const CheckoutModal({super.key});

  @override
  ConsumerState<CheckoutModal> createState() => _CheckoutModalState();
}

class _CheckoutModalState extends ConsumerState<CheckoutModal> {
  // Lógica de Pagos
  final List<PaymentMethodDetail> _payments = [];
  String _currentMethod = 'Efectivo';
  final TextEditingController _amountCtrl = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  
  // Variables de Bancos y Crédito
  String? _selectedBankAccountId; // Cambiamos String fijo por ID de cuenta real
  DateTime? _creditDeadline;
  bool _isProcessing = false;

  bool _generateElectronicInvoice = false;

  // Calculados
  double get _totalAdded => _payments.fold(0, (sum, p) => sum + p.amount);
  double get _grandTotal => ref.read(cartProvider).grandTotal;
  double get _remaining => _grandTotal - _totalAdded;

  @override
  void initState() {
    super.initState();
    _updateAmountField();

    // --- NUEVO: LÓGICA PARA SELECCIONAR TODO AL TOCAR ---
    _amountFocusNode.addListener(() {
      if (_amountFocusNode.hasFocus) {
        // Usamos microtask para esperar a que el dedo termine de tocar la pantalla,
        // de lo contrario Flutter pondrá el cursor donde cayó el dedo y quitará la selección.
        Future.microtask(() {
          if (mounted && _amountCtrl.text.isNotEmpty) {
            _amountCtrl.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _amountCtrl.text.length,
            );
          }
        });
      }
    });
    // ----------------------------------------------------
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _updateAmountField() {
    if (_remaining > 0) {
      _amountCtrl.text = CurrencyFormatterNoDecimal.format(_remaining);
    } else {
      _amountCtrl.text = '';
    }
  }

  // --- AGREGAR PAGO (MODIFICADO PARA USAR CUENTAS REALES) ---
  void _addPayment(List<BankAccount> accounts) {
    final amountText = _amountCtrl.text.replaceAll(',', '');
    final amount = double.tryParse(amountText) ?? 0;

    if (amount <= 0) return;

    // Validaciones
    if (_currentMethod == 'Crédito' && _creditDeadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Selecciona fecha límite'), backgroundColor: Colors.orange));
      return;
    }
    if (_currentMethod == 'Transferencia' && _selectedBankAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Selecciona el banco destino'), backgroundColor: Colors.orange));
      return;
    }

    // Obtener nombre del banco para mostrar en la lista (UI)
    String? bankNameDisplay;
    if (_currentMethod == 'Transferencia' && _selectedBankAccountId != null) {
      // Buscamos el nombre real de la cuenta seleccionada
      try {
        final account = accounts.firstWhere((a) => a.id == _selectedBankAccountId);
        bankNameDisplay = account.name;
      } catch (_) {
        bankNameDisplay = 'Banco Desconocido';
      }
    }

    setState(() {
      _payments.add(PaymentMethodDetail(
        method: _currentMethod,
        amount: amount,
        bankName: bankNameDisplay, // Guardamos el nombre para el recibo y la lista visual
        paymentDeadline: _currentMethod == 'Crédito' ? _creditDeadline : null,
      ));
      
      // Limpiar temporales
      _creditDeadline = null;
      _selectedBankAccountId = null; // Reiniciar selección para obligar a elegir de nuevo si agrega otro
      _updateAmountField(); 
    });
  }

  void _removePayment(int index) {
    setState(() {
      _payments.removeAt(index);
      _updateAmountField();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _creditDeadline = picked);
  }

  // --- PROCESAR VENTA (CON INTEGRACIÓN A TESORERÍA CORREGIDA) ---
  Future<void> _processSale(List<BankAccount> accounts) async {
    // 1. VALIDACIÓN DE DINERO COMPLETO
    if (_remaining > 0) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ Faltan ${CurrencyFormatter.format(_remaining)}'), backgroundColor: Colors.red));
       return;
    }

    // 2. NUEVA VALIDACIÓN DE TESORERÍA (CAJAS DE EFECTIVO)
    // Verificamos si hay al menos un pago en Efectivo y si existe alguna caja activa
    final hasCashPayment = _payments.any((p) => p.method == 'Efectivo');
    final hasCashAccount = accounts.any((a) => a.isCash && a.isActive);

    if (hasCashPayment && !hasCashAccount) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Configuración Incompleta', style: TextStyle(color: Colors.orange)),
            content: const Text('Para recibir pagos en efectivo, primero debes crear al menos una "Caja" en el módulo de Tesorería.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/finance'); // O la ruta a tu módulo de tesorería
                },
                child: const Text('Ir a Tesorería'),
              )
            ],
          ),
        );
        return; // Detenemos el proceso
    }

    final cart = ref.read(cartProvider);
    Client? clienteParaFactura;

    // --- MAGIA PURA: AUDITORÍA DIAN EN TIEMPO REAL ---
    if (_generateElectronicInvoice) {
      // 1. Lectura segura del StreamProvider
      final clientsList = ref.read(clientsStreamProvider).asData?.value ?? [];
      
      // 2. Asignamos a la variable externa (clienteParaFactura) usando una búsqueda 100% compatible
      clienteParaFactura = clientsList.any((c) => c.name == cart.clientName)
          ? clientsList.firstWhere((c) => c.name == cart.clientName)
          : null;
      
      // 3. Validamos usando clienteParaFactura
      if (clienteParaFactura == null || cart.clientName == 'Cliente General') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Para Facturación Electrónica debes seleccionar un cliente registrado (No sirve "Cliente General").'), backgroundColor: Colors.orange));
        return;
      }
      
      if (clienteParaFactura.idNumber.isEmpty || clienteParaFactura.email.isEmpty || clienteParaFactura.address.isEmpty || clienteParaFactura.daneCode.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ El cliente seleccionado NO tiene los datos DIAN completos (NIT, Correo, Dirección, Código DANE). Ve a contactos y edítalo.'), duration: Duration(seconds: 4), backgroundColor: Colors.red));
        return;
      }
    }
    // ------------------------------------------------

    setState(() => _isProcessing = true);

    try {
      final double realTotalSale = _grandTotal; 
      final userProfile = ref.read(userProfileProvider).value; 
      final companyProfile = ref.read(companyProfileProvider).value;
      final String officialId = FirebaseFirestore.instance.collection('tmp').doc().id;

      final chargesMap = cart.extraCharges.map((c) => {'reason': c.name, 'amount': c.amount}).toList();
      final discountsMap = cart.appliedDiscounts.map((d) => {'reason': d.name, 'amount': -d.amount}).toList();
      final allCosts = [...chargesMap, ...discountsMap];

      double changeRemaining = _totalAdded - realTotalSale;
      if (changeRemaining < 0) changeRemaining = 0;

      final String finalSellerName = (userProfile != null && userProfile.name.trim().isNotEmpty) ? userProfile.name.trim() : 'Admin';

      DateTime? deadline;
      try {
        final creditPayment = _payments.firstWhere((p) => p.method == 'Crédito');
        deadline = creditPayment.paymentDeadline;
      } catch (_) {}

      // 2. GUARDAR VENTA Y ATRAPAR LA VENTA REAL (CON POS-0001 Y DIAN)
      final newSale = await ref.read(salesRepositoryProvider).processSale(
        cartItems: cart.items,
        total: realTotalSale, 
        paymentMethods: _payments, 
        paymentDeadline: deadline,
        clientName: cart.clientName,
        sellerName: finalSellerName,
        additionalCosts: allCosts,
        customId: officialId,
        isElectronicInvoice: _generateElectronicInvoice,  
        client: clienteParaFactura,
      );

      // 3. REGISTRAR EN TESORERÍA (CON DESCUENTO DE VUELTAS)
      final financeRepo = ref.read(financeRepositoryProvider);
      
      for (var payment in _payments) {
        String? targetAccountId;
        double amountToRegister = payment.amount; 

        if (payment.method == 'Efectivo') {
          final cashAccount = accounts.firstWhere((a) => a.isDefault && a.isCash && a.isActive, orElse: () => accounts.firstWhere((a) => a.isCash && a.isActive, orElse: () => accounts.first));
          targetAccountId = cashAccount.id;

          if (changeRemaining > 0) {
            if (amountToRegister >= changeRemaining) {
              amountToRegister -= changeRemaining;
              changeRemaining = 0; 
            } else {
              changeRemaining -= amountToRegister;
              amountToRegister = 0;
            }
          }
        } 
        else if (payment.method == 'Transferencia' && payment.bankName != null) {
          try {
            final bankAccount = accounts.firstWhere((a) => a.name == payment.bankName);
            targetAccountId = bankAccount.id;
          } catch (_) {}
        }

        if (targetAccountId != null && amountToRegister > 0) {
          await financeRepo.addTransaction(BankTransaction(
            id: '', accountId: targetAccountId, type: 'SALE', amount: amountToRegister, 
            description: 'Venta #${newSale.ticketNumber ?? officialId} - ${cart.clientName}', 
            date: DateTime.now(), relatedDocId: officialId
          ));
        }
      }

      // 4. ÉXITO Y LIMPIEZA
      if (mounted) {
        ref.read(cartProvider.notifier).clear(); 
        Navigator.of(context).pop(); 
        
        // ¡Enviamos la venta real devuelta por la base de datos!
        _showSuccessDialog(context, newSale, companyProfile);
      }

    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        
        // --- AQUÍ ATRAPAMOS EL AVISO SECRETO ---
        if (e.toString().contains("ERROR_SALDO_AGOTADO")) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 30),
                  SizedBox(width: 10),
                  Text('Facturas Agotadas', style: TextStyle(fontSize: 18)),
                ],
              ),
              content: const Text(
                'Has agotado todas tus facturas electrónicas gratuitas y no tienes saldo prepago.\n\n'
                '¿Deseas registrar esta venta como una Factura Normal (POS) para no hacer esperar a tu cliente?'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx), // Cierra la alerta y no hace nada
                  child: const Text('Cancelar Venta', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                  onPressed: () {
                    Navigator.pop(ctx); // Cierra la alerta
                    
                    // REINTENTO AUTOMÁTICO: Apagamos el switch de la DIAN y volvemos a llamar el proceso
                    setState(() => _generateElectronicInvoice = false);
                    _processSale(accounts); 
                  },
                  child: const Text('Continuar como POS', style: TextStyle(color: Colors.white)),
                ),
              ],
            )
          );
        } else {
          // Si el error es otra cosa (ej. se cayó el internet), se muestra el error normal
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // --- DIÁLOGO DE ÉXITO CON LOS DOS BOTONES ---
  void _showSuccessDialog(BuildContext parentContext, Sale saleData, dynamic companyProfile) {
    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            bool isPrinting = false;
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                padding: const EdgeInsets.all(20),
                width: 400, 
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 60, color: Colors.green),
                    const SizedBox(height: 15),
                    const Text("¡Venta Exitosa!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(saleData.ticketNumber ?? saleData.id, style: TextStyle(fontSize: 14, color: Colors.indigo, fontWeight: FontWeight.bold)),
                    Text("Total: ${CurrencyFormatter.format(saleData.total)}", style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                    const SizedBox(height: 25),

                    if (saleData.isElectronicInvoice)
                       Container(
                         padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 15),
                         decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                         child: const Text("⏳ Factura enviada a la DIAN. Tardará unos segundos en reflejarse en el historial.", textAlign: TextAlign.center, style: TextStyle(color: Colors.indigo, fontSize: 12)),
                       ),

                    // --- LOS DOS BOTONES ---
                    Row(
                      children: [
                        // Botón 1: Descargar / Compartir (WhatsApp / Guardar)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isPrinting ? null : () async {
                              setState(() => isPrinting = true);
                              try {
                                // AHORA LLAMAMOS A shareTicket
                                await PdfGenerator.shareTicket(saleData, companyProfile);
                                setState(() => isPrinting = false);
                              } catch (e) {
                                setState(() => isPrinting = false);
                              }
                            },
                            icon: isPrinting 
                              ? const SizedBox(width:15, height:15, child:CircularProgressIndicator(strokeWidth:2)) 
                              : const Icon(Icons.download, color: Colors.indigo), // Cambié el icono para que tenga más sentido
                            label: const Text("Descargar", style: TextStyle(color: Colors.indigo)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(color: Colors.indigo)
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Botón 2: IMPRESIÓN DIRECTA TÉRMICA
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isPrinting ? null : () async {
                              setState(() => isPrinting = true);
                              try {
                                // Este sigue llamando a printTicket para abrir el diálogo de impresión
                                await PdfGenerator.printTicket(saleData, companyProfile);
                                if (context.mounted) Navigator.pop(context);
                              } catch (e) {
                                setState(() => isPrinting = false);
                              }
                            },
                            icon: const Icon(Icons.print),
                            label: const Text("Imprimir"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[800], 
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12)
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar", style: TextStyle(color: Colors.grey)))
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = ref.watch(cartProvider).grandTotal;
    final isCovered = _remaining <= 0;
    
    // 1. CARGAMOS LAS CUENTAS REALES DE TESORERÍA
    final accountsAsync = ref.watch(bankAccountsProvider);
    ref.watch(clientsStreamProvider);

    final companyProfile = ref.watch(companyProfileProvider).value;
    final isEmpresarial = companyProfile?.subscriptionStatus == 'empresarial';

    return accountsAsync.when(
      loading: () => const SizedBox(height: 400, child: Center(child: CircularProgressIndicator())),
      error: (e,s) => SizedBox(height: 400, child: Center(child: Text("Error cargando bancos: $e"))),
      data: (accounts) {
        
        // Filtramos solo los BANCOS para el dropdown (excluyendo cajas de efectivo)
        final bankAccounts = accounts.where((a) => !a.isCash && a.isActive).toList();

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Total a Pagar', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                  Text(CurrencyFormatter.format(total), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.green), textAlign: TextAlign.center),
                  const SizedBox(height: 20),

                  // LISTA PAGOS
                  if (_payments.isNotEmpty) ...[
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: _payments.asMap().entries.map((e) => ListTile(
                          dense: true,
                          leading: Icon(_getIcon(e.value.method), color: Colors.indigo),
                          title: Text('${e.value.method} ${e.value.method == 'Transferencia' ? '(${e.value.bankName})' : ''}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(CurrencyFormatter.format(e.value.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.red), onPressed: () => _removePayment(e.key))
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  if (!isCovered) ...[
                    Text("Falta cubrir: ${CurrencyFormatter.format(_remaining)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 25),

                    // --- PASO 1: SELECCIONAR MÉTODO ---
                    const Align(
                      alignment: Alignment.centerLeft, 
                      child: Text("1. Selecciona el método de pago:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey))
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['Efectivo', 'Transferencia', 'Tarjeta', 'Crédito'].map((method) {
                          final isSelected = _currentMethod == method;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(method),
                              selected: isSelected,
                              onSelected: (val) {
                                if (val) setState(() { _currentMethod = method; _selectedBankAccountId = null; _creditDeadline = null; });
                              },
                              avatar: Icon(_getIcon(method), color: isSelected ? Colors.white : Colors.black54),
                              selectedColor: Theme.of(context).primaryColor,
                              labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- PASO 2: INGRESAR MONTO Y DATOS ---
                    Align(
                      alignment: Alignment.centerLeft, 
                      child: Text("2. ¿Cuánto vas a recibir con $_currentMethod?", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey))
                    ),
                    const SizedBox(height: 8),

                    TextField(
                      controller: _amountCtrl,
                      focusNode: _amountFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Monto recibido', 
                        prefixIcon: const Icon(Icons.attach_money), 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), 
                        isDense: true,
                        filled: true,
                        fillColor: Colors.blue.shade50.withOpacity(0.3)
                      ),
                      // ¡CRUCIAL! Esto hace que el botón de abajo cambie en vivo mientras escribes
                      onChanged: (_) => setState(() {}), 
                    ),
                    const SizedBox(height: 10),

                    // CAMPOS DINÁMICOS (Banco o Fecha de Crédito)
                    if (_currentMethod == 'Transferencia') ...[
                      if (bankAccounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text("⚠️ No tienes bancos registrados en Tesorería. Ve al menú Tesorería para crearlos.", style: TextStyle(color: Colors.orange, fontSize: 12)),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: _selectedBankAccountId,
                          items: bankAccounts.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                          onChanged: (val) => setState(() => _selectedBankAccountId = val),
                          decoration: InputDecoration(
                            labelText: 'Banco Destino', 
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), 
                            prefixIcon: const Icon(Icons.account_balance), 
                            isDense: true
                          ),
                        )
                    ] else if (_currentMethod == 'Crédito') ...[
                      InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.calendar_today),
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                          ),
                          child: Text(
                            _creditDeadline != null 
                              ? DateFormat('dd/MM/yyyy').format(_creditDeadline!) 
                              : 'Seleccionar Fecha Compromiso de Pago',
                            style: TextStyle(color: _creditDeadline == null ? Colors.grey : Colors.black),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // --- PASO 3: EL BOTÓN DESCRIPTIVO GIGANTE ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          FocusScope.of(context).unfocus(); // Oculta el teclado táctil
                          _addPayment(accounts);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16), 
                          backgroundColor: Colors.indigo.shade50, 
                          foregroundColor: Colors.indigo.shade800,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: BorderSide(color: Colors.indigo.shade200)
                        ),
                        icon: const Icon(Icons.add_circle, size: 24),
                        label: Text(
                          "Añadir \$${_amountCtrl.text.isEmpty ? '0' : _amountCtrl.text} en $_currentMethod",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),
                  ],

                  if (isCovered && _totalAdded > total) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withOpacity(0.3))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Cambio / Devuelta:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[800])),
                          Text(CurrencyFormatter.format(_totalAdded - total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green[800])),
                        ],
                      ),
                    )
                  ],

                  const SizedBox(height: 25),
                  // --- SWITCH DE FACTURACIÓN ELECTRÓNICA (SOLO EMPRESARIAL) ---
                  if (isEmpresarial && isCovered) ...[
                     Container(
                       decoration: BoxDecoration(
                         color: Colors.indigo.shade50,
                         borderRadius: BorderRadius.circular(12),
                         border: Border.all(color: Colors.indigo.shade200)
                       ),
                       child: SwitchListTile(
                         title: const Text("Generar Factura Electrónica (DIAN)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)),
                         value: _generateElectronicInvoice,
                         activeColor: Colors.indigo,
                         onChanged: (val) => setState(() => _generateElectronicInvoice = val),
                       ),
                     ),
                     const SizedBox(height: 20),
                  ],
                  // -----------------------------------------------------
                  
                  ElevatedButton(
                    onPressed: (isCovered && !_isProcessing) ? () => _processSale(accounts) : null,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _isProcessing 
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) 
                      : const Text('FINALIZAR VENTA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getIcon(String method) {
    switch (method) {
      case 'Efectivo': return Icons.payments_outlined;
      case 'Transferencia': return Icons.qr_code_2;
      case 'Tarjeta': return Icons.credit_card;
      case 'Crédito': return Icons.receipt_long;
      default: return Icons.attach_money;
    }
  }
}