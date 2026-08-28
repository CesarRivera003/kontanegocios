import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// --- IMPORTACIONES DE TU PROYECTO ---
import '../../inventory/presentation/inventory_providers.dart';
import '../../inventory/domain/product_model.dart';
import '../../sales/domain/cart_item_model.dart'; 
import '../../../core/utils/currency_formatter.dart';
import '../presentation/checkout_modal.dart';
import 'cart_provider.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../home/presentation/dashboard_shell.dart';

import '../../clients/presentation/client_providers.dart'; 
import '../../clients/domain/client_model.dart'; 
import '../../cash/presentation/cash_providers.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../settings/data/settings_repository.dart';

// ============================================================================
// 1. PANTALLA PRINCIPAL (ORQUESTADOR)
// ============================================================================
class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clientsStreamProvider);
    
    // --- 1. VERIFICAR SI LA CAJA ESTÁ CERRADA ---
    final historyAsync = ref.watch(cashHistoryProvider);
    bool isClosedToday = false;
    
    historyAsync.whenData((list) {
      final now = DateTime.now();
      final todayStr = "${now.year}-${now.month}-${now.day}";
      final found = list.where((item) => "${item.date.year}-${item.date.month}-${item.date.day}" == todayStr);
      if (found.isNotEmpty) isClosedToday = true;
    });

    // --- 2. PANTALLA DE BLOQUEO ---
    if (isClosedToday) {
      return Scaffold(
        appBar: MediaQuery.of(context).size.width <= 900
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => DashboardShell.scaffoldKey.currentState?.openDrawer(),
                ),
                title: const Text('Punto de Venta'))
            : null,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 80, color: Colors.orange),
              const SizedBox(height: 20),
              const Text("CAJA CERRADA", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
              const SizedBox(height: 10),
              const Text("No puedes realizar ventas porque tu turno ya fue cerrado.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 25),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                onPressed: () => context.push('/cash'),
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text("Ir a la Sección Caja"),
              )
            ],
          ),
        ),
      );
    }

    // --- 3. PANTALLA DE VENTAS (RESPONSIVA) ---
    return Scaffold(
      appBar: MediaQuery.of(context).size.width <= 900
          ? AppBar(
            leading: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => DashboardShell.scaffoldKey.currentState?.openDrawer(),
            ),
            title: const Text('Punto de Venta'))
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 900;
          if (isDesktop) {
            // MODO PC
            return const Row(
              children: [
                Expanded(flex: 7, child: ProductCatalogWidget()),
                VerticalDivider(width: 1),
                Expanded(flex: 3, child: CartPanelWidget(isMobileModal: false)),
              ],
            );
          } else {
            // MODO MÓVIL
            return const Stack(
              children: [
                ProductCatalogWidget(),
                Positioned(
                  bottom: 16, left: 16, right: 16,
                  child: MobileCartSummaryWidget(),
                ),
              ],
            );
          }
        },
      ),
    );
  }
}

// ============================================================================
// 2. WIDGET: CATÁLOGO DE PRODUCTOS (Izquierda)
// ============================================================================
class ProductCatalogWidget extends ConsumerStatefulWidget {
  const ProductCatalogWidget({super.key});

  @override
  ConsumerState<ProductCatalogWidget> createState() => _ProductCatalogWidgetState();
}

