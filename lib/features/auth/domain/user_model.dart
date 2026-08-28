enum UserRole { admin, manager, cashier }

class UserModel {
  final String id;
  final String email;
  final String name;
  final UserRole role;
  final bool isActive;
  final String ownerId;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.isActive = true,
    required this.ownerId,
  });

  // --- 1. REGLAS DE MENÚS (¿Qué puede ver en la barra lateral?) ---
  bool get showMenuExpenses => role == UserRole.admin || role == UserRole.manager;
  bool get showMenuReports  => role == UserRole.admin;
  bool get showMenuSettings => role == UserRole.admin || role == UserRole.manager;
  
  // El cajero solo ve: Ventas, Historial, Inventario, Contactos.
  // (Estos menús siempre son true, así que no necesitamos getters para restringirlos,
  // pero los pongo por claridad lógica si quisieras).
  
  // --- 2. REGLAS DE ACCIÓN (¿Qué puede tocar?) ---
  
  // Solo Admin y Supervisor pueden EDITAR o CREAR datos en Inventario/Contactos
  bool get canEditData => role == UserRole.admin || role == UserRole.manager;
  
  // Solo Admin y Supervisor pueden BORRAR cosas (El Supervisor puede borrar productos, pero no usuarios)
  bool get canDeleteItems => role == UserRole.admin || role == UserRole.manager;
  
  // --- 3. REGLAS DE PRIVACIDAD (¿Qué puede saber?) ---
  
  // Solo Admin y Supervisor pueden ver COSTOS y GANANCIAS
  bool get canViewCosts => role == UserRole.admin || role == UserRole.manager;

  // --- 4. REGLAS ADMINISTRATIVAS ---
  
  // Solo Admin puede gestionar USUARIOS (Crear/Borrar empleados)
  bool get canManageUsers => role == UserRole.admin;
  
  // Solo Admin puede editar los DATOS DE LA EMPRESA (Nombre, Logo, Plan)
  bool get canEditCompanyConfig => role == UserRole.admin;

  // --- BOILERPLATE (Serialización) ---
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role.name,
      'isActive': isActive,
      'ownerId': ownerId,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      id: docId,
      email: map['email'] ?? '',
      name: map['name'] ?? 'Usuario',
      role: UserRole.values.firstWhere(
        (e) => e.name == (map['role'] ?? 'cashier'), 
        orElse: () => UserRole.cashier
      ),
      isActive: map['isActive'] ?? true,
      ownerId: map['ownerId'] ?? '',
    );
  }
}