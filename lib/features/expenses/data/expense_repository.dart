import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/expense_model.dart';

class ExpenseRepository {
  final FirebaseFirestore _firestore;
  final String userId;

  ExpenseRepository(this._firestore, this.userId);

  CollectionReference get _expensesRef => 
      _firestore.collection('companies').doc(userId).collection('expenses');

  // Referencia para guardar la lista de categorías
  DocumentReference get _categoriesRef => 
      _firestore.collection('companies').doc(userId).collection('config').doc('expense_categories');

  // 1. Obtener Gastos (Ordenados por fecha)
  Stream<List<Expense>> getExpenses() {
    return _expensesRef.orderBy('date', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Expense.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // 2. Guardar / Editar
  Future<void> saveExpense(Expense expense) async {
    if (expense.id.isEmpty) {
      await _expensesRef.add(expense.toMap());
    } else {
      await _expensesRef.doc(expense.id).update(expense.toMap());
    }
  }

  // 3. Eliminar un gasto
  Future<void> deleteExpense(String expenseId) async {
    await _firestore
        .collection('companies')
        .doc(userId)
        .collection('expenses')
        .doc(expenseId)
        .delete();
  }

  // 4. OBTENER CATEGORÍAS
  Future<List<String>> getManagedCategories() async {
    try {
      // .get() lee de la caché local si no hay internet gracias a persistenceEnabled
      final doc = await _categoriesRef.get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        return List<String>.from(data['list'] ?? []);
      }
    } catch (e) {
      // Si falla algo raro
    }
    
    return [
      'Arriendo',
      'Servicios Públicos',
      'Nómina',
      'Mantenimiento',
      'Insumos',
      'Publicidad',
      'Transporte',
      'Impuestos',
      'Otros'
    ];
  }

  // 5. GUARDAR LISTA DE CATEGORÍAS
  Future<void> saveManagedCategories(List<String> categories) async {
    await _categoriesRef.set({'list': categories});
  }

  // --- 6. REGISTRAR PAGO (CORREGIDO PARA OFFLINE) ---
  // Antes usaba Transaction (Online). Ahora usa Lectura+Update (Offline Compatible).
  Future<void> addPayment(String expenseId, ExpensePayment payment) async {
    final docRef = _expensesRef.doc(expenseId);

    // 1. LEER (Lee de caché si no hay internet)
    final snapshot = await docRef.get();
    
    if (!snapshot.exists) throw Exception("El gasto no existe localmente ni en red");

    final data = snapshot.data() as Map<String, dynamic>;
    
    // 2. CÁLCULOS
    final double totalAmount = (data['amount'] ?? 0).toDouble();
    List<dynamic> paymentsList = List.from(data['payments'] ?? []);
    
    // Agregamos el nuevo pago
    paymentsList.add(payment.toMap());
    
    // Calculamos total pagado
    double totalPaid = 0;
    for (var p in paymentsList) {
      totalPaid += (p['amount'] ?? 0).toDouble();
    }
    
    // Determinamos si sigue pendiente (Margen de error de 1 peso)
    bool isStillPending = totalPaid < (totalAmount - 1.0);

    // 3. GUARDAR (Funciona offline, sincroniza después)
    await docRef.update({
      'payments': paymentsList,
      'isPending': isStillPending,
      'isPaid': !isStillPending,
    });
  }

  // 7. ACTUALIZAR OBSERVACIÓN
  Future<void> updateObservation(String expenseId, String newObservation) async {
    await _expensesRef.doc(expenseId).update({
      'observations': newObservation,
    });
  }
}