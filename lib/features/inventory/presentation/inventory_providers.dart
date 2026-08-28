import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/inventory_repository.dart';
import '../domain/product_model.dart';

// 1. Proveedor del Repositorio
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  // 1. Esperamos a saber cuál es la empresa
  final companyIdAsync = ref.watch(companyIdProvider);
  
  // 2. Si aún está cargando o no hay usuario, lanzamos error o loading
  final String? companyId = companyIdAsync.value;
  if (companyId == null) throw Exception('Cargando empresa...');

  // 3. Usamos el ID de la EMPRESA, no del usuario logueado
  return InventoryRepository(FirebaseFirestore.instance, companyId);
});

// 2. Proveedor de la Lista de Productos (Stream)
final productsStreamProvider = StreamProvider<List<Product>>((ref) {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.getProducts(); 
});

// --- NUEVO: PROVEEDOR PÚBLICO DE INVENTARIO PARA CATÁLOGOS ---
// Este proveedor no depende del usuario logueado, sino que recibe el ID de la empresa por parámetro
final publicInventoryStreamProvider = StreamProvider.family<List<Product>, String>((ref, businessId) {
  return FirebaseFirestore.instance
      .collection('companies')
      .doc(businessId)
      .collection('products')
      .snapshots()
      .map((snapshot) {
        return snapshot.docs
            .map((doc) => Product.fromMap(doc.data(), doc.id))
            .toList();
      });
});

// 3. NOTIFIERS PARA LISTAS (CATEGORÍAS Y UNIDADES)

// --- NOTIFIER DE CATEGORÍAS ---
class CategoriesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    // 1. Estado inicial por defecto para que la UI no se quede en blanco
    final defaultCategories = ['General', 'Bebidas', 'Alimentos', 'Servicios', 'Tecnología'];
    
    // 2. Disparamos la sincronización con Firebase en segundo plano
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
        .doc('inventory');

    try {
      final doc = await docRef.get();
      if (doc.exists && doc.data() != null && doc.data()!.containsKey('categories')) {
        // Si ya existen en Firebase, reemplazamos la memoria con lo que hay en la nube
        final List<dynamic> dbCategories = doc.data()!['categories'];
        state = dbCategories.map((e) => e.toString()).toList();
      } else {
        // ¡LA SOLUCIÓN! Si no existen, guardamos la lista por defecto en Firebase
        await docRef.set({
          'categories': defaultList
        }, SetOptions(merge: true));
        state = defaultList;
      }
    } catch (e) {
      print("Error sincronizando categorías: $e");
    }
  }

  Future<void> add(String item) async {
    final catTrimmed = item.trim();
    if (catTrimmed.isEmpty || state.contains(catTrimmed)) return;

    // Actualiza la pantalla instantáneamente
    state = [...state, catTrimmed];
    
    // Lo guarda en Firebase
    final companyId = ref.read(companyIdProvider).value;
    if (companyId != null && companyId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('config')
          .doc('inventory')
          .set({
            'categories': FieldValue.arrayUnion([catTrimmed])
          }, SetOptions(merge: true));
    }
  }

  Future<void> remove(String item) async {
    if (item == 'General') return; // Proteger categoría principal

    // Actualiza la pantalla instantáneamente
    state = state.where((element) => element != item).toList();
    
    // Lo borra de Firebase
    final companyId = ref.read(companyIdProvider).value;
    if (companyId != null && companyId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('config')
          .doc('inventory')
          .set({
            'categories': FieldValue.arrayRemove([item])
          }, SetOptions(merge: true));
    }
  }
}

final productCategoriesProvider = NotifierProvider<CategoriesNotifier, List<String>>(() {
  return CategoriesNotifier();
});

// --- NOTIFIER DE UNIDADES ---
class UnitsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final defaultUnits = ['Und', 'Kg', 'Mts', 'Litro', 'Caja', 'Paquete'];
    _syncWithFirestore(defaultUnits);
    return defaultUnits;
  }

  Future<void> _syncWithFirestore(List<String> defaultList) async {
    final companyId = ref.read(companyIdProvider).value;
    if (companyId == null || companyId.isEmpty) return;

    final docRef = FirebaseFirestore.instance
        .collection('companies')
        .doc(companyId)
        .collection('config')
        .doc('inventory');

    try {
      final doc = await docRef.get();
      if (doc.exists && doc.data() != null && doc.data()!.containsKey('units')) {
        final List<dynamic> dbUnits = doc.data()!['units'];
        state = dbUnits.map((e) => e.toString()).toList();
      } else {
        await docRef.set({
          'units': defaultList
        }, SetOptions(merge: true));
        state = defaultList;
      }
    } catch (e) {
      print("Error sincronizando unidades: $e");
    }
  }

  Future<void> add(String item) async {
    final itemTrimmed = item.trim();
    if (itemTrimmed.isEmpty || state.contains(itemTrimmed)) return;

    state = [...state, itemTrimmed];
    
    final companyId = ref.read(companyIdProvider).value;
    if (companyId != null && companyId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('config')
          .doc('inventory')
          .set({
            'units': FieldValue.arrayUnion([itemTrimmed])
          }, SetOptions(merge: true));
    }
  }

  Future<void> remove(String item) async {
    if (item == 'Und') return; // Proteger unidad principal

    state = state.where((element) => element != item).toList();
    
    final companyId = ref.read(companyIdProvider).value;
    if (companyId != null && companyId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('config')
          .doc('inventory')
          .set({
            'units': FieldValue.arrayRemove([item])
          }, SetOptions(merge: true));
    }
  }
}

final productUnitsProvider = NotifierProvider<UnitsNotifier, List<String>>(() {
  return UnitsNotifier();
});