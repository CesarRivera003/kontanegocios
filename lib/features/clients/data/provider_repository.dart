import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/provider_model.dart';

class ProviderRepository {
  final FirebaseFirestore _firestore;
  final String userId;

  ProviderRepository(this._firestore, this.userId);

  CollectionReference get _ref => 
      _firestore.collection('companies').doc(userId).collection('providers');

  Stream<List<ProviderModel>> getProviders() {
    return _ref.orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return ProviderModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  Future<void> saveProvider(ProviderModel provider) async {
    if (provider.id.isEmpty) {
      await _ref.add(provider.toMap());
    } else {
      await _ref.doc(provider.id).update(provider.toMap());
    }
  }

  Future<void> deleteProvider(String id) async {
    await _ref.doc(id).delete();
  }
}