import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/client_repository.dart';
import '../domain/client_model.dart';
import '../data/provider_repository.dart';
import '../domain/provider_model.dart';


final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  final companyId = ref.watch(companyIdProvider).value;
  if (companyId == null) throw Exception('Cargando empresa...');
  
  return ClientRepository(FirebaseFirestore.instance, companyId);
});

final clientsStreamProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(clientRepositoryProvider).getClients();
});

// REPOSITORIO
final providerRepositoryProvider = Provider<ProviderRepository>((ref) {
  final companyId = ref.watch(companyIdProvider).value;
  if (companyId == null) throw Exception('Cargando empresa...');
  
  return ProviderRepository(FirebaseFirestore.instance, companyId);
});

// STREAM DE PROVEEDORES
final providersStreamProvider = StreamProvider<List<ProviderModel>>((ref) {
  return ref.watch(providerRepositoryProvider).getProviders();
});

// --- NOTIFIER DE CATEGORÍAS DE PROVEEDORES ---
class ProviderCategoriesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final defaultCategories = ['General', 'Insumos', 'Servicios', 'Transporte', 'Arriendos'];
    _syncWithFirestore(defaultCategories);
    return defaultCategories;
  }

  Future<void> _syncWithFirestore(List<String> defaultList) async {
    final companyId = ref.read(companyIdProvider).value;
    if (companyId == null || companyId.isEmpty) return;

    final docRef = FirebaseFirestore.instance
        .collection('companies')
        .doc(companyId)
        .collection('config')
        .doc('providers'); // Usamos un documento específico para proveedores

    try {
      final doc = await docRef.get();
      if (doc.exists && doc.data() != null && doc.data()!.containsKey('categories')) {
        final List<dynamic> dbCategories = doc.data()!['categories'];
        state = dbCategories.map((e) => e.toString()).toList();
      } else {
        await docRef.set({
          'categories': defaultList
        }, SetOptions(merge: true));
        state = defaultList;
      }
    } catch (e) {
      print("Error sincronizando categorías de proveedores: $e");
    }
  }

  Future<void> add(String item) async {
    final catTrimmed = item.trim();
    if (catTrimmed.isEmpty || state.contains(catTrimmed)) return;

    state = [...state, catTrimmed];
    
    final companyId = ref.read(companyIdProvider).value;
    if (companyId != null && companyId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('config')
          .doc('providers')
          .set({
            'categories': FieldValue.arrayUnion([catTrimmed])
          }, SetOptions(merge: true));
    }
  }

  Future<void> remove(String item) async {
    if (item == 'General') return; // Proteger categoría principal

    state = state.where((element) => element != item).toList();
    
    final companyId = ref.read(companyIdProvider).value;
    if (companyId != null && companyId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('config')
          .doc('providers')
          .set({
            'categories': FieldValue.arrayRemove([item])
          }, SetOptions(merge: true));
    }
  }
}

final providerCategoriesProvider = NotifierProvider<ProviderCategoriesNotifier, List<String>>(() {
  return ProviderCategoriesNotifier();
});