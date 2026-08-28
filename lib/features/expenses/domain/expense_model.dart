import 'package:cloud_firestore/cloud_firestore.dart';

// 1. CLASE PARA LOS ABONOS INDIVIDUALES (ESTA YA ESTABA BIEN)
class ExpensePayment {
  final DateTime date;
  final double amount;
  final String note;
  
  // NUEVOS CAMPOS PARA EL CUADRE
  final String paymentMethod; // 'Efectivo', 'Transferencia', etc.
  final String userId;        // Quién registró el abono
  final String userName;      // Nombre para mostrar en historial
  final String? bankName;     // Banco usado en el abono

  ExpensePayment({
    required this.date, 
    required this.amount, 
    this.note = '',
    this.paymentMethod = 'Efectivo',
    this.userId = '',
    this.userName = '',
    this.bankName,
  });

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(date),
    'amount': amount,
    'note': note,
    'paymentMethod': paymentMethod,
    'userId': userId,
    'userName': userName,
    'bankName': bankName,
  };

  factory ExpensePayment.fromMap(Map<String, dynamic> map) {
    return ExpensePayment(
      date: (map['date'] as Timestamp).toDate(),
      amount: (map['amount'] ?? 0).toDouble(),
      note: map['note'] ?? '',
      paymentMethod: map['paymentMethod'] ?? 'Efectivo',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      bankName: map['bankName'],
    );
  }
}

// 2. ACTUALIZACIÓN DEL MODELO DE GASTO
class Expense {
  final String id;
  final DateTime date;
  final String category;
  final String description;
  final String provider;
  final double amount;
  final String paymentMethod;
  
  final bool isPending; 
  final DateTime? paymentDeadline;
  final bool isPaid;
  final String observations; 
  final List<ExpensePayment> payments;

  // NUEVOS CAMPOS DE AUDITORÍA
  final String userId;    // Quién creó el gasto
  final String userName; // Nombre del creador
  
  // --- CAMPO NUEVO AGREGADO ---
  final String? bankName; // Nombre del banco (si fue Transferencia de contado)

  Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.description,
    this.provider = '',
    required this.amount,
    this.paymentMethod = 'Efectivo',
    this.isPending = false,
    this.paymentDeadline,
    this.isPaid = true,
    this.observations = '',
    this.payments = const [],
    this.userId = '',    
    this.userName = '', 
    // AGREGAR AL CONSTRUCTOR
    this.bankName, 
  });

  // Cálculos auxiliares
  double get totalPaid => payments.fold(0, (sum, p) => sum + p.amount);
  double get balance => amount - totalPaid;
  bool get isFullyPaid => balance <= 0;

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'category': category,
      'description': description,
      'provider': provider,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'isPending': isPending,
      'paymentDeadline': paymentDeadline != null ? Timestamp.fromDate(paymentDeadline!) : null,
      'isPaid': isFullyPaid,
      'observations': observations,
      'payments': payments.map((p) => p.toMap()).toList(),
      'userId': userId,     
      'userName': userName, 
      // GUARDAR EN BD
      'bankName': bankName, 
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map, String id) {
    return Expense(
      id: id,
      date: (map['date'] as Timestamp).toDate(),
      category: map['category'] ?? 'General',
      description: map['description'] ?? '',
      provider: map['provider'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      paymentMethod: map['paymentMethod'] ?? 'Efectivo',
      isPending: map['isPending'] ?? false,
      paymentDeadline: map['paymentDeadline'] != null ? (map['paymentDeadline'] as Timestamp).toDate() : null,
      isPaid: map['isPaid'] ?? true,
      observations: map['observations'] ?? '',
      payments: (map['payments'] as List<dynamic>? ?? [])
          .map((p) => ExpensePayment.fromMap(p as Map<String, dynamic>))
          .toList(),
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      // LEER DE BD
      bankName: map['bankName'], 
    );
  }
}