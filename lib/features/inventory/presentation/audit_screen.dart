import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/currency_formatter.dart';
import '../domain/product_model.dart';
import 'inventory_providers.dart';
import 'audit_history_screen.dart';
import '../domain/audit_model.dart';
import 'package:material_symbols_icons/symbols.dart';

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  // Estado local del arqueo: Map<ID_Producto, Cantidad_Contada>
  // Si es null, significa que no se ha auditado aún.
  final Map<String, int?> _countedStock = {};
  
  String _searchQuery = '';
  String? _selectedCategory; // Null = Todas
  bool _showOnlyPending = false; // Filtro para ver lo que falta

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final categories = ref.watch(productCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Modo Auditoría', style: TextStyle(fontSize: 18)),
            Text(
              _selectedCategory == null ? 'Inventario Completo' : 'Cat: $_selectedCategory', 
              style: const TextStyle(fontSize: 12, color: Colors.white70)
            ),
          ],
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Ver Historial',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AuditHistoryScreen())
              );
            },
          ),
          IconButton(
            icon: Icon(_showOnlyPending ? Icons.filter_alt_off : Icons.filter_alt),
            tooltip: 'Ver solo pendientes',
            onPressed: () => setState(() => _showOnlyPending = !_showOnlyPending),
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Finalizar Arqueo',
            onPressed: () => _finishAudit(ref.read(productsStreamProvider).value ?? []),
          )
        ],
      ),
      body: Column(
        children: [
          // 1. BARRA DE FILTROS Y BÚSQUEDA
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.indigo[50],
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar producto o escanear...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            icon: const Icon(Symbols.barcode_scanner,),
                            onPressed: _scanBarcode,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // FILTRO DE CATEGORÍA
                    DropdownButtonHideUnderline(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          hint: const Text("Cat."),
                          items: [
                            const DropdownMenuItem(value: null, child: Text("Todas")),
                            ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                          ],
                          onChanged: (val) => setState(() => _selectedCategory = val),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildProgressSummary(productsAsync.value ?? []),
              ],
            ),
          ),

          // 2. LISTA DE PRODUCTOS A AUDITAR
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e')),
              data: (allProducts) {
                // FILTRADO
                final filtered = allProducts.where((p) {
                  if (p.isService) return false; // No auditamos servicios
                  if (_selectedCategory != null && p.category != _selectedCategory) return false;
                  
                  final matchesSearch = p.name.toLowerCase().contains(_searchQuery) || 
                                        p.barcode.toLowerCase().contains(_searchQuery);
                  if (!matchesSearch) return false;

                  final isCounted = _countedStock.containsKey(p.id);
                  if (_showOnlyPending && isCounted) return false;

                  return true;
                }).toList();

                // ORDENAR: Pendientes primero
                filtered.sort((a, b) {
                  final aCounted = _countedStock.containsKey(a.id) ? 1 : 0;
                  final bCounted = _countedStock.containsKey(b.id) ? 1 : 0;
                  return aCounted.compareTo(bCounted);
                });

                if (filtered.isEmpty) {
                  return const Center(child: Text("No hay productos que coincidan"));
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final product = filtered[i];
                    return AuditItemTile(
                      // Clave única basada en ID para que Flutter sepa quién es quién
                      key: ValueKey(product.id), 
                      product: product,
                      currentCount: _countedStock[product.id],
                      onChanged: (newVal) {
                        // Actualizamos el estado global sin destruir el widget hijo
                        setState(() {
                          if (newVal == null) {
                            _countedStock.remove(product.id);
                          } else {
                            _countedStock[product.id] = newVal;
                          }
                        });
                      },
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

  // --- WIDGET DE RESUMEN DE PROGRESO ---
  Widget _buildProgressSummary(List<Product> allProducts) {
    // Calculamos solo sobre los productos filtrados por categoría (si aplica)
    final auditScope = allProducts.where((p) => 
      !p.isService && (_selectedCategory == null || p.category == _selectedCategory)
    ).toList();
    
    final totalItems = auditScope.length;
    final countedItems = auditScope.where((p) => _countedStock.containsKey(p.id)).length;
    final progress = totalItems == 0 ? 0.0 : countedItems / totalItems;

    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: progress, 
            backgroundColor: Colors.grey[300], 
            color: progress == 1.0 ? Colors.green : Colors.orange,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Text("$countedItems / $totalItems", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  // --- LÓGICA DE ESCÁNER ---
  Future<void> _scanBarcode() async {
    final code = await context.push<String>('/scanner');
    if (code != null) {
      setState(() {
        _searchQuery = code.toLowerCase();
      });
      // Opcional: Auto-foco o auto-incrementar si lo deseas
    }
  }

  // --- FINALIZAR Y GUARDAR ---
  void _finishAudit(List<Product> allProducts) {
    if (_countedStock.isEmpty) return;

    // Calcular impacto financiero
    double totalLoss = 0;
    double totalGain = 0;
    int itemsChanged = 0;

    _countedStock.forEach((id, realStock) {
      if (realStock == null) return;
      final product = allProducts.firstWhere((p) => p.id == id);
      final diff = realStock - product.stock;
      
      if (diff != 0) {
        itemsChanged++;
        final value = diff * product.cost;
        if (value < 0) totalLoss += value.abs();
        else totalGain += value;
      }
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmar Ajustes"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Items a ajustar"),
              trailing: Text("$itemsChanged", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.trending_down, color: Colors.red),
              title: const Text("Pérdida Inventario"),
              trailing: Text(CurrencyFormatter.format(totalLoss), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.trending_up, color: Colors.green),
              title: const Text("Sobró Inventario"),
              trailing: Text(CurrencyFormatter.format(totalGain), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ),
            const Divider(),
            const Text("Esta acción actualizará el stock permanentemente.", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () {
              Navigator.pop(ctx);
              _saveChanges(allProducts);
            },
            child: const Text("Aplicar Ajustes", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Future<void> _saveChanges(List<Product> allProducts) async {
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      
      // Lista 1: Solo productos que CAMBIARON de stock (Para ahorrar escrituras en Firestore)
      List<Product> productsToUpdate = [];
      
      // Lista 2: TODOS los productos contados (Para el historial completo)
      List<AuditItemDetail> logDetails = [];
      
      double logTotalLoss = 0;
      double logTotalGain = 0;
      int itemsWithDifferences = 0; // Contador auxiliar

      _countedStock.forEach((id, realStock) {
        if (realStock == null) return;
        final original = allProducts.firstWhere((p) => p.id == id);
        final diff = realStock - original.stock;
        
        // 1. SIEMPRE AGREGAMOS AL LOG (Sea correcto o no)
        logDetails.add(AuditItemDetail(
          productId: original.id,
          productName: original.name,
          oldStock: original.stock,
          newStock: realStock,
          cost: original.cost,
        ));

        // 2. SI HUBO DIFERENCIA, Calculamos finanzas y preparamos actualización
        if (diff != 0) {
          itemsWithDifferences++;
          
          // Calcular impacto financiero solo de lo que varió
          final financialImpact = diff * original.cost;
          if (financialImpact < 0) logTotalLoss += financialImpact.abs();
          else logTotalGain += financialImpact;

          // Agregar a la lista de actualización de Firestore
          productsToUpdate.add(Product(
            id: original.id,
            name: original.name,
            barcode: original.barcode,
            description: original.description,
            price: original.price,
            cost: original.cost,
            stock: realStock, // Nuevo Stock
            category: original.category,
            unit: original.unit,
            hasCommission: original.hasCommission,
            commissionPercentage: original.commissionPercentage,
            imageUrl: original.imageUrl,
            taxRate: original.taxRate,
            minStock: original.minStock,
            isService: original.isService,
          ));
        }
      });

      // 3. GUARDAR STOCK (Solo los que cambiaron para ser eficientes)
      if (productsToUpdate.isNotEmpty) {
        await repo.importProducts(productsToUpdate);
      }

      // 4. GUARDAR EL LOG (Siempre, si se contó algo)
      if (logDetails.isNotEmpty) {
        final newLog = AuditLog(
          id: '', 
          date: DateTime.now(),
          totalGain: logTotalGain,
          totalLoss: logTotalLoss,
          // Guardamos el total de items auditados, no solo los ajustados
          itemsAdjusted: logDetails.length, 
          details: logDetails,
        );
        
        await repo.saveAuditLog(newLog);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Auditoría guardada. ${logDetails.length} productos verificados (${itemsWithDifferences} con ajustes)."), 
            backgroundColor: Colors.green
          )
        );
        context.pop(); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error guardando: $e"), backgroundColor: Colors.red));
      }
    }
  }
}

class AuditItemTile extends StatefulWidget {
  final Product product;
  final int? currentCount;
  final Function(int?) onChanged;

  const AuditItemTile({
    super.key, 
    required this.product, 
    required this.currentCount, 
    required this.onChanged
  });

  @override
  State<AuditItemTile> createState() => _AuditItemTileState();
}

class _AuditItemTileState extends State<AuditItemTile> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isDirty = false; // Para saber si escribiste algo y no has guardado

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentCount != null ? widget.currentCount.toString() : ''
    );
    
    // Detectar cambios para mostrar el botón de guardar
    _controller.addListener(() {
      final text = _controller.text;
      final current = widget.currentCount?.toString() ?? '';
      if (text != current && mounted) {
        setState(() => _isDirty = true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AuditItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si el valor cambia desde afuera (ej: escáner), actualizamos el texto
    if (widget.currentCount != oldWidget.currentCount) {
      // Solo actualizamos si NO estamos escribiendo actualmente
      if (!_focusNode.hasFocus) {
         _controller.text = widget.currentCount?.toString() ?? '';
         _isDirty = false;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _saveValue() {
    final text = _controller.text;
    if (text.isEmpty) {
      widget.onChanged(null); // Borrar
    } else {
      final newVal = int.tryParse(text);
      if (newVal != null) {
        widget.onChanged(newVal);
      }
    }
    setState(() => _isDirty = false);
    _focusNode.unfocus(); // Cerrar teclado opcionalmente
  }

  @override
  Widget build(BuildContext context) {
    final isAudited = widget.currentCount != null;
    final difference = isAudited ? (widget.currentCount! - widget.product.stock) : 0;

    // Color de fondo: Verde/Rojo solo si YA está guardado (auditado)
    Color? backgroundColor;
    if (isAudited) {
      backgroundColor = difference == 0 
          ? Colors.green.withOpacity(0.05) 
          : Colors.red.withOpacity(0.05);
    }

    return Container(
      color: backgroundColor,
      child: ListTile(
        title: Text(widget.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text("Sistema: ${widget.product.stock}  |  Código: ${widget.product.barcode}"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // CAMPO DE TEXTO
            SizedBox(
              width: 80,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                // Lógica de "Enter" para guardar
                onSubmitted: (_) => _saveValue(),
                // Decoración
                decoration: InputDecoration(
                  hintText: '?',
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  // Blanco si escribes, Gris si está vacío, Color suave si ya guardaste
                  fillColor: _focusNode.hasFocus ? Colors.white : (isAudited ? Colors.white.withOpacity(0.5) : Colors.grey[100]),
                  isDense: true,
                ),
              ),
            ),
            
            const SizedBox(width: 8),

            // BOTÓN DE ACCIÓN O INDICADOR
            if (_isDirty)
              // 1. Si hay cambios sin guardar: Botón CHECK
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.indigo, size: 30),
                onPressed: _saveValue,
                tooltip: 'Confirmar conteo',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else if (isAudited && difference != 0)
              // 2. Si ya guardó y hay diferencia: INDICADOR +/-
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: difference > 0 ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  difference > 0 ? "+$difference" : "$difference",
                  style: TextStyle(
                    color: difference > 0 ? Colors.green[800] : Colors.red[800],
                    fontWeight: FontWeight.bold,
                    fontSize: 12
                  ),
                ),
              )
            else if (isAudited)
              // 3. Si ya guardó y está perfecto (diferencia 0): CHECK VERDE
              const Icon(Icons.check, color: Colors.green, size: 20),
          ],
        ),
      ),
    );
  }
}