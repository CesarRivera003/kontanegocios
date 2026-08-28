import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart'; 
import 'package:flutter/foundation.dart'; 
import 'dart:io'; 
import 'package:image_picker/image_picker.dart';

import '../../../shared/widgets/custom_text_field.dart';
import '../domain/product_model.dart';
import 'inventory_providers.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/services/image_service.dart';
import '../../auth/presentation/auth_providers.dart'; 
import 'package:material_symbols_icons/symbols.dart';
import '../../settings/data/settings_repository.dart'; 

class SaveProductScreen extends ConsumerStatefulWidget {
  final Product? productToEdit;
  const SaveProductScreen({super.key, this.productToEdit});

  @override
  ConsumerState<SaveProductScreen> createState() => _SaveProductScreenState();
}

class _SaveProductScreenState extends ConsumerState<SaveProductScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _barcodeCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _commissionCtrl;
  late TextEditingController _minStockCtrl;

  late TextEditingController _categoryCtrl; 
  late TextEditingController _unitCtrl;

  bool _hasCommission = false;
  bool _isService = false; 
  bool _isLoading = false;
  
  String _taxSelection = 'Bienes Excluidos (Sin Impuesto)'; 
  
  XFile? _newImageFile; 
  final ImageService _imageService = ImageService();

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;
    
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    
    _priceCtrl = TextEditingController(text: p != null ? NumberFormat.currency(locale: 'es_CO', symbol: '', decimalDigits: 0).format(p.price).trim() : '');
    _costCtrl = TextEditingController(text: p != null ? NumberFormat.currency(locale: 'es_CO', symbol: '', decimalDigits: 0).format(p.cost).trim() : '');
    _commissionCtrl = TextEditingController(text: p != null ? NumberFormat.currency(locale: 'es_CO', symbol: '', decimalDigits: 0).format(p.commissionPercentage).trim() : '');

    _stockCtrl = TextEditingController(text: p?.stock.toString() ?? '');
    _minStockCtrl = TextEditingController(text: p?.minStock.toString() ?? '');

    _categoryCtrl = TextEditingController(text: p?.category ?? '');
    _unitCtrl = TextEditingController(text: p?.unit ?? 'Und');

    _hasCommission = p?.hasCommission ?? false;
    _isService = p?.isService ?? false;

    // Traducir de BD a UI
    if (p != null) {
      if (p.taxType == 'IVA' && p.taxRate == 19.0) _taxSelection = 'IVA (19%)';
      else if (p.taxType == 'IVA' && p.taxRate == 5.0) _taxSelection = 'IVA (5%)';
      else if (p.taxType == 'INC' && p.taxRate == 8.0) _taxSelection = 'Impuesto al Consumo / INC (8%)';
      else if (p.taxType == 'EXENTO') _taxSelection = 'Bienes Exentos (0%)';
      else _taxSelection = 'Bienes Excluidos (Sin Impuesto)';
    }

    // Escuchar cambios en el precio para actualizar la vista previa de impuestos
    _priceCtrl.addListener(() {
      setState(() {}); // Redibuja la pantalla cuando el precio cambia
    });
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    // ... dispose otros controladores
    super.dispose();
  }

  // --- NUEVA FUNCIÓN: Calcular Base e Impuesto ---
  Map<String, double> _calculateTaxBreakdown() {
    final cleanPrice = double.tryParse(_priceCtrl.text.replaceAll(',', '').replaceAll('.', '')) ?? 0.0;
    
    double taxRate = 0.0;
    if (_taxSelection == 'IVA (19%)') taxRate = 19.0;
    else if (_taxSelection == 'IVA (5%)') taxRate = 5.0;
    else if (_taxSelection == 'Impuesto al Consumo / INC (8%)') taxRate = 8.0;

    if (taxRate == 0.0) return {'base': cleanPrice, 'tax': 0.0};

    // Matemática inversa
    double base = cleanPrice / (1 + (taxRate / 100));
    double taxAmount = cleanPrice - base;

    return {'base': base, 'tax': taxAmount};
  }

  Future<void> _pickImage() async {
    final XFile? file = await _imageService.pickAndCompressImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _newImageFile = file);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    final companyProfile = ref.read(companyProfileProvider).value;
    final status = companyProfile?.subscriptionStatus ?? 'trial';
    final isPremium = status == 'pro' || status == 'empresarial' || status == 'active' || status == 'lifetime';
    final isTrialActive = companyProfile?.trialEndsAt != null && companyProfile!.trialEndsAt!.isAfter(DateTime.now());

    if (widget.productToEdit == null && !isPremium && !isTrialActive) {
      final currentProducts = ref.read(productsStreamProvider).value ?? [];
      if (currentProducts.length >= 50) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Límite de 50 productos alcanzado.'), backgroundColor: Colors.orange)
        );
        return; 
      }
    }

    setState(() => _isLoading = true);

    try {
      String productId = widget.productToEdit?.id.isNotEmpty == true 
          ? widget.productToEdit!.id 
          : DateTime.now().millisecondsSinceEpoch.toString();

      String? finalImageUrl = widget.productToEdit?.imageUrl;
      bool imageUploadFailed = false;

      if (_newImageFile != null) {
        try {
          final companyId = ref.read(companyIdProvider).value; 
          if (companyId != null) {
            finalImageUrl = await _imageService.uploadProductImage(_newImageFile!, productId, companyId).timeout(const Duration(seconds: 30));
          }
        } catch (e) {
          imageUploadFailed = true;
        }
      }

      final cleanPrice = double.tryParse(_priceCtrl.text.replaceAll(',', '').replaceAll('.', '')) ?? 0;
      final cleanCost = double.tryParse(_costCtrl.text.replaceAll(',', '').replaceAll('.', '')) ?? 0;
      final cleanComm = double.tryParse(_commissionCtrl.text.replaceAll(',', '').replaceAll('.', '')) ?? 0;
      
      final String stockRaw = _stockCtrl.text.replaceAll(',', '').replaceAll('.', '');
      final String minStockRaw = _minStockCtrl.text.replaceAll(',', '').replaceAll('.', '');
      final int cleanStock = _isService ? 0 : (int.tryParse(stockRaw) ?? 0);
      final int cleanMinStock = _isService ? 0 : (int.tryParse(minStockRaw) ?? 0);

      String dbTaxType = 'EXCLUIDO';
      double dbTaxRate = 0.0;

      if (_taxSelection == 'IVA (19%)') { dbTaxType = 'IVA'; dbTaxRate = 19.0; }
      else if (_taxSelection == 'IVA (5%)') { dbTaxType = 'IVA'; dbTaxRate = 5.0; }
      else if (_taxSelection == 'Impuesto al Consumo / INC (8%)') { dbTaxType = 'INC'; dbTaxRate = 8.0; }
      else if (_taxSelection == 'Bienes Exentos (0%)') { dbTaxType = 'EXENTO'; dbTaxRate = 0.0; }

      // Nota: Ya no forzamos a EXCLUIDO si no es empresarial. Todos guardan su configuración.

      final product = Product(
        id: productId,
        name: _nameCtrl.text.trim(),
        barcode: _isService ? '' : _barcodeCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        price: cleanPrice,
        cost: cleanCost,
        stock: cleanStock,
        category: _categoryCtrl.text.isEmpty ? 'General' : _categoryCtrl.text.trim(),
        unit: _unitCtrl.text.isEmpty ? 'Und' : _unitCtrl.text.trim(),
        hasCommission: _hasCommission,
        commissionPercentage: cleanComm,
        imageUrl: finalImageUrl,
        taxRate: dbTaxRate, 
        taxType: dbTaxType, 
        minStock: cleanMinStock,
        isService: _isService,
      );

      await ref.read(inventoryRepositoryProvider).saveProduct(product);
      
      ref.read(productCategoriesProvider.notifier).add(product.category);
      ref.read(productUnitsProvider.notifier).add(product.unit);

      if (mounted) {
        context.pop();
        if (imageUploadFailed) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado SIN FOTO (Internet inestable). Edítalo luego para subirla.'), backgroundColor: Colors.orange));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto guardado exitosamente'), backgroundColor: Colors.green));
        }
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error crítico: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(productCategoriesProvider);
    final units = ref.watch(productUnitsProvider);
    
    // Calculamos el desglose de impuestos para la UI
    final taxBreakdown = _calculateTaxBreakdown();

    return Scaffold(
      appBar: AppBar(title: Text(widget.productToEdit != null ? 'Editar Producto' : 'Nuevo Producto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 150,
                    width: 150,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey.shade300),
                      image: _newImageFile != null
                        ? DecorationImage(
                            image: kIsWeb 
                                ? NetworkImage(_newImageFile!.path) 
                                : FileImage(File(_newImageFile!.path)) as ImageProvider,
                            fit: BoxFit.cover,
                          )
                        : (widget.productToEdit?.imageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(widget.productToEdit!.imageUrl!), 
                                fit: BoxFit.cover
                              )
                            : null),
                    ),
                    child: _newImageFile == null && widget.productToEdit?.imageUrl == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                              const SizedBox(height: 5),
                              Text("Agregar Foto", style: TextStyle(color: Colors.grey[600], fontSize: 12))
                            ],
                          )
                        : null,
                  ),
                ),
              ),  

              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Tipo de Producto", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _isService = false),
                      borderRadius: BorderRadius.circular(15),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(
                          color: !_isService ? Colors.blue.shade50 : Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: !_isService ? Colors.blue.shade400 : Colors.grey.shade300,
                            width: !_isService ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.inventory_2_rounded, size: 32, color: !_isService ? Colors.blue.shade700 : Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text("Físico", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: !_isService ? Colors.blue.shade800 : Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _isService = true),
                      borderRadius: BorderRadius.circular(15),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(
                          color: _isService ? Colors.purple.shade50 : Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: _isService ? Colors.purple.shade400 : Colors.grey.shade300,
                            width: _isService ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.cloud_rounded, size: 32, color: _isService ? Colors.purple.shade700 : Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text("Servicio", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _isService ? Colors.purple.shade800 : Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              CustomTextField(label: 'Nombre del Producto', controller: _nameCtrl, icon: Icons.shopping_bag),
              const SizedBox(height: 15),
              
              Row(
                children: [
                  Expanded(child: _buildDropdown('Categoría', _categoryCtrl, categories, Icons.category)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildDropdown('Unidad', _unitCtrl, units, Icons.straighten)),
                ],
              ),
              const SizedBox(height: 15),

              Row(
                children: [
                   Expanded(child: _buildMoneyField('Precio Venta', _priceCtrl, Icons.attach_money)),
                   const SizedBox(width: 10),
                   Expanded(child: _buildMoneyField('Costo', _costCtrl, Icons.money_off)),
                ],
              ),
              const SizedBox(height: 15),

              // --- SECCIÓN: IMPUESTOS (AHORA PARA TODOS LOS PLANES) ---
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.indigo.shade100)
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.account_balance, color: Colors.indigo, size: 18),
                        SizedBox(width: 8),
                        Text("Clasificación Tributaria (DIAN)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text("El precio de venta de arriba ya DEBE incluir este impuesto.", style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _taxSelection,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(), 
                        isDense: true, 
                        fillColor: Colors.white, 
                        filled: true
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Bienes Excluidos (Sin Impuesto)', child: Text('Bienes Excluidos (Sin Impuesto)')),
                        DropdownMenuItem(value: 'Bienes Exentos (0%)', child: Text('Bienes Exentos (0%)')),
                        DropdownMenuItem(value: 'IVA (5%)', child: Text('IVA (5%)')),
                        DropdownMenuItem(value: 'IVA (19%)', child: Text('IVA (19%)')),
                        DropdownMenuItem(value: 'Impuesto al Consumo / INC (8%)', child: Text('Impuesto al Consumo / INC (8%)')),
                      ],
                      onChanged: (v) => setState(() => _taxSelection = v!),
                    ),
                    
                    // --- NUEVO: VISUALIZACIÓN DINÁMICA DE BASE VS IVA ---
                    if (_taxSelection != 'Bienes Excluidos (Sin Impuesto)' && _taxSelection != 'Bienes Exentos (0%)') ...[
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade100)
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text("Valor Base (Empresa)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(CurrencyFormatter.format(taxBreakdown['base']!), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                              ],
                            ),
                            Container(height: 30, width: 1, color: Colors.grey.shade300),
                            Column(
                              children: [
                                const Text("Impuesto (DIAN)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(CurrencyFormatter.format(taxBreakdown['tax']!), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                              ],
                            ),
                          ],
                        ),
                      )
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 15),
              // -------------------------------------------------------------

              if (!_isService) ...[
                const Divider(thickness: 1, height: 30),
                const Align(
                  alignment: Alignment.centerLeft, 
                  child: Text("Control de Inventario", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))
                ),
                const SizedBox(height: 10),
                
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockCtrl,
                        keyboardType: TextInputType.number, 
                        decoration: const InputDecoration(labelText: 'Stock Actual', prefixIcon: Icon(Icons.warehouse), border: OutlineInputBorder()),
                        validator: (v) => v!.isEmpty ? 'Requerido' : null,
                      )
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _minStockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Stock Mínimo', prefixIcon: Icon(Icons.notifications_active), border: OutlineInputBorder()),
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                CustomTextField(label: 'Código de Barras', controller: _barcodeCtrl,
                suffixIcon: IconButton(
                    icon: const Icon(Symbols.barcode_scanner, color: Colors.indigo),
                    onPressed: () async {
                      final code = await context.push<String>('/scanner');
                      if (code != null) {
                        setState(() {
                          _barcodeCtrl.text = code;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 15),
              ],

              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descripción (Opcional)', prefixIcon: Icon(Icons.description), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),

              SwitchListTile(
                title: const Text('¿Genera Comisión?', style: TextStyle(fontWeight: FontWeight.bold)),
                value: _hasCommission,
                activeColor: Colors.green,
                onChanged: (val) => setState(() => _hasCommission = val),
              ),
              if (_hasCommission)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _buildMoneyField('% Porcentaje Comisión', _commissionCtrl, Icons.payments),
                ),

              const SizedBox(height: 30),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white
                  ),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('GUARDAR PRODUCTO'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, TextEditingController controller, List<String> options, IconData icon) {
    final uniqueOptions = options.toSet().toList()..sort();
    
    return LayoutBuilder(
      builder: (context, constraints) {
        return DropdownMenu<String>(
          width: constraints.maxWidth,
          controller: controller,
          enableFilter: true,
          requestFocusOnTap: true,
          label: Text(label),
          leadingIcon: Icon(icon),
          helperText: 'Selecciona o escribe',
          menuHeight: 300,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          dropdownMenuEntries: uniqueOptions.map((opt) {
            return DropdownMenuEntry<String>(
              value: opt,
              label: opt,
            );
          }).toList(),
          onSelected: (val) {
            if (val != null) controller.text = val;
          },
        );
      }
    );
  }

  Widget _buildMoneyField(String label, TextEditingController ctrl, IconData icon) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [CurrencyInputFormatter()], 
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder()),
      validator: (val) => val!.isEmpty ? 'Requerido' : null,
      // Se eliminó la obligación de 'onChanged' aquí porque el listener en initState ya hace el trabajo
    );
  }
}