import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../domain/promotion_model.dart';
import 'promotions_providers.dart';
import '../../inventory/presentation/inventory_providers.dart'; // Para cargar productos
import '../../inventory/domain/product_model.dart';

class SavePromotionScreen extends ConsumerStatefulWidget {
  final Promotion? promoToEdit;
  const SavePromotionScreen({super.key, this.promoToEdit});

  @override
  ConsumerState<SavePromotionScreen> createState() => _SavePromotionScreenState();
}

class _SavePromotionScreenState extends ConsumerState<SavePromotionScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _percentageCtrl;
  late TextEditingController _minQtyCtrl;
  late TextEditingController _buyQtyCtrl;
  late TextEditingController _getQtyCtrl;

  PromotionType _selectedType = PromotionType.seasonal;
  DateTimeRange? _selectedDateRange;
  List<String> _selectedProductIds = [];
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final p = widget.promoToEdit;
    
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _percentageCtrl = TextEditingController(text: p?.percentage.toString() ?? '0');
    _minQtyCtrl = TextEditingController(text: p?.minQuantity.toString() ?? '0');
    _buyQtyCtrl = TextEditingController(text: p?.buyQuantity.toString() ?? '1');
    _getQtyCtrl = TextEditingController(text: p?.getQuantity.toString() ?? '1');
    
    if (p != null) {
      _selectedType = p.type;
      _selectedDateRange = DateTimeRange(start: p.startDate, end: p.endDate);
      _selectedProductIds = List.from(p.targetProductIds);
      _isActive = p.isActive;
    } else {
      // Fechas por defecto: Hoy hasta fin de mes
      final now = DateTime.now();
      _selectedDateRange = DateTimeRange(start: now, end: now.add(const Duration(days: 30)));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _percentageCtrl.dispose();
    _minQtyCtrl.dispose();
    _buyQtyCtrl.dispose();
    _getQtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona al menos un producto')));
      return;
    }

    final newPromo = Promotion(
      id: widget.promoToEdit?.id ?? '',
      name: _nameCtrl.text,
      type: _selectedType,
      targetProductIds: _selectedProductIds,
      startDate: _selectedDateRange!.start,
      endDate: _selectedDateRange!.end,
      isActive: _isActive,
      // Valores numéricos según el tipo
      percentage: (_selectedType != PromotionType.buyXgetY) ? double.parse(_percentageCtrl.text) : 0,
      minQuantity: (_selectedType == PromotionType.volume) ? int.parse(_minQtyCtrl.text) : 0,
      buyQuantity: (_selectedType == PromotionType.buyXgetY) ? int.parse(_buyQtyCtrl.text) : 0,
      getQuantity: (_selectedType == PromotionType.buyXgetY) ? int.parse(_getQtyCtrl.text) : 0,
    );

    try {
      await ref.read(promotionsRepositoryProvider).savePromotion(newPromo);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Promoción guardada'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.promoToEdit == null ? 'Nueva Promoción' : 'Editar Promoción')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. NOMBRE Y ESTADO
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre de la Promo', border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? 'Requerido' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    children: [
                      const Text("Activa"),
                      Switch(value: _isActive, onChanged: (v) => setState(() => _isActive = v)),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 20),

              // 2. TIPO DE PROMOCIÓN
              const Text("Tipo de Oferta", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              DropdownButtonFormField<PromotionType>(
                value: _selectedType,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: PromotionType.seasonal, child: Text('Descuento % (Fecha)')),
                  DropdownMenuItem(value: PromotionType.volume, child: Text('Descuento por Volumen (Mayorista)')),
                  DropdownMenuItem(value: PromotionType.buyXgetY, child: Text('Pague X Lleve Y (Regalo)')),
                ],
                onChanged: (val) => setState(() => _selectedType = val!),
              ),
              const SizedBox(height: 20),

              // 3. CAMPOS DINÁMICOS SEGÚN TIPO
              _buildDynamicFields(),

              const SizedBox(height: 20),

              // 4. FECHAS
              const Text("Vigencia", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              InkWell(
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context, 
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime(2030),
                    initialDateRange: _selectedDateRange
                  );
                  if (picked != null) setState(() => _selectedDateRange = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.start)}  -  ${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.end)}"),
                      const Icon(Icons.calendar_today, size: 18),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 5. SELECCIÓN DE PRODUCTOS
              const Text("Productos que aplican", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              _buildProductSelector(),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(onPressed: _save, child: const Text("GUARDAR PROMOCIÓN")),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicFields() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          // CASO 1 Y 2: PORCENTAJE
          if (_selectedType == PromotionType.seasonal || _selectedType == PromotionType.volume)
            TextFormField(
              controller: _percentageCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Porcentaje de Descuento (%)', prefixIcon: Icon(Icons.percent)),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
          
          // CASO 2: CANTIDAD MÍNIMA
          if (_selectedType == PromotionType.volume) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _minQtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad Mínima para aplicar', helperText: 'Ej: A partir de 12 unidades'),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
          ],

          // CASO 3: PAGUE X LLEVE Y
          if (_selectedType == PromotionType.buyXgetY)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _buyQtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Pague (Compre)'),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: TextFormField(
                    controller: _getQtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Lleve (Gratis)',
                    helperText: 'Lo que se lleva adicional',)
                  ),
                ),
              ],
            )
        ],
      ),
    );
  }

  Widget _buildProductSelector() {
    return Consumer(
      builder: (context, ref, child) {
        final productsAsync = ref.watch(productsStreamProvider);
        
        return productsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_,__) => const Text("Error cargando productos"),
          data: (allProducts) {
            return Column(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.list),
                  label: Text("Seleccionar Productos (${_selectedProductIds.length})"),
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (ctx) => _ProductMultiSelectDialog(
                        allProducts: allProducts,
                        selectedIds: _selectedProductIds,
                        onChanged: (ids) {
                          setState(() => _selectedProductIds = ids);
                        },
                      ),
                    );
                  },
                ),
                // Pequeña lista de preview
                if (_selectedProductIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: 5,
                      children: _selectedProductIds.take(5).map((id) {
                        final p = allProducts.firstWhere((e) => e.id == id, orElse: () => Product(id: '', name: '?', barcode: '', price: 0, cost: 0, stock: 0, category: ''));
                        return Chip(label: Text(p.name, style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact);
                      }).toList(),
                    ),
                  )
              ],
            );
          },
        );
      },
    );
  }
}

