import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// import '../../home/presentation/dashboard_shell.dart'; // Si lo necesitas

import '../../../core/utils/currency_formatter.dart';
import '../domain/product_model.dart';
import 'inventory_providers.dart';

import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'dart:io'; // Si necesitas manejo de bytes en algunas plataformas
import 'package:flutter/foundation.dart';

import 'package:intl/intl.dart'; // Para fecha en el nombre del archivo
// Asegúrate de tener path_provider y share_plus en pubspec.yaml para guardar/compartir
import 'package:path_provider/path_provider.dart'; 
import 'package:share_plus/share_plus.dart';

// 1. IMPORTAR PERFIL PARA PERMISOS
import '../../auth/presentation/user_profile_provider.dart';
import '../presentation/audit_screen.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/auth_providers.dart';
import 'package:material_symbols_icons/symbols.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    final productsAsync = ref.watch(productsStreamProvider);

    // 2. OBTENER PERMISOS
    final userProfile = ref.watch(userProfileProvider).value;
    final bool canEdit = userProfile?.canEditData ?? false; // Admin y Supervisor

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: isMobile ? IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ) : null,
          title: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Color.fromARGB(255, 0, 0, 0)),
            cursorColor: const Color.fromARGB(255, 0, 0, 0),
            
            decoration: InputDecoration( 
              hintText: 'Buscar producto...',
              hintStyle: const TextStyle(color: Color.fromARGB(179, 3, 3, 3)),
              border: InputBorder.none,
              prefixIcon: const Icon(Symbols.search, color: Color.fromARGB(255, 0, 0, 0)),
              
              suffixIcon: IconButton(
                icon: const Icon(Symbols.barcode_scanner, color: Colors.black),
                tooltip: 'Escanear código',
                onPressed: () async {
                  final code = await context.push<String>('/scanner');
                  if (code != null) {
                    _searchCtrl.text = code;
                    setState(() {
                      _query = code.toLowerCase();
                    });
                  }
                },
              ),
            ),
            
            onChanged: (val) {
              setState(() {
                _query = val.toLowerCase();
              });
            },
          ),
          actions: [
            // 3. OCULTAR IMPORTAR EXCEL SI NO TIENE PERMISOS
            if (canEdit)...[
              IconButton(
                icon: const Icon(Icons.playlist_add_check_circle, color: Colors.indigo),
                tooltip: 'Modo Auditoría (Arqueo)',
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(builder: (context) => const AuditScreen())
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.download, color: Colors.blue),
                tooltip: 'Exportar Excel',
                onPressed: () {
                  // Necesitamos acceder a la lista actual. 
                  // La forma más limpia es leer el provider o pasarla si ya la tienes en el build.
                  final products = ref.read(productsStreamProvider).asData?.value ?? [];
                  _exportExcel(products);
                },
              ),
              IconButton(
                icon: const Icon(Icons.upload_file, color: Colors.green),
                tooltip: 'Importar Excel',
                onPressed: () => _showImportInstructionsDialog(context),
              ),
            const SizedBox(width: 10),
            ]
          ],
          backgroundColor: const Color.fromARGB(255, 255, 255, 255),
          iconTheme: const IconThemeData(color: Color.fromARGB(255, 0, 0, 0)), 
          
          bottom: const TabBar(
            indicatorColor: Color.fromARGB(255, 58, 56, 56),
            indicatorWeight: 3,
            labelColor: Color.fromARGB(255, 53, 51, 51),
            unselectedLabelColor: Color.fromARGB(153, 70, 68, 68),
            tabs: [
              Tab(icon: Icon(Icons.inventory_2), text: 'Físicos'),
              Tab(icon: Icon(Icons.design_services), text: 'Servicios'),
            ],
          ),
        ),
        
        // 4. OCULTAR BOTÓN DE NUEVO ITEM SI NO TIENE PERMISOS
        floatingActionButton: canEdit ? FloatingActionButton.extended(
          onPressed: () => context.push('/inventory/save'),
          backgroundColor: Colors.indigo,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Nuevo Item', style: TextStyle(color: Colors.white)),
        ) : null,
        
        body: productsAsync.when(
          data: (allProducts) {
            final filtered = allProducts.where((p) {
              final matchName = p.name.toLowerCase().contains(_query);
              final matchCode = p.barcode.toLowerCase().contains(_query);
              return matchName || matchCode;
            }).toList();

            final physicalProducts = filtered.where((p) => !p.isService).toList();
            final serviceProducts = filtered.where((p) => p.isService).toList();

            return TabBarView(
              children: [
                _buildProductList(physicalProducts, context, isService: false),
                _buildProductList(serviceProducts, context, isService: true),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  Widget _buildProductList(List<Product> products, BuildContext context, {required bool isService}) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isService ? Icons.design_services_outlined : Icons.inventory_2_outlined,
              size: 60,
              color: Colors.grey[300]
            ),
            const SizedBox(height: 10),
            Text(
              _query.isEmpty 
                ? (isService ? "No hay servicios registrados" : "Inventario vacío")
                : "No se encontraron resultados",
              style: const TextStyle(color: Colors.grey)
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100, top: 10, left: 10, right: 10),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final isLowStock = !isService && (product.stock <= product.minStock);

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            leading: CircleAvatar(
              backgroundColor: isService ? Colors.purple[50] : (isLowStock ? Colors.red[50] : Colors.blue[50]),
              child: Icon(
                isService ? Icons.design_services : (isLowStock ? Icons.warning : Icons.inventory_2),
                color: isService ? Colors.purple : (isLowStock ? Colors.red : Colors.blue),
              ),
            ),
            title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.category, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(
                  CurrencyFormatter.format(product.price), 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isService)
                  const Text("Digital / Servicio", style: TextStyle(fontSize: 11, color: Colors.purple, fontWeight: FontWeight.bold))
                else ...[
                  Text("Stock: ${product.stock}", style: const TextStyle(fontSize: 12)),
                  if (isLowStock)
                    const Text("Stock Bajo", style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            onTap: () => _showProductDetails(context, product),
          ),
        );
      },
    );
  }

  void _showProductDetails(BuildContext context, Product product) {
    // 5. LEER PERMISOS NUEVAMENTE PARA EL MODAL
    final userProfile = ref.read(userProfileProvider).value;
    final bool canEdit = userProfile?.canEditData ?? false;
    final bool canDelete = userProfile?.canDeleteItems ?? false;
    final bool canViewCosts = userProfile?.canViewCosts ?? false;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: product.isService ? Colors.purple[100] : Colors.blue[100],
                      borderRadius: BorderRadius.circular(5)
                    ),
                    child: Text(
                      product.isService ? 'SERVICIO' : 'FÍSICO',
                      style: TextStyle(
                        color: product.isService ? Colors.purple[900] : Colors.blue[900], 
                        fontWeight: FontWeight.bold, fontSize: 10
                      )
                    ),
                  )
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _DetailBadge(label: 'Precio Venta', value: CurrencyFormatter.format(product.price), color: Colors.green),
                  
                  // 6. MOSTRAR COSTO SOLO SI TIENE PERMISO (Admin/Supervisor)
                  if (canViewCosts)
                    _DetailBadge(label: 'Costo', value: CurrencyFormatter.format(product.cost), color: Colors.orange),
                  
                  if (!product.isService)
                    _DetailBadge(label: 'Stock Actual', value: '${product.stock}', color: Colors.blue),
                ],
              ),
              
              const SizedBox(height: 20),
              
              if (product.description.isNotEmpty) ...[
                const Text("Descripción:", style: TextStyle(fontWeight: FontWeight.bold)),
                Text(product.description),
                const SizedBox(height: 20),
              ],
              
              if (!product.isService) ...[
                Row(
                  children: [
                    const Icon(Icons.qr_code, size: 16, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text("Código: ${product.barcode.isEmpty ? 'N/A' : product.barcode}", style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // 7. OCULTAR BOTONES DE EDICIÓN/ELIMINACIÓN SI NO TIENE PERMISOS
              if (canEdit)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/inventory/save', extra: product);
                    },
                    icon: const Icon(Icons.edit, color: Colors.indigo),
                    label: const Text('Editar'),
                  ),
                  
                  // 8. SOLO MOSTRAR ELIMINAR SI TIENE PERMISO ESPECÍFICO (Admin/Supervisor)
                  if (canDelete)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDelete(context, product);
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                    icon: const Icon(Icons.delete),
                    label: const Text('Eliminar'),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content: Text('¿Estás seguro de eliminar "${product.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteProduct(context, product);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Future<void> _deleteProduct(BuildContext context, Product product) async {
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      await repo.deleteProduct(product.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Producto eliminado correctamente'))
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  Future<void> _importExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true, 
      );

      if (result != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Procesando archivo...'), duration: Duration(seconds: 1))
        );

        final bytes = result.files.single.bytes;
        if (bytes == null) return;

        var excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables[excel.tables.keys.first];

        // --- 1. SOLUCIÓN DUPLICADOS: MAPEAR PRODUCTOS EXISTENTES ---
        // Leemos el inventario actual para saber qué códigos de barras ya existen
        final currentProducts = ref.read(productsStreamProvider).asData?.value ?? [];
        Map<String, String> barcodeToId = {};
        for (var p in currentProducts) {
          if (p.barcode.isNotEmpty) {
            barcodeToId[p.barcode] = p.id;
          }
        }

        List<Product> newProducts = [];

        for (var i = 1; i < sheet!.maxRows; i++) {
          var row = sheet.rows[i];
          if (row.isEmpty || row[0] == null) continue;

          String name = row[0]?.value?.toString() ?? 'Sin Nombre';
          String barcode = row[1]?.value?.toString() ?? '';
          double price = double.tryParse(row[2]?.value?.toString() ?? '0') ?? 0.0;
          double cost = double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0.0;
          int stock = int.tryParse(row[4]?.value?.toString() ?? '0') ?? 0;
          String category = row[5]?.value?.toString() ?? 'General';
          int minStock = int.tryParse(row[6]?.value?.toString() ?? '5') ?? 5;

          // --- NUEVO: LEER COLUMNAS DE IMPUESTOS (Índices 7 y 8) ---
          String rawTaxType = row.length > 7 ? (row[7]?.value?.toString() ?? 'EXCLUIDO') : 'EXCLUIDO';
          double rawTaxRate = row.length > 8 ? (double.tryParse(row[8]?.value?.toString() ?? '0') ?? 0.0) : 0.0;

          // Normalizar valores por seguridad
          String finalTaxType = rawTaxType.toUpperCase().trim();
          if (!['IVA', 'INC', 'EXENTO', 'EXCLUIDO'].contains(finalTaxType)) {
            finalTaxType = 'EXCLUIDO';
          }

          // --- CERCO DE SEGURIDAD TRIBUTARIO (TARIFAS COLOMBIA) ---
          if (finalTaxType == 'IVA') {
            // Solo existe IVA del 19% o del 5%. Si ponen otra cosa, forzamos a 19%.
            if (rawTaxRate != 19.0 && rawTaxRate != 5.0) {
              rawTaxRate = 19.0;
            }
          } else if (finalTaxType == 'INC') {
            // Tarifa estándar de INC es 8%.
            if (rawTaxRate != 8.0) {
              rawTaxRate = 8.0; 
            }
          } else {
            // Si es Excluido o Exento, la tarifa OBLIGATORIAMENTE es 0.
             rawTaxRate = 0.0;
          }

          // Si el Excel trae un código que ya existe en Firestore, capturamos su ID
          String existingId = '';
          if (barcode.isNotEmpty && barcodeToId.containsKey(barcode)) {
            existingId = barcodeToId[barcode]!; // ¡Esto fuerza la actualización en vez de duplicar!
          }

          newProducts.add(Product(
            id: existingId, // Vacío = Nuevo producto. Con ID = Actualizar existente.
            name: name,
            barcode: barcode,
            price: price,
            cost: cost,
            stock: stock,
            category: category,
            minStock: minStock,
            unit: 'Und', 
            isService: false,
            // --- NUEVOS CAMPOS ---
            taxType: finalTaxType,
            taxRate: rawTaxRate,
          ));
        }

        if (newProducts.isNotEmpty) {
          // Guardar o actualizar productos
          await ref.read(inventoryRepositoryProvider).importProducts(newProducts);

          // --- 2. SOLUCIÓN CATEGORÍAS: GUARDADO PERMANENTE EN FIRESTORE ---
          Set<String> importedCategories = newProducts
              .map((p) => p.category.trim())
              .where((c) => c.isNotEmpty && c != 'General')
              .toSet();

          final companyId = ref.read(companyIdProvider).value;
          
          if (companyId != null && importedCategories.isNotEmpty) {
            // Esto escribe directamente en la base de datos de configuración de tu empresa
            await FirebaseFirestore.instance
                .collection('companies')
                .doc(companyId)
                .collection('config')
                .doc('inventory')
                .set({
                  // arrayUnion agrega las categorías nuevas sin borrar las que ya tenías
                  'categories': FieldValue.arrayUnion(importedCategories.toList()) 
                }, SetOptions(merge: true));
          }

          // Actualizamos la pantalla al instante sin recargar
          for (String newCategory in importedCategories) {
            ref.read(productCategoriesProvider.notifier).add(newCategory);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('✅ Se importaron/actualizaron ${newProducts.length} productos'), backgroundColor: Colors.green)
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('⚠️ El archivo parece vacío o con formato incorrecto'))
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  Future<void> _exportExcel(List<Product> products) async {
    // 1. GENERAR EL EXCEL
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Inventario'];
    
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // --- CORRECCIÓN DE FORMATO: Mismas columnas que la plantilla ---
    // NUEVO: Agregadas las columnas de impuestos
    List<String> headers = ['Nombre', 'Código de Barras', 'Precio Venta', 'Costo', 'Stock Actual', 'Categoría', 'Stock Mínimo', 'Tipo Impuesto (IVA/INC/EXENTO/EXCLUIDO)', 'Tarifa Impuesto (%)'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Datos exportados en el mismo orden exacto
    for (var p in products) {
      sheetObject.appendRow([
        TextCellValue(p.name),
        TextCellValue(p.barcode),
        DoubleCellValue(p.price),
        DoubleCellValue(p.cost),
        IntCellValue(p.stock),
        TextCellValue(p.category),
        IntCellValue(p.minStock),
        TextCellValue(p.taxType),         
        DoubleCellValue(p.taxRate),       
      ]);
    }

    // 2. PREPARAR NOMBRE DEL ARCHIVO CON FECHA
    final date = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'Inventario_$date.xlsx';

    // 3. GUARDADO INTELIGENTE (WEB vs WINDOWS vs MÓVIL)
    if (kIsWeb) {
      // --- LÓGICA WEB ---
      excel.save(fileName: fileName); 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Descargando archivo...'), backgroundColor: Colors.green)
      );
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // --- LÓGICA ESCRITORIO (Windows) ---
      // Abre la ventana de "Guardar como..." del sistema operativo
      final fileBytes = excel.save();
      if (fileBytes != null) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Inventario',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsBytes(fileBytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Archivo guardado exitosamente'), backgroundColor: Colors.green)
            );
          }
        }
      }
    } else {
      // --- LÓGICA MÓVIL (Android/iOS) ---
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$fileName');
        
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles(
          [XFile(file.path)], 
          text: 'Reporte de Inventario $date'
        );
      }
    }
  }

