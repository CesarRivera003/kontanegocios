import 'package:cloud_firestore/cloud_firestore.dart';

class CreditNote {
  final String id;
  final String ncPrefix;
  final int ncNumber;
  final String originalFactura;
  final String cude;
  final DateTime date;

  CreditNote({
    required this.id,
    required this.ncPrefix,
    required this.ncNumber,
    required this.originalFactura,
    required this.cude,
    required this.date,
  });

  factory CreditNote.fromMap(Map<String, dynamic> map, String docId) {
    return CreditNote(
      id: docId,
      ncPrefix: map['ncPrefix'] ?? 'NC',
      ncNumber: (map['ncNumber'] ?? 0).toInt(),
      originalFactura: map['originalFactura'] ?? '',
      cude: map['cude'] ?? '',
      date: map['date'] != null ? (map['date'] as Timestamp).toDate() : DateTime.now(),
    );
  }
}