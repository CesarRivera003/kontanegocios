import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/catalog_entity.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../auth/presentation/auth_providers.dart';

// 1. Inyección de Dependencias
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  // Escuchamos el ID de la empresa usando el mismo estándar de tu app
  final companyIdAsync = ref.watch(companyIdProvider);
  final String? companyId = companyIdAsync.value;
  
  if (companyId == null) {
    throw Exception('Cargando empresa...');
  }
  
  // Inyectamos Firestore y el companyId
  return CatalogRepositoryImpl(FirebaseFirestore.instance, companyId);
});

// 2. Clase de Estado (Se mantiene exactamente igual)
class CatalogState {
  final bool isLoading;
  final List<CatalogEntity> catalogs;
  final String? errorMessage;

  CatalogState({
    this.isLoading = false,
    this.catalogs = const [],
    this.errorMessage,
  });

  CatalogState copyWith({
    bool? isLoading,
    List<CatalogEntity>? catalogs,
    String? errorMessage,
  }) {
    return CatalogState(
      isLoading: isLoading ?? this.isLoading,
      catalogs: catalogs ?? this.catalogs,
      errorMessage: errorMessage,
    );
  }
}

// 3. El Controlador (Actualizado a Notifier moderno)
class CatalogNotifier extends Notifier<CatalogState> {
  
  @override
  CatalogState build() {
    // En el nuevo estándar, el estado inicial se define dentro del método build()
    return CatalogState();
  }

  // Obtenemos el repositorio directamente usando el 'ref' que ya viene integrado en Notifier
  CatalogRepository get _repository => ref.read(catalogRepositoryProvider);

  /// Carga la lista de catálogos de un negocio
  Future<void> loadCatalogs(String businessId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final catalogs = await _repository.getCatalogs(businessId);
      state = state.copyWith(isLoading: false, catalogs: catalogs);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Error al cargar catálogos: $e');
    }
  }

  /// Crea un nuevo catálogo y actualiza la lista local
  Future<bool> createCatalog(CatalogEntity newCatalog) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final newId = await _repository.createCatalog(newCatalog);
      
      final catalogWithId = CatalogEntity(
        id: newId,
        businessId: newCatalog.businessId,
        name: newCatalog.name,
        isActive: newCatalog.isActive,
        config: newCatalog.config,
        content: newCatalog.content,
        createdAt: newCatalog.createdAt,
        updatedAt: newCatalog.updatedAt,
      );

      state = state.copyWith(
        isLoading: false,
        catalogs: [catalogWithId, ...state.catalogs],
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Error al crear catálogo: $e');
      return false;
    }
  }

  /// Actualiza un catálogo existente (como sus bloques de contenido)
  Future<bool> updateCatalog(CatalogEntity updatedCatalog) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      // Actualizamos la fecha de modificación
      final catalogToSave = updatedCatalog.copyWith(updatedAt: DateTime.now());
      
      // Llamamos al repositorio (Firebase)
      await _repository.updateCatalog(catalogToSave);
      
      // Actualizamos la lista local reemplazando el catálogo antiguo con el nuevo
      state = state.copyWith(
        isLoading: false,
        catalogs: state.catalogs.map((c) => c.id == catalogToSave.id ? catalogToSave : c).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Error al guardar cambios: $e');
      return false;
    }
  }

  /// Elimina un catálogo
  Future<void> deleteCatalog(String catalogId) async {
    try {
      await _repository.deleteCatalog(catalogId);
      state = state.copyWith(
        catalogs: state.catalogs.where((c) => c.id != catalogId).toList(),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error al eliminar catálogo: $e');
    }
  }
}

// 4. El Provider principal (Actualizado a NotifierProvider)
final catalogNotifierProvider = NotifierProvider<CatalogNotifier, CatalogState>(() {
  return CatalogNotifier();
});