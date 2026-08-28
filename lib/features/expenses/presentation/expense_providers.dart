import 'dart:async'; // Necesario para AsyncNotifier
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/expense_repository.dart'; // Usamos singular, como tu archivo original
import '../domain/expense_model.dart';

// 1. Proveedor del Repositorio
final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  final companyId = ref.watch(companyIdProvider).value;
  if (companyId == null) throw Exception('Cargando empresa...');
  
  return ExpenseRepository(FirebaseFirestore.instance, companyId);
});

// 2. Stream de Gastos
final expensesStreamProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(expenseRepositoryProvider).getExpenses();
});

// 3. NOTIFIER DE CATEGORÍAS (AsyncNotifier)
// Esto reemplaza al antiguo FutureProvider pero mantiene la compatibilidad
class ExpenseCategoriesNotifier extends AsyncNotifier<List<String>> {
  
  @override
  Future<List<String>> build() async {
    // Carga inicial desde el repositorio
    return ref.watch(expenseRepositoryProvider).getManagedCategories();
  }

  // Agregar Categoría
  Future<void> add(String item) async {
    final currentList = state.value ?? [];
    if (!currentList.contains(item) && item.isNotEmpty) {
      // 1. Actualizamos el estado localmente (Optimista)
      final newList = [...currentList, item];
      state = AsyncData(newList);
      
      // 2. Guardamos en Firebase
      await ref.read(expenseRepositoryProvider).saveManagedCategories(newList);
    }
  }

  // Eliminar Categoría
  Future<void> remove(String item) async {
    final currentList = state.value ?? [];
    if (currentList.contains(item)) {
      final newList = currentList.where((e) => e != item).toList();
      state = AsyncData(newList);
      
      await ref.read(expenseRepositoryProvider).saveManagedCategories(newList);
    }
  }
}

// El proveedor final que usará tu UI
final expenseCategoriesProvider = AsyncNotifierProvider<ExpenseCategoriesNotifier, List<String>>(() {
  return ExpenseCategoriesNotifier();
});