class ProviderModel { // Usamos ProviderModel para no confundir con la clase Provider de Riverpod
  final String id;
  final String name;
  final String nit; // Identificación
  final String phone;
  final String email; // (Opcional pero útil)
  
  // Datos Bancarios
  final String bank;
  final String accountType; // Ahorros / Corriente
  final String accountNumber;
  
  // Extra
  final String category; // Ej: Insumos, Servicios

  ProviderModel({
    required this.id,
    required this.name,
    required this.nit,
    required this.phone,
    this.email = '',
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
      bank: map['bank'] ?? '',
      accountType: map['accountType'] ?? 'Ahorros',
      accountNumber: map['accountNumber'] ?? '',
      category: map['category'] ?? 'General',
    );
  }
}