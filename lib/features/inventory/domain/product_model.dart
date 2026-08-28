class Product {
  final String id;
  final String name;
  final String barcode;
  final String description; 
  final double price; 
  final double cost;
  final int stock;
  final String category;
  final String unit; 
  final bool hasCommission; 
  final double commissionPercentage; 
  final String? imageUrl;
  
  // --- CAMPOS DE IMPUESTOS (DIAN) ---
  final double taxRate; // El porcentaje numérico (Ej: 19.0, 8.0, 5.0, 0.0)
  final String taxType; // 'IVA', 'INC', 'EXENTO', 'EXCLUIDO'
  
  final int minStock;
  final bool isService;

  Product({
    required this.id,
    required this.name,
    required this.barcode,
    this.description = '',
    required this.price,
    required this.cost,
    required this.stock,
    required this.category,
    this.unit = 'Und',
    this.hasCommission = false,
    this.commissionPercentage = 0.0,
    this.imageUrl,
    this.taxRate = 0.0,
    this.taxType = 'EXCLUIDO', // Por defecto no genera impuesto desglosado
    this.minStock = 5,
    this.isService = false,
  });

  factory Product.fromMap(Map<String, dynamic> map, String docId) {
    return Product(
      id: docId,
      name: map['name'] ?? '',
      barcode: map['barcode'] ?? '',
      description: map['description'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      cost: (map['cost'] ?? 0).toDouble(),
      stock: (map['stock'] ?? 0).toInt(),
      category: map['category'] ?? 'General',
      unit: map['unit'] ?? 'Und',
      hasCommission: map['hasCommission'] ?? false,
      commissionPercentage: (map['commissionPercentage'] ?? 0).toDouble(),
      imageUrl: map['imageUrl'],
      taxRate: (map['taxRate'] ?? 0).toDouble(),
      taxType: map['taxType'] ?? 'EXCLUIDO',
      minStock: (map['minStock'] ?? 5).toInt(),
      isService: map['isService'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'barcode': barcode,
      'description': description,
      'price': price,
      'cost': cost,
      'stock': stock,
      'category': category,
      'unit': unit,
      'hasCommission': hasCommission,
      'commissionPercentage': commissionPercentage,
      'imageUrl': imageUrl,
      'taxRate': taxRate,
      'taxType': taxType,
      'minStock': minStock,
      'isService': isService,
    };
  }
}