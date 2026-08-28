import 'package:cloud_firestore/cloud_firestore.dart';

class BankAccount {
  final String id;
  final String name; 
  final String accountNumber;
  final double balance;
  final bool isCash; 
  final bool isDefault;
  final bool isActive;

  BankAccount({
    required this.id,
    required this.name,
    this.accountNumber = '',
    required this.balance,
    this.isCash = false,
    this.isDefault = false,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'accountNumber': accountNumber,
      'balance': balance,
      'isCash': isCash,
      'isDefault': isDefault,
      'isActive': isActive,
    };
  }

  factory BankAccount.fromMap(Map<String, dynamic> map, String id) {
    return BankAccount(
      id: id,
      name: map['name'] ?? '',
      accountNumber: map['accountNumber'] ?? '',
      balance: (map['balance'] ?? 0).toDouble(),
      isCash: map['isCash'] ?? false,
      isDefault: map['isDefault'] ?? false,
      isActive: map['isActive'] ?? true,
    );
  }
}

class BankTransaction {
  final String id;
  final String accountId;
  final String type; 
  final double amount;
  final String description; 
  final DateTime date;
  final String? transferRelatedAccountId; 
  final String? relatedDocId; 

  BankTransaction({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.description,
    required this.date,
    this.transferRelatedAccountId,
    this.relatedDocId,
  });

  Map<String, dynamic> toMap() {
    return {
      'accountId': accountId,
      'type': type,
      'amount': amount,
      'description': description,
      'date': Timestamp.fromDate(date),
      'transferRelatedAccountId': transferRelatedAccountId,
      'relatedDocId': relatedDocId,
    };
  }

  factory BankTransaction.fromMap(Map<String, dynamic> map, String id) {
    return BankTransaction(
      id: id,
      accountId: map['accountId'] ?? '',
      type: map['type'] ?? 'INCOME',
      amount: (map['amount'] ?? 0).toDouble(),
      description: map['description'] ?? '',
      date: (map['date'] as Timestamp).toDate(),
      transferRelatedAccountId: map['transferRelatedAccountId'],
      relatedDocId: map['relatedDocId'],
    );
  }
}