class ProviderModel { 
  final String id;
  final String name;
  final String nit; // Identificación
  final String phone;
  final String email; 
  final String address; // <-- NUEVO: Dirección
  
  // Datos Bancarios
  final String bank;
  final String accountType; // Ahorros / Corriente
  final String accountNumber;
  
  // Extra
  final String category; // Ej: Insumos, Servicios

  ProviderModel({
    required this.id,
    required this.name,
    this.nit = '', // <-- Ahora con valor por defecto vacío
    required this.phone,
    this.email = '',
    this.address = '', // <-- NUEVO
    this.bank = '',
    this.accountType = 'Ahorros',
    this.accountNumber = '',
    this.category = 'General',
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'nit': nit,
      'phone': phone,
      'email': email,
      'address': address, // <-- NUEVO
      'bank': bank,
      'accountType': accountType,
      'accountNumber': accountNumber,
      'category': category,
    };
  }

  factory ProviderModel.fromMap(Map<String, dynamic> map, String id) {
    return ProviderModel(
      id: id,
      name: map['name'] ?? '',
      nit: map['nit'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      address: map['address'] ?? '', // <-- NUEVO
      bank: map['bank'] ?? '',
      accountType: map['accountType'] ?? 'Ahorros',
      accountNumber: map['accountNumber'] ?? '',
      category: map['category'] ?? 'General',
    );
  }
}