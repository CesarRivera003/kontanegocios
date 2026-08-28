import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// =============================================================================
// IMPORTS: AUTENTICACIÓN Y CORE
// =============================================================================
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/legal/terms_screen.dart';
import '../../features/auth/presentation/legal/privacy_screen.dart';
import '../../features/auth/domain/user_model.dart'; 
import '../../shared/widgets/barcode_scanner_screen.dart';
import '../../features/auth/presentation/email_verification_screen.dart';

// =============================================================================
// IMPORTS: MÓDULOS PRINCIPALES (SHELL)
// =============================================================================
import '../../features/home/presentation/dashboard_shell.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/sales/presentation/pos_screen.dart';
import '../../features/sales/presentation/sales_screen.dart';
import '../../features/cash/presentation/cash_screen.dart';
import '../../features/cash/presentation/cash_history_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/inventory/presentation/save_product_screen.dart';
import '../../features/inventory/domain/product_model.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/expenses/presentation/save_expense_screen.dart';
import '../../features/expenses/domain/expense_model.dart';
import '../../features/clients/presentation/clients_screen.dart'; 
import '../../features/clients/presentation/save_client_screen.dart';
import '../../features/clients/domain/client_model.dart';
import '../../features/clients/presentation/save_provider_screen.dart';
import '../../features/clients/domain/provider_model.dart';
import '../../features/finance/presentation/finance_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/catalogs/presentation/screens/catalogs_list_screen.dart';
import '../../features/catalogs/presentation/screens/catalog_wrapper_screen.dart';

// =============================================================================
// IMPORTS: CONFIGURACIÓN, SEGURIDAD Y SUSCRIPCIÓN
// =============================================================================
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/company_profile_screen.dart';
import '../../features/settings/presentation/security_screen.dart';
import '../../features/settings/presentation/user_management_screen.dart';
import '../../features/settings/presentation/save_user_screen.dart';
import '../../features/settings/presentation/electronic_invoice_config_screen.dart';
import '../../features/settings/presentation/electronic_invoices_screen.dart';
import '../../features/settings/presentation/subscription_screen.dart';
import '../../features/settings/presentation/subscription_blocker.dart';

// =============================================================================
// IMPORTS: PROMOCIONES
// =============================================================================
import '../../features/promotions/domain/promotion_model.dart';
import '../../features/promotions/presentation/promotions_screen.dart';
import '../../features/promotions/presentation/save_promotion_screen.dart';


