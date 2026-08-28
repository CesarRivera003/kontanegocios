import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/catalog_entity.dart';
import '../../domain/entities/catalog_content_entity.dart';
import '../providers/catalog_provider.dart';
import '../../../inventory/presentation/inventory_providers.dart';
import 'catalog_viewer_screen.dart';
import 'catalog_create_screen.dart';
import 'text_style_toolbar.dart';
import 'package:google_fonts/google_fonts.dart';

class CatalogEditorScreen extends ConsumerStatefulWidget {
  final CatalogEntity catalog;

  const CatalogEditorScreen({Key? key, required this.catalog}) : super(key: key);

  @override
  ConsumerState<CatalogEditorScreen> createState() => _CatalogEditorScreenState();
}

class _CatalogEditorScreenState extends ConsumerState<CatalogEditorScreen> {
  late CatalogEntity _currentCatalog;
  // NUEVO: Una lista local que Dart nos permite modificar libremente
  late List<CatalogContentEntity> _editableContent; 

  @override
  void initState() {
    super.initState();
    _currentCatalog = widget.catalog;
    // Creamos una copia fresca y 100% editable de los bloques
    _editableContent = List<CatalogContentEntity>.from(widget.catalog.content);
  }

  void _showAddBlockModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Agregar nuevo bloque', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.title),
                title: const Text('Título'),
                onTap: () {
                  Navigator.pop(context);
                  _addContentBlock(CatalogContentType.title);
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('Texto descriptivo'),
                onTap: () {
                  Navigator.pop(context);
                  _addContentBlock(CatalogContentType.text);
                },
              ),
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text('Cuadrícula de Productos'),
                onTap: () {
                  Navigator.pop(context);
                  _addContentBlock(CatalogContentType.productGrid);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _addContentBlock(CatalogContentType type) {
    final newBlock = CatalogContentEntity(
      id: const Uuid().v4(),
      type: type,
      // CORRECCIÓN: Lo dejamos vacío para que se vea el hintText de fondo
      textValue: (type == CatalogContentType.title || type == CatalogContentType.text) ? '' : null,
      productIds: type == CatalogContentType.productGrid ? [] : null,
    );

    setState(() {
      // Ahora agregamos a nuestra lista editable de forma segura
      _editableContent.add(newBlock);
    });
  }

  Future<void> _saveChanges() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Guardando cambios...'), duration: Duration(seconds: 1)),
    );

    // RECONSTRUIMOS la entidad completa con la lista editable
    final catalogToSave = CatalogEntity(
      id: _currentCatalog.id,
      businessId: _currentCatalog.businessId,
      name: _currentCatalog.name,
      isActive: _currentCatalog.isActive,
      config: _currentCatalog.config,
      content: _editableContent, // Inyectamos nuestra lista modificada
      createdAt: _currentCatalog.createdAt,
      updatedAt: DateTime.now(), // Actualizamos la fecha de modificación
    );

