import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/sales/domain/sale_model.dart';
import '../../features/sales/domain/cart_item_model.dart';
import '../../features/inventory/domain/product_model.dart';
import '../../features/clients/domain/client_model.dart';
import '../../features/sales/data/plemsi_service.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/auth/presentation/auth_providers.dart';

enum SyncStatus { idle, syncing, success, error }

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final String? message;

  const SyncState({
    this.status = SyncStatus.idle,
    this.pendingCount = 0,
    this.message,
  });

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    String? message,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      message: message ?? this.message,
    );
  }
}

/// Motor de retransmisión y sincronización automática para Riverpod 3.x
class SyncQueueService extends Notifier<SyncState> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSyncing = false;
  bool _isDisposed = false;

  @override
  SyncState build() {
    ref.onDispose(() {
      _isDisposed = true;
    });
    return const SyncState();
  }

  /// Método principal: Sincroniza todas las ventas y facturas pendientes
  Future<void> syncPendingSales() async {
    final companyId = ref.read(companyIdProvider).value ?? '';
    if (_isSyncing || companyId.isEmpty) return;
    _isSyncing = true;

    try {
      final salesRef = _firestore
          .collection('companies')
          .doc(companyId)
          .collection('sales');

      // 1. Buscamos ventas locales que necesiten sincronización
      final pendingSnapshot = await salesRef
          .where('needsSync', isEqualTo: true)
          .get(const GetOptions(source: Source.serverAndCache));

      if (pendingSnapshot.docs.isEmpty) {
        if (!_isDisposed) {
          state = const SyncState(status: SyncStatus.idle, pendingCount: 0);
        }
        _isSyncing = false;
        return;
      }

      final pendingSales = pendingSnapshot.docs
          .map((doc) => Sale.fromMap(doc.data(), doc.id))
          .toList();

      // Ordenar cronológicamente (las más antiguas primero)
      pendingSales.sort((a, b) => a.date.compareTo(b.date));

      if (!_isDisposed) {
        state = state.copyWith(
          status: SyncStatus.syncing,
          pendingCount: pendingSales.length,
          message: 'Sincronizando ${pendingSales.length} transacciones...',
        );
      }

      final plemsi = PlemsiService(_firestore);
      final settingsRepo = SettingsRepository(_firestore, companyId);
      int syncedCount = 0;

      for (final sale in pendingSales) {
        final docRef = salesRef.doc(sale.id);

        // CASO A: Venta con Facturación Electrónica pendiente
        if (sale.isElectronicInvoice &&
            (sale.dianStatus == 'Pendiente_Sincronizacion' ||
                sale.dianStatus == 'Pendiente')) {
          if (sale.clientData != null) {
            final client = Client.fromMap(
              sale.clientData!,
              sale.clientData!['id'] ?? '',
            );

            final hasBalance = await settingsRepo.hasInvoiceBalance();
            if (!hasBalance) {
              await docRef.update({
                'dianStatus': 'Saldo_Agotado',
                'needsSync': false,
              });
              continue;
            }

            final cartItems = _mapToCartItems(sale.items);
            final safePaymentMethods = sale.initialPayments
                .map((p) => PaymentMethodDetail(
                      method: p.method,
                      amount: p.amount,
                      bankName: p.bankName,
                      paymentDeadline: null,
                    ))
                .toList();

            final feResult = await plemsi.emitInvoice(
              companyId: companyId,
              saleId: sale.id,
              client: client,
              cartItems: cartItems,
              totalSaleValue: sale.total,
              paymentMethods: safePaymentMethods,
              additionalCosts: sale.additionalCosts,
              paymentDeadline: sale.earliestDeadline,
            );

            if (feResult != null && feResult['status'] != 'Rechazada') {
              await docRef.update({
                'dianStatus': feResult['status'] ?? 'Aceptada',
                'cufe': feResult['cufe'],
                'pdfUrl': feResult['pdfUrl'],
                'dianPrefix': feResult['prefix'],
                'dianNumber': feResult['number'],
                'needsSync': false,
              });
              await settingsRepo.consumeElectronicInvoice();
            } else {
              await docRef.update({
                'dianStatus': 'Rechazada_Por_Validar',
                'needsSync': false,
              });
            }
          } else {
            await docRef.update({'needsSync': false});
          }
        }
        // CASO B: Venta POS común
        else {
          await docRef.update({'needsSync': false});
        }

        syncedCount++;
      }

      if (!_isDisposed) {
        state = SyncState(
          status: SyncStatus.success,
          pendingCount: 0,
          message: '¡Sincronización completada! ($syncedCount ventas procesadas)',
        );
      }

      // Regresar a reposo automáticamente a los 4 segundos
      Future.delayed(const Duration(seconds: 4), () {
        if (!_isDisposed && state.status == SyncStatus.success) {
          state = const SyncState(status: SyncStatus.idle);
        }
      });
    } catch (e) {
      debugPrint("❌ Error en SyncQueueService: $e");
      if (!_isDisposed) {
        state = state.copyWith(
          status: SyncStatus.error,
          message: 'Error al sincronizar algunas ventas',
        );
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Reconstruye los CartItems de forma segura con todos los campos de Product
  List<CartItem> _mapToCartItems(List<Map<String, dynamic>> items) {
    return items.map((m) {
      final product = Product(
        id: m['productId'] ?? '',
        name: m['name'] ?? '',
        barcode: '',
        description: '',
        price: (m['price'] ?? 0).toDouble(),
        cost: 0.0,
        stock: 0,
        category: 'General',
        unit: m['unit'] ?? 'Und',
        taxRate: (m['taxRate'] ?? 0).toDouble(),
        taxType: m['taxType'] ?? 'EXCLUIDO',
      );
      return CartItem(
        product: product,
        quantity: (m['quantity'] ?? 1) is int
            ? m['quantity'] as int
            : (m['quantity'] as num).toInt(),
        price: (m['price'] ?? 0).toDouble(),
      );
    }).toList();
  }
}

/// Provider global registrado con NotifierProvider para Riverpod 3.x
final syncQueueServiceProvider =
    NotifierProvider<SyncQueueService, SyncState>(SyncQueueService.new);