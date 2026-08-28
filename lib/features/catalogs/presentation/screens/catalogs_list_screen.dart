import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/catalog_provider.dart';
import '../screens/catalog_create_screen.dart';
import 'catalog_editor_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'catalog_viewer_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class CatalogsListScreen extends ConsumerStatefulWidget {
  final String businessId; // Requerimos el ID del negocio para filtrar sus catálogos

  const CatalogsListScreen({Key? key, required this.businessId}) : super(key: key);

  @override
  ConsumerState<CatalogsListScreen> createState() => _CatalogsListScreenState();
}

class _CatalogsListScreenState extends ConsumerState<CatalogsListScreen> {
  @override
  void initState() {
    super.initState();
    // Cargamos los catálogos justo después de que se renderiza el primer frame
    Future.microtask(() => 
      ref.read(catalogNotifierProvider.notifier).loadCatalogs(widget.businessId)
    );
  }

  @override
  Widget build(BuildContext context) {
    // Escuchamos los cambios en el estado (cargando, error, lista de catálogos)
    final catalogState = ref.watch(catalogNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Catálogos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Si hay historial en la pila, hace pop normal
            if (context.canPop()) {
              context.pop();
            } else {
              // Si viene del drawer y no hay historial, lo enviamos al inicio
              context.go('/dashboard'); 
            }
          },
        ),
      ),
      body: _buildBody(catalogState),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CatalogCreateScreen(businessId: widget.businessId),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(CatalogState state) {
    // 1. Estado de carga inicial
    if (state.isLoading && state.catalogs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. Estado de error
    if (state.errorMessage != null && state.catalogs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            state.errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    // 3. Estado vacío (sin catálogos)
    if (state.catalogs.isEmpty) {
      return const Center(
        child: Text('Aún no tienes catálogos en Konta Negocios. ¡Crea el primero!'),
      );
    }

    // 4. Lista de catálogos
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: state.catalogs.length,
      itemBuilder: (context, index) {
        final catalog = state.catalogs[index];
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12.0),
          child: ListTile(
            title: Text(catalog.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              catalog.config.themeType.toString().contains('preset') 
                  ? 'Plantilla predeterminada' 
                  : 'Diseño personalizado'
            ),
            // Reemplaza el trailing anterior con este:
            trailing: Row(
              mainAxisSize: MainAxisSize.min, // MUY IMPORTANTE para que no rompa el diseño
              children: [
                // 1. Botón de Vista Previa
                IconButton(
                  icon: const Icon(Icons.remove_red_eye_outlined, color: Colors.blue),
                  tooltip: 'Ver catálogo',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CatalogViewerScreen(catalog: catalog),
                      ),
                    );
                  },
                ),
                // 2. Botón de Compartir
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.green),
                  tooltip: 'Compartir',
                  onPressed: () async {
                    final String catalogUrl = 'https://app.kontanegocios.com/c/${catalog.id}';
                    final String textToShare = '¡Hola! Mira nuestro catálogo "${catalog.name}": $catalogUrl';

                    if (kIsWeb) {
                      // Si estamos en PC/Navegador, copiamos el enlace al portapapeles
                      await Clipboard.setData(ClipboardData(text: textToShare));
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enlace copiado al portapapeles 📋'),
                            backgroundColor: Colors.black87,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } else {
                      // Si estamos en un celular, abrimos el menú nativo de compartir
                      Share.share(textToShare, subject: 'Catálogo de productos');
                    }
                  },
                ),
                // 3. Botón de Eliminar
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Eliminar',
                  onPressed: () {
                    // Llama al método de eliminar del Provider
                    ref.read(catalogNotifierProvider.notifier).deleteCatalog(catalog.id);
                  },
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CatalogEditorScreen(catalog: catalog),
                ),
              );
            },
          ),
        );
      },
    );
  }
}