    final success = await ref.read(catalogNotifierProvider.notifier).updateCatalog(catalogToSave);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Catálogo actualizado exitosamente ✅'),
            backgroundColor: Colors.green,
          ),
        );
        // Actualizamos nuestra referencia local por si el usuario sigue editando
        setState(() {
          _currentCatalog = catalogToSave;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: ${ref.read(catalogNotifierProvider).errorMessage}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _hexToColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return Colors.black;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editando: ${_currentCatalog.name}'),
        actions: [
          // --- NUEVO BOTÓN DE CONFIGURACIÓN ---
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes del Catálogo',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CatalogCreateScreen(
                    businessId: _currentCatalog.businessId,
                    catalogToEdit: _currentCatalog, 
                  ),
                ),
              );
              if (result != null && result is CatalogEntity) {
                setState(() {
                  _currentCatalog = result; 
                });
              }
            },
          ),
          // --- BOTÓN DE VISTA PREVIA
          IconButton(
            icon: const Icon(Icons.remove_red_eye_outlined),
            onPressed: () {
              final previewCatalog = CatalogEntity(
                id: _currentCatalog.id,
                businessId: _currentCatalog.businessId,
                name: _currentCatalog.name,
                isActive: _currentCatalog.isActive,
                config: _currentCatalog.config,
                content: _editableContent,
                createdAt: _currentCatalog.createdAt,
                updatedAt: _currentCatalog.updatedAt,
              );

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CatalogViewerScreen(catalog: previewCatalog),
                ),
              );
            },
            tooltip: 'Vista Previa',
          ),
          // --- BOTÓN DE GUARDAR
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveChanges,
            tooltip: 'Guardar cambios',
          ),
        ],
      ),
      body: _editableContent.isEmpty // Usamos la lista editable
          ? const Center(
              child: Text(
                'Tu catálogo está vacío.\nToca el botón + para agregar contenido.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _editableContent.length,
              itemBuilder: (context, index) {
                final block = _editableContent[index];
                return _buildBlockWidget(block, index);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddBlockModal,
        icon: const Icon(Icons.add),
        label: const Text('Agregar Sección'),
      ),
    );
  }

  Widget _buildBlockWidget(CatalogContentEntity block, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  block.type.name.toUpperCase(),
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () {
                    setState(() {
                      _editableContent.removeAt(index);
                    });
                  },
                )
              ],
            ),
            const SizedBox(height: 8),
            
            // --- CAMPOS DE TEXTO ---
            if (block.type == CatalogContentType.title || block.type == CatalogContentType.text)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: block.textValue,
                    // AQUÍ ESTÁ LA MAGIA EN TIEMPO REAL:
                    style: GoogleFonts.getFont(
                      block.fontFamily ?? 'Roboto',
                      fontSize: block.fontSize ?? 16.0,
                      color: _hexToColor(block.textColor),
                      fontWeight: block.isBold ? FontWeight.bold : FontWeight.normal,
                      fontStyle: block.isItalic ? FontStyle.italic : FontStyle.normal,
                      decoration: block.isUnderline ? TextDecoration.underline : TextDecoration.none,
                    ),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: block.type == CatalogContentType.title 
                          ? 'Ej: Título de la sección' 
                          : 'Escribe aquí tu descripción...',
                    ),
                    maxLines: block.type == CatalogContentType.text ? 3 : 1,
                    onChanged: (val) {
                      setState(() {
                        _editableContent[index] = CatalogContentEntity(
                          id: block.id,
                          type: block.type,
                          textValue: val, 
                          productIds: block.productIds,
                          // Mantenemos los estilos existentes al cambiar el texto
                          fontSize: block.fontSize,
                          fontFamily: block.fontFamily,
                          textColor: block.textColor,
                          isBold: block.isBold,
                          isItalic: block.isItalic,
                          isUnderline: block.isUnderline,
                          hasTextBackground: block.hasTextBackground,
                          textBackgroundColor: block.textBackgroundColor,
                        );
                      });
                    },
                  ),
                  
                  // --- NUEVA BARRA DE HERRAMIENTAS DE DISEÑO ---
                  TextDesignToolbar(
                    fontSize: block.fontSize,
                    fontFamily: block.fontFamily,
                    textColor: block.textColor,
                    isBold: block.isBold,
                    isItalic: block.isItalic,
                    isUnderline: block.isUnderline,
                    
                    // PASAMOS LAS NUEVAS VARIABLES
                    hasTextBackground: block.hasTextBackground, 
                    textBackgroundColor: block.textBackgroundColor, 
                    
                    // RECIBIMOS LAS NUEVAS VARIABLES (newHasBg, newBgColor)
                    onChanged: (newSize, newFont, newColor, newBold, newItalic, newUnderline, newHasBg, newBgColor) {
                      setState(() {
                        // Actualizamos la entidad con los nuevos estilos seleccionados
                        _editableContent[index] = CatalogContentEntity(
                          id: block.id,
                          type: block.type,
                          textValue: block.textValue, 
                          productIds: block.productIds,
                          fontSize: newSize,
                          fontFamily: newFont,
                          textColor: newColor,
                          isBold: newBold,
                          isItalic: newItalic,
                          isUnderline: newUnderline,
                          
                          // GUARDAMOS LAS NUEVAS VARIABLES
                          hasTextBackground: newHasBg, 
                          textBackgroundColor: newBgColor, 
                        );
                      });
                    },
                  ),
                ],
              )
              
            // --- CUADRÍCULA DE PRODUCTOS ---
            else if (block.type == CatalogContentType.productGrid)
              InkWell(
                onTap: () async {
                  final selectedIds = await showModalBottomSheet<List<String>>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) {
                      return FractionallySizedBox(
                        heightFactor: 0.85,
                        child: ProductSelectionModal(
                          initialSelectedIds: block.productIds ?? [],
                        ),
                      );
                    },
                  );

                  if (selectedIds != null) {
                    setState(() {
                      _editableContent[index] = CatalogContentEntity(
                        id: block.id,
                        type: block.type,
                        textValue: block.textValue, 
                        productIds: selectedIds, 
                      );
                    });
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.inventory_2, size: 40, color: Colors.blue),
                      const SizedBox(height: 8),
                      Text(
                        (block.productIds == null || block.productIds!.isEmpty)
                            ? 'Toca aquí para seleccionar productos'
                            : '${block.productIds!.length} productos seleccionados',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (block.productIds != null && block.productIds!.isNotEmpty)
                        const Text(
                          '(Toca nuevamente para modificar la selección)',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MODAL DE SELECCIÓN DE PRODUCTOS
// =============================================================================
class ProductSelectionModal extends ConsumerStatefulWidget {
  final List<String> initialSelectedIds;

  const ProductSelectionModal({
    Key? key,
    required this.initialSelectedIds,
  }) : super(key: key);

  @override
  ConsumerState<ProductSelectionModal> createState() => _ProductSelectionModalState();
}

class _ProductSelectionModalState extends ConsumerState<ProductSelectionModal> {
  late List<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    // Hacemos una copia local de los IDs para trabajar con ellos
    _selectedIds = List.from(widget.initialSelectedIds);
  }

  void _toggleProduct(String productId) {
    setState(() {
      if (_selectedIds.contains(productId)) {
        _selectedIds.remove(productId);
      } else {
        _selectedIds.add(productId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Escuchamos el stream de productos del inventario
    final productsAsyncValue = ref.watch(productsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar Productos'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context), // Cierra sin guardar
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Devuelve la lista de IDs al editor del catálogo
              Navigator.of(context).pop(_selectedIds);
            },
            child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: productsAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text('Error cargando inventario: $error', style: const TextStyle(color: Colors.red)),
        ),
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('No hay productos en tu inventario.'));
          }

          return ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final isSelected = _selectedIds.contains(product.id);

              return CheckboxListTile(
                value: isSelected,
                onChanged: (bool? value) {
                  _toggleProduct(product.id);
                },
                secondary: product.imageUrl != null
                    ? CircleAvatar(backgroundImage: NetworkImage(product.imageUrl!))
                    : CircleAvatar(child: Text(product.name[0].toUpperCase())),
                title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Stock: ${product.stock} ${product.unit} | \$${product.price}'),
              );
            },
          );
        },
      ),
      // Muestra un contador en la parte inferior
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.blue.withOpacity(0.1),
        child: Text(
          '${_selectedIds.length} productos seleccionados',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
        ),
      ),
    );
  }
}