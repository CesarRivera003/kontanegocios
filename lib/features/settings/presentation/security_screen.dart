import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Importante para manejar Auth directo
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmDeleteCtrl = TextEditingController(); // Para confirmar borrado
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-llenar el correo actual
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _emailCtrl.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmDeleteCtrl.dispose();
    super.dispose();
  }

  // --- MÉTODOS DE ACCIÓN ---

  // 1. CAMBIAR CORREO
  Future<void> _updateEmail() async {
    final newEmail = _emailCtrl.text.trim();
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      _showSnack('Ingresa un correo válido', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.currentUser?.verifyBeforeUpdateEmail(newEmail);
      _showSnack('Se ha enviado un correo de verificación a $newEmail. Confírmalo para completar el cambio.', Colors.green);
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. CAMBIAR CONTRASEÑA
  Future<void> _updatePassword() async {
    final newPass = _passwordCtrl.text.trim();
    if (newPass.length < 6) {
      _showSnack('La contraseña debe tener al menos 6 caracteres', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.currentUser?.updatePassword(newPass);
      _passwordCtrl.clear();
      _showSnack('¡Contraseña actualizada con éxito!', Colors.green);
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 3. ELIMINAR CUENTA
  Future<void> _deleteAccount() async {
    // Verificación final de seguridad
    if (_confirmDeleteCtrl.text != 'ELIMINAR') {
      _showSnack('Escribe "ELIMINAR" para confirmar', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Borrar usuario de Auth
      await FirebaseAuth.instance.currentUser?.delete();
      
      // 2. Cerrar sesión y sacar de la app
      await ref.read(authRepositoryProvider).signOut();
      
      // La redirección a /login la maneja el app_router automáticamente al detectar logout
      
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      _showSnack('Error desconocido: $e', Colors.red);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // MANEJO DE ERRORES COMUNES
  void _handleAuthError(FirebaseAuthException e) {
    if (e.code == 'requires-recent-login') {
      _showReauthDialog();
    } else {
      _showSnack('Error: ${e.message}', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _showReauthDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seguridad'),
        content: const Text('Por tu seguridad, esta acción requiere que hayas iniciado sesión recientemente.\n\nPor favor, cierra sesión e ingresa de nuevo para intentar esta operación.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authRepositoryProvider).signOut();
            },
            child: const Text('Cerrar Sesión Ahora', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  // DIÁLOGO DE CONFIRMACIÓN DE BORRADO
  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar cuenta permanentemente?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Esta acción NO se puede deshacer. Perderás acceso a tus datos.'),
            const SizedBox(height: 20),
            const Text('Escribe "ELIMINAR" para confirmar:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmDeleteCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'ELIMINAR',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAccount();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ELIMINAR CUENTA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Seguridad de la Cuenta")),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              "Gestiona tus credenciales de acceso.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),

            // --- SECCIÓN CORREO ---
            const Text("Cambiar Correo Electrónico", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo Correo',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _updateEmail,
                      child: const Text("Actualizar Correo"),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // --- SECCIÓN CONTRASEÑA ---
            const Text("Cambiar Contraseña", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nueva Contraseña',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _updatePassword,
                      child: const Text("Actualizar Contraseña"),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 50),

            // --- ZONA DE PELIGRO ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.3))
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red),
                      SizedBox(width: 10),
                      Text("Zona de Peligro", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text("Eliminar tu cuenta borrará tu acceso al sistema. Los datos de la empresa permanecerán si hay otros usuarios, o se borrarán si eres el único dueño.", style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _showDeleteConfirmation,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text("ELIMINAR MI CUENTA"),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}