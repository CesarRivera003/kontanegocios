import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/user_management_repository.dart';
import '../../auth/domain/user_model.dart';

// Proveedor del Repositorio
final userManagementRepositoryProvider = Provider<UserManagementRepository>((ref) {
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) throw Exception("No autenticado");
  
  // Asumimos que el usuario actual es el "Dueño" o Admin
  return UserManagementRepository(FirebaseFirestore.instance, user.uid);
});

// Stream de la lista de usuarios
final companyUsersStreamProvider = StreamProvider<List<UserModel>>((ref) {
  return ref.watch(userManagementRepositoryProvider).getCompanyUsers();
});