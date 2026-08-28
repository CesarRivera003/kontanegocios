import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 1. CAMBIO: Importamos Firestore en vez de Functions
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';

// 1. Proveedor del repositorio (instancia única)
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    FirebaseAuth.instance, 
    FirebaseFirestore.instance // 2. CAMBIO: Pasamos Firestore (Base de Datos)
  );
});

// 2. Proveedor del estado de autenticación (¿Está logueado?)
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// Este es el que faltaba. Extrae el UID del usuario logueado.
final userIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.asData?.value?.uid;
});

// NUEVO: Provider que determina el ID de la EMPRESA (Dueño)
final companyIdProvider = StreamProvider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;

  if (user == null) return Stream.value(null);

  // 1. Escuchamos el "Directorio de Usuarios" para ver si este email pertenece a un empleado
  // Nota: Usamos el email porque al login aún no sabemos el ownerId
  return FirebaseFirestore.instance
      .collection('user_directory')
      .doc(user.email) // Buscamos por email
      .snapshots()
      .map((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          // A. Si existe en directorio, devolvemos el ID del JEFE
          return snapshot.data()!['ownerId'] as String;
        }
        // B. Si no existe, asumimos que este usuario es el DUEÑO
        return user.uid;
      });
});