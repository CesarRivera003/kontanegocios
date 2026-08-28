import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/catalog_entity.dart';
import '../../domain/entities/catalog_content_entity.dart';
import '../../../inventory/domain/product_model.dart';
import '../../../inventory/presentation/inventory_providers.dart';
import '../providers/cart_provider.dart';
import 'order_summary_modal.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';

import '../../../promotions/domain/promotion_model.dart';
import '../../../promotions/presentation/promotions_providers.dart';

class CatalogViewerScreen extends ConsumerWidget {
  final CatalogEntity catalog;

  const CatalogViewerScreen({Key? key, required this.catalog}) : super(key: key);

  String _formatPrice(double price) {
    final formatter = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
    return formatter.format(price);
  }

  Color _hexToColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return Colors.black87;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  void _shareCatalog(BuildContext context) async {
    final String catalogUrl = 'https://app.kontanegocios.com/c/${catalog.id}';
    final String textToShare = '¡Hola! Mira nuestro catálogo "${catalog.name}": $catalogUrl';

    if (kIsWeb) {
      // Si estamos en PC/Navegador, copiamos el enlace al portapapeles
      await Clipboard.setData(ClipboardData(text: textToShare));
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enlace copiado al portapapeles 📋'),
            backgroundColor: Colors.black87,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Si estamos en un celular, abrimos el menú nativo de compartir
      Share.share(textToShare, subject: 'Catálogo de productos');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsyncValue = ref.watch(publicInventoryStreamProvider(catalog.businessId));

    // 1. Obtenemos la configuración del fondo desde el modelo
    final backgroundStyle = catalog.config.customStyle?.background;
    
    // 2. Verificamos si es de tipo textura
    final isTexture = backgroundStyle?.type.toString().endsWith('texture') ?? false; 
    
    // 3. Definimos el color sólido (o el crema por defecto)
    final solidColor = (backgroundStyle != null && !isTexture)
        ? _hexToColor(backgroundStyle.value)
        : const Color(0xFFFBFBF9); 

    return Scaffold(
      // Si usamos textura, el Scaffold debe ser transparente
      backgroundColor: isTexture ? Colors.transparent : solidColor,
      body: Container(
        decoration: BoxDecoration(
          color: isTexture ? null : solidColor,
          // Preparamos la imagen de fondo para que se repita como patrón
          image: isTexture
              ? DecorationImage(
                  image: AssetImage(backgroundStyle!.value), 
                  repeat: ImageRepeat.repeat,
                )
              : null,
        ),
        child: productsAsyncValue.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
          data: (inventoryProducts) {
            // Centramos y restringimos el ancho para pantallas grandes (PC/Tablets)
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 750), // Ancho máximo
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // 1. App Bar Minimalista y Centrada
                    SliverAppBar(
                      expandedHeight: 100.0,
                      floating: false,
                      pinned: true,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      scrolledUnderElevation: 1,
                      centerTitle: true,
                      
                      // 1. Botón de salir (Atrás) con fondo blanco
                      leading: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const BackButton(color: Colors.black87),
                        ),
                      ),
                      
                      actions: [
                        // 2. Botón de compartir con fondo blanco
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.ios_share, color: Colors.black87),
                              onPressed: () => _shareCatalog(context),
                            ),
                          ),
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        centerTitle: true,
                        titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        // 3. Título del catálogo con fondo blanco tipo "pastilla"
                        title: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9), // Un poco de opacidad luce muy bien
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            catalog.name.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              fontSize: 16, // Lo reduje a 16 para que encaje mejor con el nuevo padding
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 2. Contenido dinámico
                    if (catalog.content.isEmpty)
                      const SliverFillRemaining(
                        child: Center(child: Text('Este catálogo aún no tiene contenido.', style: TextStyle(color: Colors.grey))),
                      )
                    else
                      ...catalog.content.map((block) {
                        return _buildSliverBlock(block, inventoryProducts, ref);
                      }).toList(),

                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      
      floatingActionButton: Consumer(
        builder: (context, ref, child) {
          final cart = ref.watch(cartProvider);
          if (cart.isEmpty) return const SizedBox.shrink();

          final totalItems = cart.values.fold(0, (sum, qty) => sum + qty);

          return FloatingActionButton.extended(
            onPressed: () {
              // AHORA ABRIMOS EL MODAL EN LUGAR DE ENVIAR DIRECTO
              productsAsyncValue.whenData((inventory) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (context) => FractionallySizedBox(
                    heightFactor: 0.85, // Ocupa el 85% de la pantalla
                    child: OrderSummaryModal(catalog: catalog, inventory: inventory),
                  ),
                );
              });
            },
            backgroundColor: Colors.black87,
            elevation: 4,
            icon: const Icon(Icons.shopping_bag, color: Colors.white),
            label: Text(
              'Ver Pedido ($totalItems)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat, // Botón centrado
    );
  }

