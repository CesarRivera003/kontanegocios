// lib/features/catalogs/data/models/catalog_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/catalog_entity.dart';
import '../../domain/entities/catalog_content_entity.dart';

class CatalogModel extends CatalogEntity {
  CatalogModel({
    required super.id,
    required super.businessId,
    required super.name,
    super.isActive = true,
    required super.config,
    required super.content,
    required super.createdAt,
    required super.updatedAt,
  });

  factory CatalogModel.fromEntity(CatalogEntity entity, {String? forceBusinessId}) {
    return CatalogModel(
      id: entity.id,
      businessId: forceBusinessId ?? entity.businessId,
      name: entity.name,
      isActive: entity.isActive,
      config: CatalogConfigModel.fromEntity(entity.config),
      content: entity.content.map((c) => CatalogContentModel.fromEntity(c)).toList(),
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  factory CatalogModel.fromJson(Map<String, dynamic> json, String id) {
    return CatalogModel(
      id: id,
      businessId: json['businessId'] ?? '',
      name: json['name'] ?? '',
      isActive: json['isActive'] ?? true,
      config: CatalogConfigModel.fromJson(json['config'] ?? {}),
      content: (json['content'] as List<dynamic>? ?? [])
          .map((item) => CatalogContentModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'businessId': businessId,
      'name': name,
      'isActive': isActive,
      'config': (config as CatalogConfigModel).toJson(),
      'content': content.map((item) => (item as CatalogContentModel).toJson()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class CatalogConfigModel extends CatalogConfigEntity {
  CatalogConfigModel({
    required super.themeType,
    super.presetTheme,
    super.customStyle,
    required super.showPrices,
    super.whatsappContact,
  });

  factory CatalogConfigModel.fromEntity(CatalogConfigEntity entity) {
    return CatalogConfigModel(
      themeType: entity.themeType,
      presetTheme: entity.presetTheme,
      customStyle: entity.customStyle != null 
          ? CustomStyleModel.fromEntity(entity.customStyle!) 
          : null,
      showPrices: entity.showPrices,
      whatsappContact: entity.whatsappContact,
    );
  }

  factory CatalogConfigModel.fromJson(Map<String, dynamic> json) {
    return CatalogConfigModel(
      themeType: ThemeType.values.firstWhere(
        (e) => e.toString() == 'ThemeType.${json['themeType']}',
        orElse: () => ThemeType.preset,
      ),
      presetTheme: json['presetTheme'],
      customStyle: json['customStyle'] != null
          ? CustomStyleModel.fromJson(json['customStyle'])
          : null,
      showPrices: json['showPrices'] ?? true,
      whatsappContact: json['whatsappContact'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeType': themeType.toString().split('.').last,
      'presetTheme': presetTheme,
      'customStyle': customStyle != null ? (customStyle as CustomStyleModel).toJson() : null,
      'showPrices': showPrices,
      'whatsappContact': whatsappContact,
    };
  }
}

// --- NUEVO: Modelo para el Fondo ---
class BackgroundStyleModel extends BackgroundStyleEntity {
  BackgroundStyleModel({
    required super.type,
    required super.value,
  });

  factory BackgroundStyleModel.fromEntity(BackgroundStyleEntity entity) {
    return BackgroundStyleModel(
      type: entity.type,
      value: entity.value,
    );
  }

  factory BackgroundStyleModel.fromJson(Map<String, dynamic> json) {
    return BackgroundStyleModel(
      type: BackgroundType.values.firstWhere(
        (e) => e.toString() == 'BackgroundType.${json['type']}',
        orElse: () => BackgroundType.presetColor,
      ),
      value: json['value'] ?? '#FBFBF9',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString().split('.').last,
      'value': value,
    };
  }
}

class CustomStyleModel extends CustomStyleEntity {
  CustomStyleModel({
    required super.primaryColor,
    required super.secondaryColor,
    super.bannerUrl,
    super.logoUrl,
    super.background,
  });

  factory CustomStyleModel.fromEntity(CustomStyleEntity entity) {
    return CustomStyleModel(
      primaryColor: entity.primaryColor,
      secondaryColor: entity.secondaryColor,
      bannerUrl: entity.bannerUrl,
      logoUrl: entity.logoUrl,
      background: entity.background != null 
          ? BackgroundStyleModel.fromEntity(entity.background!) 
          : null,
    );
  }

  factory CustomStyleModel.fromJson(Map<String, dynamic> json) {
    return CustomStyleModel(
      primaryColor: json['primaryColor'] ?? '#000000',
      secondaryColor: json['secondaryColor'] ?? '#FFFFFF',
      bannerUrl: json['bannerUrl'],
      logoUrl: json['logoUrl'],
      background: json['background'] != null 
          ? BackgroundStyleModel.fromJson(json['background']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'primaryColor': primaryColor,
      'secondaryColor': secondaryColor,
      'bannerUrl': bannerUrl,
      'logoUrl': logoUrl,
      'background': background != null ? (background as BackgroundStyleModel).toJson() : null,
    };
  }
}

class CatalogContentModel extends CatalogContentEntity {
  CatalogContentModel({
    required super.id,
    required super.type,
    super.textValue,
    super.productIds,
    super.fontSize,
    super.fontFamily,
    super.textColor,
    super.isBold = false,
    super.isItalic = false,
    super.isUnderline = false,
  });

  factory CatalogContentModel.fromEntity(CatalogContentEntity entity) {
    return CatalogContentModel(
      id: entity.id,
      type: entity.type,
      textValue: entity.textValue,
      productIds: entity.productIds,
      fontSize: entity.fontSize,
      fontFamily: entity.fontFamily,
      textColor: entity.textColor,
      isBold: entity.isBold,
      isItalic: entity.isItalic,
      isUnderline: entity.isUnderline,
    );
  }

  factory CatalogContentModel.fromJson(Map<String, dynamic> json) {
    return CatalogContentModel(
      id: json['id'] ?? '',
      type: CatalogContentType.values.firstWhere(
        (e) => e.toString() == 'CatalogContentType.${json['type']}',
        orElse: () => CatalogContentType.text,
      ),
      textValue: json['textValue'],
      productIds: (json['productIds'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      fontFamily: json['fontFamily'],
      textColor: json['textColor'],
      isBold: json['isBold'] ?? false,
      isItalic: json['isItalic'] ?? false,
      isUnderline: json['isUnderline'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString().split('.').last,
      'textValue': textValue,
      'productIds': productIds,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'textColor': textColor,
      'isBold': isBold,
      'isItalic': isItalic,
      'isUnderline': isUnderline,
    };
  }
}