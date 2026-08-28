import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/promotion_model.dart';

class PromotionsRepository {
  final FirebaseFirestore _firestore;
  final String userId;

  PromotionsRepository(this._firestore, this.userId);

  CollectionReference get _ref => 
      _firestore.collection('companies').doc(userId).collection('promotions');

  // Obtener solo promociones activas y vigentes (Opcional filtrar en cliente)
  Stream<List<Promotion>> getActivePromotions() {
    return _ref.where('isActive', isEqualTo: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Promotion.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }
  
  // Obtener todas para el panel de config
  Stream<List<Promotion>> getAllPromotions() {
    return _ref.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Promotion.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
    });
  }

  Future<void> savePromotion(Promotion promo) async {
    if (promo.id.isEmpty) {
      await _ref.add(promo.toMap());
    } else {
      await _ref.doc(promo.id).update(promo.toMap());
    }
  }

  Future<void> deletePromotion(String id) async {
    await _ref.doc(id).delete();
  }
}