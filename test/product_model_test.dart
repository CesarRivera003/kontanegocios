import 'package:flutter_test/flutter_test.dart';
import 'package:konta_gestor/features/inventory/domain/product_model.dart';

void main() {
  group('Product Model Tests', () {
    test('Should create Product instance with valid data', () {
      final product = Product(
        id: '1',
        name: 'Test Product',
        barcode: '12345',
        price: 100.0,
        cost: 50.0,
        stock: 10,
        category: 'Test Category',
      );

      expect(product.id, '1');
      expect(product.name, 'Test Product');
      expect(product.price, 100.0);
    });

    test('fromMap should parse map correctly', () {
      final map = {
        'name': 'Map Product',
        'barcode': '98765',
        'price': 250.0,
        'cost': 120.0,
        'stock': 5,
        'category': 'General',
      };

      final product = Product.fromMap(map, 'doc_123');

      expect(product.id, 'doc_123');
      expect(product.name, 'Map Product');
      expect(product.price, 250.0);
      expect(product.stock, 5);
      expect(product.taxType, 'EXCLUIDO'); // default value check
    });

    test('toMap should generate correct map with sanitized string', () {
      final product = Product(
        id: '1',
        name: '<script>alert(1)</script>',
        barcode: '12345',
        description: 'Test <img src="x">',
        price: 100.0,
        cost: 50.0,
        stock: 10,
        category: 'Test Category',
      );

      final map = product.toMap();

      expect(map['name'], '&lt;script&gt;alert(1)&lt;/script&gt;');
      expect(map['description'], 'Test &lt;img src="x"&gt;');
      expect(map['barcode'], '12345');
      expect(map['price'], 100.0);
      expect(map['cost'], 50.0);
      expect(map['stock'], 10);
      expect(map['category'], 'Test Category');
    });

    test('fromMap edge case handling: negative fallback to zero', () {
      final map = <String, dynamic>{
        'price': -50.0,
        'cost': -10.0,
        'stock': -5,
        'minStock': -2,
        'commissionPercentage': -10.0,
        'taxRate': -19.0
      };
      final product = Product.fromMap(map, 'doc_123');

      expect(product.id, 'doc_123');
      expect(product.price, 0.0);
      expect(product.cost, 0.0);
      expect(product.stock, 0);
      expect(product.minStock, 0);
      expect(product.commissionPercentage, 0.0);
      expect(product.taxRate, 0.0);
    });

    test('Constructor throws AssertionError for negative values', () {
      expect(() => Product(
        id: '1',
        name: 'Negative Price',
        barcode: '123',
        price: -500.0,
        cost: 0,
        stock: 0,
        category: 'Test',
      ), throwsA(isA<AssertionError>()));

      expect(() => Product(
        id: '1',
        name: 'Negative Cost',
        barcode: '123',
        price: 10,
        cost: -10,
        stock: 0,
        category: 'Test',
      ), throwsA(isA<AssertionError>()));

      expect(() => Product(
        id: '1',
        name: 'Negative Stock',
        barcode: '123',
        price: 10,
        cost: 5,
        stock: -1,
        category: 'Test',
      ), throwsA(isA<AssertionError>()));
    });
  });
}
