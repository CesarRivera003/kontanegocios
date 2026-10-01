import 'package:cloud_firestore/cloud_firestore.dart';

// ===========================================================================
// MODELO DE NOTA DÉBITO
// ===========================================================================
class DebitNote {
  final String id;
  final String ndPrefix;
  final int ndNumber;
  final String originalFactura;
  final String cude;
  final double totalAdded;
  final String reason;
  final DateTime date;

  DebitNote({
    required this.id,
    required this.ndPrefix,
    required this.ndNumber,
    required this.originalFactura,
    required this.cude,
    required this.totalAdded,
    required this.reason,
    required this.date,
  });

  factory DebitNote.fromMap(Map<String, dynamic> map, String docId) {
    return DebitNote(
      id: docId,
      ndPrefix: map['ndPrefix'] ?? 'ND',
      ndNumber: (map['ndNumber'] ?? 0).toInt(),
      originalFactura: map['originalFactura'] ?? '',
      cude: map['cude'] ?? '',
      totalAdded: (map['totalAdded'] ?? 0).toDouble(),
      reason: map['reason'] ?? '',
      date: map['date'] != null ? (map['date'] as Timestamp).toDate() : DateTime.now(),
    );
  }
}