  // --- HELPER PARA DIBUJAR EL FONDO DEL TEXTO ---
  Widget _buildTextWithBackground(CatalogContentEntity block, Widget textWidget) {
    if (block.hasTextBackground == true) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _hexToColor(block.textBackgroundColor ?? '#FFFFFF').withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: textWidget,
      );
    }
    return textWidget;
  }

  // --- RENDERIZADOR DE BLOQUES ESTILIZADO ---
  Widget _buildSliverBlock(CatalogContentEntity block, List<Product> inventory, WidgetRef ref) {
    // 1. CREAMOS EL ESTILO DINÁMICO AQUÍ
    final customStyle = GoogleFonts.getFont(
      block.fontFamily ?? 'Roboto',
      fontSize: block.fontSize ?? (block.type == CatalogContentType.title ? 28.0 : 15.0),
      color: _hexToColor(block.textColor),
      fontWeight: block.isBold ? FontWeight.bold : (block.type == CatalogContentType.title ? FontWeight.w400 : FontWeight.normal),
      fontStyle: block.isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: block.isUnderline ? TextDecoration.underline : TextDecoration.none,
      height: block.type == CatalogContentType.title ? 1.2 : 1.6,
    );

    switch (block.type) {
      case CatalogContentType.title:
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 12),
            // Centramos para que el fondo no ocupe todo el ancho de la pantalla
            child: Center(
              child: _buildTextWithBackground(
                block,
                Text(
                  block.textValue ?? '',
                  textAlign: TextAlign.center,
                  style: customStyle, 
                ),
              ),
            ),
          ),
        );

      case CatalogContentType.text:
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
            child: Center(
              child: _buildTextWithBackground(
                block,
                Text(
                  block.textValue ?? '',
                  textAlign: TextAlign.center,
                  style: customStyle, 
                ),
              ),
            ),
          ),
        );

      case CatalogContentType.productGrid:
        if (block.productIds == null || block.productIds!.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final blockProducts = inventory.where((p) => block.productIds!.contains(p.id)).toList();

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220.0, 
              mainAxisSpacing: 24.0,
              crossAxisSpacing: 16.0,
              childAspectRatio: 0.58, 
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                return HoverableProductCard(
                  product: blockProducts[index],
                  showPrices: catalog.config.showPrices,
                  formatPrice: _formatPrice,
                  businessId: catalog.businessId,
                );
              },
              childCount: blockProducts.length,
            ),
          ),
        );
        
      default:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

}

class HoverableProductCard extends ConsumerStatefulWidget {
  final Product product;
  final bool showPrices;
  final String Function(double) formatPrice;
  final String businessId; // <-- NUEVO PARÁMETRO

  const HoverableProductCard({
    Key? key,
    required this.product,
    required this.showPrices,
    required this.formatPrice,
    required this.businessId,
  }) : super(key: key);

  @override
  ConsumerState<HoverableProductCard> createState() => _HoverableProductCardState();
}

