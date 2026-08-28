import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/catalog_entity.dart';
import '../../../inventory/domain/product_model.dart';
import '../providers/cart_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class OrderSummaryModal extends ConsumerWidget {
  final CatalogEntity catalog;
  final List<Product> inventory;

  const OrderSummaryModal({
    Key? key,
    required this.catalog,
    required this.inventory,
  }) : super(key: key);

  String _formatPrice(double price) {
    final formatter = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
    return formatter.format(price);
  }

  // Lógica de WhatsApp trasladada aquí y corregida (+57)
  Future<void> _sendOrderToWhatsApp(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || catalog.config.whatsappContact == null || catalog.config.whatsappContact!.isEmpty) return;

    double grandTotal = 0;
    StringBuffer message = StringBuffer();
    
    // Encabezado del mensaje usando formato de WhatsApp (Negritas con *)
    message.writeln('*NUEVO PEDIDO - ${catalog.name}*');
    message.writeln('Hola, me interesan los siguientes productos:\n');

    // Iteramos sobre el carrito para buscar el producto en el inventario
    cart.forEach((productId, quantity) {
      final product = inventory.firstWhere((p) => p.id == productId);
      final totalProduct = product.price * quantity;
      grandTotal += totalProduct;
      
      // Usamos un guion simple en lugar del emoji
      message.writeln('- $quantity x ${product.name} (${_formatPrice(totalProduct)})');
    });

    // Total final
    message.writeln('\n*TOTAL ESTIMADO: ${_formatPrice(grandTotal)}*');
    message.writeln('\n¡Quedo atento a la disponibilidad!');

    // LIMPIEZA Y FORMATEO DEL TELÉFONO (Solo se hace una vez)
    String phone = catalog.config.whatsappContact!.replaceAll(RegExp(r'[^0-9]'), '');
    // Si el usuario puso 10 dígitos (formato estándar colombiano) y no empieza con 57, se lo agregamos
    if (phone.length == 10 && !phone.startsWith('57')) {
      phone = '57$phone';
    }

    // Preparamos el mensaje para la URL
    final encodedMessage = Uri.encodeQueryComponent(message.toString()); 
    
    // Verificamos si el sistema operativo es móvil (iOS o Android)
    final isMobile = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;

    Uri url;
    if (kIsWeb && !isMobile) {
      // Si el usuario está en Web y NO está en un celular (ej: Windows/Mac), abrimos WhatsApp Web
      url = Uri.parse('https://web.whatsapp.com/send?phone=$phone&text=$encodedMessage');
    } else {
      // Si está en un celular (ya sea desde tu App nativa o desde Chrome/Safari web), 
      // usamos el enlace universal 'wa.me' que abre la app de WhatsApp directamente.
      url = Uri.parse('https://wa.me/$phone?text=$encodedMessage');
    }

    // ABRIMOS WHATSAPP
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      // Limpiamos el carrito y cerramos el modal después de enviar el pedido exitosamente
      ref.read(cartProvider.notifier).clearCart();
      if (context.mounted) Navigator.pop(context);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    }
  }  

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    // Calculamos el total en vivo
    double grandTotal = 0;
    final cartItems = cart.entries.map((entry) {
      final product = inventory.firstWhere((p) => p.id == entry.key);
      grandTotal += product.price * entry.value;
      return {'product': product, 'qty': entry.value};
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabecera del Modal
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Resumen de Pedido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () {
                      cartNotifier.clearCart();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_sweep, color: Colors.red),
                    label: const Text('Vaciar', style: TextStyle(color: Colors.red)),
                  )
                ],
              ),
            ),
            const Divider(height: 1),
            
            // Lista de productos en el carrito
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: cartItems.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = cartItems[index];
                  final product = item['product'] as Product;
                  final qty = item['qty'] as int;

                  return ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: product.imageUrl != null 
                            ? DecorationImage(image: NetworkImage(product.imageUrl!), fit: BoxFit.cover)
                            : null,
                        color: Colors.grey[200],
                      ),
                      child: product.imageUrl == null ? const Icon(Icons.image, color: Colors.grey) : null,
                    ),
                    title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_formatPrice(product.price * qty), style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => cartNotifier.decrement(product.id),
                        ),
                        Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => cartNotifier.addOrIncrement(product.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            // Footer con Total y Botón de Envío
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total a pagar:', style: TextStyle(fontSize: 18, color: Colors.black54)),
                      Text(_formatPrice(grandTotal), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366), // Verde WhatsApp
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: cart.isEmpty ? null : () => _sendOrderToWhatsApp(context, ref),
                      icon: const Icon(Icons.send, color: Colors.white),
                      label: const Text('Enviar pedido por WhatsApp', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}