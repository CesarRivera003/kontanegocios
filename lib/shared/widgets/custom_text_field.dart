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
  
  // --- NUEVAS PROPIEDADES ---
  final bool readOnly; 
  final bool enabled;

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
    // Inicializamos con valores por defecto
    this.readOnly = false,
    this.enabled = true,
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
          
          // CONECTAMOS LAS PROPIEDADES
          readOnly: readOnly,
          enabled: enabled,

          inputFormatters: isNumber 
              ? [FilteringTextInputFormatter.digitsOnly] 
              : null,
          maxLines: maxLines,
          decoration: InputDecoration(
            prefixIcon: icon != null ? Icon(icon, color: Colors.grey[600]) : null,
            suffixIcon: suffixIcon,
            
            // FEEDBACK VISUAL:
            // Si es de solo lectura, ponemos un fondo gris suave
            filled: readOnly || !enabled,
            fillColor: (readOnly || !enabled) ? Colors.grey[100] : null,

            hintText: 'Ingresa tu $label',
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          validator: (value) {
            // Si es de solo lectura, generalmente no validamos que esté vacío
            if (!readOnly && (value == null || value.isEmpty)) {
              return 'Este campo es obligatorio';
            }
            return null;
          },
        ),
      ],
    );
  }
}