import 'dart:convert'; // Necesario para Base64
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart'; 
import '../../../shared/widgets/custom_text_field.dart';
import '../domain/company_model.dart';
import '../data/settings_repository.dart';
import '../../auth/presentation/user_profile_provider.dart';
import '../../auth/domain/user_model.dart';

class CompanyProfileScreen extends ConsumerStatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  ConsumerState<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends ConsumerState<CompanyProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameCtrl = TextEditingController();
  final _nitCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _sloganCtrl = TextEditingController();
  
  String? _imageBase64; // La imagen en memoria
  bool _isLoading = false;
  bool _isInitialized = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery, 
        imageQuality: 50, 
        maxWidth: 500,
      );
      
      if (image != null) {
        // CAMBIO CLAVE: Usamos readAsBytes() directamente desde el XFile
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar imagen: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // 1. CREAMOS UN DICCIONARIO SOLO CON LOS CAMPOS VISIBLES
      // ¡No instanciamos el modelo para no arrastrar variables ocultas!
      final Map<String, dynamic> updateData = {
        'name': _nameCtrl.text.trim(),
        'nit': _nitCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'slogan': _sloganCtrl.text.trim(),
      };

      // Solo enviamos la imagen si realmente se cargó una
      if (_imageBase64 != null) {
        updateData['imageBase64'] = _imageBase64;
      }

      final repository = ref.read(settingsRepositoryProvider);

      if (repository != null) {
        // 2. LLAMAMOS A LA NUEVA FUNCIÓN BLINDADA
        await repository.updateCompanyProfileData(updateData);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sincronizando con el servidor, intenta de nuevo en un segundo.'), backgroundColor: Colors.orange),
        );
        return;
      }

      // 3. FORZAR ACTUALIZACIÓN GLOBAL
      ref.invalidate(companyProfileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil actualizado correctamente')));
        context.pop(); 
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. VERIFICAR PERMISOS
    final userProfile = ref.watch(userProfileProvider).value;
    final bool isAdmin = userProfile?.role == UserRole.admin;

    // --- LÓGICA REACTIVA PARA LLENAR LOS DATOS (NUEVO) ---
    final profileAsync = ref.watch(companyProfileProvider);
    
    // Si ya tenemos los datos y aún no hemos llenado los campos de texto...
    if (profileAsync.hasValue && profileAsync.value != null && !_isInitialized) {
      final currentProfile = profileAsync.value!;
      
      _nameCtrl.text = currentProfile.name;
      _nitCtrl.text = currentProfile.nit;
      _addressCtrl.text = currentProfile.address;
      _phoneCtrl.text = currentProfile.phone;
      _emailCtrl.text = currentProfile.email;
      _sloganCtrl.text = currentProfile.slogan;
      _imageBase64 = currentProfile.imageBase64;
      
      _isInitialized = true; // Para que no se vuelva a sobreescribir si el admin escribe algo
    }
    // -----------------------------------------------------

    // Decodificar imagen para mostrarla en la vista previa
    ImageProvider? imageProvider;
    if (_imageBase64 != null && _imageBase64!.isNotEmpty) {
      try {
        imageProvider = MemoryImage(base64Decode(_imageBase64!));
      } catch (e) {
        imageProvider = null;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil de Empresa')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // AVISO SI NO ES ADMIN
              if (!isAdmin)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200)
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 10),
                      Expanded(child: Text("Solo lectura. Contacta al administrador para modificar estos datos.", style: TextStyle(color: Colors.blue, fontSize: 12))),
                    ],
                  ),
                ),

              // FOTO DE PERFIL CON BOTÓN DE EDITAR (Solo si es Admin)
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: imageProvider,
                      child: imageProvider == null 
                        ? const Icon(Icons.store, size: 60, color: Colors.grey) 
                        : null,
                    ),
                    if (isAdmin)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          backgroundColor: Colors.blue,
                          radius: 20,
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            onPressed: _pickImage,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // CAMPOS DE TEXTO (Deshabilitados si no es Admin)
              // NOTA: 'enabled: isAdmin' hace que se vean gris si es false.
              // Para que se vean negro pero no editables, usamos readOnly: !isAdmin
              _buildField('Nombre Comercial', _nameCtrl, Icons.business, isAdmin),
              _buildField('NIT / Identificación', _nitCtrl, Icons.badge, isAdmin),
              _buildField('Eslogan / Frase', _sloganCtrl, Icons.format_quote, isAdmin),
              _buildField('Dirección', _addressCtrl, Icons.location_on, isAdmin),
              _buildField('Teléfono Contacto', _phoneCtrl, Icons.phone, isAdmin, isPhone: true),
              _buildField('Email Contacto', _emailCtrl, Icons.email, isAdmin, isEmail: true),
              
              const SizedBox(height: 30),
              
              if (isAdmin)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white
                    ),
                    child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('GUARDAR CAMBIOS'),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  // Helper para construir campos con estado de solo lectura
  Widget _buildField(String label, TextEditingController ctrl, IconData icon, bool isAdmin, {bool isPhone = false, bool isEmail = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: CustomTextField(
        label: label, 
        controller: ctrl, 
        icon: icon,
        // Si no es admin, es solo lectura
        readOnly: !isAdmin, 
        keyboardType: isPhone ? TextInputType.phone : (isEmail ? TextInputType.emailAddress : TextInputType.text),
      ),
    );
  }
}