import 'package:flutter_test/flutter_test.dart';
import 'package:konta_gestor/features/sales/domain/sale_model.dart';
import 'package:konta_gestor/features/sales/domain/cart_item_model.dart';
import 'package:konta_gestor/features/inventory/domain/product_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('POS Sales - Model Validations (Edge Cases)', () {
    test('PaymentMethodDetail prevents negative amounts in constructor', () {
      expect(() => PaymentMethodDetail(method: 'Efectivo', amount: -500), throwsA(isA<AssertionError>()));
    });

    test('PaymentMethodDetail fromMap fallbacks negative to zero', () {
      final payment = PaymentMethodDetail.fromMap({'method': 'Efectivo', 'amount': -500});
      expect(payment.amount, 0.0);
    });

    test('Sale prevents negative totals', () {
      final payment = PaymentMethodDetail(method: 'Efectivo', amount: 50);
      expect(() => Sale(
        id: '1',
        date: DateTime.now(),
        total: -50,
        items: [],
        initialPayments: [payment]
      ), throwsA(isA<AssertionError>()));
    });

    test('Sale fromMap fallbacks negative totals to zero', () {
      final sale = Sale.fromMap({'date': Timestamp.now(), 'total': -50}, '1');
      expect(sale.total, 0.0);
    });

    test('CartItem calculation with basic tax', () {
      final product = Product(id: '1', name: 'A', barcode: '1', price: 119, cost: 50, stock: 10, category: 'A', taxRate: 19, taxType: 'IVA');
      final item = CartItem(product: product, quantity: 2, price: null);

      expect(item.total, 238);
      expect(item.totalBase, 200);
      expect(item.totalTaxAmount, 38);
    });

    test('CartItem handles quantity zero or negative by throwing AssertionError', () {
       final product = Product(id: '1', name: 'A', barcode: '1', price: 100, cost: 50, stock: 10, category: 'A');
       expect(() => CartItem(product: product, quantity: -5, price: null), throwsA(isA<AssertionError>()));
       expect(() => CartItem(product: product, quantity: 0, price: null), throwsA(isA<AssertionError>()));
    });

    test('CartItem copyWith falls back securely', () {
      final product = Product(id: '1', name: 'A', barcode: '1', price: 100, cost: 50, stock: 10, category: 'A');
      final item = CartItem(product: product, quantity: 2, price: 100);
      final invalidCopy = item.copyWith(quantity: -5, price: -10);
      expect(invalidCopy.quantity, 2);
      expect(invalidCopy.price, 100);
    });
  });
}
