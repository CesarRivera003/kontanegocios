import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Necesario para actualizar el nombre
import '../../auth/presentation/auth_providers.dart';
import '../data/settings_repository.dart';
import '../../home/presentation/dashboard_shell.dart';
import 'dart:convert';
import '../../expenses/presentation/expense_providers.dart';
import '../../auth/domain/user_model.dart'; // Para UserRole

// Importamos los proveedores de inventario para gestionar las listas
import '../../inventory/presentation/inventory_providers.dart';
import '../../auth/presentation/user_profile_provider.dart';
import '../../clients/presentation/client_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    
    final profileAsync = ref.watch(companyProfileProvider);
    final user = ref.watch(authRepositoryProvider).currentUser;
    final userProfile = ref.watch(userProfileProvider).value;

    // VERIFICAMOS SI ES ADMIN
    final bool isAdmin = userProfile?.role == UserRole.admin;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        leading: isMobile ? IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            DashboardShell.scaffoldKey.currentState?.openDrawer();
          },
        ) : null,
        title: const Text('Configuración'),
      ),
      body: ListView(
        children: [
          // 1. CABECERA PERFIL (EMPRESA)
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 35,
                  backgroundColor: Colors.blue[100],
                  backgroundImage: (profileAsync.value?.imageBase64 != null && profileAsync.value!.imageBase64!.isNotEmpty)
                      ? MemoryImage(base64Decode(profileAsync.value!.imageBase64!))
                      : null,
                  child: (profileAsync.value?.imageBase64 == null || profileAsync.value!.imageBase64!.isEmpty)
                      ? Text(
                          profileAsync.value?.name.isNotEmpty == true ? profileAsync.value!.name[0].toUpperCase() : 'E',
                          style: TextStyle(fontSize: 28, color: Colors.blue[900], fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profileAsync.value?.name ?? 'Configurar Empresa',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      if (profileAsync.value?.nit != null)
                        Text(
                          'NIT: ${profileAsync.value?.nit}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                    ],
                  ),
                ),
                // Botón para VER/EDITAR datos de la empresa (Visible para todos, pero restringido adentro)
                IconButton(
                  icon: const Icon(Icons.store, color: Colors.blue),
                  tooltip: 'Datos de Empresa',
                  onPressed: () {
                    try {
                      context.push('/save-company'); 
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ruta no configurada')));
                    }
                  },
                )
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. SECCIÓN: MI CUENTA (VISIBLE PARA TODOS)
          const _SectionHeader(title: 'MI CUENTA'),
          
          // NUEVO: CAMBIAR NOMBRE DE USUARIO
          _SettingsTile(
            icon: Icons.badge_outlined,
            title: 'Mi Nombre',
            // Muestra el nombre actual o "Usuario"
            subtitle: userProfile?.name ?? 'Personalizar nombre',
            trailing: const Icon(Icons.edit, size: 16, color: Colors.blue),
            onTap: () => _showEditNameDialog(context, ref, userProfile),
          ),
          
          _SettingsTile(
            icon: Icons.security,
            title: 'Seguridad y Privacidad',
            subtitle: 'Contraseña, correo y eliminación de cuenta',
            onTap: () => context.push('/settings/security'),
          ),

          const SizedBox(height: 10),

          // 3. SECCIONES RESTRINGIDAS (SOLO ADMIN)
          if (isAdmin)
            _SettingsTile(
              icon: Icons.pin_outlined,
              title: 'PIN de Autorización',
              subtitle: 'Código rápido para autorizar cajas',
              trailing: const Icon(Icons.edit, size: 16, color: Colors.blue),
              onTap: () => _showEditPinDialog(context, ref, profileAsync.value?.id),
            ),
          
          if (isAdmin) ...[
            const _SectionHeader(title: 'VENTAS Y MARKETING'),
            _SettingsTile(
              icon: Icons.local_offer_outlined,
              title: 'Promociones y Ofertas',
              subtitle: 'Configure descuentos automáticos y 2x1',
              onTap: () => context.push('/settings/promotions'),
            ),

            const _SectionHeader(title: 'PERSONALIZACIÓN'),
            _SettingsTile(
              icon: Icons.category,
              title: 'Categorías de Productos',
              subtitle: 'Administrar lista de categorías',
              onTap: () => _showManageListDialog(
                context, 
                'Categorías', 
                productCategoriesProvider, 
                (ref, item) => ref.read(productCategoriesProvider.notifier).remove(item)
              ),
            ),
            _SettingsTile(
              icon: Icons.straighten,
              title: 'Unidades de Medida',
              subtitle: 'Administrar unidades (Kg, Und, Lt...)',
              onTap: () => _showManageListDialog(
                context, 
                'Unidades', 
                productUnitsProvider, 
                (ref, item) => ref.read(productUnitsProvider.notifier).remove(item)
              ),
            ),
            _SettingsTile(
              icon: Icons.monetization_on_outlined,
              title: 'Categorías de Gastos',
              subtitle: 'Nómina, Arriendo, Servicios...',
              onTap: () => _showManageListDialog(
                context, 
                'Categorías de Gastos', 
                expenseCategoriesProvider, 
                (ref, item) => ref.read(expenseCategoriesProvider.notifier).remove(item)
              ),
            ),
            _SettingsTile(
              icon: Icons.local_shipping_outlined,
              title: 'Categorías de Proveedores',
              subtitle: 'Administrar categorías (Insumos, Servicios...)',
              onTap: () => _showManageListDialog(
                context, 
                'Categorías de Proveedores', 
                providerCategoriesProvider, 
                (ref, item) => ref.read(providerCategoriesProvider.notifier).remove(item)
              ),
            ),
            
            const SizedBox(height: 10),

            const _SectionHeader(title: 'EQUIPO Y ACCESO'),
            _SettingsTile(
              icon: Icons.people, 
              title: 'Gestión de Usuarios', 
              subtitle: 'Administrar empleados y permisos',
              onTap: () => context.push('/settings/users'),
            ),
            
            const SizedBox(height: 10),

            const _SectionHeader(title: 'SUSCRIPCIÓN'),
            Builder(
              builder: (context) {
                final p = profileAsync.value;
                String planName = 'Cargando...';
                String subtitle = 'Ver detalles';
                IconData planIcon = Icons.star_border;
                Color iconColor = Colors.grey;

                if (p != null) {
                  final isExpiredTime = p.trialEndsAt != null && p.trialEndsAt!.isBefore(DateTime.now());
                  final hasFreemium = (p.referralCount >= 2 && p.currentMonthSales < 4000000) || p.subscriptionStatus == 'freemium';

                  // --- CORRECCIÓN: RECONOCIMIENTO DE LOS NUEVOS PLANES ---
                  final isPro = p.subscriptionStatus == 'pro' || p.subscriptionStatus == 'active'; // Mantenemos 'active' por retrocompatibilidad
                  final isEmpresarial = p.subscriptionStatus == 'empresarial';

                  if (isPro || isEmpresarial) {
                    // Diferenciamos visualmente los planes Premium
                    planName = isEmpresarial ? 'Plan Empresarial' : 'Plan Pro'; 
                    planIcon = isEmpresarial ? Icons.domain : Icons.workspace_premium; 
                    iconColor = isEmpresarial ? Colors.indigo : Colors.amber;
                    
                    if (p.trialEndsAt != null) {
                      final fecha = "${p.trialEndsAt!.day}/${p.trialEndsAt!.month}/${p.trialEndsAt!.year}";
                      subtitle = 'Próximo cobro: $fecha';
                    } else {
                      subtitle = 'Acceso total e ilimitado';
                    }
                  } else if (p.subscriptionStatus == 'lifetime') {
                    planName = 'VIP Vitalicio'; subtitle = 'Cuenta de cortesía'; planIcon = Icons.diamond; iconColor = Colors.purple;
                  } else if (hasFreemium) {
                    planName = 'Emprendedor (Gratis)'; subtitle = 'Ventas del mes: \$${p.currentMonthSales.toStringAsFixed(0)}'; planIcon = Icons.handshake; iconColor = Colors.blue;
                  } else if (!isExpiredTime) {
                    final days = p.trialEndsAt!.difference(DateTime.now()).inDays;
                    planName = 'Prueba ($days días)'; subtitle = 'Mejorar a Premium'; planIcon = Icons.timer; iconColor = Colors.orange;
                  } else {
                    planName = 'Suscripción Pausada'; subtitle = 'Límite excedido o prueba vencida'; planIcon = Icons.error_outline; iconColor = Colors.red;
                  }
                }

                return ListTile(
                  tileColor: Colors.white,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(planIcon, color: iconColor),
                  ),
                  title: Text(planName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: () => context.push('/subscription'),
                );
              }
            ),

            if (isAdmin && profileAsync.value?.subscriptionStatus == 'empresarial') ...[
              const _SectionHeader(title: 'FACTURACIÓN ELECTRÓNICA'),
              _SettingsTile(
                icon: Icons.receipt_long, // Cambiamos el icono a uno más parecido a una factura
                title: 'Facturación Electrónica DIAN',
                subtitle: 'Consultar saldo, paquetes y resolución',
                onTap: () => context.push('/settings/fe-config'),
              ),
              _SettingsTile(
                icon: Icons.history_edu_outlined,
                title: 'Gestión de Facturas',
                subtitle: 'Estado DIAN, Notas Crédito y PDF',
                onTap: () => context.push('/settings/fe-dashboard'),
              ),
            ],
          ],

          const SizedBox(height: 10),

          // 4. SECCIÓN: SOPORTE Y LEGAL (VISIBLE PARA TODOS)
          const _SectionHeader(title: 'SOPORTE Y LEGAL'),
          _SettingsTile(
            icon: Icons.description, 
            title: 'Términos y Condiciones', 
            subtitle: 'Leer contrato de uso',
            onTap: () => context.push('/terms'),
          ),
          _SettingsTile(
            icon: Icons.privacy_tip, 
            title: 'Política de Privacidad', 
            subtitle: 'Tratamiento de datos',
            onTap: () => context.push('/privacy'),
          ),

          const SizedBox(height: 30),

          // BOTÓN CERRAR SESIÓN
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authRepositoryProvider).signOut();
              },
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // --- NUEVO: DIÁLOGO PARA CAMBIAR NOMBRE DE USUARIO (CON CREACIÓN DE PERFIL ADMIN) ---
  void _showEditNameDialog(BuildContext context, WidgetRef ref, UserModel? user) {
    final nameCtrl = TextEditingController(text: user?.name ?? '');
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Editar Mi Nombre"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Este nombre aparecerá en los registros de ventas y gastos que realices.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Nombre", border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isNotEmpty && user != null) {
                try {
                  Navigator.pop(ctx); // Cerrar diálogo rápido para buena UX
                  
                  final companyId = ref.read(companyIdProvider).value;
                  if (companyId != null) {
                    final userRef = FirebaseFirestore.instance
                        .collection('companies')
                        .doc(companyId)
                        .collection('users')
                        .doc(user.id);
                        
                    // Verificamos si el documento ya existe
                    final docSnap = await userRef.get();
                    
                    if (docSnap.exists) {
                      // Si ya existe (cajero normal o admin ya registrado), solo actualizamos el nombre
                      await userRef.update({'name': newName});
                    } else {
                      // Si NO existe (Es el dueño original la primera vez), creamos el perfil completo
                      // para estandarizar la base de datos
                      await userRef.set({
                        'id': user.id,
                        'name': newName,
                        'email': user.email,
                        'role': 'admin', // Forzamos el rol supremo
                        'isActive': true,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }
                    
                    // Forzamos la recarga del perfil localmente en la app
                    ref.invalidate(userProfileProvider);
                    
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Nombre actualizado, hola $newName"), backgroundColor: Colors.green)
                      );
                    }
                  }
                } catch (e) {
                  debugPrint("Error actualizando nombre: $e");
                  if (context.mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
                     );
                  }
                }
              }
            },
            child: const Text("Guardar"),
          )
        ],
      ),
    );
  }

  // ... (El resto de métodos _showManageListDialog, _SectionHeader, etc., se mantienen igual)
  void _showManageListDialog(
    BuildContext context, 
    String title, 
    dynamic provider, 
    Function(WidgetRef, String) onRemove 
  ) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final dynamic rawValue = ref.watch(provider);
          List<String> items = [];
          bool isLoading = false;

          if (rawValue is AsyncValue<List<String>>) {
            items = rawValue.asData?.value ?? [];
            isLoading = rawValue.isLoading && items.isEmpty; 
          } else if (rawValue is List<String>) {
            items = rawValue;
          }

          return AlertDialog(
            title: Text('Gestionar $title'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300, 
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(child: Text('La lista está vacía', style: TextStyle(color: Colors.grey)))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(item, style: const TextStyle(fontWeight: FontWeight.w500)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Eliminar',
                                onPressed: () {
                                  onRemove(ref, item);
                                },
                              ),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- NUEVO: DIÁLOGO PARA CAMBIAR PIN ---
  void _showEditPinDialog(BuildContext context, WidgetRef ref, String? fallbackId) {
    // Usamos el ID global de la empresa para evitar desajustes de estado
    final companyId = ref.read(companyIdProvider).value ?? fallbackId;
    if (companyId == null) return;
    
    final pinCtrl = TextEditingController();
    bool isSaving = false;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Configurar PIN de Admin"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Este PIN numérico te permitirá autorizar movimientos de efectivo de los cajeros rápidamente.", 
                  style: TextStyle(fontSize: 12, color: Colors.grey)
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: "Nuevo PIN (4 a 6 números)", 
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dialpad)
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: isSaving ? null : () async {
                  final pin = pinCtrl.text.trim();
                  if (pin.length >= 4) {
                    setState(() => isSaving = true);
                    try {
                      // Guardamos el PIN en el documento de configuración de la empresa
                      await FirebaseFirestore.instance
                          .collection('companies')
                          .doc(companyId)
                          .collection('config')
                          .doc('security') // Documento específico para seguridad
                          .set({'adminPin': pin}, SetOptions(merge: true));
                      
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PIN configurado correctamente"), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      setState(() => isSaving = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                    }
                  } else {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("El PIN debe tener al menos 4 números"), backgroundColor: Colors.orange));
                  }
                },
                child: isSaving ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Guardar PIN"),
              )
            ],
          );
        }
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 5),
      child: Text(title, style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon, 
    required this.title, 
    required this.subtitle, 
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 1),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.blue[700]),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}