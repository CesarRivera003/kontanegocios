import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/finance_model.dart';

class FinanceRepository {
  final FirebaseFirestore _firestore;
  final String userId; // ID de la empresa/usuario

  FinanceRepository(this._firestore, this.userId);

  // Referencia principal a la colección de cuentas bancarias/cajas
  CollectionReference get _accountsRef => 
      _firestore.collection('companies').doc(userId).collection('bank_accounts');

  // ==============================================================================
  // GESTIÓN DE CUENTAS (Cajas y Bancos)
  // ==============================================================================

  /// Obtiene la lista de cuentas en tiempo real
  Stream<List<BankAccount>> getAccounts() {
    return _accountsRef.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return BankAccount.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  /// Crea una nueva cuenta o caja con su saldo inicial
  Future<void> createAccount(BankAccount account) async {
    // 1. Crear la cuenta
    final docRef = await _accountsRef.add(account.toMap());

    // 2. Si tiene saldo inicial, registrarlo como movimiento de "Apertura"
    if (account.balance > 0) {
      final tx = BankTransaction(
        id: '', // Se genera auto
        accountId: docRef.id,
        type: 'DEPOSIT', // Depósito inicial
        amount: account.balance,
        description: 'Saldo Inicial de Apertura',
        date: DateTime.now(),
      );
      
      // Guardamos la transacción en la subcolección
      await docRef.collection('transactions').add(tx.toMap());
    }
  }

  // ==============================================================================
  // GESTIÓN DE TRANSACCIONES (Movimientos)
  // ==============================================================================

  /// Referencia a la subcolección de transacciones de una cuenta específica
  CollectionReference _transactionsRef(String accountId) =>
      _accountsRef.doc(accountId).collection('transactions');

  /// Obtiene el historial de movimientos de una cuenta
  Stream<List<BankTransaction>> getTransactions(String accountId) {
    return _transactionsRef(accountId)
        .orderBy('date', descending: true)
        .limit(50) // Limitamos a 50 para optimizar lectura
        .snapshots()
        .map((s) => s.docs.map((d) => BankTransaction.fromMap(d.data() as Map<String, dynamic>, d.id)).toList());
  }

  /// Agrega una transacción simple (Ingreso o Gasto) y actualiza el saldo de forma atómica
  Future<void> addTransaction(BankTransaction tx) async {
    final accountDoc = _accountsRef.doc(tx.accountId);
    final newTxRef = _transactionsRef(tx.accountId).doc();
    
    // Determinar si suma o resta
    final bool isAddition = ['DEPOSIT', 'SALE', 'INCOME', 'TRANSFER_IN'].contains(tx.type);
    final double delta = isAddition ? tx.amount : -tx.amount;

    final batch = _firestore.batch();
    
    // 1. Guardar la transacción
    batch.set(newTxRef, tx.toMap());

    // 2. Actualizar el saldo usando FieldValue.increment (Funciona ONLINE y OFFLINE)
    batch.set(accountDoc, {
      'balance': FieldValue.increment(delta),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ==============================================================================
  // TRANSFERENCIAS ENTRE CUENTAS
  // ==============================================================================

  Future<void> transferFunds({
    required String sourceAccountId,
    required String destinationAccountId,
    required double amount,
    required String description, 
  }) async {
    await _firestore.runTransaction((transaction) async {
      final sourceRef = _accountsRef.doc(sourceAccountId);
      final destRef = _accountsRef.doc(destinationAccountId);
      
      final sourceTxRef = sourceRef.collection('transactions').doc();
      final destTxRef = destRef.collection('transactions').doc();

      final sourceSnapshot = await transaction.get(sourceRef);
      final destSnapshot = await transaction.get(destRef);

      if (!sourceSnapshot.exists || !destSnapshot.exists) {
        throw Exception("Una de las cuentas no existe");
      }

      final double sourceBalance = ((sourceSnapshot.data() as Map<String, dynamic>)['balance'] ?? 0).toDouble();
      final double destBalance = ((destSnapshot.data() as Map<String, dynamic>)['balance'] ?? 0).toDouble();

      final txOut = BankTransaction(
        id: sourceTxRef.id,
        accountId: sourceAccountId,
        type: 'TRANSFER_OUT',
        amount: amount,
        description: 'Transferencia a: $description',
        date: DateTime.now(),
        transferRelatedAccountId: destinationAccountId,
      );

      final txIn = BankTransaction(
        id: destTxRef.id,
        accountId: destinationAccountId,
        type: 'TRANSFER_IN',
        amount: amount,
        description: 'Recibido de: $description',
        date: DateTime.now(),
        transferRelatedAccountId: sourceAccountId,
      );

      transaction.set(sourceTxRef, txOut.toMap());
      transaction.set(destTxRef, txIn.toMap());
      
      transaction.update(sourceRef, {'balance': sourceBalance - amount});
      transaction.update(destRef, {'balance': destBalance + amount});
    });
  }

  // --- ESTABLECER CUENTA PRINCIPAL (DEFAULT) ---
  Future<void> setAsDefaultAccount(String accountId, bool isCashType) async {
    final batch = _firestore.batch();
    final query = await _accountsRef.where('isCash', isEqualTo: isCashType).get();
    
    for (var doc in query.docs) {
      batch.update(doc.reference, {'isDefault': false});
    }

    final targetRef = _accountsRef.doc(accountId);
    batch.update(targetRef, {'isDefault': true});
    await batch.commit();
  }

  // --- ACTUALIZAR O BORRAR CUENTAS ---
  Future<void> updateAccount(BankAccount account) async {
    await _accountsRef.doc(account.id).update(account.toMap());
  }

  Future<void> deleteAccountPermanent(String accountId) async {
    await _accountsRef.doc(accountId).delete();
  }

  // ==============================================================================
  // NUEVO: REVERSIÓN INTELIGENTE (SIMPLIFICADA)
  // ==============================================================================
  Future<void> registerReversal({
    required double amount, 
    required bool isCash, 
    String? bankName, // <--- AHORA SÍ ACEPTAMOS ESTE PARÁMETRO
    required String description,
  }) async {
    // 1. Buscamos las cuentas
    final accountsSnapshot = await _accountsRef.get();
    final accounts = accountsSnapshot.docs.map((d) => BankAccount.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
    
    String? targetAccountId;

    if (isCash) {
      // Buscar caja
      try {
        targetAccountId = accounts.firstWhere((a) => a.isCash && a.isDefault, 
            orElse: () => accounts.firstWhere((a) => a.isCash, orElse: () => accounts.first)).id;
      } catch (_) {}
    } else {
      // Solo procedemos si nos dieron un nombre de banco (para Transferencias)
      if (bankName != null && bankName.isNotEmpty) {
        try {
          // Buscamos coincidencia exacta o parcial del nombre
          final acc = accounts.firstWhere((a) => !a.isCash && a.name.toLowerCase().contains(bankName.toLowerCase()));
          targetAccountId = acc.id;
        } catch (_) {
          // Si nos dieron un nombre pero NO existe el banco, NO hacemos nada.
          // No queremos afectar un banco equivocado.
          return; 
        }
      } else {
        // Si bankName es NULL (ej: Crédito, Otros), NO seleccionamos ninguna cuenta.
        // Retornamos inmediatamente para no afectar tesorería.
        return; 
      }
    }

    if (targetAccountId == null) return; 

    // Guardamos en variable segura para evitar error de null check dentro de transaction
    final String safeAccountId = targetAccountId;

    // 2. Ejecutar la Transacción
    final accountDoc = _accountsRef.doc(safeAccountId);
    
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(accountDoc);
      if (!snapshot.exists) return;

      final currentBalance = ((snapshot.data() as Map<String, dynamic>)['balance'] ?? 0).toDouble();
      
      // 1. MATEMÁTICA: Usamos el monto con su signo original (Negativo o Positivo)
      // para afectar el saldo correctamente.
      final double newBalance = currentBalance + amount; 

      // 2. VISUAL: Preparamos los datos para que se vean BONITOS en la lista.
      // Si el monto es positivo (>0) significa que el dinero ENTRA (Devolución de gasto).
      // Si el monto es negativo (<0) significa que el dinero SALE (Anulación de venta).
      
      final String visualType = amount > 0 ? 'INCOME' : 'EXPENSE'; 
      final double visualAmount = amount.abs(); // Quitamos el signo menos para guardar

      final newTxRef = _transactionsRef(safeAccountId).doc();
      
      transaction.set(newTxRef, {
        'id': newTxRef.id,
        'accountId': safeAccountId,
        'type': visualType, // <--- CAMBIO CLAVE: Usamos tipos que tu App ya sabe colorear
        'amount': visualAmount, // <--- CAMBIO CLAVE: Guardamos siempre positivo
        'description': description,
        'date': DateTime.now(),
        'isReversal': true, // (Opcional) Marca para identificarlo en reportes futuros
      });
      
      transaction.update(accountDoc, {'balance': newBalance});
    });
  }
}