class _ProductCatalogWidgetState extends ConsumerState<ProductCatalogWidget> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleScan() async {
    final code = await context.push<String>('/scanner');
    if (code != null) {
      final products = ref.read(productsStreamProvider).asData?.value ?? [];
      try {
        final product = products.firstWhere((p) => p.barcode == code);
        ref.read(cartProvider.notifier).addProduct(product);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ ${product.name} agregado al carrito'), 
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 1500),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('⚠️ Producto no encontrado (Código: $code)'), 
            backgroundColor: Colors.red
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o código...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Symbols.barcode_scanner, color: Colors.indigo),
                    tooltip: 'Escanear y agregar',
                    onPressed: _handleScan,
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                ],
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
          ),
        ),
        
        Expanded(
          child: productsAsync.when(
            data: (products) {
              final filtered = products.where((p) {
                return p.name.toLowerCase().contains(_searchQuery) ||
                       p.barcode.contains(_searchQuery);
              }).toList();

              filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 10),
                      Text("No se encontraron productos", style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 80), 
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200, 
                  childAspectRatio: 0.75, 
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, index) => _ProductCard(product: filtered[index]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text("Error: $e")),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 3. WIDGET: PANEL DEL CARRITO (Derecha en PC / Modal en Móvil)
// ============================================================================
class CartPanelWidget extends ConsumerStatefulWidget {
  final bool isMobileModal;
  const CartPanelWidget({super.key, required this.isMobileModal});

  @override
  ConsumerState<CartPanelWidget> createState() => _CartPanelWidgetState();
}

class _CartPanelWidgetState extends ConsumerState<CartPanelWidget> {
  
  // --- DIÁLOGOS EXTRAÍDOS ---
  void _showEditItemDialog(CartItem item) {
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final priceCtrl = TextEditingController(text: item.price.toStringAsFixed(0)); 

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.product.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [CurrencyInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Precio Unitario', 
                prefixText: '\$ ', 
                border: const OutlineInputBorder(),
                helperText: 'Original: ${CurrencyFormatter.format(item.product.price)}'
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              int newQty = int.tryParse(qtyCtrl.text) ?? 1;
              if (newQty <= 0) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('⚠️ La cantidad mínima es 1'),
                  backgroundColor: Colors.orange,
                ));
                qtyCtrl.text = '1';
                newQty = 1; 
              }

              final cleanPrice = priceCtrl.text.replaceAll(',', ''); 
              final newPrice = double.tryParse(cleanPrice) ?? item.price;
              
              if (!item.product.isService && newQty > item.product.stock) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('⚠️ Stock insuficiente. Máximo: ${item.product.stock}'),
                  backgroundColor: Colors.orange,
                ));
                return;
              }
              
              ref.read(cartProvider.notifier).updateItem(item.product, newQty, newPrice);
              Navigator.pop(ctx);
            },
            child: const Text('Actualizar'),
          )
        ],
      ),
    );
  }

  void _showAddCostDialog() {
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Costo Adicional'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Concepto', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: costCtrl, 
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [CurrencyInputFormatter()],
            decoration: const InputDecoration(labelText: 'Valor', prefixText: '\$ ', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
               if(nameCtrl.text.isNotEmpty && costCtrl.text.isNotEmpty) {
                  final cleanCost = costCtrl.text.replaceAll(',', '');
                  final costValue = double.tryParse(cleanCost) ?? 0.0;
                  ref.read(cartProvider.notifier).addExtraCharge(nameCtrl.text, costValue);
                 Navigator.pop(ctx);
               }
            },
            child: const Text('Agregar'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final clientsAsync = ref.watch(clientsStreamProvider);
    final companyProfile = ref.watch(companyProfileProvider).value;
    final isEmpresarial = companyProfile?.subscriptionStatus == 'empresarial';

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          if (widget.isMobileModal)
             AppBar(
               title: const Text("Carrito de Compras"), 
               automaticallyImplyLeading: false, 
               actions: [IconButton(icon: const Icon(Icons.close), onPressed: ()=>Navigator.pop(context))]
             ),

          // (1) SELECTOR DE CLIENTE
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).primaryColor.withOpacity(0.05),
            child: Row(
              children: [
                Icon(Icons.person, color: Theme.of(context).primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Consumer(
                    builder: (context, ref, child) {
                      final clientsList = clientsAsync.asData?.value ?? []; 
                      
                      return Autocomplete<Client>(
                        key: ValueKey(cartState.clientName),
                        initialValue: TextEditingValue(text: cartState.clientName ?? 'Cliente General'),
                        optionsBuilder: (TextEditingValue val) {
                          if (val.text.isEmpty) return const Iterable<Client>.empty();
                          return clientsList.where((c) => 
                            c.name.toLowerCase().contains(val.text.toLowerCase()) || 
                            c.idNumber.contains(val.text)
                          );
                        },
                        displayStringForOption: (Client option) => option.name,
                        onSelected: (Client selection) {
                          ref.read(cartProvider.notifier).setClient(selection.name);
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return Focus(
                            onFocusChange: (hasFocus) {
                              if (!hasFocus) {
                                Future.delayed(const Duration(milliseconds: 150), () {
                                  final text = controller.text.trim();
                                  final isValid = text == 'Cliente General' || clientsList.any((c) => c.name.toLowerCase() == text.toLowerCase());

                                  if (isValid) {
                                    ref.read(cartProvider.notifier).setClient(text);
                                  } else {
                                    controller.text = 'Cliente General';
                                    ref.read(cartProvider.notifier).setClient('Cliente General');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('⚠️ Cliente no encontrado. Se asignó "Cliente General"'), 
                                        backgroundColor: Colors.orange,
                                        duration: Duration(seconds: 3),
                                      )
                                    );
                                  }
                                });
                              }
                            },
                            child: TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                hintText: 'Buscar por nombre o cédula...',
                                helperText: '🔍 Busca por nombre o ID',
                                helperStyle: TextStyle(color: Colors.blueGrey, fontStyle: FontStyle.italic),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              onTap: () {
                                if (controller.text.isNotEmpty) {
                                  controller.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: controller.text.length
                                  );
                                }
                              },
                              onSubmitted: (String value) {
                                onFieldSubmitted(); 
                                focusNode.unfocus(); 
                              },
                            ),
                          );
                        },
                      );
                    }
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1), 
                  onPressed: () async { 
                    try { await context.push('/save-client'); } catch (e) { }
                  },
                  tooltip: 'Crear Nuevo Cliente',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // (2) LISTA DE PRODUCTOS
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                if (cartState.items.isEmpty && cartState.extraCharges.isEmpty)
                   const Padding(
                     padding: EdgeInsets.all(40), 
                     child: Center(
                       child: Column(
                         children: [
                           Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey),
                           SizedBox(height: 10),
                           Text("El carrito está vacío", style: TextStyle(color: Colors.grey)),
                         ],
                       ),
                     )
                   ),
                
                ...cartState.items.map((item) => Card(
                  key: ValueKey(item.product.id), 
                  elevation: 0,
                  color: Colors.grey[50],
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => _showEditItemDialog(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(item.product.name, 
                                  maxLines: 1, 
                                  overflow: TextOverflow.ellipsis, 
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)
                                ),
                              ),
                              Text(CurrencyFormatter.format(item.price), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 14, color: Colors.red),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                      splashRadius: 16,
                                      onPressed: () => ref.read(cartProvider.notifier).removeOne(item.product),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Text("${item.quantity}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 14, color: Colors.green),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                      splashRadius: 16,
                                      onPressed: () {
                                        if (!item.product.isService && item.quantity >= item.product.stock) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Stock máximo alcanzado"), duration: Duration(milliseconds: 500))
                                          );
                                          return;
                                        }
                                        ref.read(cartProvider.notifier).addProduct(item.product);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                CurrencyFormatter.format(item.total), 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.grey, size: 18), 
                                onPressed: () => ref.read(cartProvider.notifier).removeItem(item.product),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                splashRadius: 16,
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                )),

                if (cartState.extraCharges.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4), 
                    child: Text("Cargos Adicionales", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))
                  ),
                  ...cartState.extraCharges.asMap().entries.map((entry) => Container(
                    key: ValueKey("charge_${entry.key}"),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.orange[50]
                    ),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.local_shipping, size: 20, color: Colors.orange),
                      title: Text(entry.value.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(CurrencyFormatter.format(entry.value.amount), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red, size: 18), 
                            onPressed: () => ref.read(cartProvider.notifier).removeExtraCharge(entry.key),
                            splashRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  )),
                ]
              ],
            ),
          ),

          // BOTONES DE ACCIÓN RÁPIDA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.grey[50], border: const Border(top: BorderSide(color: Colors.grey, width: 0.2))),
            child: Row(
              children: [
                if (!isEmpresarial)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 18), 
                    label: const Text("Costos adicionales"),
                    onPressed: _showAddCostDialog, 
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 18),
                  label: const Text("Vaciar", style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    if (cartState.items.isNotEmpty || cartState.extraCharges.isNotEmpty) {
                       ref.read(cartProvider.notifier).clear();
                    }
                  },
                ),
              ],
            ),
          ),

          // RESUMEN Y TOTAL
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white, 
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, -4), blurRadius: 10)]
            ),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Subtotal Productos:", style: TextStyle(color: Colors.grey)),
                  Text(CurrencyFormatter.format(cartState.productsTotal)),
                ]),
                if (cartState.discountsTotal > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text("Ahorro Promociones:", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    Text("- ${CurrencyFormatter.format(cartState.discountsTotal)}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ]),
                ),
                if (cartState.chargesTotal > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text("Otros Cargos:", style: TextStyle(color: Colors.grey)),
                      Text(CurrencyFormatter.format(cartState.chargesTotal)),
                    ]),
                  ),

                if (cartState.totalTaxAmount > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.shade100)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("Desglose Tributario", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),
                        const SizedBox(height: 4),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text("Base Total:", style: TextStyle(color: Colors.indigo, fontSize: 12)),
                          Text(CurrencyFormatter.format(cartState.totalTaxExclusive), style: const TextStyle(color: Colors.indigo, fontSize: 12)),
                        ]),
                        ...cartState.taxSummary.entries.map((tax) => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                          children: [
                            Text("${tax.key}:", style: const TextStyle(color: Colors.indigo, fontSize: 12)),
                            Text(CurrencyFormatter.format(tax.value), style: const TextStyle(color: Colors.indigo, fontSize: 12)),
                          ]
                        )),
                      ],
                    ),
                  ),
                ],

                const Divider(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("TOTAL:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(CurrencyFormatter.format(cartState.grandTotal), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, 
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                    ),
                    onPressed: cartState.items.isEmpty && cartState.extraCharges.isEmpty ? null : () {
                      if (widget.isMobileModal) Navigator.pop(context); 
                      showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const CheckoutModal());
                    },
                    child: const Text("COBRAR", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ============================================================================
// 4. WIDGET: RESUMEN FLOTANTE (Móvil)
// ============================================================================
class MobileCartSummaryWidget extends ConsumerWidget {
  const MobileCartSummaryWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartProvider); 
    final count = cartState.items.length;      
    final total = cartState.grandTotal;        

    if (count == 0 && cartState.extraCharges.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shopping_cart, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text("$count items  |  ${CurrencyFormatter.format(total)}", 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (ctx) { 
                  return Consumer(
                    builder: (context, ref, child) {
                      ref.watch(cartProvider); 
                      return SizedBox(
                        height: MediaQuery.of(context).size.height * 0.85, 
                        child: const CartPanelWidget(isMobileModal: true),
                      );
                    },
                  );
                },
              );
            },
            child: const Text("Ver")
          )
        ],
      ),
    );
  }
}

