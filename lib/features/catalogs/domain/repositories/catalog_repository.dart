// lib/features/catalogs/domain/repositories/catalog_repository.dart

import '../entities/catalog_entity.dart';

abstract class CatalogRepository {
  /// Obtiene todos los catálogos pertenecientes a un negocio específico
  Future<List<CatalogEntity>> getCatalogs(String businessId);

  /// Obtiene los detalles de un catálogo específico por su ID (ideal para la vista pública)
  Future<CatalogEntity?> getCatalogById(String catalogId);

  /// Guarda un nuevo catálogo en la base de datos y devuelve el ID generado
  Future<String> createCatalog(CatalogEntity catalog);

  /// Actualiza la información o contenido de un catálogo existente
  Future<void> updateCatalog(CatalogEntity catalog);

  /// Elimina un catálogo de la base de datos
  Future<void> deleteCatalog(String catalogId);
}