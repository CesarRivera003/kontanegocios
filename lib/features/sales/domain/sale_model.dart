import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_item_model.dart'; 

class PaymentMethodDetail {
  final String method;
  final double amount;
  final String? bankName;
  final DateTime? paymentDeadline;

  PaymentMethodDetail({
    required this.method,
    required this.amount,
    this.bankName,
    this.paymentDeadline,
  });

  Map<String, dynamic> toMap() => {
    'method': method,
    'amount': amount,
    'bankName': bankName,
    'paymentDeadline': paymentDeadline != null ? Timestamp.fromDate(paymentDeadline!) : null,
  };

  factory PaymentMethodDetail.fromMap(Map<String, dynamic> map) {
    return PaymentMethodDetail(
      method: map['method'] ?? 'Efectivo',
      amount: (map['amount'] ?? 0).toDouble(),
      bankName: map['bankName'],
      paymentDeadline: map['paymentDeadline'] != null ? (map['paymentDeadline'] as Timestamp).toDate() : null,
    );
  }
}

class SalePayment {
  final DateTime date;
  final double amount;
  final String note;
  final String method; 
  final String recordedBy; 

  SalePayment({
    required this.date,
    required this.amount,
    required this.note,
    this.method = 'Efectivo', 
    this.recordedBy = 'Admin', 
  });

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(date),
    'amount': amount,
    'note': note,
    'method': method,
    'recordedBy': recordedBy,
  };

  factory SalePayment.fromMap(Map<String, dynamic> map) {
    return SalePayment(
      date: (map['date'] as Timestamp).toDate(),
      amount: (map['amount'] ?? 0).toDouble(),
      note: map['note'] ?? '',
      method: map['method'] ?? 'Efectivo', 
      recordedBy: map['recordedBy'] ?? '',
    );
  }
}

class Sale {
  final String id;
  final DateTime date;
  final double total;
  final List<Map<String, dynamic>> items; 
  final String? clientName;
  final String? sellerName;
  final List<PaymentMethodDetail> initialPayments;
  final List<SalePayment> payments; 
  final List<Map<String, dynamic>> additionalCosts;

  // --- NUEVOS CAMPOS: FACTURACIÓN ELECTRÓNICA ---
  final bool isElectronicInvoice; 
  final String? cufe;             // Código Único de Factura Electrónica
  final String dianStatus;        // 'No Aplica', 'Pendiente', 'Aceptada', 'Rechazada'
  final String? pdfUrl;           // Link al PDF oficial de Plemsi
  final String? ticketNumber; // NUEVO: Ej: POS-00105
  final String? dianPrefix;   // NUEVO: Ej: SETT
  final int? dianNumber;      // NUEVO: Ej: 45
  final String? clientIdNumber;

  Sale({
    required this.id,
    required this.date,
    required this.total,
    required this.items,
    required this.initialPayments,
    this.clientName,
    this.clientIdNumber,
    this.sellerName,
    this.payments = const [], 
    this.additionalCosts = const [],
    
    this.isElectronicInvoice = false,
    this.cufe,
    this.dianStatus = 'No Aplica',
    this.pdfUrl,
    this.ticketNumber,
    this.dianPrefix,
    this.dianNumber,
  });

  double get paidInInitial => initialPayments.fold(0, (sum, p) => p.method == 'Crédito' ? sum : sum + p.amount);
  double get paidInInstallments => payments.fold(0, (sum, p) => sum + p.amount);
  double get totalPaidReal => paidInInitial + paidInInstallments;
  double get balance => total - totalPaidReal;
  String get paymentMethodsSummary => initialPayments.map((p) => p.method).toSet().join(', ');

  DateTime? get earliestDeadline {
    final credits = initialPayments.where((p) => p.paymentDeadline != null).toList();
    if (credits.isEmpty) return null;
    credits.sort((a,b) => a.paymentDeadline!.compareTo(b.paymentDeadline!));
    return credits.first.paymentDeadline;
  }
  
  int get daysOverdue => earliestDeadline != null ? DateTime.now().difference(earliestDeadline!).inDays : 0;

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'total': total,
      'items': items,
      'clientName': clientName ?? 'Cliente General',
      'clientIdNumber': clientIdNumber,
      'sellerName': sellerName ?? 'Admin',
      'initialPayments': initialPayments.map((p) => p.toMap()).toList(),
      'payments': payments.map((p) => p.toMap()).toList(),
      'additionalCosts': additionalCosts,
      
      'isElectronicInvoice': isElectronicInvoice,
      'cufe': cufe,
      'dianStatus': dianStatus,
      'pdfUrl': pdfUrl,
      'ticketNumber': ticketNumber,
      'dianPrefix': dianPrefix,
      'dianNumber': dianNumber,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map, String docId) {
    return Sale(
      id: docId,
      date: (map['date'] as Timestamp).toDate(),
      total: (map['total'] ?? 0).toDouble(),
      items: List<Map<String, dynamic>>.from(map['items'] ?? []),
      clientName: map['clientName'],
      clientIdNumber: map['clientIdNumber'],
      sellerName: map['sellerName'],
      initialPayments: (map['initialPayments'] as List<dynamic>? ?? [])
          .map((p) => PaymentMethodDetail.fromMap(p as Map<String, dynamic>))
          .toList(),
      payments: (map['payments'] as List<dynamic>? ?? [])
          .map((p) => SalePayment.fromMap(p as Map<String, dynamic>))
          .toList(),
      additionalCosts: List<Map<String, dynamic>>.from(map['additionalCosts'] ?? []),
      
      isElectronicInvoice: map['isElectronicInvoice'] ?? false,
      cufe: map['cufe'],
      dianStatus: map['dianStatus'] ?? 'No Aplica',
      pdfUrl: map['pdfUrl'],
      ticketNumber: map['ticketNumber'],
      dianPrefix: map['dianPrefix'],
      dianNumber: map['dianNumber'] != null ? (map['dianNumber'] as num).toInt() : null,
    );
  }

  static List<Map<String, dynamic>> cartItemsToMap(List<CartItem> cartItems) {
    return cartItems.map((item) {
      double commissionTotal = 0.0;
      if (item.product.hasCommission) {
        double unitCommission = item.price * (item.product.commissionPercentage / 100);
        commissionTotal = unitCommission * item.quantity;
      }
      return {
        'productId': item.product.id,
        'name': item.product.name,
        'quantity': item.quantity,
        'unit': item.product.unit,
        'price': item.price,
        'total': item.total,
        'commission': commissionTotal,
        // Al guardar la venta, también guardamos los datos tributarios del producto
        'taxRate': item.product.taxRate,
        'taxType': item.product.taxType,
      };
    }).toList();
  }
}