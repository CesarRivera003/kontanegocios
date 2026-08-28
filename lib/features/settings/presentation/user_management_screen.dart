import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'user_management_providers.dart';
import '../../auth/domain/user_model.dart';

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(companyUsersStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Usuarios')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/settings/users/add'), // Ruta para crear
        child: const Icon(Icons.person_add),
      ),
      body: usersAsync.when(
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('No has creado usuarios adicionales.'));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getRoleColor(user.role),
                    child: Icon(_getRoleIcon(user.role), color: Colors.white),
                  ),
                  title: Text(user.name, style: TextStyle(
                    decoration: user.isActive ? null : TextDecoration.lineThrough,
                    color: user.isActive ? Colors.black : Colors.grey,
                  )),
                  subtitle: Text('${_getRoleName(user.role)} • ${user.email}'),
                  
                  // TRAILING: AHORA UN ROW CON SWITCH Y BOTÓN BORRAR
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Switch Activar/Desactivar
                      Switch(
                        value: user.isActive,
                        activeColor: Colors.green,
                        onChanged: (val) {
                          ref.read(userManagementRepositoryProvider).toggleUserStatus(user.id, val);
                        },
                      ),
                      // Botón Eliminar (NUEVO)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: "Eliminar Usuario",
                        onPressed: () => _confirmDeleteUser(context, ref, user.id, user.name),
                      ),
                    ],
                  ),
                  onTap: () => context.push('/settings/users/add', extra: user),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin: return Colors.purple;
      case UserRole.manager: return Colors.orange;
      case UserRole.cashier: return Colors.blue;
    }
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.admin: return Icons.admin_panel_settings;
      case UserRole.manager: return Icons.supervisor_account;
      case UserRole.cashier: return Icons.point_of_sale;
    }
  }

  String _getRoleName(UserRole role) {
    switch (role) {
      case UserRole.admin: return 'Administrador';
      case UserRole.manager: return 'Supervisor';
      case UserRole.cashier: return 'Cajero';
    }
  }

  void _confirmDeleteUser(BuildContext context, WidgetRef ref, String userId, String userName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar Usuario"),
        content: Text("¿Estás seguro de eliminar a $userName?\nEsta acción no se puede deshacer."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // Llamamos al repositorio para borrar
                await ref.read(userManagementRepositoryProvider).deleteUser(userId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Usuario eliminado")));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              }
            },
            child: const Text("ELIMINAR", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}