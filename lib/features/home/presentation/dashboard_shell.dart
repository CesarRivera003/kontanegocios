import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/user_profile_provider.dart';
import '../../auth/domain/user_model.dart';
import '../../settings/data/settings_repository.dart';

class DashboardShell extends ConsumerStatefulWidget {
  final Widget child;
  static final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  const DashboardShell({super.key, required this.child});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _MenuEntry {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
  final bool isVisible;

  _MenuEntry({
    required this.icon,
    IconData? selectedIcon,
    required this.label,
    required this.route,
    this.isVisible = true,
  }) : selectedIcon = selectedIcon ?? icon;
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  
  int _calculateSelectedIndex(BuildContext context, List<_MenuEntry> visibleMenus) {
    final String location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < visibleMenus.length; i++) {
      if (location.startsWith(visibleMenus[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 1. ESCUCHAMOS EL ESTADO DEL PERFIL (Loading, Data, Error)
    final userProfileAsync = ref.watch(userProfileProvider);
    
    // Guardamos el estado de la empresa en una variable
    final companyProfileAsync = ref.watch(companyProfileProvider); 

    // --- BLOQUE DE SEGURIDAD (MEJORADO) ---
    // Si el usuario O la empresa están cargando, mostramos espera.
    if (userProfileAsync.isLoading || 
        !userProfileAsync.hasValue || 
        userProfileAsync.value == null || 
        companyProfileAsync.isLoading) { // <-- ¡Añadimos esta condición!
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // -----------------------------------

    final userProfile = userProfileAsync.value!; // Ahora es seguro usar el "!"
    final bool isCashier = userProfile.role == UserRole.cashier;

    // 2. REGLAS DE VISIBILIDAD
    final bool showHome = !isCashier;
    final bool showExpenses = userProfile.showMenuExpenses;
    final bool showReports  = userProfile.showMenuReports;

    // 3. REDIRECCIÓN DE SEGURIDAD
    final String location = GoRouterState.of(context).uri.toString();
    if (isCashier && (location == '/dashboard' || location == '/')) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         context.go('/pos'); 
       });
       return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 4. DEFINIMOS LOS MENÚS
    final List<_MenuEntry> allEntries = [
      _MenuEntry(icon: Icons.storefront, label: 'Inicio', route: '/dashboard', isVisible: showHome),
      _MenuEntry(icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, label: 'Ventas', route: '/pos'),
      _MenuEntry(icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet, label: 'Caja', route: '/cash'),
      _MenuEntry(icon: Icons.history_outlined, selectedIcon: Icons.history, label: 'Historial', route: '/history'),
      _MenuEntry(icon: Icons.attach_money_outlined, label: 'Gastos', route: '/expenses', isVisible: showExpenses),
      _MenuEntry(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: 'Inventario', route: '/inventory'),
      _MenuEntry(icon: Icons.people_outline, label: 'Contactos', route: '/clients'),
      _MenuEntry(icon: Icons.web_outlined, selectedIcon: Icons.web, label: 'Catálogos', route: '/catalogs', isVisible: showHome),
      _MenuEntry(icon: Icons.account_balance_outlined, selectedIcon: Icons.account_balance, label: 'Tesorería', route: '/finance', isVisible: userProfile.role == UserRole.admin),
      _MenuEntry(icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart, label: 'Reportes', route: '/reports', isVisible: showReports),
      _MenuEntry(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Config', route: '/settings', isVisible: true),
    ];

    final visibleDestinations = allEntries.where((e) => e.isVisible).toList();
    final int selectedIndex = _calculateSelectedIndex(context, visibleDestinations);

    // 6. BARRA MÓVIL ADAPTABLE
    List<_MenuEntry> mobileDestinations;
    if (isCashier) {
       mobileDestinations = visibleDestinations.where((e) => 
         ['/pos', '/history', '/inventory', '/clients'].contains(e.route)
       ).toList();
    } else {
       mobileDestinations = visibleDestinations.where((e) => 
         ['/dashboard', '/pos', '/history', '/expenses', '/reports'].contains(e.route)
       ).toList();
    }
    
    final int mobileIndex = mobileDestinations.indexWhere((e) => location.startsWith(e.route)).clamp(0, mobileDestinations.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        // --- DISEÑO PC ---
        if (constraints.maxWidth > 800) {
          final isExtended = constraints.maxWidth > 1100;
          return Scaffold(
            body: Row(
              children: [
                // Nuevo: Agregamos Scroll para que el NavigationRail no se desborde
                LayoutBuilder(
                  builder: (context, railConstraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            selectedIndex: selectedIndex,
                            onDestinationSelected: (index) => context.go(visibleDestinations[index].route),
                            extended: isExtended,
                            leading: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                              child: Image.asset(
                                'assets/images/logo_sin_titulo_small.png', 
                                height: 45, 
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, _, __) => Icon(Icons.bar_chart_rounded, size: 40, color: theme.primaryColor),
                              ),
                            ),
                            trailing: Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: IconButton(
                                    icon: const Icon(Icons.logout, color: Colors.red),
                                    onPressed: () => ref.read(authRepositoryProvider).signOut(),
                                    tooltip: 'Cerrar Sesión',
                                  ),
                                ),
                              ),
                            ),
                            destinations: visibleDestinations.map((d) => NavigationRailDestination(
                              icon: Icon(d.icon), 
                              selectedIcon: Icon(d.selectedIcon), 
                              label: Text(d.label),
                            )).toList(),
                          ),
                        ),
                      ),
                    );
                  }
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: widget.child),
              ],
            ),
          );
        }
        
        // --- DISEÑO MÓVIL ---
        else {
          return Scaffold(
            key: DashboardShell.scaffoldKey,
            drawer: Drawer(
              child: Column(
                children: [
                  // --- HEADER PERSONALIZADO (Déjalo exactamente igual al que tienes) ---
                  Container(
                    padding: const EdgeInsets.only(top: 50, bottom: 20, left: 16, right: 16),
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2C2F33), Color(0xFF121212)],
                      ),
                      border: Border(bottom: BorderSide(color: Color(0xFF3A3D42), width: 1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset(
                          'assets/images/Logo_horizontal_oscuro_small.png',
                          height: 70,
                          fit: BoxFit.contain,
                          errorBuilder: (ctx, _, __) => const Row(
                            children: [
                              Icon(Icons.bar_chart, color: Colors.white, size: 28),
                              SizedBox(width: 8),
                              Text("KONTA GESTOR", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),
                        Text(
                          userProfile.name.toUpperCase(),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8),
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 12, color: Colors.white.withOpacity(0.7)),
                            const SizedBox(width: 4),
                            Text(
                              userProfile.role.name.toUpperCase(),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.white.withOpacity(0.7), letterSpacing: 1.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // --- LISTA DE MENÚS (Ahora con scroll unificado) ---
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        // Generamos los botones de las pantallas
                        ...List.generate(visibleDestinations.length, (i) {
                          final item = visibleDestinations[i];
                          return ListTile(
                            leading: Icon(item.icon),
                            title: Text(item.label),
                            selected: i == selectedIndex,
                            onTap: () {
                              Navigator.pop(context); // Cierra el Drawer
                              context.go(item.route); // Navega
                            },
                          );
                        }),
                        const Divider(),
                        // Movemos el botón de cerrar sesión adentro de la lista
                        ListTile(
                          leading: const Icon(Icons.logout, color: Colors.red),
                          title: const Text("Cerrar Sesión", style: TextStyle(color: Colors.red)),
                          onTap: () => ref.read(authRepositoryProvider).signOut(),
                        ),
                        const SizedBox(height: 20), // Margen inferior extra para que nunca quede al ras de la pantalla
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            body: widget.child,

            bottomNavigationBar: NavigationBar(
              selectedIndex: mobileIndex,
              onDestinationSelected: (index) {
                if (index >= 0 && index < mobileDestinations.length) {
                  context.go(mobileDestinations[index].route);
                }
              },
              destinations: mobileDestinations.map((d) => NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              )).toList(),
            ),
          );
        }
      },
    );
  }
}