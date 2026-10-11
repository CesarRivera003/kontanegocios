import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isPassword;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final int? maxLines;
  final bool isNumber;
  final Widget? suffixIcon;
  final bool readOnly; 
  final bool enabled;

  // --- NUEVAS PROPIEDADES PARA CONTROLAR OBLIGATORIEDAD ---
  final bool isRequired;
  final String? Function(String?)? validator;

  const CustomTextField({
    super.key,
    required this.label,
    required this.controller,
    this.icon,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.isNumber = false,
    this.suffixIcon,
    this.readOnly = false,
    this.enabled = true,
    this.isRequired = true, // Por defecto es obligatorio
    this.validator,        // Validador personalizado opcional
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: isNumber ? TextInputType.number : keyboardType,
          readOnly: readOnly,
          enabled: enabled,
          inputFormatters: isNumber 
              ? [FilteringTextInputFormatter.digitsOnly] 
              : null,
          maxLines: maxLines,
          decoration: InputDecoration(
            prefixIcon: icon != null ? Icon(icon, color: Colors.grey[600]) : null,
            suffixIcon: suffixIcon,
            filled: readOnly || !enabled,
            fillColor: (readOnly || !enabled) ? Colors.grey[100] : null,
            hintText: 'Ingresa tu $label',
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          validator: (value) {
            // 1. Si se pasó un validador personalizado, se usa ese
            if (validator != null) {
              return validator!(value);
            }
            // 2. Si no es obligatorio o es de solo lectura, pasa libre
            if (!isRequired || readOnly || !enabled) {
              return null;
            }
            // 3. Validación por defecto si es obligatorio
            if (value == null || value.trim().isEmpty) {
              return 'Este campo es obligatorio';
            }
            return null;
          },
        ),
      ],
    );
  }
}