import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../inventory/domain/product_model.dart';
import '../domain/cart_item_model.dart';
import '../../promotions/domain/promotion_model.dart';
import '../../promotions/presentation/promotions_providers.dart';

// 1. MODELO DE CARGO EXTRA
class ExtraCharge {
  final String name;
  final double amount;
  ExtraCharge(this.name, this.amount);
}

// 2. EL NUEVO ESTADO COMPLEJO
class CartState {
  final List<CartItem> items;
  final List<ExtraCharge> extraCharges;
  final List<ExtraCharge> appliedDiscounts;
  final String clientName; 
  
  CartState({
    this.items = const [], 
    this.extraCharges = const [],
    this.appliedDiscounts = const [],
    this.clientName = 'Cliente General',
  });
  
  // Totales Brutos
  double get productsTotal => items.fold(0, (sum, item) => sum + item.total);
  double get chargesTotal => extraCharges.fold(0, (sum, item) => sum + item.amount);
  double get discountsTotal => appliedDiscounts.fold(0, (sum, item) => sum + item.amount);
  double get grandTotal => (productsTotal + chargesTotal) - discountsTotal;
  
  // --- NUEVOS CÁLCULOS TRIBUTARIOS GLOBALES (CON DESCUENTOS APLICADOS) ---
  
  // Un mapa que agrupa los impuestos. Ej: {'IVA 19%': 15000, 'IVA 5%': 2000}
  Map<String, double> get taxSummary {
    final summary = <String, double>{};
    for (var item in items) {
      if (item.product.taxRate > 0) {
        // 1. Buscamos si hay un descuento para este producto exacto
        double itemDiscount = 0.0;
        for(var d in appliedDiscounts){
            if(d.name.contains('(${item.product.name})')){
                itemDiscount += d.amount;
            }
        }
        // 2. Calculamos el impuesto sobre el valor final real
        double adjustedTotal = item.total - itemDiscount;
        double adjustedBase = adjustedTotal / (1 + (item.product.taxRate / 100));
        double adjustedTax = adjustedTotal - adjustedBase;

        final key = item.taxGroupKey;
        summary[key] = (summary[key] ?? 0) + adjustedTax;
      }
    }
    return summary;
  }

  // Base total consolidada con descuentos
  double get totalTaxExclusive {
    double totalBase = 0.0;
    for (var item in items) {
        double itemDiscount = 0.0;
        for(var d in appliedDiscounts){
            if(d.name.contains('(${item.product.name})')) itemDiscount += d.amount;
        }
        double adjustedTotal = item.total - itemDiscount;
        totalBase += item.product.taxRate > 0 ? (adjustedTotal / (1 + (item.product.taxRate / 100))) : adjustedTotal;
    }
    return totalBase;
  }
  
  // Total del dinero que corresponde a impuestos
  double get totalTaxAmount {
    double totalTax = 0.0;
    taxSummary.forEach((key, value) => totalTax += value);
    return totalTax;
  }

  // Método para clonar el estado
  CartState copyWith({List<CartItem>? items, List<ExtraCharge>? extraCharges, List<ExtraCharge>? appliedDiscounts, String? clientName}) {
    return CartState(
      items: items ?? this.items,
      extraCharges: extraCharges ?? this.extraCharges,
      appliedDiscounts: appliedDiscounts ?? this.appliedDiscounts,
      clientName: clientName ?? this.clientName,
    );
  }
}

