class Client {
  final String id;
  // Obligatorios
  final String name;
  final String phone;
  
  // Opcionales Básicos
  final String idType; // CC, NIT, TI, CE, PAS
  final String idNumber;
  final String email;
  final String address;
  final String city;
  final String secondaryContact;

  // --- NUEVOS CAMPOS: FACTURACIÓN ELECTRÓNICA (DIAN) ---
  final bool isFeEnabled;      // ¿Este cliente requiere factura electrónica?
  final String personType;     // '1' (Jurídica) o '2' (Natural) - Códigos Plemsi
  final String taxRegime;      // '48' (Responsable IVA) o '49' (No Responsable) - Códigos Plemsi
  final String daneCode;       // Código DANE del municipio (ej. 73001 para Ibagué)

  Client({
    required this.id,
    required this.name,
    required this.phone,
    this.idType = 'CC',
    this.idNumber = '',
    this.email = '',
    this.address = '',
    this.city = '',
    this.secondaryContact = '',
    
    // Inicializados para no afectar a usuarios antiguos
    this.isFeEnabled = false,
    this.personType = '2', // Por defecto Natural
    this.taxRegime = '49', // Por defecto No Responsable
    this.daneCode = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'idType': idType,
      'idNumber': idNumber,
      'email': email,
      'address': address,
      'city': city,
      'secondaryContact': secondaryContact,
      
      'isFeEnabled': isFeEnabled,
      'personType': personType,
      'taxRegime': taxRegime,
      'daneCode': daneCode,
    };
  }

  factory Client.fromMap(Map<String, dynamic> map, String id) {
    return Client(
      id: id,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      idType: map['idType'] ?? 'CC',
      idNumber: map['idNumber'] ?? '',
      email: map['email'] ?? '',
      address: map['address'] ?? '',
      city: map['city'] ?? '',
      secondaryContact: map['secondaryContact'] ?? '',
      
      isFeEnabled: map['isFeEnabled'] ?? false,
      personType: map['personType'] ?? '2',
      taxRegime: map['taxRegime'] ?? '49',
      daneCode: map['daneCode'] ?? '',
    );
  }
}