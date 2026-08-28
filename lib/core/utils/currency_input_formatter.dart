import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // 1. Si está vacío, retornamos vacío
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // 2. LIMPIEZA PREVIA:
    // Quitamos las comas que ya existían para validar el número "crudo".
    String cleanText = newValue.text.replaceAll(',', '');
    
    // Si el usuario escribió una coma decimal (ej: 100,50), la cambiamos por punto
    // para que el sistema lo entienda como decimal.
    if (cleanText.contains(',') || newValue.text.endsWith(',')) {
      cleanText = cleanText.replaceAll(',', '.');
    }

    // 3. VALIDACIÓN:
    // Ahora validamos sobre 'cleanText' (que no tiene comas de miles).
    // Permite números, un punto opcional, y máximo 2 decimales.
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(cleanText)) {
      // Si no cumple (ej: letras, dos puntos, o 3 decimales), rechazamos el cambio
      return oldValue;
    }

    // 4. MANEJO DE CASOS ESPECIALES
    // Si el usuario escribe solo ".", lo convertimos a "0."
    if (cleanText == '.') {
      return newValue.copyWith(
        text: '0.',
        selection: const TextSelection.collapsed(offset: 2),
      );
    }
    
    // 5. SEPARAR ENTEROS Y DECIMALES
    List<String> parts = cleanText.split('.');
    String integerPart = parts[0];
    String? decimalPart = parts.length > 1 ? parts[1] : null;

    // 6. FORMATEAR MILES EN LA PARTE ENTERA
    if (integerPart.isNotEmpty) {
      double? value = double.tryParse(integerPart);
      if (value != null) {
        final formatter = NumberFormat("#,###", "en_US");
        integerPart = formatter.format(value);
      }
    } else {
      // Caso raro donde integerPart está vacío pero pasó la validación (ej: ".5")
      integerPart = "0";
    }

    // 7. RECONSTRUIR EL TEXTO FINAL
    String finalText = integerPart;
    
    // Si hay parte decimal o el usuario acaba de escribir el punto
    if (decimalPart != null) {
      finalText += '.$decimalPart';
    } else if (cleanText.endsWith('.')) {
      finalText += '.';
    }

    // 8. RETORNAR CON EL CURSOR AL FINAL
    return newValue.copyWith(
      text: finalText,
      selection: TextSelection.collapsed(offset: finalText.length),
    );
  }
}