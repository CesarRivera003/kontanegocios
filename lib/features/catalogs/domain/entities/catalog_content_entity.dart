// lib/features/catalogs/domain/entities/catalog_content_entity.dart

enum CatalogContentType {
  title,             
  text,              
  featuredProducts,  
  productGrid        
}

class CatalogContentEntity {
  final String id; 
  final CatalogContentType type;
  final String? textValue; 
  final List<String>? productIds; 

  // --- NUEVAS PROPIEDADES DE ESTILO DE TEXTO ---
  final double? fontSize;
  final String? fontFamily;
  final String? textColor; // Lo guardaremos como Hex (ej. '#FF0000')
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool hasTextBackground;
  final String? textBackgroundColor;

  CatalogContentEntity({
    required this.id,
    required this.type,
    this.textValue,
    this.productIds,
    this.fontSize,
    this.fontFamily,
    this.textColor,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.hasTextBackground = false,
    this.textBackgroundColor,
  });
}