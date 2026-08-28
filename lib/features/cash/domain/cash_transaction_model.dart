import 'package:cloud_firestore/cloud_firestore.dart';

enum CashTransactionType { income, expense }

class CashTransaction {
  final String id;
  final double amount;
  final CashTransactionType type;
  final String description;
  final DateTime date;
  final String userId;

  CashTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.description,
    required this.date,
    required this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type.name,
      'description': description,
      'date': Timestamp.fromDate(date),
      'userId': userId,
    };
  }

  factory CashTransaction.fromMap(Map<String, dynamic> map) {
    // BLINDAJE: Usamos valores por defecto si algo viene null para evitar crashes
    return CashTransaction(
      id: map['id']?.toString() ?? '',
      amount: double.tryParse(map['amount']?.toString() ?? '0') ?? 0.0,
      type: map['type'] == 'expense' ? CashTransactionType.expense : CashTransactionType.income,
      description: map['description']?.toString() ?? '',
      // Manejo seguro de fechas
      date: map['date'] is Timestamp 
          ? (map['date'] as Timestamp).toDate() 
          : DateTime.now(), 
      userId: map['userId']?.toString() ?? '',
    );
  }
}