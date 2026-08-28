import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../clients/domain/client_model.dart';
import '../domain/cart_item_model.dart';
import '../domain/sale_model.dart';

class PlemsiService {
  PlemsiService(ignoreFirestoreParameter); // Ya no necesitamos Firestore aquí

  /// Llama a la Cloud Function segura para emitir la factura
  Future<Map<String, dynamic>?> emitInvoice({
    required String companyId,
    required String saleId,
    required Client client,
    required List<CartItem> cartItems,
    required double totalSaleValue,
    required List<PaymentMethodDetail> paymentMethods,
    required List<Map<String, dynamic>> additionalCosts,
    DateTime? paymentDeadline,
  }) async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('emitirFacturaPlemsi');

      String? safeDateStr;
      if (paymentDeadline != null) {
        safeDateStr = "${paymentDeadline.year}-${paymentDeadline.month.toString().padLeft(2, '0')}-${paymentDeadline.day.toString().padLeft(2, '0')}";
      }

      // Solo mandamos los datos crudos a la nube. ¡Nada de llaves ni matemáticas!
      final response = await callable.call({
        'companyId': companyId,
        'saleId': saleId,
        'client': client.toMap(), 
        'cartItems': cartItems.map((c) => {
          'product': c.product.toMap(),
          'quantity': c.quantity,
          'price': c.price,
        }).toList(),
        'paymentMethods': paymentMethods.map((p) => p.toMap()).toList(),
        'additionalCosts': additionalCosts,
        'paymentDeadline': safeDateStr,
      });

      final result = Map<String, dynamic>.from(response.data);
      return result;

    } catch (e) {
      debugPrint("❌ Error llamando a la Cloud Function de Plemsi: $e");
      return {'status': 'Pendiente', 'error': 'Error conectando al servidor seguro'};
    }
  }
}