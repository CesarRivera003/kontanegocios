import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';

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

  // Paso 1: Empresa
  final _companyFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _nitCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Paso 2: Cuentas
  final _accountFormKey = GlobalKey<FormState>();
  final _accountNameCtrl = TextEditingController(text: 'Caja General');
  final _accountBalanceCtrl = TextEditingController(text: '0');

  bool _initializedCompanyFields = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _nitCtrl.dispose();
    _phoneCtrl.dispose();
    _accountNameCtrl.dispose();
    _accountBalanceCtrl.dispose();
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

  Future<void> _saveCompanyStep() async {
    if (!_companyFormKey.currentState!.validate()) return;

    final notifier = ref.read(setupWizardProvider.notifier);
    notifier.setLoading(true);
    try {
      final repository = ref.read(settingsRepositoryProvider);
      if (repository != null) {
        await repository.updateCompanyProfileData({
          'name': _nameCtrl.text.trim(),
          'nit': _nitCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
        });
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

  Future<void> _saveAccountStep() async {
    if (!_accountFormKey.currentState!.validate()) return;

    final notifier = ref.read(setupWizardProvider.notifier);
    notifier.setLoading(true);
    try {
      final userId = ref.read(companyIdProvider).value;
      if (userId != null) {
        final financeRepo = FinanceRepository(
          FirebaseFirestore.instance,
          userId,
        );

        // Convert to double safely
        String balanceText = _accountBalanceCtrl.text.replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );
        double initialBalance = double.tryParse(balanceText) ?? 0.0;

        final account = BankAccount(
          id: '',
          name: _accountNameCtrl.text.trim(),
          balance: initialBalance,
          isCash: true,
          isDefault: true,
        );

        await financeRepo.createAccount(account);
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
      if (_phoneCtrl.text.isEmpty && currentProfile.phone.isNotEmpty)
        _phoneCtrl.text = currentProfile.phone;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _companyFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Datos de tu Negocio',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Ingresa la información básica de tu empresa. Esto aparecerá en tus recibos.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 30),

            CustomTextField(
              label: 'Nombre Comercial',
              controller: _nameCtrl,
              icon: Icons.business,
            ),
            const SizedBox(height: 15),
            CustomTextField(
              label: 'NIT / Identificación',
              controller: _nitCtrl,
              icon: Icons.badge,
            ),
            const SizedBox(height: 15),
            CustomTextField(
              label: 'Teléfono Contacto',
              controller: _phoneCtrl,
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
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
      child: Form(
        key: _accountFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tesorería Inicial',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Configura tu cuenta de efectivo principal para empezar a registrar ventas y gastos.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 30),

            CustomTextField(
              label: 'Nombre de la Cuenta / Caja',
              controller: _accountNameCtrl,
              icon: Icons.account_balance_wallet,
            ),
            const SizedBox(height: 15),
            CustomTextField(
              label: 'Saldo Inicial',
              controller: _accountBalanceCtrl,
              icon: Icons.attach_money,
              keyboardType: TextInputType.number,
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
      ),
    );
  }

  // --- PASO 3: INVENTARIO ---
  Widget _buildInventoryStep(bool isLoading) {
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
                    context.push('/inventory/save');
                    _completeSetup();
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
