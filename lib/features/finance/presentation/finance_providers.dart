import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/finance_repository.dart';
import '../domain/finance_model.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  final companyId = ref.watch(companyIdProvider).value;
  if (companyId == null) throw Exception('No company ID');
  return FinanceRepository(FirebaseFirestore.instance, companyId);
});

final bankAccountsProvider = StreamProvider<List<BankAccount>>((ref) {
  final repo = ref.watch(financeRepositoryProvider);
  return repo.getAccounts();
});

// Familia de providers para obtener transacciones de una cuenta específica
final transactionsProvider = StreamProvider.family<List<BankTransaction>, String>((ref, accountId) {
  final repo = ref.watch(financeRepositoryProvider);
  return repo.getTransactions(accountId);
});