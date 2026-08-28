import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'; // Para kIsWeb
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

class ImageService {
  final ImagePicker _picker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<XFile?> pickAndCompressImage({required ImageSource source}) async {
    try {
      // 1. PRIMER NIVEL DE COMPRESIÓN (Funciona en WEB y Móvil)
      // Al poner maxWidth y imageQuality aquí, el navegador en Web ya
      // redimensiona la imagen antes de devolvértela. ¡Problema resuelto en Web!
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,      // Máximo 1024px de ancho
        maxHeight: 1024,     // Máximo 1024px de alto
        imageQuality: 80,    // Calidad JPG 80%
      );

      if (picked == null) return null;

      // 2. SEGUNDO NIVEL (Solo para Móvil - Opcional)
      // En Android/iOS, flutter_image_compress es aún más eficiente reduciendo bytes
      // que el image_picker nativo. Lo usamos solo si NO es web.
      if (!kIsWeb) {
        final String basename = p.basenameWithoutExtension(picked.path);
        final String dir = p.dirname(picked.path);
        final String targetPath = '$dir/${basename}_compressed.jpg';

        try {
          final XFile? compressed = await FlutterImageCompress.compressAndGetFile(
            picked.path,
            targetPath,
            minWidth: 1024,
            minHeight: 1024,
            quality: 80,
            format: CompressFormat.jpeg,
          );
          // Si comprime bien, devolvemos el comprimido. Si falla, el original (que ya viene algo reducido).
          return compressed ?? picked;
        } catch (e) {
          print("Aviso: Falló compresión avanzada en móvil, usando imagen estándar: $e");
          return picked;
        }
      }

      // En Web devolvemos directamente el 'picked' que ya viene redimensionado por image_picker
      return picked;

    } catch (e) {
      print('Error al seleccionar imagen: $e');
      return null;
    }
  }

  // CAMBIO 1: Agregamos "String companyId" a los parámetros
  Future<String?> uploadProductImage(XFile image, String productId, String companyId) async {
    try {
      final imageBytes = await image.readAsBytes();
      final String fileName = '$productId.jpg';
      
      // CAMBIO 2: Construimos la ruta exacta que exigen tus reglas de seguridad
      final Reference ref = _storage
          .ref()
          .child('companies')
          .child(companyId) // <-- Esto es lo que le faltaba a Firebase para dejarte pasar
          .child('products')
          .child(fileName);

      // El metadata ya lo tenías perfecto, esto cumple la regla de "image/.*"
      final SettableMetadata metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'picked-date': DateTime.now().toString()},
      );

      final UploadTask task = ref.putData(imageBytes, metadata);
      final TaskSnapshot snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('Error subiendo imagen: $e');
      return null;
    }
  }
}