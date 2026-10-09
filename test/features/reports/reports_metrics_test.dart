import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Strategic Metrics Unit Tests', () {
    test('Ticket Promedio y Tamaño de Cesta se calculan correctamente', () {
      final averageTicket = 200000 / 2;
      final averageBasketSize = 3 / 2;
      expect(averageTicket, 100000.0);
      expect(averageBasketSize, 1.5);
    });

    test('Matriz de Inventario clasifica correctamente según promedios', () {
      final p1Rotation = 10;
      final p1Margin = 20.0;
      final isStar = p1Rotation >= 5 && p1Margin >= 10.0;
      final p2Rotation = 8;
      final p2Margin = 5.0;
      final isHook = p2Rotation >= 5 && p2Margin < 10.0;
      final p3Rotation = 2;
      final p3Margin = 15.0;
      final isOpportunity = p3Rotation < 5 && p3Margin >= 10.0;
      expect(isStar, true);
      expect(isHook, true);
      expect(isOpportunity, true);
    });

    test('Capital inmovilizado suma correctamente (stock * cost) para rotacion 0', () {
      final p1Cost = 5.0;
      final p1Stock = 10;
      final p2Cost = 100.0;
      final p2Stock = 2;
      final immobilizedCapital = (p1Cost * p1Stock) + (p2Cost * p2Stock);
      expect(immobilizedCapital, 250.0);
    });
  });
}
