import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. El Notifier que maneja el estado del carrito (Mapa de ProductId -> Cantidad)
class CartNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    return {}; // Carrito vacío inicialmente
  }

  void addOrIncrement(String productId) {
    final currentQty = state[productId] ?? 0;
    // En Riverpod 2, reasignamos el state creando un nuevo mapa
    state = {
      ...state,
      productId: currentQty + 1,
    };
  }

  void decrement(String productId) {
    final currentQty = state[productId] ?? 0;
    if (currentQty <= 1) {
      // Si llega a 0, eliminamos el producto del mapa
      final newState = Map<String, int>.from(state);
      newState.remove(productId);
      state = newState;
    } else {
      state = {
        ...state,
        productId: currentQty - 1,
      };
    }
  }

  void clearCart() {
    state = {};
  }
}

// 2. El Provider expuesto
final cartProvider = NotifierProvider<CartNotifier, Map<String, int>>(() {
  return CartNotifier();
});