// =============================================================================
// CONFIGURACIÓN GLOBAL DEL ROUTER
// =============================================================================
final routerProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authRepository.authStateChanges), 
    
    routes: [
      // -----------------------------------------------------------------------
      // 1. RUTAS PÚBLICAS Y DE INICIO
      // -----------------------------------------------------------------------
      GoRoute(path: '/', builder: (context, state) => const AuthCheck()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/terms', builder: (context, state) => const TermsScreen()),
      GoRoute(path: '/privacy', builder: (context, state) => const PrivacyScreen()),
      GoRoute(path: '/verify-email', builder: (context, state) => const EmailVerificationScreen()),
      GoRoute(
        path: '/c/:catalogId',
        builder: (context, state) {
          final catalogId = state.pathParameters['catalogId'];
          // Nota: Aquí necesitarás un "CatalogViewerWrapper" que busque el catálogo 
          // en Firebase usando el catalogId, ya que desde la URL no tienes el objeto completo.
          return CatalogWrapperScreen(catalogId: catalogId!); 
        },
      ),

      // -----------------------------------------------------------------------
      // 2. RUTAS INDEPENDIENTES (Pantallas completas / Modales fuera del menú)
      // -----------------------------------------------------------------------
      
      // Creación y Edición de Entidades
      GoRoute(
        path: '/save-client',
        builder: (context, state) => SaveClientScreen(clientToEdit: state.extra as Client?),
      ),
      GoRoute(
        path: '/save-expense',
        builder: (context, state) => SaveExpenseScreen(expenseToEdit: state.extra as Expense?),
      ),
      GoRoute(
        path: '/save-provider',
        builder: (context, state) => SaveProviderScreen(providerToEdit: state.extra as ProviderModel?),
      ),
      
      // Herramientas y Vistas Específicas
      GoRoute(path: '/scanner', builder: (context, state) => const BarcodeScannerScreen()),
      GoRoute(path: '/cash/history', builder: (context, state) => const CashHistoryScreen()),
      
      // Configuración de Perfil y Seguridad (Sin menú lateral)
      GoRoute(path: '/save-company', builder: (context, state) => const CompanyProfileScreen()),
      GoRoute(path: '/settings/security', builder: (context, state) => const SecurityScreen()),
      GoRoute(path: '/subscription', builder: (context, state) => const SubscriptionScreen()),
      
      // Gestión de Usuarios
      GoRoute(
        path: '/settings/users',
        pageBuilder: (context, state) => const NoTransitionPage(child: UserManagementScreen()),
      ),
      GoRoute(
        path: '/settings/users/add',
        pageBuilder: (context, state) {
          final userToEdit = state.extra as UserModel?;
          return NoTransitionPage(child: SaveUserScreen(userToEdit: userToEdit));
        },
      ),

      GoRoute(
        path: '/catalogs',
        builder: (context, state) {
          final companyId = ref.read(authRepositoryProvider).currentUser?.uid ?? '';
          return CatalogsListScreen(businessId: companyId);
        },
      ),

      // -----------------------------------------------------------------------
      // 3. RUTAS PROTEGIDAS (App Principal con Menú Lateral - ShellRoute)
      // -----------------------------------------------------------------------
      ShellRoute(
        builder: (context, state, child) {
          return SubscriptionBlocker(
            child: DashboardShell(child: child),
          );
        },
        routes: [
          // Módulos Core
          GoRoute(path: '/dashboard', pageBuilder: (context, state) => const NoTransitionPage(child: HomeScreen())),
          GoRoute(path: '/pos', pageBuilder: (context, state) => const NoTransitionPage(child: PosScreen())),
          GoRoute(path: '/cash', pageBuilder: (context, state) => const NoTransitionPage(child: CashScreen())),
          GoRoute(path: '/clients', pageBuilder: (context, state) => const NoTransitionPage(child: ContactsScreen())),
          GoRoute(path: '/finance', pageBuilder: (context, state) => const NoTransitionPage(child: FinanceScreen())),
          GoRoute(path: '/reports', pageBuilder: (context, state) => const NoTransitionPage(child: ReportsScreen())),

          // Módulos con pestañas iniciales
          GoRoute(
            path: '/history',
            pageBuilder: (context, state) {
              final tabIndex = state.extra as int? ?? 0; 
              return NoTransitionPage(child: SalesScreen(initialIndex: tabIndex));
            },
          ),
          GoRoute(
            path: '/expenses',
            pageBuilder: (context, state) {
              final tabIndex = state.extra as int? ?? 0;
              return NoTransitionPage(child: ExpensesScreen(initialIndex: tabIndex));
            },
          ),
          
          // Módulo Inventario (Con sub-rutas)
          GoRoute(
            path: '/inventory',
            pageBuilder: (context, state) => const NoTransitionPage(child: InventoryScreen()),
            routes: [
              GoRoute(
                path: 'save', // Resuelve a: /inventory/save
                builder: (context, state) => SaveProductScreen(productToEdit: state.extra as Product?),
              ),
            ],
          ),

          // Módulo Configuración (Con sub-rutas)
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(child: SettingsScreen()),
            routes: [
              GoRoute(
                path: 'promotions', // Resuelve a: /settings/promotions
                builder: (context, state) => const PromotionsScreen(),
                routes: [
                   GoRoute(
                    path: 'save',
                    builder: (context, state) => SavePromotionScreen(promoToEdit: state.extra as Promotion?),
                  ),
                ]
              ),
              GoRoute(
                path: 'fe-config', // Resuelve a: /settings/fe-config
                builder: (context, state) => const ElectronicInvoiceConfigScreen(),
              ),
              GoRoute(
                path: 'fe-dashboard', // Resuelve a: /settings/fe-dashboard
                builder: (context, state) => const ElectronicInvoicesScreen(),
              ),
            ]
          ),
        ],
      ),
    ], 

    // =========================================================================
    // LÓGICA DE REDIRECCIÓN Y PROTECCIÓN (GUARDS)
    // =========================================================================
    redirect: (context, state) {
      final currentUser = authRepository.currentUser; 
      final isLoggedIn = currentUser != null;
      final isEmailVerified = currentUser?.emailVerified ?? false; 
      
      // Usamos state.uri.path en lugar de matchedLocation para obtener la ruta exacta siempre
      final location = state.uri.path; 
      final publicRoutes = ['/login', '/terms', '/privacy'];
      
      // Identificamos si la ruta actual es la de un catálogo
      final isCatalogRoute = location.startsWith('/c/');

      // CASO A: Usuario NO logueado (Ej: Cliente en incógnito)
      if (!isLoggedIn) {
        // Si va a una ruta pública o a ver un catálogo, lo dejamos pasar libremente
        if (publicRoutes.contains(location) || isCatalogRoute) {
          return null; 
        }
        // Si intenta ir al dashboard, ventas, etc., lo expulsamos al login
        return '/login'; 
      }

      // CASO B: Usuario SÍ logueado pero NO ha verificado su correo
      if (isLoggedIn && !isEmailVerified) {
        // Si quiere ver un catálogo, lo dejamos
        if (isCatalogRoute) return null;

        // Para cualquier otra cosa, lo forzamos a verificar el correo
        if (location != '/verify-email') return '/verify-email';
        return null; 
      }

      // CASO C: Usuario SÍ logueado y SÍ verificado
      if (isLoggedIn && isEmailVerified) {
        // Solo bloqueamos el acceso al login, al index o a verificar correo.
        // Permitimos que puedan ver términos y privacidad estando logueados.
        if (location == '/login' || location == '/verify-email' || location == '/') {
          return '/dashboard';
        }
      }

      // Sin redirección necesaria
      return null;
    },
  );
});

// =============================================================================
// WIDGETS Y CLASES DE APOYO PARA EL ENRUTADOR
// =============================================================================

class AuthCheck extends ConsumerWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}