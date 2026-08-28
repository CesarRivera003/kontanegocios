// lib/features/catalogs/domain/entities/catalog_entity.dart

import 'catalog_content_entity.dart';

enum ThemeType {
  preset, 
  custom  
}

// --- NUEVO: ENUM PARA EL TIPO DE FONDO ---
enum BackgroundType { 
  presetColor, 
  presetImage, 
  customImage,
  texture, 
}

// --- NUEVO: ENTIDAD PARA EL FONDO ---
class BackgroundStyleEntity {
  final BackgroundType type;
  final String value; // Guardará el Hex (#FFFFFF) o la URL (https://...)

  BackgroundStyleEntity({
    required this.type,
    required this.value,
  });
}

class CustomStyleEntity {
  final String primaryColor;
  final String secondaryColor;
  final String? bannerUrl;
  final String? logoUrl;
  
  // Agregamos el fondo a la configuración visual
  final BackgroundStyleEntity? background; 

  CustomStyleEntity({
    required this.primaryColor,
    required this.secondaryColor,
    this.bannerUrl,
    this.logoUrl,
    this.background,
  });
}

class CatalogConfigEntity {
  final ThemeType themeType;
  final String? presetTheme; 
  final CustomStyleEntity? customStyle;
  final bool showPrices;
  final String? whatsappContact;

  CatalogConfigEntity({
    required this.themeType,
    this.presetTheme,
    this.customStyle,
    required this.showPrices,
    this.whatsappContact,
  });
}

class CatalogEntity {
  final String id;
  final String businessId; 
  final String name;
  final bool isActive;
  final CatalogConfigEntity config;
  final List<CatalogContentEntity> content; 
  final DateTime createdAt;
  final DateTime updatedAt;

  CatalogEntity({
    required this.id,
    required this.businessId,
    required this.name,
    this.isActive = true, 
    required this.config,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  CatalogEntity copyWith({
    String? id,
    String? businessId,
    String? name,
    bool? isActive,
    CatalogConfigEntity? config,
    List<CatalogContentEntity>? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CatalogEntity(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      config: config ?? this.config,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}