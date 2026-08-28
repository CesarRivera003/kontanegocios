import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controladores
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  // Eliminado: final _invitationCtrl = TextEditingController();

  bool _isLogin = true; // true = Login, false = Registro
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  // Variables para Términos y Condiciones
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _companyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // VALIDACIÓN DE CHECKBOXES (Solo en registro)
    if (!_isLogin) {
      if (!_acceptedTerms || !_acceptedPrivacy) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes aceptar los Términos y la Política de Privacidad para continuar'),
            backgroundColor: Colors.red,
          )
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final authRepo = ref.read(authRepositoryProvider);
      
      if (_isLogin) {
        await authRepo.signIn(_emailCtrl.text.trim(), _passCtrl.text.trim());
      } else {
        // Registro sin código de invitación
        await authRepo.signUp(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
          companyName: _companyCtrl.text.trim(),
        );
      }
      // La redirección la maneja el Router al detectar el cambio de estado
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LÓGICA DE RECUPERACIÓN DE CONTRASEÑA ---
  void _showForgotPasswordDialog() {
    // Usamos el texto que ya haya escrito en el campo de email (si hay algo)
    final resetEmailCtrl = TextEditingController(text: _emailCtrl.text);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recuperar Contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa tu correo y te enviaremos un enlace para crear una nueva contraseña.'),
            const SizedBox(height: 15),
            TextField(
              controller: resetEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo Electrónico',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _sendResetEmail(resetEmailCtrl.text.trim());
            },
            child: const Text('Enviar Enlace'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendResetEmail(String email) async {
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Por favor ingresa un correo válido"), backgroundColor: Colors.orange)
        );
      }
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Correo enviado. Revisa tu bandeja de entrada (y spam)."), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}"), backgroundColor: Colors.red)
        );
      }
    }
  }
  // ---------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Detectamos si es pantalla pequeña para ajustar diseño
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.grey[100], // Fondo neutro
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: isSmallScreen ? double.infinity : 400,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10))],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // LOGO O TÍTULO
                  Image.asset(
                    'assets/images/logo.png', // <--- Asegúrate de que el nombre coincida aquí
                    height: 80,               // Ajusta la altura a tu gusto (el icono medía 60)
                    fit: BoxFit.contain,      // Asegura que el logo no se deforme
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isLogin ? 'Bienvenido de nuevo' : 'Crea tu cuenta',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 30),

                  // CAMPO: NOMBRE EMPRESA (Solo registro)
                  if (!_isLogin) ...[
                    TextFormField(
                      controller: _companyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del Negocio',
                        prefixIcon: Icon(Icons.store),
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                      ),
                      validator: (v) => v!.isEmpty ? 'Requerido' : null,
                      textInputAction: TextInputAction.next, // Pasa al siguiente campo
                    ),
                    const SizedBox(height: 20),
                  ],

                  // CAMPO: EMAIL
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Correo Electrónico',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v!.contains('@') ? null : 'Correo inválido',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 20),

                  // CAMPO: CONTRASEÑA
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                    validator: (v) => v!.length < 6 ? 'Mínimo 6 caracteres' : null,
                    // SOLUCIÓN AL PROBLEMA DEL ENTER:
                    textInputAction: TextInputAction.done, 
                    onFieldSubmitted: (_) => _submit(), // Al dar Enter, intenta enviar
                  ),
                  if (_isLogin) 
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showForgotPasswordDialog,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                          minimumSize: Size.zero, // Para quitar padding extra
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(
                            color: Colors.blueAccent.shade700, 
                            fontSize: 13, 
                            fontWeight: FontWeight.w600
                          ),
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 20),

                  // CHECKBOXES LEGALES (Solo registro)
                  if (!_isLogin) ...[
                    // Términos
                    CheckboxListTile(
                      value: _acceptedTerms,
                      onChanged: (v) => setState(() => _acceptedTerms = v!),
                      title: GestureDetector(
                        // Aquí deberías poner la ruta real a tu pantalla de términos
                        onTap: () => context.push('/terms'), 
                        child: const Text(
                          "Acepto los Términos y Condiciones",
                          style: TextStyle(fontSize: 12, decoration: TextDecoration.underline, color: Colors.blue),
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    // Privacidad
                    CheckboxListTile(
                      value: _acceptedPrivacy,
                      onChanged: (v) => setState(() => _acceptedPrivacy = v!),
                      title: GestureDetector(
                        // Aquí deberías poner la ruta real a tu pantalla de políticas
                        onTap: () => context.push('/privacy'), 
                        child: const Text(
                          "Acepto la Política de Tratamiento de Datos",
                          style: TextStyle(fontSize: 12, decoration: TextDecoration.underline, color: Colors.blue),
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // BOTÓN DE ACCIÓN
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isLogin ? 'INGRESAR' : 'REGISTRARSE', style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  
                  const SizedBox(height: 20),

                  // SWITCH LOGIN/REGISTRO
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                        // Resetear errores o estados al cambiar
                        _acceptedTerms = false;
                        _acceptedPrivacy = false;
                      });
                    },
                    child: Text(
                      _isLogin ? '¿No tienes cuenta? Regístrate gratis' : '¿Ya tienes cuenta? Inicia sesión',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}