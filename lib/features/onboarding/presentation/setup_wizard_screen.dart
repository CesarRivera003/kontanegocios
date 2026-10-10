import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../settings/data/settings_repository.dart';
import '../../finance/data/finance_repository.dart';
import '../../finance/domain/finance_model.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/product_model.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import 'setup_wizard_providers.dart';

class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
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
  final _accountNameCtrl = TextEditingController(text: 'Caja General');
  final _accountBalanceCtrl = TextEditingController(text: '0');
  List<BankAccount> _tempAccounts = [];
  bool _isCashAccount = true;

  // Paso 3: Inventario manual
  final _inventoryFormKey = GlobalKey<FormState>();
  final _prodNameCtrl = TextEditingController();
  final _prodCategoryCtrl = TextEditingController(text: 'General');
  final _prodUnitCtrl = TextEditingController(text: 'und');
  final _prodPriceCtrl = TextEditingController();
  final _prodCostCtrl = TextEditingController();
  final _prodStockCtrl = TextEditingController();
  final _prodMinStockCtrl = TextEditingController();
  final _prodBarcodeCtrl = TextEditingController();
  final _prodDescriptionCtrl = TextEditingController();
  bool _prodHasCommission = false;
  bool _showManualInventoryForm = false; // Toggle manual form

  bool _initializedCompanyFields = false;

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
    _prodNameCtrl.dispose();
    _prodCategoryCtrl.dispose();
    _prodUnitCtrl.dispose();
    _prodPriceCtrl.dispose();
    _prodCostCtrl.dispose();
    _prodStockCtrl.dispose();
    _prodMinStockCtrl.dispose();
    _prodBarcodeCtrl.dispose();
    _prodDescriptionCtrl.dispose();
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
      if (currentUser != null && _userNameCtrl.text.trim().isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({'name': _userNameCtrl.text.trim()});
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

    // La primera cuenta creada será la default
    bool isDefault = _tempAccounts.isEmpty;

    final account = BankAccount(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // ID temporal
      name: _accountNameCtrl.text.trim(),
      balance: initialBalance,
      isCash: _isCashAccount,
      isDefault: isDefault,
    );

    setState(() {
      _tempAccounts.add(account);
      _accountNameCtrl.clear();
      _accountBalanceCtrl.text = '0';
    });
  }

  Future<void> _saveAccountStep() async {
    // Si no ha añadido cuentas y hay algo en el form, lo añadimos
    if (_tempAccounts.isEmpty && _accountNameCtrl.text.trim().isNotEmpty) {
      _addTempAccount();
    }

    final notifier = ref.read(setupWizardProvider.notifier);
    notifier.setLoading(true);

    try {
      final userId = ref.read(companyIdProvider).value;
      if (userId != null && _tempAccounts.isNotEmpty) {
        final financeRepo = FinanceRepository(
          FirebaseFirestore.instance,
          userId,
        );

        for (var acc in _tempAccounts) {
          // Remover ID temporal para que firebase lo genere
          final accountToSave = BankAccount(
            id: '',
            name: acc.name,
            balance: acc.balance,
            isCash: acc.isCash,
            isDefault: acc.isDefault,
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

    if (profileAsync.hasValue &&
        profileAsync.value != null &&
        !_initializedCompanyFields) {
      final currentProfile = profileAsync.value!;
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
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Omitir por ahora'),
          ),
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
            'Crea tus cuentas de efectivo y bancos. La primera que agregues se configurará como la principal por defecto para tus ventas en efectivo.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 30),

          // Lista de cuentas agregadas
          if (_tempAccounts.isNotEmpty) ...[
            const Text(
              'Cuentas configuradas:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _tempAccounts.length,
              itemBuilder: (context, index) {
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
                    'Tipo: ${acc.isCash ? 'Efectivo' : 'Banco'}'
                    '${acc.isDefault ? ' (Principal)' : ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _tempAccounts.removeAt(index);
                        // Re-asignar default si se borró la principal
                        if (acc.isDefault && _tempAccounts.isNotEmpty) {
                          _tempAccounts[0] = BankAccount(
                            id: _tempAccounts[0].id,
                            name: _tempAccounts[0].name,
                            balance: _tempAccounts[0].balance,
                            isCash: _tempAccounts[0].isCash,
                            isDefault: true,
                          );
                        }
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
                Text(
                  _tempAccounts.isEmpty
                      ? 'Añadir Primera Cuenta'
                      : 'Añadir Otra Cuenta',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
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
                  onPressed: isLoading ? null : _skipStep,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Omitir'),
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
    notifier.setLoading(true);

    try {
      final invRepo = ref.read(inventoryRepositoryProvider);

      double price =
          double.tryParse(
            _prodPriceCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          0.0;
      double cost =
          double.tryParse(
            _prodCostCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          0.0;
      int stock =
          int.tryParse(_prodStockCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
          0;
      int minStock =
          int.tryParse(
            _prodMinStockCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          0;

      final product = Product(
        id: '',
        name: _prodNameCtrl.text.trim(),
        category: _prodCategoryCtrl.text.trim(),
        unit: _prodUnitCtrl.text.trim(),
        price: price,
        cost: cost,
        stock: stock,
        minStock: minStock,
        barcode: _prodBarcodeCtrl.text.trim(),
        description: _prodDescriptionCtrl.text.trim(),
        hasCommission: _prodHasCommission,
      );

      await invRepo.addProduct(product);

      // Update categories provider just in case
      if (product.category.isNotEmpty) {
        ref.read(productCategoriesProvider.notifier).add(product.category);
      }
      if (product.unit.isNotEmpty) {
        ref.read(productUnitsProvider.notifier).add(product.unit);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Producto guardado con éxito'),
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
                    'Crear Producto Manual',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              CustomTextField(
                label: 'Nombre del Producto *',
                controller: _prodNameCtrl,
                icon: Icons.inventory,
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      label: 'Categoría *',
                      controller: _prodCategoryCtrl,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CustomTextField(
                      label: 'Unidad *',
                      controller: _prodUnitCtrl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      label: 'Precio Venta *',
                      controller: _prodPriceCtrl,
                      icon: Icons.attach_money,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CustomTextField(
                      label: 'Costo *',
                      controller: _prodCostCtrl,
                      icon: Icons.money_off,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      label: 'Stock Actual *',
                      controller: _prodStockCtrl,
                      icon: Icons.layers,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CustomTextField(
                      label: 'Alerta Min. Stock',
                      controller: _prodMinStockCtrl,
                      icon: Icons.warning_amber,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              CustomTextField(
                label: 'Código de Barras',
                controller: _prodBarcodeCtrl,
                icon: Icons.qr_code,
              ),
              const SizedBox(height: 15),
              CustomTextField(
                label: 'Descripción',
                controller: _prodDescriptionCtrl,
                icon: Icons.description,
                maxLines: 2,
              ),
              const SizedBox(height: 15),
              SwitchListTile(
                title: const Text('¿Genera comisión?'),
                value: _prodHasCommission,
                onChanged: (val) => setState(() => _prodHasCommission = val),
              ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _saveManualProduct,
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
                          'Guardar y Finalizar',
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
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: isLoading ? null : _completeSetup,
              child: const Text(
                'Dejar para más tarde / Finalizar',
                style: TextStyle(fontSize: 16),
              ),
            ),
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
