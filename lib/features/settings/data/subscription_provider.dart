import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SubscriptionRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> applyReferralCode(String myCompanyId, String enteredCode) async {
    final cleanCode = enteredCode.trim().toUpperCase();

    // 1. EL CAMBIO CLAVE: Usamos collectionGroup para buscar dentro de las subcolecciones 'config'
    final query = await _db.collectionGroup('config')
        .where('referralCode', isEqualTo: cleanCode)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('El código no existe. Verifica e intenta de nuevo.');
    }

    // 2. Referencia al perfil del amigo (El documento 'profile' exacto)
    final inviterProfileRef = query.docs.first.reference;
    
    // 3. Referencia a MI propio perfil exacto
    final myProfileRef = _db.collection('companies').doc(myCompanyId).collection('config').doc('profile');

    // Validamos que no intente usar su propio código
    // (Extraemos el ID de la empresa a partir de la ruta del documento del amigo)
    final inviterCompanyId = inviterProfileRef.parent.parent?.id;
    if (inviterCompanyId == myCompanyId) {
      throw Exception('No puedes usar tu propio código de invitación.');
    }

    // 4. TRANSACCIÓN CORREGIDA
    await _db.runTransaction((transaction) async {
      final myCompanySnap = await transaction.get(myProfileRef);
      final inviterSnap = await transaction.get(inviterProfileRef);

      final myData = myCompanySnap.data();
      final inviterData = inviterSnap.data();

      if (myData == null || inviterData == null) {
        throw Exception('Error leyendo los datos.');
      }

      if (myData['referredBy'] != null && myData['referredBy'].toString().isNotEmpty) {
        throw Exception('Ya has utilizado un código de invitado previamente.');
      }

      final now = DateTime.now();
      
      // Fechas
      DateTime inviterDate = inviterData['trialEndsAt']?.toDate() ?? now;
      if (inviterDate.isBefore(now)) inviterDate = now;
      final newInviterDate = inviterDate.add(const Duration(days: 30));

      DateTime myDate = myData['trialEndsAt']?.toDate() ?? now;
      if (myDate.isBefore(now)) myDate = now;
      final newMyDate = myDate.add(const Duration(days: 15));

      // Actualizamos LOS PERFILES, no la raíz
      transaction.update(inviterProfileRef, {
        'referralCount': FieldValue.increment(1),
        'trialEndsAt': Timestamp.fromDate(newInviterDate),
      });

      transaction.update(myProfileRef, {
        'referredBy': cleanCode,
        'trialEndsAt': Timestamp.fromDate(newMyDate),
      });
    });
  }
}

final subscriptionRepositoryProvider = Provider((ref) => SubscriptionRepository());