class _HoverableProductCardState extends ConsumerState<HoverableProductCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final quantity = cart[widget.product.id] ?? 0;
    final cartNotifier = ref.read(cartProvider.notifier);

    // --- NUEVA LÓGICA: Buscar promociones ---
    final activePromotionsAsync = ref.watch(publicActivePromotionsProvider(widget.businessId));
    final activePromotions = activePromotionsAsync.value ?? [];

    Promotion? myPromo;
    try {
      myPromo = activePromotions.firstWhere((p) => p.targetProductIds.contains(widget.product.id));
    } catch (e) {
      myPromo = null; 
    }

    String badgeText = '';
    Color badgeColor = Colors.red;
    
    if (myPromo != null) {
      if (myPromo.type == PromotionType.seasonal) {
        badgeText = "-${myPromo.percentage.toStringAsFixed(0)}%"; // Ej: -15%
        badgeColor = Colors.red;
      } else if (myPromo.type == PromotionType.volume) {
        badgeText = "Dto. Mayorista"; // Oferta por volumen
        badgeColor = Colors.orange.shade700;
      } else if (myPromo.type == PromotionType.buyXgetY) {
        final paga = myPromo.buyQuantity;
        final lleva = myPromo.buyQuantity + myPromo.getQuantity;
        
        if (paga == 1 && lleva == 2) {
          badgeText = "2x1"; // Mantenemos el clásico si es exactamente 2x1
        } else {
          // Usamos \n para apilar el texto y ahorrar ancho
          badgeText = "LLEVA $lleva\nPAGA $paga"; 
        }
        badgeColor = Colors.purple;
      }
    }
    // ----------------------------------------

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => cartNotifier.addOrIncrement(widget.product.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isHovered ? 0.1 : 0.03),
                blurRadius: _isHovered ? 12 : 8,
                offset: Offset(0, _isHovered ? 6 : 4),
              ),
            ],
            border: Border.all(
              color: quantity > 0 ? Colors.black87 : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.product.imageUrl != null && widget.product.imageUrl!.isNotEmpty
                          ? Image.network(widget.product.imageUrl!, fit: BoxFit.cover)
                          : Icon(Icons.camera_alt_outlined, size: 40, color: Colors.grey[300]),
                      
                      // --- NUEVO: BADGE DE PROMOCIÓN ---
                      if (myPromo != null)
                        Positioned(
                          top: 8,
                          left: 8, // A la izquierda para no tapar el círculo del carrito
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                            ),
                            child: Text(
                              badgeText,
                              textAlign: TextAlign.center, // Centra las dos líneas
                              style: const TextStyle(
                                color: Colors.white, 
                                fontWeight: FontWeight.bold, 
                                fontSize: 10, // Letra ligeramente más pequeña para que encaje
                                height: 1.1,  // Reduce el espacio entre la línea superior e inferior
                              ),
                            ),
                          ),
                        ),
                      
                      // Insignia (Badge) del carrito
                      if (quantity > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.black87,
                            child: Text('$quantity', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text(
                      widget.product.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.black87),
                    ),
                    
                    if (widget.product.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        // NOTA: Asegúrate de tener la función _showProductDetailsModal agregada aquí abajo como lo hicimos antes
                        onTap: () => _showProductDetailsModal(context, widget.product, cartNotifier, myPromo),
                        child: const Text(
                          "Ver más detalles",
                          style: TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    
                    if (widget.showPrices)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _isHovered && quantity > 0
                            ? Container(
                                key: const ValueKey('controls'),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 18),
                                      onPressed: () => cartNotifier.decrement(widget.product.id),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    ),
                                    Text('$quantity', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 18),
                                      onPressed: () => cartNotifier.addOrIncrement(widget.product.id),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                key: const ValueKey('price'),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.black12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                // --- NUEVO: LÓGICA DE PRECIO TACHADO ---
                                child: (myPromo != null && myPromo.type == PromotionType.seasonal)
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Precio Original Tachado
                                        Text(
                                          widget.formatPrice(widget.product.price),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w400, 
                                            fontSize: 11, 
                                            color: Colors.grey, 
                                            decoration: TextDecoration.lineThrough, // Tacha el texto
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Nuevo Precio con Descuento
                                        Text(
                                          widget.formatPrice(widget.product.price * (1 - (myPromo.percentage / 100))),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900, 
                                            fontSize: 14, 
                                            color: Colors.red, // Rojo para resaltar la oferta
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      widget.formatPrice(widget.product.price),
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
                                    ),
                                // ----------------------------------------
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // --- NUEVA FUNCIÓN: MODAL DE DETALLES DEL PRODUCTO ---
  void _showProductDetailsModal(BuildContext context, Product product, dynamic cartNotifier, Promotion? myPromo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite que el modal ocupe más espacio
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.85, // Ocupará el 85% de la pantalla
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Botón para cerrar
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0, right: 8.0),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              
              // 2. Contenido Scrolleable (Aquí la descripción puede ser infinita)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Foto Grande
                      Center(
                        child: Container(
                          height: 250, 
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[50], // Fondo muy sutil por si la imagen no ocupa todo el ancho
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200), // Borde elegante
                          ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                              ? Image.network(product.imageUrl!, height: 250, width: double.infinity, fit: BoxFit.contain)
                              : Icon(Icons.camera_alt_outlined, size: 80, color: Colors.grey[400]),
                          ),
                        ),  
                      ),
                      const SizedBox(height: 24),
                      
                      // Título y Precio
                      Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (widget.showPrices)
                        if (myPromo != null && myPromo.type == PromotionType.seasonal)
                          Row(
                            children: [
                              Text(
                                widget.formatPrice(product.price),
                                style: const TextStyle(fontSize: 18, color: Colors.grey, decoration: TextDecoration.lineThrough),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                widget.formatPrice(product.price * (1 - (myPromo.percentage / 100))),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.red),
                              ),
                            ],
                          )
                        else
                          Text(
                            widget.formatPrice(product.price),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87),
                          ),

                        // --- NUEVO: MENSAJE DE DESCUENTO MAYORISTA ---
                        if (myPromo != null && myPromo.type == PromotionType.volume) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.orange.shade800, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Lleva ${myPromo.minQuantity} o más unidades y obtén un ${myPromo.percentage.toStringAsFixed(0)}% de descuento adicional en este producto.",
                                    style: TextStyle(
                                      color: Colors.orange.shade900, 
                                      fontSize: 13, 
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // ---------------------------------------------
                      
                      const Divider(height: 20, color: Colors.black12),
                      
                      // Descripción Completa
                      const Text("Descripción", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                      const SizedBox(height: 12),
                      Text(
                        product.description,
                        style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black54),
                      ),
                      const SizedBox(height: 40), 
                    ],
                  ),
                ),
              ),
              
              // 3. Botón inferior fijo para agregar al pedido
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    cartNotifier.addOrIncrement(product.id);
                    Navigator.pop(context); // Cierra el modal automáticamente
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${product.name} agregado al pedido'), 
                        duration: const Duration(seconds: 1),
                        backgroundColor: Colors.black87,
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text("Agregar al Pedido", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}