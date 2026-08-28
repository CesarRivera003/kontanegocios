import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/user_profile_provider.dart';
import '../../auth/domain/user_model.dart';
import '../data/cash_repository.dart';
import '../domain/cash_count_model.dart';
import '../domain/cash_transaction_model.dart';

// 1. Proveedor de Movimientos del Día (Entradas/Salidas)
// Se actualiza automáticamente si agregas algo.
final dailyMovementsProvider = StreamProvider.autoDispose<List<CashTransaction>>((ref) {
  final userProfile = ref.watch(userProfileProvider).value;
  if (userProfile == null) return Stream.value([]);
  
  return ref.watch(cashRepositoryProvider).getDailyMovements(userProfile.id ?? '');
});

// 2. Proveedor de Historial de Cierres
final cashHistoryProvider = StreamProvider.autoDispose<List<CashCountModel>>((ref) {
  final userProfile = ref.watch(userProfileProvider).value;
  if (userProfile == null) return Stream.value([]);

  final bool isAdmin = userProfile.role == UserRole.admin || userProfile.role == UserRole.manager;
  
  return ref.watch(cashRepositoryProvider).getClosureHistory(
    userProfile.id ?? '', 
    isAdmin
  );
});

// 3. Proveedor de Totales del Sistema (Ventas y Gastos automáticos)
// Usamos FutureProvider para cargarlo una vez y ya.
final systemTotalsProvider = FutureProvider.autoDispose<Map<String, double>>((ref) async {
  final userProfile = ref.watch(userProfileProvider).value;
  if (userProfile == null) return {'sales': 0.0, 'expenses': 0.0};

  final bool canHaveExpenses = userProfile.role != UserRole.cashier;
  
  return ref.read(cashRepositoryProvider).getUserDailyTotals(
    userName: userProfile.name,
    canHaveExpenses: canHaveExpenses,
  );
});

// 4. Proveedor de Base Guardada
final savedBaseProvider = FutureProvider.autoDispose<double>((ref) async {
  final userProfile = ref.watch(userProfileProvider).value;
  if (userProfile == null) return 0.0;
  
  return ref.read(cashRepositoryProvider).getBaseDraft(userProfile.id ?? '');
});