import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/domain/user_model.dart';
import 'user_management_providers.dart';

class SaveUserScreen extends ConsumerStatefulWidget {
  final UserModel? userToEdit;
  const SaveUserScreen({super.key, this.userToEdit});

  @override
  ConsumerState<SaveUserScreen> createState() => _SaveUserScreenState();
}

class _SaveUserScreenState extends ConsumerState<SaveUserScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _passCtrl;
  
  UserRole _selectedRole = UserRole.cashier;
  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.userToEdit != null;
    
    _nameCtrl = TextEditingController(text: widget.userToEdit?.name ?? '');
    _emailCtrl = TextEditingController(text: widget.userToEdit?.email ?? '');
    _passCtrl = TextEditingController(); // Vacío al editar
    
    if (_isEditing) {
      _selectedRole = widget.userToEdit!.role;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final repo = ref.read(userManagementRepositoryProvider);

      if (_isEditing) {
        // ACTUALIZAR ROL O NOMBRE (No cambiamos password ni email aquí por seguridad simple)
        final updatedUser = UserModel(
          id: widget.userToEdit!.id,
          email: _emailCtrl.text, // Mantenemos el email visualmente
          name: _nameCtrl.text.trim(),
          role: _selectedRole,
          ownerId: widget.userToEdit!.ownerId,
          isActive: widget.userToEdit!.isActive,
        );
        await repo.updateUser(updatedUser);
        
      } else {
        // CREAR NUEVO USUARIO
        await repo.createUser(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          role: _selectedRole,
        ).timeout(const Duration(seconds: 10), onTimeout: () {}); // Timeout por seguridad
      }

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuario guardado exitosamente'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar Usuario' : 'Nuevo Usuario')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // NOMBRE
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre del Empleado', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 15),

              // EMAIL (Solo lectura si se edita para no romper Auth)
              TextFormField(
                controller: _emailCtrl,
                readOnly: _isEditing,
                decoration: InputDecoration(
                  labelText: 'Correo Electrónico', 
                  border: const OutlineInputBorder(), 
                  prefixIcon: const Icon(Icons.email),
                  filled: _isEditing,
                  fillColor: Colors.grey[200]
                ),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 15),

              // PASSWORD (Solo al crear)
              if (!_isEditing) ...[
                TextFormField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña Temporal', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
                  validator: (v) => v!.length < 6 ? 'Mínimo 6 caracteres' : null,
                ),
                const SizedBox(height: 5),
                const Text('El usuario podrá cambiarla después.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 20),
              ],

              const Divider(),
              const Text("Asignar Rol", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              // SELECTOR DE ROL
              _buildRoleOption(UserRole.admin, 'Administrador', 'Acceso Total', Colors.purple),
              _buildRoleOption(UserRole.manager, 'Supervisor', 'Todo menos crear usuarios', Colors.orange),
              _buildRoleOption(UserRole.cashier, 'Cajero', 'Acceso Básico (Configurable)', Colors.blue),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.indigo, 
                    foregroundColor: Colors.white
                  ),
                  child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                    : Text(_isEditing ? 'ACTUALIZAR DATOS' : 'CREAR USUARIO'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleOption(UserRole role, String title, String subtitle, Color color) {
    final isSelected = _selectedRole == role;
    return Card(
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected ? BorderSide(color: color, width: 2) : BorderSide.none
      ),
      child: RadioListTile<UserRole>(
        value: role,
        groupValue: _selectedRole,
        activeColor: color,
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? color : Colors.black)),
        subtitle: Text(subtitle),
        secondary: Icon(
          role == UserRole.admin ? Icons.admin_panel_settings : 
          role == UserRole.manager ? Icons.supervisor_account : Icons.point_of_sale,
          color: isSelected ? color : Colors.grey,
        ),
        onChanged: (val) => setState(() => _selectedRole = val!),
      ),
    );
  }
}