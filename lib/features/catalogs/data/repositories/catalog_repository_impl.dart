// lib/features/catalogs/data/repositories/catalog_repository_impl.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/catalog_entity.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../models/catalog_model.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  final FirebaseFirestore _firestore;
  final String businessId; // Inyectado de forma segura, igual que en ClientRepository

  CatalogRepositoryImpl(this._firestore, this.businessId);

  // Referencia directa y blindada a la subcolección de catálogos de la empresa
  CollectionReference<Map<String, dynamic>> get _catalogsRef => 
      _firestore.collection('companies').doc(businessId).collection('catalogs');

  @override
  Future<List<CatalogEntity>> getCatalogs(String businessIdParam) async {
    try {
      final snapshot = await _catalogsRef
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => CatalogModel.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('Error al obtener los catálogos: $e');
    }
  }

  @override
  Future<CatalogEntity?> getCatalogById(String catalogId) async {
    try {
      final doc = await _catalogsRef.doc(catalogId).get();
      if (doc.exists && doc.data() != null) {
        return CatalogModel.fromJson(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      throw Exception('Error al obtener el catálogo: $e');
    }
  }

  @override
  Future<String> createCatalog(CatalogEntity catalog) async {
    try {
      // Usamos el factory inyectando el ID del negocio por seguridad
      final catalogModel = CatalogModel.fromEntity(catalog, forceBusinessId: businessId);

      final docRef = await _catalogsRef.add(catalogModel.toJson());
      return docRef.id;
    } catch (e) {
      throw Exception('Error al crear el catálogo: $e');
    }
  }

  @override
  Future<void> updateCatalog(CatalogEntity catalog) async {
    try {
      final catalogModel = CatalogModel.fromEntity(catalog, forceBusinessId: businessId);
      
      await _catalogsRef.doc(catalog.id).update(catalogModel.toJson());
    } catch (e) {
      throw Exception('Error al actualizar el catálogo: $e');
    }
  }

  @override
  Future<void> deleteCatalog(String catalogId) async {
    try {
      await _catalogsRef.doc(catalogId).delete();
    } catch (e) {
      throw Exception('Error al eliminar el catálogo: $e');
    }
  }
}