import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool isEmailVerified = false;
  Timer? timer;
  bool canResendEmail = true;

  @override
  void initState() {
    super.initState();
    isEmailVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    if (!isEmailVerified) {
      _sendVerificationEmail();
      // El "vigilante" revisa cada 3 segundos si el usuario ya verificó en su correo
      timer = Timer.periodic(const Duration(seconds: 3), (_) => _checkEmailVerified());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerified() async {
    // Recargar es OBLIGATORIO para que Firebase se dé cuenta de que ya verificó
    await FirebaseAuth.instance.currentUser?.reload();
    
    setState(() {
      isEmailVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    });

    if (isEmailVerified) {
      timer?.cancel();
      // ¡Magia! Lo mandamos al dashboard automáticamente
      if (mounted) context.go('/dashboard');
    }
  }

  Future<void> _sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.sendEmailVerification();
      
      setState(() => canResendEmail = false);
      await Future.delayed(const Duration(seconds: 30));
      if (mounted) setState(() => canResendEmail = true);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? 'tu correo';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 100, color: Colors.indigo),
              const SizedBox(height: 24),
              const Text('Verifica tu correo', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.indigo), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(
                'Hemos enviado un enlace seguro a:\n$userEmail\n\nPor favor, haz clic en el enlace para activar tu cuenta.', 
                textAlign: TextAlign.center, 
                style: const TextStyle(fontSize: 16, color: Colors.black87)
              ),
              const SizedBox(height: 30),
              
              const CircularProgressIndicator(color: Colors.indigo),
              const SizedBox(height: 15),
              const Text('Esperando confirmación...', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              
              const SizedBox(height: 40),
              
              ElevatedButton.icon(
                onPressed: canResendEmail ? _sendVerificationEmail : null,
                icon: const Icon(Icons.refresh),
                label: Text(canResendEmail ? 'Reenviar correo' : 'Espera 30s para reenviar'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: Colors.indigo.shade50,
                  foregroundColor: Colors.indigo,
                  elevation: 0
                ),
              ),
              const SizedBox(height: 20),
              
              TextButton(
                onPressed: () {
                  FirebaseAuth.instance.signOut();
                  context.go('/login');
                },
                child: const Text('Me equivoqué de correo (Salir)', style: TextStyle(color: Colors.red)),
              )
            ],
          ),
        ),
      ),
    );
  }
}