import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../domain/provider_model.dart';
import 'client_providers.dart';
import '../../../core/services/network_connectivity_service.dart';

class SaveProviderScreen extends ConsumerStatefulWidget {
  final ProviderModel? providerToEdit;
  const SaveProviderScreen({super.key, this.providerToEdit});

  @override
  ConsumerState<SaveProviderScreen> createState() => _SaveProviderScreenState();
}

class _SaveProviderScreenState extends ConsumerState<SaveProviderScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _nitCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _bankCtrl;
  late TextEditingController _accountNumCtrl;
  late TextEditingController _categoryCtrl;
  
  String _paymentMethod = 'Cuenta Bancaria'; // Opciones más amplias
  bool _isLoading = false;

  final List<String> _paymentOptions = [
    'Cuenta Bancaria',
    'Nequi / Daviplata',
    'Efectivo',
    'Link de Pago / Web',
    'Otro'
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.providerToEdit;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _nitCtrl = TextEditingController(text: p?.nit ?? '');
    _phoneCtrl = TextEditingController(text: p?.phone ?? '');
    _addressCtrl = TextEditingController(text: p?.address ?? '');
    _emailCtrl = TextEditingController(text: p?.email ?? '');
    _bankCtrl = TextEditingController(text: p?.bank ?? '');
    _accountNumCtrl = TextEditingController(text: p?.accountNumber ?? '');
    _categoryCtrl = TextEditingController(text: p?.category ?? '');
    
    // Adaptamos el tipo de cuenta antiguo a los nuevos métodos si es necesario
    if (p != null && p.accountType.isNotEmpty) {
      if (_paymentOptions.contains(p.accountType)) {
         _paymentMethod = p.accountType;
      } else if (p.accountType == 'Ahorros' || p.accountType == 'Corriente') {
         _paymentMethod = 'Cuenta Bancaria';
         // Podríamos guardar si era ahorros/corriente en el nombre del banco si quisiéramos ser estrictos
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final category = _categoryCtrl.text.isEmpty ? 'General' : _categoryCtrl.text.trim();

      ref.read(providerCategoriesProvider.notifier).add(category);
      
      final provider = ProviderModel(
        id: widget.providerToEdit?.id ?? '',
        name: _nameCtrl.text.trim(),
        nit: _nitCtrl.text.trim(), // Opcional
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim(), // <-- NUEVO: Guardar dirección
        bank: _paymentMethod == 'Cuenta Bancaria' || _paymentMethod == 'Nequi / Daviplata' ? _bankCtrl.text.trim() : '',
        accountType: _paymentMethod, 
        accountNumber: _paymentMethod == 'Efectivo' ? '' : _accountNumCtrl.text.trim(),
        category: category,
      );

      final networkStatus = ref.read(networkConnectivityProvider);
      final bool isOnline = networkStatus != NetworkStatus.offline;
      final providerRepo = ref.read(providerRepositoryProvider);

      if (isOnline) {
        try {
          await providerRepo.saveProvider(provider).timeout(const Duration(seconds: 2));
        } catch (_) {}
      } else {
        // En offline: guardado local inmediato
        providerRepo.saveProvider(provider).catchError((_) {});
      }
      
      if(mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOnline ? 'Proveedor Guardado' : 'ℹ️ Proveedor guardado localmente'), 
            backgroundColor: isOnline ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(providerCategoriesProvider);
    final uniqueCategories = categories.toSet().toList()..sort();
    // Determinar qué campos mostrar según el método de pago
    bool requiresBankName = _paymentMethod == 'Cuenta Bancaria';
    bool requiresAccountNumber = _paymentMethod != 'Efectivo';

    return Scaffold(
      appBar: AppBar(title: Text(widget.providerToEdit != null ? 'Editar Proveedor' : 'Nuevo Proveedor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 1. Nombre (Obligatorio)
              CustomTextField(
                label: 'Nombre / Razón Social *', 
                controller: _nameCtrl, 
                icon: Icons.store,
              ),
              const SizedBox(height: 15),

              // 2. NIT (Opcional) y Teléfono (Obligatorio)
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      label: 'NIT / CC (Opcional)', 
                      controller: _nitCtrl, 
                      icon: Icons.badge,
                      validator: (_) => null, // <-- Opcional
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CustomTextField(
                      label: 'Teléfono *', 
                      controller: _phoneCtrl, 
                      icon: Icons.phone, 
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),

              // Correo Electrónico (Opcional)
              CustomTextField(
                label: 'Correo Electrónico (Opcional)',
                controller: _emailCtrl,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                isRequired: false, // ✅ Opcional
              ),
              const SizedBox(height: 15),

              // Dirección (Opcional)
              CustomTextField(
                label: 'Dirección (Opcional)',
                controller: _addressCtrl,
                icon: Icons.location_on_outlined,
                isRequired: false, // ✅ Opcional
              ),
              const SizedBox(height: 15),

              // --- MENÚ DESPLEGABLE INTELIGENTE DE CATEGORÍAS ---
              LayoutBuilder(
                builder: (context, constraints) {
                  return DropdownMenu<String>(
                    width: constraints.maxWidth,
                    controller: _categoryCtrl,
                    enableFilter: true,
                    requestFocusOnTap: true,
                    label: const Text('Categoría (Elige o escribe una nueva)'),
                    leadingIcon: const Icon(Icons.category),
                    menuHeight: 250,
                    inputDecorationTheme: const InputDecorationTheme(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                    ),
                    dropdownMenuEntries: uniqueCategories.map((opt) {
                      return DropdownMenuEntry<String>(
                        value: opt,
                        label: opt,
                      );
                    }).toList(),
                    onSelected: (val) {
                      if (val != null) _categoryCtrl.text = val;
                    },
                  );
                }
              ),             
              const SizedBox(height: 25),
              const Text('Método de Pago Preferido por el Proveedor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              
              // Dropdown para Método de Pago
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(), 
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                  prefixIcon: Icon(Icons.payment),
                  helperText: 'Selecciona un medio de pago', // <-- AQUÍ
                ),
                items: _paymentOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _paymentMethod = v!),
              ),
              const SizedBox(height: 15),

              // Campos Dinámicos
              if (requiresBankName) ...[
                // ¡Corregido! Quitamos el required: false
                CustomTextField(label: 'Banco (Ej: Bancolombia)', controller: _bankCtrl, icon: Icons.account_balance),
                const SizedBox(height: 15),
              ],
              
              if (requiresAccountNumber) ...[
                // ¡Corregido! Quitamos el required: false
                CustomTextField(
                  label: _paymentMethod == 'Link de Pago / Web' ? 'Enlace / Referencia' : 'Número de Cuenta / Nequi', 
                  controller: _accountNumCtrl, 
                  icon: _paymentMethod == 'Link de Pago / Web' ? Icons.link : Icons.numbers, 
                  keyboardType: _paymentMethod == 'Link de Pago / Web' ? TextInputType.url : TextInputType.number,
                ),
              ],
              
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.indigo),
                  child: _isLoading ? const CircularProgressIndicator() : const Text('GUARDAR PROVEEDOR', style: TextStyle(color: Colors.white)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}