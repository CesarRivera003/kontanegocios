import '../../inventory/domain/product_model.dart';

class CartItem {
  final Product product;
  final int quantity;
  final double price; // Precio unitario (Ya incluye impuesto)

  CartItem({
    required this.product, 
    required this.quantity,
    required double? price, 
  }) : price = price ?? product.price;

  // El total bruto que paga el cliente por esta línea
  double get total => price * quantity; 
  
  // --- NUEVA LÓGICA TRIBUTARIA INDIVIDUAL ---

  // Devuelve cuánto es la Base (sin impuestos) por esta cantidad de items
  double get totalBase {
    if (product.taxRate > 0) {
       return total / (1 + (product.taxRate / 100));
    }
    return total; // Si no tiene impuesto, la base es el total
  }

  // Devuelve cuánto es el valor del impuesto cobrado por esta línea
  double get totalTaxAmount {
    return total - totalBase;
  }

  // Identificador rápido para agrupar en el resumen
  String get taxGroupKey {
    if (product.taxRate == 0) return 'Excluido/Exento';
    return '${product.taxType} ${product.taxRate.toInt()}%';
  }

  CartItem copyWith({int? quantity, double? price}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
    );
  }
}