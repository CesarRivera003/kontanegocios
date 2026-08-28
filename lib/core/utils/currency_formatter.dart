import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final _formatter = NumberFormat.currency(
    locale: 'en_US', // Usa comas para miles y punto para decimales
    symbol: '', // Sin símbolo para que solo sea el número
    decimalDigits: 2, // Máximo 2 decimales
  );

  static String format(double value) {
    return _formatter.format(value);
  }

  // Para limpiar el texto y convertirlo a double (quita comas)
  static double parse(String value) {
    return double.tryParse(value.replaceAll(',', '')) ?? 0.0;
  }
}