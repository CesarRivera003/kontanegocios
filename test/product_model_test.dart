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

    test('toMap should generate correct map', () {
      final product = Product(
        id: '1',
        name: 'Test Product',
        barcode: '12345',
        price: 100.0,
        cost: 50.0,
        stock: 10,
        category: 'Test Category',
      );

      final map = product.toMap();

      expect(map['name'], 'Test Product');
      expect(map['barcode'], '12345');
      expect(map['price'], 100.0);
      expect(map['cost'], 50.0);
      expect(map['stock'], 10);
      expect(map['category'], 'Test Category');
    });

    test('fromMap edge case handling: null safety and default values', () {
      // Intentionally passing empty/null values that the model handles via fallbacks
      final map = <String, dynamic>{};
      final product = Product.fromMap(map, 'doc_123');

      expect(product.id, 'doc_123');
      expect(product.name, '');
      expect(product.price, 0.0);
      expect(product.cost, 0.0);
      expect(product.stock, 0);
      expect(product.category, 'General');
      expect(product.unit, 'Und');
      expect(product.isService, false);
      expect(product.taxType, 'EXCLUIDO');
      expect(product.taxRate, 0.0);
    });
  });

  group('Product Edge Cases Analysis (To document in QA report)', () {
    test('Model allows negative prices which should ideally be prevented at domain or UI level', () {
      final product = Product(
        id: '1',
        name: 'Negative Price',
        barcode: '123',
        price: -500.0,
        cost: 0,
        stock: 0,
        category: 'Test',
      );

      // En este momento el modelo SÍ permite negativos. Esto es un bug de dominio
      // que documentaremos en el reporte.
      expect(product.price, -500.0);
    });
  });
}
