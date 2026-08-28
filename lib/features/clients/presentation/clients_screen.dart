import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'client_providers.dart';
import '../../clients/domain/client_model.dart';
import '../../home/presentation/dashboard_shell.dart';
import 'package:flutter/services.dart';

// 1. IMPORTAR PERFIL PARA PERMISOS
import '../../auth/presentation/user_profile_provider.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Escuchamos el cambio de pestaña para actualizar el botón flotante (FAB)
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  Future<void> _launchApp(String phone, bool isWhatsapp) async {
    var number = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (isWhatsapp) {
      if (number.length == 10) number = '57$number';
      final uri = Uri.parse("https://wa.me/$number");
      launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final uri = Uri(scheme: 'tel', path: number);
      launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    
    // 2. DEFINICIÓN DE PERMISOS
    final userProfile = ref.watch(userProfileProvider).value;
    
    // Admin y Supervisor tienen poder "Supremo"
    final bool isBoss = userProfile?.canEditData ?? false; 
    
    // REGLA: ¿Quién puede Editar CLIENTES? -> ¡Todos! (Incluso el cajero)
    final bool canEditClients = true; 
    
    // REGLA: ¿Quién puede Editar PROVEEDORES? -> Solo Admin/Supervisor
    final bool canEditProviders = isBoss;

    // Determinar si mostramos el botón "+" según la pestaña actual
    final bool showFab = _tabController.index == 0 
        ? canEditClients 
        : canEditProviders;

    return Scaffold(
      appBar: AppBar(
        leading: isMobile ? IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => DashboardShell.scaffoldKey.currentState?.openDrawer(),
        ): null,
        title: const Text('Contactos'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'CLIENTES', icon: Icon(Icons.people)),
            Tab(text: 'PROVEEDORES', icon: Icon(Icons.local_shipping)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _query = val.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Buscar contacto...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey[100]
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildClientsList(),   // Pestaña 1
                _buildProvidersList(), // Pestaña 2
              ],
            ),
          ),
        ],
      ),
      
      // 3. BOTÓN FLOTANTE INTELIGENTE
      floatingActionButton: showFab ? FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            context.push('/save-client'); // Crear Cliente
          } else {
            context.push('/save-provider'); // Crear Proveedor
          }
        },
        child: const Icon(Icons.add),
      ) : null,
    );
  }

  // --- LISTA CLIENTES ---
  Widget _buildClientsList() {
    final clientsAsync = ref.watch(clientsStreamProvider);
    return clientsAsync.when(
      data: (clients) {
        final filtered = clients.where((c) => c.name.toLowerCase().contains(_query)).toList();
        if (filtered.isEmpty) return const Center(child: Text('No hay clientes'));
        
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 150, top: 10, left: 10, right: 10),
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final client = filtered[i];
            return ListTile(
              leading: CircleAvatar(child: Text(client.name.isNotEmpty ? client.name[0] : '?')),
              title: Text(client.name),
              subtitle: Text(client.phone),
              trailing: _buildActionButtons(client.phone),
              onTap: () => _showClientDetail(context, client),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
    );
  }

  // --- LISTA PROVEEDORES ---
  Widget _buildProvidersList() {
    final providersAsync = ref.watch(providersStreamProvider);
    
    final userProfile = ref.watch(userProfileProvider).value;
    final bool isBoss = userProfile?.canEditData ?? false;
    final bool canDelete = userProfile?.canDeleteItems ?? false;

    return providersAsync.when(
      data: (providers) {
        // MEJORA: Buscar por nombre o por categoría
        final filtered = providers.where((p) {
          final nameMatch = p.name.toLowerCase().contains(_query);
          final categoryMatch = p.category.toLowerCase().contains(_query);
          return nameMatch || categoryMatch;
        }).toList();

        if (filtered.isEmpty) return const Center(child: Text('No se encontraron proveedores'));

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 150, top: 10, left: 10, right: 10),
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final provider = filtered[i];
            
            // Texto para mostrar en la UI basado en el método de pago
            String paymentInfo = '';
            if (provider.accountType == 'Efectivo') {
              paymentInfo = 'Pago en Efectivo';
            } else if (provider.accountType == 'Link de Pago / Web') {
              paymentInfo = 'Enlace: ${provider.accountNumber}';
            } else {
               String bankText = provider.bank.isNotEmpty ? '${provider.bank} - ' : '';
               paymentInfo = '$bankText${provider.accountType}: ${provider.accountNumber}';
            }

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo[100],
                  child: const Icon(Icons.store, color: Colors.indigo),
                ),
                title: Text(provider.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(provider.category, style: const TextStyle(color: Colors.blueGrey)), // Resaltamos la categoría
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.phone, color: Colors.green), onPressed: () => _launchApp(provider.phone, false)),
                    IconButton(icon: const Icon(Icons.message, color: Colors.green), onPressed: () => _launchApp(provider.phone, true)),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Teléfono: ${provider.phone}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        if (provider.nit.isNotEmpty) ...[
                          Text('NIT / CC: ${provider.nit}'),
                          const SizedBox(height: 5),
                        ],
                        const Text('DATOS DE PAGO:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(paymentInfo, style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 10),
                        
                        if (isBoss)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.edit), 
                              label: const Text('Editar'), 
                              onPressed: () => context.push('/save-provider', extra: provider)
                            ),
                            
                            if (canDelete)
                            TextButton.icon(
                              icon: const Icon(Icons.delete, color: Colors.red), 
                              label: const Text('Eliminar'), 
                              onPressed: () => _confirmDeleteProvider(context, ref, provider.id, provider.name),
                            ),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildActionButtons(String phone) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.phone, color: Colors.green), onPressed: () => _launchApp(phone, false)),
        IconButton(icon: const Icon(Icons.message, color: Colors.green), onPressed: () => _launchApp(phone, true)),
      ],
    );
  }

  // --- DETALLE DE CLIENTE (MODAL) ---
  void _showClientDetail(BuildContext context, Client client) {
    final userProfile = ref.read(userProfileProvider).value;
    
    // REGLA: Todos pueden editar clientes
    final bool canEdit = true; 
    // REGLA: Solo Admin/Supervisor puede borrar
    final bool canDelete = userProfile?.canDeleteItems ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        
        void copyToClipboard() {
          final String info = """
Datos del Cliente:
Nombre: ${client.name}
ID: ${client.idType} ${client.idNumber}
Tel: ${client.phone}
Email: ${client.email}
Dirección: ${client.address} ${client.city}
            """;
          Clipboard.setData(ClipboardData(text: info)).then((_) {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Datos copiados al portapapeles'), backgroundColor: Colors.blue),
            );
          });
        }

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 30, child: Text(client.name.isNotEmpty ? client.name[0] : '?', style: const TextStyle(fontSize: 24))),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(client.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text("ID: ${client.idType} ${client.idNumber}", style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.blue),
                    tooltip: 'Copiar datos',
                    onPressed: copyToClipboard,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              _ContactRow(icon: Icons.phone, value: client.phone),
              _ContactRow(icon: Icons.email, value: client.email),
              _ContactRow(icon: Icons.location_on, value: '${client.address} ${client.city}'),
              if (client.secondaryContact.isNotEmpty)
                _ContactRow(icon: Icons.perm_contact_calendar, value: 'Secundario: ${client.secondaryContact}'),

              const SizedBox(height: 25),
              
              // BOTONES DE ACCIÓN PARA CLIENTES
              if (canEdit)
              Row(
                children: [
                  // 1. EDITAR (Visible para todos)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text("Editar"),
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push('/save-client', extra: client);
                      },
                    ),
                  ),
                  
                  // 2. ELIMINAR (Solo Admin/Supervisor)
                  if (canDelete) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text("Eliminar", style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx); 
                          _confirmDeleteClient(context, client.id); 
                        },
                      ),
                    ),
                  ],
                ],
              )
            ],
          ),
        );
      }
    );
  }

  void _confirmDeleteClient(BuildContext context, String clientId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: const Text('¿Estás seguro? Se perderá la información de contacto, aunque sus ventas históricas permanecerán.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              ref.read(clientRepositoryProvider).deleteClient(clientId);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cliente eliminado'), backgroundColor: Colors.red)
              );
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  
  void _confirmDeleteProvider(BuildContext context, WidgetRef ref, String providerId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Proveedor'),
        content: Text('¿Estás seguro de eliminar a "$name"?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); 
              ref.read(providerRepositoryProvider).deleteProvider(providerId).then((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Proveedor eliminado correctamente'), backgroundColor: Colors.green)
                );
              }).catchError((e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red)
                );
              });
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  const _ContactRow({required this.icon, required this.value});
  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [Icon(icon, color: Colors.grey, size: 20), const SizedBox(width: 10), Expanded(child: Text(value))]),
    );
  }
}