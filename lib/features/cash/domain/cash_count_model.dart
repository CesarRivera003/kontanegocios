// Archivo: cash_count_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class CashCountModel {
  final String id;
  final DateTime date;
  final String userId;
  final String userName;
  final String userRole;
  
  final double baseAmount; 
  final double provisions; 
  final double cashSales;  
  final double cashExpenses; 
  
  final double theoreticalBalance; 
  final double realBalance; 
  final double difference;

  // NUEVO: Lista de mapas para guardar "Qué fue lo que pasó"
  // Ejemplo: [{'desc': 'Taxi', 'amount': 10000, 'type': 'expense'}]
  final List<Map<String, dynamic>> movementsDetail; 
  
  // NUEVO: Campo para saber cuánto se dejó para mañana
  final double nextDayBase;

  CashCountModel({
    required this.id,
    required this.date,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.baseAmount,
    required this.provisions,
    required this.cashSales,
    required this.cashExpenses,
    required this.theoreticalBalance,
    required this.realBalance,
    required this.difference,
    this.movementsDetail = const [], // Por defecto vacía
    this.nextDayBase = 0.0,          // Por defecto 0
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': Timestamp.fromDate(date),
      'userId': userId,
      'userName': userName,
      'userRole': userRole,
      'baseAmount': baseAmount,
      'provisions': provisions, 
      'cashSales': cashSales,
      'cashExpenses': cashExpenses,
      'theoreticalBalance': theoreticalBalance,
      'realBalance': realBalance,
      'difference': difference,
      'movementsDetail': movementsDetail, // Guardamos la lista
      'nextDayBase': nextDayBase,
    };
  }

  factory CashCountModel.fromMap(Map<String, dynamic> map) {
    return CashCountModel(
      id: map['id']?.toString() ?? '',
      date: map['date'] is Timestamp 
          ? (map['date'] as Timestamp).toDate() 
          : DateTime.now(),
      userId: map['userId']?.toString() ?? '',
      userName: map['userName']?.toString() ?? 'Usuario',
      userRole: map['userRole']?.toString() ?? '',
      baseAmount: double.tryParse(map['baseAmount']?.toString() ?? '0') ?? 0.0,
      provisions: double.tryParse(map['provisions']?.toString() ?? '0') ?? 0.0,
      cashSales: double.tryParse(map['cashSales']?.toString() ?? '0') ?? 0.0,
      cashExpenses: double.tryParse(map['cashExpenses']?.toString() ?? '0') ?? 0.0,
      theoreticalBalance: double.tryParse(map['theoreticalBalance']?.toString() ?? '0') ?? 0.0,
      realBalance: double.tryParse(map['realBalance']?.toString() ?? '0') ?? 0.0,
      difference: double.tryParse(map['difference']?.toString() ?? '0') ?? 0.0,
      // Recuperamos la lista de detalles de forma segura
      movementsDetail: List<Map<String, dynamic>>.from(map['movementsDetail'] ?? []),
      nextDayBase: double.tryParse(map['nextDayBase']?.toString() ?? '0') ?? 0.0,
    );
  }
}