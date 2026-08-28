import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TextDesignToolbar extends StatelessWidget {
  final double? fontSize;
  final String? fontFamily;
  final String? textColor;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  
  // --- NUEVAS PROPIEDADES RECIBIDAS ---
  final bool hasTextBackground;
  final String? textBackgroundColor;
  
  // Actualizamos la función para enviar los dos nuevos valores
  final Function(
    double? newSize,
    String? newFont,
    String? newColor,
    bool newBold,
    bool newItalic,
    bool newUnderline,
    bool newHasBg,
    String? newBgColor,
  ) onChanged;

  const TextDesignToolbar({
    Key? key,
    this.fontSize,
    this.fontFamily,
    this.textColor,
    required this.isBold,
    required this.isItalic,
    required this.isUnderline,
    this.hasTextBackground = false,
    this.textBackgroundColor,
    required this.onChanged,
  }) : super(key: key);

  static const List<String> availableFonts = [
    'Roboto', 
    'Montserrat',
    'Lato',
    'Oswald',
    'Playfair Display',
    'Bebas Neue',
    'Pacifico',
  ];

  static const List<String> quickColors = [
    '#FFFFFF', // NUEVO: Color Blanco agregado al inicio
    '#000000', 
    '#424242', 
    '#B71C1C', 
    '#0D47A1', 
    '#1B5E20', 
    '#E65100', 
  ];

  Color _hexToColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return Colors.black;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final currentSize = fontSize ?? 16.0;
    final currentFont = fontFamily ?? 'Roboto';
    
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- FILA 1: FUENTE Y TAMAÑO ---
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: availableFonts.contains(currentFont) ? currentFont : 'Roboto',
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 20),
                      style: const TextStyle(color: Colors.black87, fontSize: 13),
                      items: availableFonts.map((font) {
                        return DropdownMenuItem(
                          value: font,
                          child: Text(
                            font,
                            style: GoogleFonts.getFont(font == 'Roboto' ? 'Montserrat' : font).copyWith(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (newFont) => onChanged(currentSize, newFont, textColor, isBold, isItalic, isUnderline, hasTextBackground, textBackgroundColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                      onPressed: () => onChanged(currentSize > 10 ? currentSize - 2 : currentSize, currentFont, textColor, isBold, isItalic, isUnderline, hasTextBackground, textBackgroundColor),
                    ),
                    Text('${currentSize.toInt()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                      onPressed: () => onChanged(currentSize < 48 ? currentSize + 2 : currentSize, currentFont, textColor, isBold, isItalic, isUnderline, hasTextBackground, textBackgroundColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const Divider(height: 16),
          
          // --- FILA 2: ESTILOS, ACTIVADOR DE FONDO Y COLOR DE TEXTO ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _StyleToggleButton(
                  icon: Icons.format_bold,
                  isActive: isBold,
                  onTap: () => onChanged(currentSize, currentFont, textColor, !isBold, isItalic, isUnderline, hasTextBackground, textBackgroundColor),
                ),
                _StyleToggleButton(
                  icon: Icons.format_italic,
                  isActive: isItalic,
                  onTap: () => onChanged(currentSize, currentFont, textColor, isBold, !isItalic, isUnderline, hasTextBackground, textBackgroundColor),
                ),
                _StyleToggleButton(
                  icon: Icons.format_underline,
                  isActive: isUnderline,
                  onTap: () => onChanged(currentSize, currentFont, textColor, isBold, isItalic, !isUnderline, hasTextBackground, textBackgroundColor),
                ),
                
                const SizedBox(width: 6),
                
                // --- NUEVO: BOTÓN PARA ACTIVAR EL FONDO ---
                Tooltip(
                  message: 'Fondo del texto',
                  child: _StyleToggleButton(
                    icon: Icons.format_color_fill,
                    isActive: hasTextBackground,
                    onTap: () => onChanged(currentSize, currentFont, textColor, isBold, isItalic, isUnderline, !hasTextBackground, textBackgroundColor ?? '#FFFFFF'),
                  ),
                ),

                const SizedBox(width: 12),
                Container(width: 1, height: 24, color: Colors.grey[300]),
                const SizedBox(width: 12),

                // Paleta de colores para el TEXTO
                ...quickColors.map((hex) {
                  final isSelected = (textColor ?? '#000000') == hex;
                  return GestureDetector(
                    onTap: () => onChanged(currentSize, currentFont, hex, isBold, isItalic, isUnderline, hasTextBackground, textBackgroundColor),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _hexToColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade400, width: isSelected ? 2 : 1),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2, offset: const Offset(0, 1))
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          
          // --- FILA 3: COLOR DE FONDO (Solo visible si el fondo está activado) ---
          if (hasTextBackground) ...[
            const Divider(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Icon(Icons.palette_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text('Color de fondo:', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  
                  // Paleta de colores para el FONDO
                  ...quickColors.map((hex) {
                    final isSelected = (textBackgroundColor ?? '#FFFFFF') == hex;
                    return GestureDetector(
                      onTap: () => onChanged(currentSize, currentFont, textColor, isBold, isItalic, isUnderline, hasTextBackground, hex),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _hexToColor(hex),
                          borderRadius: BorderRadius.circular(4), // Cuadrado para diferenciarlo del texto
                          border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade400, width: isSelected ? 2 : 1),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StyleToggleButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _StyleToggleButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.transparent,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isActive ? Colors.blue[700] : Colors.grey[700],
        ),
      ),
    );
  }
}