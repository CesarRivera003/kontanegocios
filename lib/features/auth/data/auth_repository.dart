import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math'; // <-- NECESARIO PARA GENERAR EL CÓDIGO

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
}

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepository(this._auth, this._firestore);

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  // --- NUEVO: GENERADOR DE CÓDIGO DE REFERIDO ---
  String _generateReferralCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final code = String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
    return 'KNT-$code'; // Ej: KNT-A8X92M
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String companyName,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final user = userCredential.user;
      if (user == null) throw AuthException("Error al crear usuario");

      final batch = _firestore.batch();

      final companyRef = _firestore.collection('companies').doc(user.uid);
      batch.set(companyRef, {
        'name': companyName,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'plan': 'trial', // Cambiado a trial por defecto
        'isActive': true,
      });

      final userRef = companyRef.collection('users').doc(user.uid);
      batch.set(userRef, {
        'name': 'Admin', 
        'email': email,
        'role': 'admin', 
        'createdAt': FieldValue.serverTimestamp(),
      });

      final profileRef = companyRef.collection('config').doc('profile');
      batch.set(profileRef, {
        'name': companyName,
        'email': email,
        // --- AQUÍ ESTÁ LA MAGIA DEL MOTOR VIRAL ---
        'referralCode': _generateReferralCode(),
        'referralCount': 0,
        'paidReferralCount': 0,
        'subscriptionStatus': 'trial',
        // Otorga 15 días gratis sumándolos a la fecha actual
        'trialEndsAt': DateTime.now().add(const Duration(days: 15)),
      });

      final defaultCashRef = companyRef.collection('bank_accounts').doc(); 
      batch.set(defaultCashRef, {
        'name': 'Caja Principal',
        'accountNumber': '',
        'balance': 0.0,
        'isCash': true,
        'isDefault': true, 
        'isActive': true,
      });

      await batch.commit();

    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    } catch (e) {
      throw AuthException("Error desconocido: $e");
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  String _handleFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found': 
      case 'wrong-password': 
      case 'invalid-credential': 
      case 'invalid-login-credentials': 
        return 'Correo o contraseña incorrecta. Intente de nuevo.';
      case 'email-already-in-use': 
        return 'El correo ya está registrado.';
      case 'invalid-email': 
        return 'El formato del correo es inválido.';
      case 'weak-password': 
        return 'La contraseña es muy débil (mínimo 6 caracteres).';
      default: 
        return 'Error de autenticación: ${e.code}'; 
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance, FirebaseFirestore.instance);
});