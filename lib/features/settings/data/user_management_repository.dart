import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; // <--- Importante
import '../../auth/domain/user_model.dart';

class UserManagementRepository {
  final FirebaseFirestore _firestore;
  final String currentAdminId; // El ID de quien está logueado actualmente

  UserManagementRepository(this._firestore, this.currentAdminId);

  // Referencia donde se guardan los empleados de ESTA empresa
  CollectionReference get _usersRef => 
      _firestore.collection('companies').doc(currentAdminId).collection('users');

  // 1. OBTENER LISTA DE USUARIOS
  Stream<List<UserModel>> getCompanyUsers() {
    return _usersRef.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // 2. CREAR NUEVO USUARIO (USANDO CLOUD FUNCTIONS)
  // Esta función ahora delega el trabajo pesado a la nube para saltarse las restricciones
  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    required UserRole role,
  }) async {
    try {
      final functions = FirebaseFunctions.instance;
      
      // Llamamos a la función 'createEmployee' que subiste con 'firebase deploy'
      final result = await functions.httpsCallable('createEmployee').call({
        'email': email,
        'password': password,
        'name': name,
        'role': role.name,
        'companyId': currentAdminId
      });

      // Si la función responde éxito, no necesitamos hacer nada más aquí.
      print("Respuesta de Cloud Function: ${result.data}");
      
    } catch (e) {
      // Capturamos errores de la nube (ej: email ya existe, contraseña débil)
      if (e is FirebaseFunctionsException) {
        throw Exception("Error de Nube: ${e.message}");
      }
      throw Exception("Error al crear usuario: $e");
    }
  }

  // 3. EDITAR ROL O ESTADO
  // Esto sí lo podemos hacer directo porque las reglas permiten al dueño editar sus empleados
  Future<void> updateUser(UserModel user) async {
    await _usersRef.doc(user.id).update(user.toMap());
  }

  // 4. ACTIVAR / DESACTIVAR
  Future<void> toggleUserStatus(String userId, bool isActive) async {
    await _usersRef.doc(userId).update({'isActive': isActive});
  }

  // 5. ELIMINAR USUARIO
  Future<void> deleteUser(String userId) async {
    // Usamos _usersRef que es la variable que ya tienes definida arriba
    await _usersRef.doc(userId).delete();
  }
}