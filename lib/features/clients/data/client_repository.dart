import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/client_model.dart';

class ClientRepository {
  final FirebaseFirestore _firestore;
  final String userId;

  ClientRepository(this._firestore, this.userId);

  CollectionReference get _clientsRef => 
      _firestore.collection('companies').doc(userId).collection('clients');

  // 1. Obtener Clientes
  Stream<List<Client>> getClients() {
    return _clientsRef.orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Client.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // 2. Guardar / Actualizar
  Future<void> saveClient(Client client) async {
    if (client.id.isEmpty) {
      await _clientsRef.add(client.toMap());
    } else {
      await _clientsRef.doc(client.id).update(client.toMap());
    }
  }

  // 3. Verificar si tiene ventas antes de borrar
  Future<bool> hasSales(String clientName) async {
    // Buscamos en las ventas si el nombre del cliente aparece
    // Nota: Idealmente usaríamos ID, pero por ahora en Sales guardamos el nombre.
    final query = await _firestore
        .collection('companies')
        .doc(userId)
        .collection('sales')
        .where('clientName', isEqualTo: clientName)
        .limit(1)
        .get();

    return query.docs.isNotEmpty;
  }

  // 4. Eliminar Cliente
  Future<void> deleteClient(String id) async {
    await _firestore
        .collection('companies')
        .doc(userId)
        .collection('clients')
        .doc(id)
        .delete();
  }
}