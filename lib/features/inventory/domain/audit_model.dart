import 'package:cloud_firestore/cloud_firestore.dart';

class AuditLog {
  final String id;
  final DateTime date;
  final double totalGain; // Cuánto dinero "sobró"
  final double totalLoss; // Cuánto dinero se "perdió"
  final int itemsAdjusted; // Cuántos productos se tocaron
  final List<AuditItemDetail> details; // Lista detallada de cambios

  AuditLog({
    required this.id,
    required this.date,
    required this.totalGain,
    required this.totalLoss,
    required this.itemsAdjusted,
    required this.details,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'totalGain': totalGain,
      'totalLoss': totalLoss,
      'itemsAdjusted': itemsAdjusted,
      'details': details.map((x) => x.toMap()).toList(),
    };
  }

  factory AuditLog.fromMap(Map<String, dynamic> map, String id) {
    return AuditLog(
      id: id,
      date: (map['date'] as Timestamp).toDate(),
      totalGain: (map['totalGain'] ?? 0).toDouble(),
      totalLoss: (map['totalLoss'] ?? 0).toDouble(),
      itemsAdjusted: (map['itemsAdjusted'] ?? 0).toInt(),
      details: List<AuditItemDetail>.from(
        (map['details'] as List<dynamic>).map((x) => AuditItemDetail.fromMap(x))
      ),
    );
  }
}

class AuditItemDetail {
  final String productName;
  final String productId;
  final int oldStock;
  final int newStock;
  final double cost; // Costo unitario en ese momento

  AuditItemDetail({
    required this.productName,
    required this.productId,
    required this.oldStock,
    required this.newStock,
    required this.cost,
  });

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'productId': productId,
      'oldStock': oldStock,
      'newStock': newStock,
      'cost': cost,
    };
  }

  factory AuditItemDetail.fromMap(Map<String, dynamic> map) {
    return AuditItemDetail(
      productName: map['productName'] ?? '',
      productId: map['productId'] ?? '',
      oldStock: map['oldStock'] ?? 0,
      newStock: map['newStock'] ?? 0,
      cost: (map['cost'] ?? 0).toDouble(),
    );
  }
}