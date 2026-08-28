class CompanyProfile {
  final String id;
  final String name;
  final String nit;
  final String address;
  final String phone;
  final String email;
  final String slogan;
  final String? imageBase64;

  // --- NUEVOS CAMPOS: SUSCRIPCIÓN Y REFERIDOS ---
  final String referralCode;       // Su propio código para invitar (ej: KNT-A8X9)
  final String? referredBy;        // El código de quien lo invitó (para evitar auto-invitaciones)
  final int referralCount;         // Cuentas gratis creadas con su código
  final int paidReferralCount;     // Cuentas que han pagado con su código
  final DateTime? trialEndsAt;     // Fecha en que expira su prueba o mes regalado
  final String subscriptionStatus; // 'trial', 'freemium', 'pro', 'empresarial', 'expired', 'lifetime'
  final double currentMonthSales;  // Acumulado de ventas del mes
  final String currentMonth;       // Mes actual (Ej: "2026-03")

  CompanyProfile({
    this.id = '',
    this.name = '',
    this.nit = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.slogan = '',
    this.imageBase64,
    
    // Inicializamos los nuevos campos
    this.referralCode = '',
    this.referredBy,
    this.referralCount = 0,
    this.paidReferralCount = 0,
    this.trialEndsAt,
    this.subscriptionStatus = 'trial', // Por defecto todos inician en prueba
    this.currentMonthSales = 0.0,
    this.currentMonth = '',
  });

  // Convertir de Firestore (Map) a Objeto Dart
  factory CompanyProfile.fromMap(Map<String, dynamic>? map, String docId) {
    if (map == null) return CompanyProfile(id: docId);
    
    // Manejo seguro de la fecha de Firestore a Dart
    DateTime? trialDate;
    if (map['trialEndsAt'] != null) {
      // Dependiendo de si es un Timestamp de Firebase o un String
      trialDate = map['trialEndsAt'].toDate(); 
    }

    return CompanyProfile(
      id: docId,
      name: map['name'] ?? '',
      nit: map['nit'] ?? '',
      address: map['address'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      slogan: map['slogan'] ?? '',
      imageBase64: map['imageBase64'],
      
      referralCode: map['referralCode'] ?? '',
      referredBy: map['referredBy'],
      referralCount: map['referralCount'] ?? 0,
      paidReferralCount: map['paidReferralCount'] ?? 0,
      trialEndsAt: trialDate,
      subscriptionStatus: map['subscriptionStatus'] ?? 'trial',
      currentMonthSales: (map['currentMonthSales'] as num?)?.toDouble() ?? 0.0,
      currentMonth: map['currentMonth'] ?? '',
    );
  }

  // Convertir de Objeto Dart a Firestore (Map)
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'nit': nit,
      'address': address,
      'phone': phone,
      'email': email,
      'slogan': slogan,
      'imageBase64': imageBase64,
      
      'referralCode': referralCode,
      'referredBy': referredBy,
      'referralCount': referralCount,
      'paidReferralCount': paidReferralCount,
      'trialEndsAt': trialEndsAt,
      'subscriptionStatus': subscriptionStatus,
      'currentMonthSales': currentMonthSales,
      'currentMonth': currentMonth,
    };
  }
  
  // Helper para copiar el objeto con nuevos valores
  CompanyProfile copyWith({
    String? name,
    String? nit,
    String? address,
    String? phone,
    String? email,
    String? slogan,
    String? imageBase64,
    
    String? referralCode,
    String? referredBy,
    int? referralCount,
    int? paidReferralCount,
    DateTime? trialEndsAt,
    String? subscriptionStatus,
  }) {
    return CompanyProfile(
      id: this.id,
      name: name ?? this.name,
      nit: nit ?? this.nit,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      slogan: slogan ?? this.slogan,
      imageBase64: imageBase64 ?? this.imageBase64,
      
      referralCode: referralCode ?? this.referralCode,
      referredBy: referredBy ?? this.referredBy,
      referralCount: referralCount ?? this.referralCount,
      paidReferralCount: paidReferralCount ?? this.paidReferralCount,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
    );
  }
}