// 3. EL NOTIFIER (LOGICA)
// Fíjate que aquí dice Notifier<CartState>, NO Notifier<List<CartItem>>
class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    // --- CORRECCIÓN AQUÍ ---
    // Escuchamos los cambios en las promociones.
    // Si llegan datos nuevos (o se actualizan), recalculamos el carrito inmediatamente.
    ref.listen(activePromotionsStreamProvider, (previous, next) {
      if (next.hasValue && state.items.isNotEmpty) {
        _recalculateDiscounts();
      }
    });
    // -----------------------
    
    return CartState();
  }

  // Método privado para calcular descuentos basado en las promos actuales
  void _recalculateDiscounts() {
    // Obtenemos las promociones activas desde el provider
    // Nota: ref.read es seguro aquí porque se llama tras una acción del usuario
    final promotionsValue = ref.read(activePromotionsStreamProvider);
    final promotions = promotionsValue.asData?.value ?? [];

    List<ExtraCharge> newDiscounts = [];

    // Recorremos cada item del carrito para ver si tiene promo
    for (var item in state.items) {
      // Buscamos si hay alguna promo válida para este producto
      // Prioridad: 3 (Regalo) > 2 (Volumen) > 1 (Fecha) 
      // (Puedes cambiar esta lógica de prioridad según prefieras)
      
      final applicablePromos = promotions.where((p) => 
        p.isValidNow() && p.targetProductIds.contains(item.product.id)
      ).toList();

      for (var promo in applicablePromos) {
        double discountAmount = 0.0;

        // TIPO 3: Pague X lleve Y Gratis
        if (promo.type == PromotionType.buyXgetY) {
          final packSize = promo.buyQuantity + promo.getQuantity;
          if (item.quantity >= packSize) {
            // Cuantos "packs" completos lleva
            final packs = (item.quantity / packSize).floor();
            final freeItems = packs * promo.getQuantity;
            discountAmount = freeItems * item.product.price;
          }
        }
        // TIPO 2: Volumen (Mayorista)
        else if (promo.type == PromotionType.volume) {
          if (item.quantity >= promo.minQuantity) {
            discountAmount = item.total * (promo.percentage / 100);
          }
        }
        // TIPO 1: Temporada (% Simple)
        else if (promo.type == PromotionType.seasonal) {
          discountAmount = item.total * (promo.percentage / 100);
        }

        if (discountAmount > 0) {
          newDiscounts.add(ExtraCharge(
            "${promo.name} (${item.product.name})", 
            discountAmount
          ));
          // Importante: Si aplica una, ¿aplica otras? 
          // Por ahora hacemos 'break' para que solo aplique la primera que encuentre y no se sumen locamente.
          break; 
        }
      }
    }

    state = state.copyWith(appliedDiscounts: newDiscounts);
  }

  // Agregar Producto
  void addProduct(Product product) {
    final index = state.items.indexWhere((i) => i.product.id == product.id);
    List<CartItem> newItems = [...state.items];

    if (index >= 0) {
      // CASO 1: El producto ya está en el carrito (aumentar cantidad)
      // MODIFICACIÓN: Permitimos si es servicio O si la cantidad es menor al stock
      if (product.isService || newItems[index].quantity < product.stock) {
        newItems[index] = newItems[index].copyWith(quantity: newItems[index].quantity + 1);
      }
    } else {
      // CASO 2: Producto nuevo en el carrito
      // MODIFICACIÓN: Permitimos si es servicio O si tiene stock disponible
      if (product.isService || product.stock > 0) {
        // Al agregar, el precio inicial es el del producto
        newItems.add(CartItem(product: product, quantity: 1, price: product.price));
      }
    }
    state = state.copyWith(items: newItems);
    _recalculateDiscounts();
  }

  // Actualizar item (Precio/Cantidad)
  void updateItem(Product product, int quantity, double price) {
    final index = state.items.indexWhere((i) => i.product.id == product.id);
    if (index >= 0) {
      // SEGURIDAD: Si es físico y la cantidad excede el stock, no actualizamos
      if (!product.isService && quantity > product.stock) return;

      List<CartItem> newItems = [...state.items];
      newItems[index] = newItems[index].copyWith(quantity: quantity, price: price);
      state = state.copyWith(items: newItems);
      _recalculateDiscounts();
    }
    
  }

  // Eliminar producto
  void removeItem(Product product) {
    state = state.copyWith(items: state.items.where((i) => i.product.id != product.id).toList());
    _recalculateDiscounts();
  }
  
  // Disminuir en 1 (Lógica rápida)
  void removeOne(Product product) {
     final index = state.items.indexWhere((i) => i.product.id == product.id);
     if (index >= 0) {
       if (state.items[index].quantity > 1) {
         updateItem(product, state.items[index].quantity - 1, state.items[index].price);
       } else {
         removeItem(product);
       }
     }
  }

  // Costos Extra
  void addExtraCharge(String name, double amount) {
    state = state.copyWith(extraCharges: [...state.extraCharges, ExtraCharge(name, amount)]);
  }

  void removeExtraCharge(int index) {
    final newCharges = [...state.extraCharges];
    newCharges.removeAt(index);
    state = state.copyWith(extraCharges: newCharges);
  }

  // Cliente
  void setClient(String name) {
    state = state.copyWith(clientName: name);
  }

  // Limpiar todo
  void clear() => state = CartState();
}

// 4. EL PROVIDER DEFINITIVO
final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);