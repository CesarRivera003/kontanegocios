import 'package:cloud_firestore/cloud_firestore.dart';

enum PromotionType {
  seasonal, // 1. Descuento por fecha (% fijo)
  volume,   // 2. Descuento por cantidad mayorista
  buyXgetY  // 3. Pague X lleve Y (Gratis)
}

class Promotion {
  final String id;
  final String name;
  final PromotionType type;
  
  final List<String> targetProductIds; // Productos a los que aplica
  
  final double percentage; // Para tipos 1 y 2 (Ej: 10 para 10%)
  final int minQuantity;   // Para tipo 2 (Ej: 12 unidades)
  
  final int buyQuantity;   // Para tipo 3 (Compre 2)
  final int getQuantity;   // Para tipo 3 (Lleve 1 gratis)
  
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;

  Promotion({
    required this.id,
    required this.name,
    required this.type,
    required this.targetProductIds,
    this.percentage = 0.0,
    this.minQuantity = 0,
    this.buyQuantity = 0,
    this.getQuantity = 0,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
  });

  // Validar si la promoción está vigente hoy
  bool isValidNow() {
    final now = DateTime.now();
    return isActive && now.isAfter(startDate) && now.isBefore(endDate.add(const Duration(days: 1)));
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type.index, // Guardamos el índice del enum (0, 1, 2)
      'targetProductIds': targetProductIds,
      'percentage': percentage,
      'minQuantity': minQuantity,
      'buyQuantity': buyQuantity,
      'getQuantity': getQuantity,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'isActive': isActive,
    };
  }

  factory Promotion.fromMap(Map<String, dynamic> map, String id) {
    return Promotion(
      id: id,
      name: map['name'] ?? '',
      type: PromotionType.values[map['type'] ?? 0],
      targetProductIds: List<String>.from(map['targetProductIds'] ?? []),
      percentage: (map['percentage'] ?? 0).toDouble(),
      minQuantity: (map['minQuantity'] ?? 0).toInt(),
      buyQuantity: (map['buyQuantity'] ?? 0).toInt(),
      getQuantity: (map['getQuantity'] ?? 0).toInt(),
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: (map['endDate'] as Timestamp).toDate(),
      isActive: map['isActive'] ?? true,
    );
  }
}