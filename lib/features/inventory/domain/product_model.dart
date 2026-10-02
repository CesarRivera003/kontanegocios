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
  }) : assert(price >= 0, 'Price cannot be negative'),
       assert(cost >= 0, 'Cost cannot be negative'),
       assert(stock >= 0, 'Stock cannot be negative'),
       assert(commissionPercentage >= 0, 'Commission cannot be negative'),
       assert(taxRate >= 0, 'Tax rate cannot be negative'),
       assert(minStock >= 0, 'Min stock cannot be negative');

  static String _sanitizeString(String input) {
    return input.replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }

  factory Product.fromMap(Map<String, dynamic> map, String docId) {
    double parsedPrice = (map['price'] ?? 0).toDouble();
    double parsedCost = (map['cost'] ?? 0).toDouble();
    int parsedStock = (map['stock'] ?? 0).toInt();
    double parsedCommission = (map['commissionPercentage'] ?? 0).toDouble();
    double parsedTaxRate = (map['taxRate'] ?? 0).toDouble();
    int parsedMinStock = (map['minStock'] ?? 5).toInt();

    return Product(
      id: docId,
      name: map['name'] ?? '',
      barcode: map['barcode'] ?? '',
      description: map['description'] ?? '',
      price: parsedPrice < 0 ? 0.0 : parsedPrice,
      cost: parsedCost < 0 ? 0.0 : parsedCost,
      stock: parsedStock < 0 ? 0 : parsedStock,
      category: map['category'] ?? 'General',
      unit: map['unit'] ?? 'Und',
      hasCommission: map['hasCommission'] ?? false,
      commissionPercentage: parsedCommission < 0 ? 0.0 : parsedCommission,
      imageUrl: map['imageUrl'],
      taxRate: parsedTaxRate < 0 ? 0.0 : parsedTaxRate,
      taxType: map['taxType'] ?? 'EXCLUIDO',
      minStock: parsedMinStock < 0 ? 0 : parsedMinStock,
      isService: map['isService'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': _sanitizeString(name),
      'barcode': barcode,
      'description': _sanitizeString(description),
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