// ============================================================================
// 5. WIDGET: TARJETA DE PRODUCTO INDIVIDUAL
// ============================================================================
class _ProductCard extends ConsumerWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasStock = product.stock > 0 || product.isService;

    Color bgColor;
    Color iconColor;
    IconData icon;

    if (!hasStock) {
      bgColor = Colors.grey[200]!;
      iconColor = Colors.grey;
      icon = Icons.block;
    } else if (product.isService) {
      bgColor = Colors.purple[50]!;
      iconColor = Colors.purple;
      icon = Icons.design_services;
    } else {
      bgColor = Colors.blue[50]!;
      iconColor = Colors.blue[700]!;
      icon = Icons.inventory_2;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias, 
      child: InkWell(
        onTap: hasStock ? () => ref.read(cartProvider.notifier).addProduct(product) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor, 
                ),
                child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                    ? Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover, 
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(icon, size: 40, color: iconColor),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, 
                                valueColor: AlwaysStoppedAnimation<Color>(iconColor)
                              )
                            )
                          );
                        },
                      )
                    : Center(
                        child: Icon(icon, size: 40, color: iconColor),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name, 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), 
                    maxLines: 2, 
                    overflow: TextOverflow.ellipsis
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CurrencyFormatter.format(product.price), 
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 14)
                  ),
                  const SizedBox(height: 2),
                  if (product.isService)
                    const Text(
                      "Servicio / Digital",
                      style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold),
                    )
                  else
                    Text(
                      hasStock ? "Stock: ${product.stock} Und" : "Agotado",
                      style: TextStyle(
                        fontSize: 11, 
                        color: hasStock ? Colors.grey[600] : Colors.red,
                        fontWeight: hasStock ? FontWeight.normal : FontWeight.bold
                      )
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}