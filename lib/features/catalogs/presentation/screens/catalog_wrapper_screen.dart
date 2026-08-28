import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'catalog_viewer_screen.dart';
import '../../data/models/catalog_model.dart'; // Asegúrate que esta ruta coincida con la ubicación de tu catalog_model.dart

class CatalogWrapperScreen extends StatefulWidget {
  final String catalogId;

  const CatalogWrapperScreen({Key? key, required this.catalogId}) : super(key: key);

  @override
  State<CatalogWrapperScreen> createState() => _CatalogWrapperScreenState();
}

class _CatalogWrapperScreenState extends State<CatalogWrapperScreen> {
  bool _isLoading = true;
  CatalogModel? _catalog;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  Future<void> _fetchCatalog() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('catalogs')
          .get();

      // Buscamos el documento cuyo ID en Firestore coincida exactamente con la URL
      final matchingDoc = snapshot.docs.where((doc) {
        return doc.id == widget.catalogId;
      }).firstOrNull;

      if (matchingDoc != null && matchingDoc.exists) {
        final data = matchingDoc.data();
        
        setState(() {
          // Usamos tu modelo exacto pasando el mapa y el ID del documento
          _catalog = CatalogModel.fromJson(data, matchingDoc.id);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'El catálogo con ID "${widget.catalogId}" no fue encontrado.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al conectar con la base de datos: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFBFBF9),
        body: Center(child: CircularProgressIndicator(color: Colors.black87)),
      );
    }

    if (_errorMessage != null || _catalog == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBFBF9),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storefront_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Catálogo no disponible',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Renderizamos tu visor de catálogos público pasándole el modelo convertido
    return CatalogViewerScreen(catalog: _catalog!);
  }
}