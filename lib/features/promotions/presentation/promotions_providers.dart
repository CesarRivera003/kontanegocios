import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/promotions_repository.dart';
import '../domain/promotion_model.dart';

final promotionsRepositoryProvider = Provider<PromotionsRepository>((ref) {
  final userId = ref.watch(userIdProvider);
  if (userId == null) throw Exception('No user');
  return PromotionsRepository(FirebaseFirestore.instance, userId);
});

// Stream de todas las promociones (Para el panel de admin)
final allPromotionsStreamProvider = StreamProvider<List<Promotion>>((ref) {
  return ref.watch(promotionsRepositoryProvider).getAllPromotions();
});

// Stream solo de las activas (Para el carrito de ventas)
final activePromotionsStreamProvider = StreamProvider<List<Promotion>>((ref) {
  return ref.watch(promotionsRepositoryProvider).getActivePromotions();
});

// --- NUEVO: Stream público de promociones activas para el catálogo web ---
final publicActivePromotionsProvider = StreamProvider.family<List<Promotion>, String>((ref, businessId) {
  return FirebaseFirestore.instance
      .collection('companies')
      .doc(businessId)
      .collection('promotions')
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map((snapshot) {
        final promos = snapshot.docs.map((doc) => Promotion.fromMap(doc.data(), doc.id)).toList();
        // Filtramos en memoria para asegurar que la vigencia sea válida hoy
        return promos.where((promo) => promo.isValidNow()).toList();
      });
});