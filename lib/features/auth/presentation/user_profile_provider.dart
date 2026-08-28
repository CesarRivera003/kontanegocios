import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_providers.dart'; // Donde tienes authRepositoryProvider y companyIdProvider
import '../domain/user_model.dart';

// Este provider te da el objeto UserModel completo del usuario actual
final userProfileProvider = StreamProvider<UserModel?>((ref) {
  final authUser = ref.watch(authStateProvider).value;
  final companyIdAsync = ref.watch(companyIdProvider);
  
  // Si no hay usuario o aún no sabemos la empresa, retornamos null
  if (authUser == null || companyIdAsync.value == null) {
    return Stream.value(null);
  }

  final companyId = companyIdAsync.value!;

  // AHORA BUSCAMOS EN LA BASE DE DATOS PARA TODOS (DUEÑOS Y CAJEROS)
  return FirebaseFirestore.instance
      .collection('companies')
      .doc(companyId)
      .collection('users')
      .doc(authUser.uid)
      .snapshots()
      .map((snapshot) {
        
        // 1. SI EXISTE EL PERFIL (Camino ideal): 
        // Como ya guardaste tu nombre en configuración, la app entrará por aquí
        // y te reconocerá como "Cesar" con todos tus poderes de administrador.
        if (snapshot.exists && snapshot.data() != null) {
          return UserModel.fromMap(snapshot.data()!, snapshot.id);
        }

        // 2. SALVAVIDAS (Si es el dueño pero aún no crea su perfil con su nombre):
        if (authUser.uid == companyId) {
          return UserModel(
            id: authUser.uid,
            email: authUser.email ?? '',
            name: authUser.displayName ?? 'Admin',
            role: UserRole.admin, // El dueño siempre es admin
            ownerId: authUser.uid,
            isActive: true
          );
        }

        // 3. Si no existe y no es el dueño (ej. empleado borrado)
        return null;
      });
});