// --- 1. DIÁLOGO DE INSTRUCCIONES ANTES DE IMPORTAR ---
  void _showImportInstructionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.upload_file, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text("Importar Inventario"),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Para que el sistema lea tus productos correctamente, el archivo Excel debe tener exactamente estas 9 columnas en la fila 1:"),
            SizedBox(height: 15),
            Text("1. Nombre\n2. Código de Barras\n3. Precio Venta\n4. Costo\n5. Stock Actual\n6. Categoría\n7. Stock Mínimo\n8. Tipo Impuesto (Escribir: IVA, INC, EXENTO o EXCLUIDO)\n9. Tarifa Impuesto (Ej: 19 o 5)", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 15),
            Text("Si no tienes este formato, descarga la plantilla a continuación, llénala y luego presiona Continuar.", style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadExcelTemplate(); // Llama a descargar la plantilla
            },
            icon: const Icon(Icons.download),
            label: const Text("Descargar Plantilla"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _importExcel(); // Llama a la importación real
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text("Continuar"),
          ),
        ],
      ),
    );
  }

  // --- 2. GENERAR Y DESCARGAR LA PLANTILLA VACÍA ---
  Future<void> _downloadExcelTemplate() async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Plantilla_Inventario'];
    
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Encabezados exactos que usa la importación (NUEVO)
    List<String> headers = ['Nombre', 'Código de Barras', 'Precio Venta', 'Costo', 'Stock Actual', 'Categoría', 'Stock Mínimo', 'Tipo Impuesto (IVA/INC/EXENTO/EXCLUIDO)', 'Tarifa Impuesto (%)'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Fila de ejemplo para que el usuario se guíe (NUEVO)
    sheetObject.appendRow([
      TextCellValue('Ej: Gaseosa 2L'),
      TextCellValue('770123456789'),
      DoubleCellValue(5000),
      DoubleCellValue(3500),
      IntCellValue(24),
      TextCellValue('Bebidas'),
      IntCellValue(5),
      TextCellValue('IVA'), // Ejemplo Tipo
      DoubleCellValue(19),   // Ejemplo Tarifa
    ]);

    final fileName = 'Plantilla_Inventario.xlsx';

    if (kIsWeb) {
      excel.save(fileName: fileName); 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Descargando plantilla...'), backgroundColor: Colors.green)
      );
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // --- LÓGICA ESCRITORIO (Windows) PARA LA PLANTILLA ---
      final fileBytes = excel.save();
      if (fileBytes != null) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Plantilla',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );
        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsBytes(fileBytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Plantilla guardada exitosamente'), backgroundColor: Colors.green)
            );
          }
        }
      }
    } else {
      // --- LÓGICA MÓVIL (Android/iOS) ---
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles([XFile(file.path)], text: 'Plantilla de Inventario');
      }
    }
  }

}



class _DetailBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _DetailBadge({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          value, 
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)
        ),
      ],
    );
  }
}