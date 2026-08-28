import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/product_model.dart';
import '../domain/audit_model.dart';

class InventoryRepository {
  final FirebaseFirestore _firestore;
  final String userId; // Necesitamos el ID para saber en qué "empresa" guardar

  InventoryRepository(this._firestore, this.userId);

  // Referencia a la colección de productos de este usuario
  CollectionReference get _productsRef => 
      _firestore.collection('companies').doc(userId).collection('products');

  // 1. OBTENER PRODUCTOS (En tiempo real)
  Stream<List<Product>> getProducts() {
    return _productsRef.orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Product.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // --- GUARDAR PRODUCTO (CREAR O EDITAR) ---
  // Este es el método que te faltaba o daba error
  Future<void> saveProduct(Product product) async {
  await _productsRef.doc(product.id).set(product.toMap(), SetOptions(merge: true));
  }
  
  // 2. AGREGAR PRODUCTO
  Future<void> addProduct(Product product) async {
    await _productsRef.add(product.toMap());
  }

  // 3. EDITAR PRODUCTO
  Future<void> updateProduct(Product product) async {
    await _productsRef.doc(product.id).update(product.toMap());
  }

  // 4. ELIMINAR PRODUCTO
  // EN INVENTORY_REPOSITORY.DART

  Future<void> deleteProduct(String productId) async {
    final companyRef = _firestore.collection('companies').doc(userId);
    
    // 1. VALIDACIÓN DE VENTAS ASOCIADAS
    // Buscamos en todas las ventas si este producto fue vendido alguna vez.
    // Nota: Si tienes miles de ventas, esto puede ser lento. 
    // (Lo ideal a futuro es marcar el producto como "Archivado" en vez de borrarlo).
    
    final salesSnap = await companyRef.collection('sales').get();
    
    final hasSales = salesSnap.docs.any((doc) {
      final items = List<Map<String, dynamic>>.from(doc.data()['items'] ?? []);
      // Buscamos si el ID del producto está en la lista de items de esa venta
      return items.any((item) => item['productId'] == productId);
    });

    if (hasSales) {
      throw Exception("No se puede eliminar: El producto tiene historial de ventas. Te sugerimos editarlo y poner stock 0 o cambiarle el nombre a 'OBSOLETO'.");
    }

    // 2. SI NO TIENE VENTAS, PROCEDEMOS A BORRAR
    await companyRef.collection('products').doc(productId).delete();
  }

  // Verificar si un código de barras ya existe (excluyendo el producto actual si estamos editando)
  Future<bool> barcodeExists(String barcode, {String? excludeId}) async {
    final query = _productsRef.where('barcode', isEqualTo: barcode);
    final snapshot = await query.get();

    // Si no hay documentos, es falso (no existe)
    if (snapshot.docs.isEmpty) return false;

    // Si hay documentos, verificamos si es el mismo que estamos editando
    if (excludeId != null) {
      for (var doc in snapshot.docs) {
        if (doc.id != excludeId) return true; // Existe en OTRO producto
      }
      return false; // Solo existe en este mismo (es válido)
    }
    
    return true; // Existe y es un producto nuevo
  }

  // --- IMPORTACIÓN MASIVA Y ACTUALIZACIÓN POR LOTES ---
  Future<void> importProducts(List<Product> products) async {
    // Firestore tiene un límite de 500 escrituras por lote.
    int chunkSize = 400;
    
    for (var i = 0; i < products.length; i += chunkSize) {
      final batch = _firestore.batch();
      final chunk = products.skip(i).take(chunkSize);

      for (var product in chunk) {
        DocumentReference docRef;

        // --- CORRECCIÓN AQUÍ ---
        if (product.id.isNotEmpty) {
          // CASO 1: ARQUEO / EDICIÓN MASIVA
          // Si ya tiene ID, apuntamos al documento existente para ACTUALIZARLO.
          docRef = _productsRef.doc(product.id);
        } else {
          // CASO 2: IMPORTAR EXCEL (Nuevos)
          // Si no tiene ID (viene vacío), generamos uno nuevo.
          docRef = _productsRef.doc();
        }

        // Usamos merge: true por seguridad, para que si el producto existe,
        // actualice los campos cambiados (stock) sin borrar lo demás accidentalmente.
        batch.set(docRef, product.toMap(), SetOptions(merge: true));
      }
      
      // Ejecutamos el lote
      await batch.commit();
    }
  }

  // Referencia a la colección de logs de auditoría
  CollectionReference get _auditRef => 
      _firestore.collection('companies').doc(userId).collection('audit_logs');

  // 1. GUARDAR LOG (Se llamará al finalizar el arqueo)
  Future<void> saveAuditLog(AuditLog log) async {
    await _auditRef.add(log.toMap());
  }

  // 2. OBTENER HISTORIAL (Ordenado por fecha descendente)
  Stream<List<AuditLog>> getAuditHistory() {
    return _auditRef.orderBy('date', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return AuditLog.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }
}