import 'package:flutter_test/flutter_test.dart';
import 'package:konta_gestor/features/sales/domain/sale_model.dart';
import 'package:konta_gestor/features/sales/domain/cart_item_model.dart';
import 'package:konta_gestor/features/inventory/domain/product_model.dart';
import 'package:konta_gestor/features/sales/presentation/cart_provider.dart';

void main() {
  group('POS Sales - Model Validations (Edge Cases)', () {
    test('PaymentMethodDetail allows negative amounts', () {
      final payment = PaymentMethodDetail(method: 'Efectivo', amount: -500);
      // El modelo actualmente NO previene negativos, lo cual es un bug de dominio a reportar.
      expect(payment.amount, -500);
    });

    test('Sale allows negative totals and payments', () {
      final payment = PaymentMethodDetail(method: 'Efectivo', amount: -50);
      final sale = Sale(
        id: '1',
        date: DateTime.now(),
        total: -50,
        items: [],
        initialPayments: [payment]
      );
      // BUG: El modelo permite totales y pagos negativos
      expect(sale.total, -50);
      expect(sale.paidInInitial, -50);
    });

    test('CartItem calculation with basic tax', () {
      final product = Product(id: '1', name: 'A', barcode: '1', price: 119, cost: 50, stock: 10, category: 'A', taxRate: 19, taxType: 'IVA');
      final item = CartItem(product: product, quantity: 2, price: null);

      expect(item.total, 238);
      expect(item.totalBase, 200);
      expect(item.totalTaxAmount, 38);
    });

    test('CartItem handles quantity zero or negative', () {
       final product = Product(id: '1', name: 'A', barcode: '1', price: 100, cost: 50, stock: 10, category: 'A');
       final item = CartItem(product: product, quantity: -5, price: null);

       // BUG: El modelo de CartItem no previene cantidades negativas
       expect(item.quantity, -5);
       expect(item.total, -500);
    });
  });
}

// No podemos testear fácilmente CartNotifier (Riverpod Notifier) con dependencias externas profundas sin un ProviderContainer
// y mocks de Firebase, pero documentaremos los hallazgos basados en el análisis estático.