// DIÁLOGO INTERNO PARA SELECCIONAR PRODUCTOS
class _ProductMultiSelectDialog extends StatefulWidget {
  final List<Product> allProducts;
  final List<String> selectedIds;
  final Function(List<String>) onChanged;

  const _ProductMultiSelectDialog({required this.allProducts, required this.selectedIds, required this.onChanged});

  @override
  State<_ProductMultiSelectDialog> createState() => _ProductMultiSelectDialogState();
}

class _ProductMultiSelectDialogState extends State<_ProductMultiSelectDialog> {
  late List<String> _tempSelectedIds;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tempSelectedIds = List.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.allProducts.where((p) => p.name.toLowerCase().contains(_search.toLowerCase())).toList();

    return AlertDialog(
      title: const Text("Seleccionar Productos"),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(hintText: 'Buscar...', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final p = filtered[i];
                  final isSelected = _tempSelectedIds.contains(p.id);
                  return CheckboxListTile(
                    title: Text(p.name),
                    subtitle: Text("\$${p.price}"),
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _tempSelectedIds.add(p.id);
                        } else {
                          _tempSelectedIds.remove(p.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
        ElevatedButton(
          onPressed: () {
            widget.onChanged(_tempSelectedIds);
            Navigator.pop(context);
          }, 
          child: const Text("Confirmar")
        )
      ],
    );
  }
}