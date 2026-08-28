import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart'; 

import '../../domain/entities/catalog_entity.dart';
import '../providers/catalog_provider.dart';

class CatalogCreateScreen extends ConsumerStatefulWidget {
  final String businessId;
  final CatalogEntity? catalogToEdit; 

  const CatalogCreateScreen({
    Key? key, 
    required this.businessId,
    this.catalogToEdit,
  }) : super(key: key);

  @override
  ConsumerState<CatalogCreateScreen> createState() => _CatalogCreateScreenState();
}

class _CatalogCreateScreenState extends ConsumerState<CatalogCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _whatsappController = TextEditingController();
  
  // --- NUEVAS VARIABLES DE ESTADO PARA EL DISEÑO ---
  bool _showPrices = true;
  BackgroundType _selectedBgType = BackgroundType.presetColor;
  String _selectedBgValue = '#FBFBF9'; // Crema por defecto

  // Listas de opciones preparadas
  final List<String> _solidColors = ['#FBFBF9', '#FFFFFF', '#F0F4F8', '#FFF0F5', '#E6F4EA', '#2C3E50'];
  final List<String> _textures = [
    'assets/textures/animales.png',
    'assets/textures/arquitectura.png',
    'assets/textures/aseo.png',
    'assets/textures/cafe.png',
    'assets/textures/camara.png',
    'assets/textures/colores.png',
    'assets/textures/comidarapida.png',
    'assets/textures/cuadricula.png',
    'assets/textures/estrellas.png',
    'assets/textures/floresyhojas.png',
    'assets/textures/halloween.png',
    'assets/textures/hojas.png',
    'assets/textures/lazos.png',
    'assets/textures/lineas.png',
    'assets/textures/madres.png',
    'assets/textures/manchascolores.png',
    'assets/textures/mapas.png',
    'assets/textures/navidad.png',
    'assets/textures/ninos.png',
    'assets/textures/olas.png',
    'assets/textures/otono.png',
    'assets/textures/piedra.png',
    'assets/textures/pinos.png',
    'assets/textures/puntos.png',
    'assets/textures/ropa.png',
    'assets/textures/vintage.png',
    'assets/textures/violin.png',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.catalogToEdit != null) {
      final catalog = widget.catalogToEdit!;
      _nameController.text = catalog.name;
      _whatsappController.text = catalog.config.whatsappContact ?? '';
      _showPrices = catalog.config.showPrices;
      
      // Cargamos el fondo si ya existe
      if (catalog.config.customStyle?.background != null) {
        _selectedBgType = catalog.config.customStyle!.background!.type;
        _selectedBgValue = catalog.config.customStyle!.background!.value;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  void _saveCatalog() async {
    if (_formKey.currentState!.validate()) {
      
      final existingStyle = widget.catalogToEdit?.config.customStyle;
      
      final backgroundStyle = BackgroundStyleEntity(
        type: _selectedBgType,
        value: _selectedBgValue,
      );

      final customStyle = CustomStyleEntity(
        primaryColor: existingStyle?.primaryColor ?? '#000000',
        secondaryColor: existingStyle?.secondaryColor ?? '#FFFFFF',
        bannerUrl: existingStyle?.bannerUrl,
        logoUrl: existingStyle?.logoUrl,
        background: backgroundStyle, 
      );

      final config = CatalogConfigEntity(
        themeType: ThemeType.custom,
        presetTheme: widget.catalogToEdit?.config.presetTheme,
        customStyle: customStyle,
        showPrices: _showPrices, 
        whatsappContact: _whatsappController.text.trim(),
      );

      bool success;
      
      // NUEVO: Declaramos una variable que vivirá en todo este bloque
      CatalogEntity catalogResult; 

      if (widget.catalogToEdit == null) {
        // MODO CREACIÓN
        catalogResult = CatalogEntity(
          id: const Uuid().v4(), 
          businessId: widget.businessId,
          name: _nameController.text.trim(),
          config: config,
          content: [], 
          isActive: true, 
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        success = await ref.read(catalogNotifierProvider.notifier).createCatalog(catalogResult);
      } else {
        // MODO EDICIÓN
        catalogResult = CatalogEntity(
          id: widget.catalogToEdit!.id,
          businessId: widget.catalogToEdit!.businessId,
          name: _nameController.text.trim(),
          config: config,
          content: widget.catalogToEdit!.content, 
          isActive: widget.catalogToEdit!.isActive,
          createdAt: widget.catalogToEdit!.createdAt,
          updatedAt: DateTime.now(),
        );
        
        success = await ref.read(catalogNotifierProvider.notifier).updateCatalog(catalogResult);
      }

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.catalogToEdit == null ? 'Catálogo creado exitosamente' : 'Catálogo actualizado exitosamente'), 
              backgroundColor: Colors.green
            ),
          );
          // AHORA SÍ: Devolvemos el resultado guardado
          Navigator.pop(context, catalogResult); 
        } else {
          final error = ref.read(catalogNotifierProvider).errorMessage ?? 'Error desconocido';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(catalogNotifierProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.catalogToEdit == null ? 'Nuevo Catálogo' : 'Ajustes Generales'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Información Básica', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Nombre del catálogo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.storefront)),
                      validator: (value) => value == null || value.isEmpty ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _whatsappController,
                      decoration: const InputDecoration(labelText: 'WhatsApp para pedidos', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone_android)),
                      keyboardType: TextInputType.phone,
                      validator: (value) => value == null || value.isEmpty ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 24),
                    
                    // --- NUEVA SECCIÓN DE CONFIGURACIÓN ---
                    SwitchListTile(
                      title: const Text('Mostrar precios a los clientes', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Si lo desactivas, los clientes tendrán que preguntarte el valor.'),
                      value: _showPrices,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (bool value) => setState(() => _showPrices = value),
                    ),
                    
                    const Divider(height: 40),
                    const Text('Diseño de Fondo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    
                    // Selector de Tipo de Fondo
                    SegmentedButton<BackgroundType>(
                      segments: const [
                        ButtonSegment(value: BackgroundType.presetColor, label: Text('Color Sólido'), icon: Icon(Icons.format_color_fill)),
                        ButtonSegment(value: BackgroundType.texture, label: Text('Textura'), icon: Icon(Icons.texture)),
                      ],
                      selected: {_selectedBgType},
                      onSelectionChanged: (Set<BackgroundType> newSelection) {
                        setState(() {
                          _selectedBgType = newSelection.first;
                          // Reseteamos al primer valor de la lista correspondiente
                          _selectedBgValue = _selectedBgType == BackgroundType.presetColor ? _solidColors.first : _textures.first;
                        });
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Renderizamos los colores o las texturas dependiendo de la selección
                    if (_selectedBgType == BackgroundType.presetColor)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _solidColors.map((colorHex) {
                          final isSelected = _selectedBgValue == colorHex;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedBgValue = colorHex),
                            child: Container(
                              width: 50, height: 50,
                              decoration: BoxDecoration(
                                color: _hexToColor(colorHex),
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300, width: isSelected ? 3 : 1),
                                boxShadow: [if (isSelected) BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 8)]
                              ),
                            ),
                          );
                        }).toList(),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _textures.map((texturePath) {
                          final isSelected = _selectedBgValue == texturePath;
                          final textureName = texturePath.split('/').last.replaceAll('.png', '').toUpperCase();
                          return Tooltip(
                            message: textureName, // Aquí se muestra el texto al pasar el ratón
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedBgValue = texturePath),
                              child: Container(
                                width: 60, height: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300, width: isSelected ? 3 : 1),
                                  // Aquí intentamos previsualizar la textura. Si no existen aún, se verá en blanco por ahora.
                                  image: DecorationImage(
                                    image: AssetImage(texturePath),
                                    repeat: ImageRepeat.repeat,
                                    // Agregamos onError para que no rompa la app mientras no tengas los assets creados
                                    onError: (exception, stackTrace) {}, 
                                  ),
                                ),
                                child: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                              ),
                            )
                          );
                        }).toList(),
                      ),
                      
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saveCatalog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(widget.catalogToEdit == null ? 'Continuar al Editor' : 'Guardar Cambios', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}