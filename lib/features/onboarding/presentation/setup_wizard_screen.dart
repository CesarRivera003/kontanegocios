import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../settings/data/settings_repository.dart';
import '../../finance/data/finance_repository.dart';
import '../../finance/domain/finance_model.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/product_model.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/user_profile_provider.dart';
import 'setup_wizard_providers.dart';

class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class ProductDraftRow {
  final String id = DateTime.now().microsecondsSinceEpoch.toString();
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController costCtrl = TextEditingController();
  final TextEditingController stockCtrl = TextEditingController();
  final TextEditingController minStockCtrl = TextEditingController();
  final TextEditingController barcodeCtrl = TextEditingController();
  final TextEditingController descriptionCtrl = TextEditingController();
  final TextEditingController categoryCtrl = TextEditingController(
    text: 'General',
  );

  bool isService = false;
  XFile? imageFile;

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    costCtrl.dispose();
    stockCtrl.dispose();
    minStockCtrl.dispose();
    barcodeCtrl.dispose();
    descriptionCtrl.dispose();
    categoryCtrl.dispose();
  }
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  final PageController _pageController = PageController();

  // Paso 1: Perfil y Empresa
  final _companyFormKey = GlobalKey<FormState>();
  final _userNameCtrl = TextEditingController(); // Nuevo: Nombre del Usuario
  final _nameCtrl = TextEditingController();
  final _nitCtrl = TextEditingController();
  final _sloganCtrl = TextEditingController(); // Nuevo
  final _addressCtrl = TextEditingController(); // Nuevo
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController(); // Nuevo
  String? _imageBase64; // Nuevo

  // Paso 2: Cuentas
  final _accountFormKey = GlobalKey<FormState>();
  final _accountNameCtrl = TextEditingController();
  final _accountBalanceCtrl = TextEditingController(text: '0');

  // Cuenta principal (Caja General) se maneja por separado para facilitar su edición inicial
  final _mainAccountBalanceCtrl = TextEditingController(text: '0');

  List<BankAccount> _tempAccounts = [];
  BankAccount? _existingMainAccount;
  bool _isLoadingMainAccount = true;
  bool _isCashAccount = true;

  // Paso 3: Inventario manual
  final _inventoryFormKey = GlobalKey<FormState>();
  List<ProductDraftRow> _productDrafts = [];
  bool _showManualInventoryForm = false; // Toggle manual form

  bool _initializedCompanyFields = false;

  @override
  void initState() {
    super.initState();
    _loadMainAccount();
    // Iniciar con 2 filas
    _productDrafts.add(ProductDraftRow());
    _productDrafts.add(ProductDraftRow());
  }

  Future<void> _loadMainAccount() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userId = ref.read(companyIdProvider).value;
      if (userId != null) {
        final financeRepo = FinanceRepository(
          FirebaseFirestore.instance,
          userId,
        );
        final accounts = await financeRepo.getAccounts().first;

        final mainAcc = accounts.firstWhere(
          (acc) => acc.isDefault && acc.isCash,
          orElse: () => accounts.firstWhere(
            (acc) => acc.name.toLowerCase().contains('caja'),
            orElse: () => BankAccount(
              id: '',
              name: 'Caja General',
              balance: 0,
              isCash: true,
              isDefault: true,
            ),
          ),
        );

        if (mounted) {
          setState(() {
            _existingMainAccount = mainAcc;
            if (mainAcc.id.isNotEmpty) {
              _mainAccountBalanceCtrl.text = mainAcc.balance.toInt().toString();
            }
            _isLoadingMainAccount = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingMainAccount = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _userNameCtrl.dispose();
    _nameCtrl.dispose();
    _nitCtrl.dispose();
    _sloganCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _accountNameCtrl.dispose();
    _accountBalanceCtrl.dispose();
    _mainAccountBalanceCtrl.dispose();
    for (var p in _productDrafts) {
      p.dispose();
    }
    super.dispose();
  }

  void _onStepChanged(int step) {
    ref.read(setupWizardProvider.notifier).setStep(step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _completeSetup() async {
    final notifier = ref.read(setupWizardProvider.notifier);
    notifier.setLoading(true);
    try {
      final repository = ref.read(settingsRepositoryProvider);
      if (repository != null) {
        await repository.updateCompanyProfileData({'hasCompletedSetup': true});
      }
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Configuración completada!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      notifier.setLoading(false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
        maxWidth: 500,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar imagen: $e')));
      }
    }
  }

  Future<void> _saveCompanyStep() async {
    if (!_companyFormKey.currentState!.validate()) return;

    final notifier = ref.read(setupWizardProvider.notifier);
    notifier.setLoading(true);
    try {
      // 1. Guardar nombre del usuario si aplica
      final authRepo = ref.read(authRepositoryProvider);
      final currentUser = authRepo.currentUser;
      final companyId = ref.read(companyIdProvider).value;
      if (currentUser != null &&
          companyId != null &&
          _userNameCtrl.text.trim().isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('companies')
            .doc(companyId)
            .collection('users')
            .doc(currentUser.uid)
            .set({
              'name': _userNameCtrl.text.trim(),
              'role': 'admin',
            }, SetOptions(merge: true));
      }

      // 2. Guardar datos de la empresa
      final repository = ref.read(settingsRepositoryProvider);
      if (repository != null) {
        final Map<String, dynamic> updateData = {
          'name': _nameCtrl.text.trim(),
          'nit': _nitCtrl.text.trim(),
          'slogan': _sloganCtrl.text.trim(),
          'address': _addressCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
        };

        if (_imageBase64 != null) {
          updateData['imageBase64'] = _imageBase64;
        }

        await repository.updateCompanyProfileData(updateData);
      }
      notifier.nextStep();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      notifier.setLoading(false);
    }
  }

  void _addTempAccount() {
    if (!_accountFormKey.currentState!.validate()) return;
    if (_accountNameCtrl.text.trim().isEmpty) return;

    String balanceText = _accountBalanceCtrl.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    double initialBalance = double.tryParse(balanceText) ?? 0.0;

    // Cuentas adicionales son forzadas a isDefault: false
    final account = BankAccount(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // ID temporal
      name: _accountNameCtrl.text.trim(),
      balance: initialBalance,
      isCash: _isCashAccount,
      isDefault: false,
    );

    setState(() {
      _tempAccounts.add(account);
      _accountNameCtrl.clear();
      _accountBalanceCtrl.text = '0';
    });
  }

  Future<void> _saveAccountStep() async {
    final notifier = ref.read(setupWizardProvider.notifier);
    notifier.setLoading(true);

    try {
      final userId = ref.read(companyIdProvider).value;
      if (userId != null) {
        final financeRepo = FinanceRepository(
          FirebaseFirestore.instance,
          userId,
        );

        // 1. Update Existing Main Account Balance (do NOT recreate it)
        if (_existingMainAccount != null &&
            _existingMainAccount!.id.isNotEmpty) {
          String mainBalanceText = _mainAccountBalanceCtrl.text.replaceAll(
            RegExp(r'[^0-9]'),
            '',
          );
          double mainInitialBalance = double.tryParse(mainBalanceText) ?? 0.0;

          if (_existingMainAccount!.balance != mainInitialBalance) {
            final updatedAccount = BankAccount(
              id: _existingMainAccount!.id,
              name: _existingMainAccount!.name,
              balance: mainInitialBalance,
              isCash: _existingMainAccount!.isCash,
              isDefault: _existingMainAccount!.isDefault,
              accountNumber: _existingMainAccount!.accountNumber,
              isActive: _existingMainAccount!.isActive,
            );
            await financeRepo.updateAccount(updatedAccount);
          }
        }

        // 2. Add New Additional Accounts
        for (var acc in _tempAccounts) {
          final accountToSave = BankAccount(
            id: '',
            name: acc.name,
            balance: acc.balance,
            isCash: acc.isCash,
            isDefault: false, // Ensure additional accounts are never default
          );
          await financeRepo.createAccount(accountToSave);
        }
      }

      notifier.nextStep();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      notifier.setLoading(false);
    }
  }

  Future<void> _skipStep() async {
    final notifier = ref.read(setupWizardProvider.notifier);
    final state = ref.read(setupWizardProvider);
    if (state.currentStep < 2) {
      notifier.nextStep();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      await _completeSetup();
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Plantilla_Inventario'];

      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Encabezados exactos que usa la importación
      List<String> headers = [
        'Nombre del Producto',
        'Código de Barras',
        'Precio de Venta',
        'Costo Unitario',
        'Stock Actual',
        'Categoría',
        'Stock Mínimo',
        'Tipo de Impuesto (IVA/INC/EXENTO/EXCLUIDO)',
        'Tarifa Impuesto % (Ej: 19 o 0)',
      ];

      sheetObject.appendRow(headers.map((h) => TextCellValue(h)).toList());

      List<List<dynamic>> examples = [
        [
          'Empanada de Carne',
          '123456789',
          '2500',
          '1000',
          '50',
          'Alimentos',
          '10',
          'EXCLUIDO',
          '0',
        ],
        [
          'Gaseosa 1.5L',
          '987654321',
          '6000',
          '4000',
          '24',
          'Bebidas',
          '12',
          'IVA',
          '19',
        ],
        [
          'Hamburguesa',
          '',
          '15000',
          '8000',
          '0',
          'Comidas Rápidas',
          '0',
          'INC',
          '8',
        ],
        [
          'Servicio de Domicilio',
          '',
          '5000',
          '0',
          '0',
          'Servicios',
          '0',
          'EXENTO',
          '0',
        ],
      ];

      for (var row in examples) {
        sheetObject.appendRow(
          row.map((cell) => TextCellValue(cell.toString())).toList(),
        );
      }

      final fileName = 'Plantilla_Inventario_Konta.xlsx';

      if (kIsWeb) {
        excel.save(fileName: fileName);
      } else {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);

        final fileBytes = excel.save();
        if (fileBytes != null) {
          await file.writeAsBytes(fileBytes);
          await Share.shareXFiles(
            [XFile(file.path)],
            text:
                'Aquí tienes la plantilla de Excel para importar tus productos a Konta Negocios.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar plantilla: $e')),
        );
      }
    }
  }

  // Copiado de InventoryScreen para Excel
  Future<void> _importExcel() async {
    final notifier = ref.read(setupWizardProvider.notifier);
    notifier.setLoading(true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Procesando archivo...'),
            duration: Duration(seconds: 1),
          ),
        );

        final bytes = result.files.single.bytes;
        if (bytes == null) return;

        var excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables[excel.tables.keys.first];

        // --- 1. SOLUCIÓN DUPLICADOS: MAPEAR PRODUCTOS EXISTENTES ---
        final currentProducts =
            ref.read(productsStreamProvider).asData?.value ?? [];
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
          double price =
              double.tryParse(row[2]?.value?.toString() ?? '0') ?? 0.0;
          double cost =
              double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0.0;
          int stock = int.tryParse(row[4]?.value?.toString() ?? '0') ?? 0;
          String category = row[5]?.value?.toString() ?? 'General';
          int minStock = int.tryParse(row[6]?.value?.toString() ?? '5') ?? 5;

          String rawTaxType = row.length > 7
              ? (row[7]?.value?.toString() ?? 'EXCLUIDO')
              : 'EXCLUIDO';
          double rawTaxRate = row.length > 8
              ? (double.tryParse(row[8]?.value?.toString() ?? '0') ?? 0.0)
              : 0.0;

          String finalTaxType = rawTaxType.toUpperCase().trim();
          if (!['IVA', 'INC', 'EXENTO', 'EXCLUIDO'].contains(finalTaxType)) {
            finalTaxType = 'EXCLUIDO';
          }

          if (finalTaxType == 'IVA') {
            if (rawTaxRate != 19.0 && rawTaxRate != 5.0) {
              rawTaxRate = 19.0;
            }
          } else if (finalTaxType == 'INC') {
            if (rawTaxRate != 8.0) {
              rawTaxRate = 8.0;
            }
          } else {
            rawTaxRate = 0.0;
          }

          String existingId = '';
          if (barcode.isNotEmpty && barcodeToId.containsKey(barcode)) {
            existingId = barcodeToId[barcode]!;
          }

          newProducts.add(
            Product(
              id: existingId,
              name: name,
              barcode: barcode,
              price: price,
              cost: cost,
              stock: stock,
              category: category,
              minStock: minStock,
              unit: 'Und',
              isService: false,
              taxType: finalTaxType,
              taxRate: rawTaxRate,
            ),
          );
        }

        if (newProducts.isNotEmpty) {
          final invRepo = ref.read(inventoryRepositoryProvider);
          try {
            await invRepo
                .importProducts(newProducts)
                .timeout(const Duration(seconds: 4));
          } catch (_) {
            invRepo.importProducts(newProducts).catchError((_) {});
          }

          Set<String> importedCategories = newProducts
              .map((p) => p.category.trim())
              .where((c) => c.isNotEmpty && c != 'General')
              .toSet();

          final companyId = ref.read(companyIdProvider).value;

          if (companyId != null && importedCategories.isNotEmpty) {
            final catDoc = FirebaseFirestore.instance
                .collection('companies')
                .doc(companyId)
                .collection('config')
                .doc('inventory');

            catDoc
                .set({
                  'categories': FieldValue.arrayUnion(
                    importedCategories.toList(),
                  ),
                }, SetOptions(merge: true))
                .catchError((_) {});
          }

          for (String newCategory in importedCategories) {
            ref.read(productCategoriesProvider.notifier).add(newCategory);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✅ Se importaron/actualizaron ${newProducts.length} productos',
                ),
                backgroundColor: Colors.green,
              ),
            );
            await _completeSetup(); // Complete setup after successful import
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '⚠️ El archivo parece vacío o con formato incorrecto',
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al importar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      notifier.setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupWizardProvider);
    final profileAsync = ref.watch(companyProfileProvider);
    final userProfileAsync = ref.watch(userProfileProvider);

    if (profileAsync.hasValue &&
        profileAsync.value != null &&
        !_initializedCompanyFields) {
      final currentProfile = profileAsync.value!;
      if (userProfileAsync.hasValue && userProfileAsync.value != null) {
        if (_userNameCtrl.text.isEmpty &&
            userProfileAsync.value!.name.isNotEmpty) {
          _userNameCtrl.text = userProfileAsync.value!.name;
        }
      }
      if (_nameCtrl.text.isEmpty && currentProfile.name.isNotEmpty)
        _nameCtrl.text = currentProfile.name;
      if (_nitCtrl.text.isEmpty && currentProfile.nit.isNotEmpty)
        _nitCtrl.text = currentProfile.nit;
      if (_sloganCtrl.text.isEmpty && currentProfile.slogan.isNotEmpty)
        _sloganCtrl.text = currentProfile.slogan;
      if (_addressCtrl.text.isEmpty && currentProfile.address.isNotEmpty)
        _addressCtrl.text = currentProfile.address;
      if (_phoneCtrl.text.isEmpty && currentProfile.phone.isNotEmpty)
        _phoneCtrl.text = currentProfile.phone;
      if (_emailCtrl.text.isEmpty && currentProfile.email.isNotEmpty)
        _emailCtrl.text = currentProfile.email;
      if (_imageBase64 == null && currentProfile.imageBase64 != null)
        _imageBase64 = currentProfile.imageBase64;

      _initializedCompanyFields = true;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Configuración Inicial'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: _skipStep, child: const Text('Omitir')),
        ],
      ),
      body: Column(
        children: [
          // Stepper Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStepIndicator(0, state.currentStep, 'Empresa'),
                _buildStepLine(0, state.currentStep),
                _buildStepIndicator(1, state.currentStep, 'Cuentas'),
                _buildStepLine(1, state.currentStep),
                _buildStepIndicator(2, state.currentStep, 'Inventario'),
              ],
            ),
          ),

          // Page View
          Expanded(
            child: PageView(
              controller: _pageController,
              physics:
                  const NeverScrollableScrollPhysics(), // Deshabilita swipe manual
              children: [
                _buildCompanyStep(state.isLoading),
                _buildAccountStep(state.isLoading),
                _buildInventoryStep(state.isLoading),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int stepIndex, int currentStep, String label) {
    bool isCompleted = currentStep > stepIndex;
    bool isActive = currentStep == stepIndex;

    Color circleColor = isCompleted || isActive
        ? Colors.blue.shade700
        : Colors.grey.shade300;
    Color textColor = isActive
        ? Colors.blue.shade800
        : (isCompleted ? Colors.blue.shade700 : Colors.grey.shade500);

    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(shape: BoxShape.circle, color: circleColor),
          alignment: Alignment.center,
          child: isCompleted
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : Text(
                  '${stepIndex + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: textColor,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(int stepIndex, int currentStep) {
    bool isCompleted = currentStep > stepIndex;
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8).copyWith(bottom: 15),
      color: isCompleted ? Colors.blue.shade700 : Colors.grey.shade300,
    );
  }

  // --- PASO 1: EMPRESA ---
  Widget _buildCompanyStep(bool isLoading) {
    ImageProvider? imageProvider;
    if (_imageBase64 != null && _imageBase64!.isNotEmpty) {
      try {
        imageProvider = MemoryImage(base64Decode(_imageBase64!));
      } catch (e) {
        imageProvider = null;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _companyFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Perfil y Negocio',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Completa tus datos personales y los de tu negocio. Esto será visible en tus recibos y documentos.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 30),

            // Foto de perfil del negocio
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: imageProvider,
                    child: imageProvider == null
                        ? const Icon(Icons.store, size: 50, color: Colors.grey)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Colors.blue.shade700,
                      radius: 18,
                      child: IconButton(
                        icon: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 18,
                        ),
                        onPressed: isLoading ? null : _pickImage,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            CustomTextField(
              label: 'Tu Nombre Completo',
              controller: _userNameCtrl,
              icon: Icons.person,
            ),
            const SizedBox(height: 15),
            CustomTextField(
              label: 'Nombre Comercial',
              controller: _nameCtrl,
              icon: Icons.business,
            ),
            const SizedBox(height: 15),
            CustomTextField(
              label: 'NIT / Identificación (CC)',
              controller: _nitCtrl,
              icon: Icons.badge,
            ),
            const SizedBox(height: 15),
            CustomTextField(
              label: 'Eslogan o frase del negocio',
              controller: _sloganCtrl,
              icon: Icons.format_quote,
            ),
            const SizedBox(height: 15),
            CustomTextField(
              label: 'Dirección del negocio',
              controller: _addressCtrl,
              icon: Icons.location_on,
            ),
            const SizedBox(height: 15),
            CustomTextField(
              label: 'Teléfono de Contacto',
              controller: _phoneCtrl,
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 15),
            CustomTextField(
              label: 'Email de Contacto',
              controller: _emailCtrl,
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
            ),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : _saveCompanyStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Continuar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- PASO 2: CUENTAS ---
  Widget _buildAccountStep(bool isLoading) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tesorería Inicial',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Configura tus cuentas de efectivo y bancos.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 30),

          // Caja General (Principal) - Fija
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.star, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Caja General (Principal)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                const Text(
                  'Cuenta donde ingresarán tus ventas en efectivo por defecto.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 15),
                CustomTextField(
                  label: 'Saldo Inicial (Si tienes dinero en caja)',
                  controller: _mainAccountBalanceCtrl,
                  icon: Icons.attach_money,
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Lista de cuentas ADICIONALES agregadas
          if (_tempAccounts.length > 1) ...[
            const Text(
              'Cuentas adicionales:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Excluimos la primera cuenta (Caja General)
              itemCount: _tempAccounts.length - 1,
              itemBuilder: (context, idx) {
                final index = idx + 1;
                final acc = _tempAccounts[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    acc.isCash ? Icons.money : Icons.account_balance,
                    color: Colors.blue,
                  ),
                  title: Text(
                    acc.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Saldo inicial: ${CurrencyFormatter.format(acc.balance)}\n'
                    'Tipo: ${acc.isCash ? 'Efectivo' : 'Banco'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _tempAccounts.removeAt(index);
                      });
                    },
                  ),
                );
              },
            ),
            const Divider(height: 30),
          ],

          // Formulario para añadir nueva cuenta
          Form(
            key: _accountFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Añadir Otra Cuenta (Bancos / Más cajas)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text('Efectivo'),
                        value: true,
                        groupValue: _isCashAccount,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          if (val != null) setState(() => _isCashAccount = val);
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text('Banco'),
                        value: false,
                        groupValue: _isCashAccount,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          if (val != null) setState(() => _isCashAccount = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CustomTextField(
                  label: 'Nombre de la Cuenta / Banco',
                  controller: _accountNameCtrl,
                  icon: _isCashAccount
                      ? Icons.account_balance_wallet
                      : Icons.account_balance,
                ),
                const SizedBox(height: 15),
                CustomTextField(
                  label: 'Saldo Inicial',
                  controller: _accountBalanceCtrl,
                  icon: Icons.attach_money,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 15),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _addTempAccount,
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir a la lista'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          final notifier = ref.read(
                            setupWizardProvider.notifier,
                          );
                          notifier.previousStep();
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Atrás'),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  onPressed: isLoading ? null : _saveAccountStep,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Continuar',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveManualProduct() async {
    if (!_inventoryFormKey.currentState!.validate()) return;

    final notifier = ref.read(setupWizardProvider.notifier);
    final companyId = ref.read(companyIdProvider).value;

    // Custom validation
    bool hasError = false;
    for (var row in _productDrafts) {
      if (row.nameCtrl.text.trim().isEmpty) continue; // Skip empty rows

      if (row.priceCtrl.text.trim().isEmpty ||
          row.costCtrl.text.trim().isEmpty) {
        hasError = true;
      }
      if (!row.isService && row.stockCtrl.text.trim().isEmpty) {
        hasError = true;
      }
    }

    if (hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor completa los campos obligatorios (*).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    notifier.setLoading(true);

    try {
      final invRepo = ref.read(inventoryRepositoryProvider);
      final ImageService imageService = ImageService();

      List<Product> validProducts = [];
      Set<String> newCategories = {};

      for (var row in _productDrafts) {
        if (row.nameCtrl.text.trim().isNotEmpty &&
            row.priceCtrl.text.trim().isNotEmpty) {
          double price =
              double.tryParse(
                row.priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
              ) ??
              0.0;
          double cost = row.isService
              ? 0.0
              : (double.tryParse(
                      row.costCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
                    ) ??
                    0.0);
          int stock = row.isService
              ? 0
              : (int.tryParse(
                      row.stockCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
                    ) ??
                    0);
          int minStock = row.isService
              ? 0
              : (int.tryParse(
                      row.minStockCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
                    ) ??
                    0);
          String barcode = row.isService ? '' : row.barcodeCtrl.text.trim();
          String description = row.descriptionCtrl.text.trim();
          String category = row.categoryCtrl.text.trim();
          if (category.isEmpty) category = 'General';

          // Handle image upload
          String? imageUrl;
          if (row.imageFile != null && companyId != null) {
            // Generate a temporary ID or just use row ID
            String tempId = row.id;
            imageUrl = await imageService.uploadProductImage(
              row.imageFile!,
              tempId,
              companyId,
            );
          }

          validProducts.add(
            Product(
              id: '',
              name: row.nameCtrl.text.trim(),
              category: category,
              unit: row.isService ? 'Servicio' : 'Und',
              price: price,
              cost: cost,
              stock: stock,
              minStock: minStock,
              barcode: barcode,
              description: description,
              imageUrl: imageUrl,
              isService: row.isService,
            ),
          );

          if (category != 'General') newCategories.add(category);
        }
      }

      if (validProducts.isNotEmpty) {
        await invRepo.importProducts(validProducts); // Uses batch commit

        for (var cat in newCategories) {
          ref.read(productCategoriesProvider.notifier).add(cat);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${validProducts.length} productos guardados con éxito',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _completeSetup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      notifier.setLoading(false);
    }
  }

  // --- PASO 3: INVENTARIO ---
  Widget _buildInventoryStep(bool isLoading) {
    if (_showManualInventoryForm) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _inventoryFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () =>
                        setState(() => _showManualInventoryForm = false),
                  ),
                  const Text(
                    'Ingreso Rápido de Inventario',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  horizontalMargin: 0,
                  headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  columns: const [
                    DataColumn(label: Text('Foto')),
                    DataColumn(label: Text('Nombre *')),
                    DataColumn(label: Text('¿Servicio?')),
                    DataColumn(label: Text('Precio *')),
                    DataColumn(label: Text('Costo')),
                    DataColumn(label: Text('Stock')),
                    DataColumn(label: Text('Categoría')),
                    DataColumn(label: Text('')),
                  ],
                  rows: _productDrafts.map((row) {
                    final int idx = _productDrafts.indexOf(row);
                    return DataRow(
                      cells: [
                        DataCell(
                          InkWell(
                            onTap: () async {
                              final ImagePicker picker = ImagePicker();
                              final XFile? image = await picker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 50,
                                maxWidth: 500,
                              );
                              if (image != null) {
                                setState(() {
                                  row.imageFile = image;
                                });
                              }
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                                image: row.imageFile != null
                                    ? (kIsWeb
                                          ? DecorationImage(
                                              image: NetworkImage(
                                                row.imageFile!.path,
                                              ),
                                              fit: BoxFit.cover,
                                            )
                                          : DecorationImage(
                                              image: FileImage(
                                                File(row.imageFile!.path),
                                              ),
                                              fit: BoxFit.cover,
                                            ))
                                    : null,
                              ),
                              child: row.imageFile == null
                                  ? const Icon(
                                      Icons.camera_alt,
                                      size: 20,
                                      color: Colors.grey,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 150,
                            child: TextFormField(
                              controller: row.nameCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Ej. Camisa',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Switch(
                            value: row.isService,
                            onChanged: (val) {
                              setState(() {
                                row.isService = val;
                                if (val) {
                                  row.stockCtrl.text = '';
                                  row.costCtrl.text = '';
                                }
                              });
                            },
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              controller: row.priceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '\$ 0',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              controller: row.costCtrl,
                              keyboardType: TextInputType.number,
                              enabled: !row.isService,
                              decoration: InputDecoration(
                                hintText: '\$ 0',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                filled: row.isService,
                                fillColor: Colors.grey.shade200,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              controller: row.stockCtrl,
                              keyboardType: TextInputType.number,
                              enabled: !row.isService,
                              decoration: InputDecoration(
                                hintText: '0',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                filled: row.isService,
                                fillColor: Colors.grey.shade200,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              controller: row.minStockCtrl,
                              keyboardType: TextInputType.number,
                              enabled: !row.isService,
                              decoration: InputDecoration(
                                hintText: '0',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                filled: row.isService,
                                fillColor: Colors.grey.shade200,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              controller: row.barcodeCtrl,
                              enabled: !row.isService,
                              decoration: InputDecoration(
                                hintText: '12345',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                filled: row.isService,
                                fillColor: Colors.grey.shade200,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              controller: row.categoryCtrl,
                              decoration: const InputDecoration(
                                hintText: 'General',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 150,
                            child: TextFormField(
                              controller: row.descriptionCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Detalles...',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              if (_productDrafts.length > 1) {
                                setState(() {
                                  row.dispose();
                                  _productDrafts.removeAt(idx);
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 15),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _productDrafts.add(ProductDraftRow());
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Agregar otra fila'),
              ),

              const SizedBox(height: 40),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              setState(() => _showManualInventoryForm = false);
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Atrás'),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _saveManualProduct,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Guardar Productos y Finalizar',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Carga de Inventario',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            '¿Cómo te gustaría agregar tus productos?',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 30),

          _buildActionCard(
            icon: Icons.upload_file,
            title: 'Carga Masiva (Excel)',
            subtitle:
                'Importa tus productos rápidamente desde una plantilla Excel.',
            color: Colors.green.shade600,
            onTap: isLoading ? null : _importExcel,
          ),

          const SizedBox(height: 15),

          _buildActionCard(
            icon: Icons.add_box,
            title: 'Ingreso Manual',
            subtitle: 'Registra tus productos uno a uno de forma detallada.',
            color: Colors.blue.shade600,
            onTap: isLoading
                ? null
                : () {
                    setState(() => _showManualInventoryForm = true);
                  },
          ),

          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          final notifier = ref.read(
                            setupWizardProvider.notifier,
                          );
                          notifier.previousStep();
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Atrás'),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _completeSetup,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Finalizar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey.shade400,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
