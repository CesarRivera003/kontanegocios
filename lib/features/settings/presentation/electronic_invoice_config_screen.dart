import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/auth_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class ElectronicInvoiceConfigScreen extends ConsumerStatefulWidget {
  const ElectronicInvoiceConfigScreen({super.key});

  @override
  ConsumerState<ElectronicInvoiceConfigScreen> createState() => _ElectronicInvoiceConfigScreenState();
}

class _ElectronicInvoiceConfigScreenState extends ConsumerState<ElectronicInvoiceConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controladores (Se eliminó apiKeyCtrl para el modelo de reventa)
  final TextEditingController _prefixCtrl = TextEditingController();
  final TextEditingController _resolutionCtrl = TextEditingController();
  
  bool _isTestEnv = true;
  bool _isLoading = true;
  bool _isSaving = false;

  int _monthlyUsed = 0;
  final int _monthlyLimit = 100;
  int _extraBalance = 0;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final companyId = ref.read(companyIdProvider).value;
    if (companyId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('companies').doc(companyId)
          .collection('config').doc('fe_config')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _prefixCtrl.text = data['prefix'] ?? '';
        _resolutionCtrl.text = data['resolutionNumber'] ?? '';
        _isTestEnv = data['isTestEnvironment'] ?? true;
        _monthlyUsed = data['monthlyUsed'] ?? 0;
        _extraBalance = data['extraBalance'] ?? 0;
      }
    } catch (e) {
      debugPrint("Error cargando config FE: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final companyId = ref.read(companyIdProvider).value;
    
    try {
      await FirebaseFirestore.instance
          .collection('companies').doc(companyId)
          .collection('config').doc('fe_config')
          .set({
        'prefix': _prefixCtrl.text.trim().toUpperCase(),
        'resolutionNumber': _resolutionCtrl.text.trim(),
        'isTestEnvironment': false, // 🟢 <-- Cambiado a false fijo para el cliente final
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Datos de la DIAN guardados'), backgroundColor: Colors.green));
        FocusScope.of(context).unfocus();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _buyExtraPackage(String packageId, int amount, double price) async {
    final companyId = ref.read(companyIdProvider).value;
    if (companyId == null) return;

    // 1. TU LLAVE PÚBLICA DE WOMPI (TEST)
    const String wompiPubKey = "pub_test_h1RQ72f6N14rK8tbrMoKFBAltSGEeNwS";
    
    // 2. PREPARAR EL PRECIO EN CENTAVOS
    final int amountInCents = (price * 100).toInt(); 
    
    // 3. LA REFERENCIA MÁGICA (Ej: PKG-50_abc123xyz_1715629200000)
    final String uniqueReference = "${packageId}_${companyId}_${DateTime.now().millisecondsSinceEpoch}";

    // 4. URL DE RETORNO
    const String redirectUrl = "https://kontanegocios.com"; 
    
    final Uri wompiUrl = Uri.parse(
      "https://checkout.wompi.co/p/"
      "?public-key=$wompiPubKey"
      "&currency=COP"
      "&amount-in-cents=$amountInCents"
      "&reference=$uniqueReference"
      "&redirect-url=$redirectUrl"
    );

    try {
      if (await canLaunchUrl(wompiUrl)) {
        await launchUrl(wompiUrl, mode: LaunchMode.externalApplication); 
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir la pasarela'), backgroundColor: Colors.red));
      }
    } catch (e) {
      debugPrint("Error abriendo Wompi: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text("Gestión Factura Electrónica")),
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUsageDashboard(),
            const SizedBox(height: 30),
            _buildExtraPackages(),
            const SizedBox(height: 30),
            _buildTechnicalConfig(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageDashboard() {
    double progress = _monthlyUsed / _monthlyLimit;
    if (progress > 1.0) progress = 1.0;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Tu consumo este mes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Plan 100 Facturas"),
              Text("$_monthlyUsed / $_monthlyLimit", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress, backgroundColor: Colors.grey[200], color: Colors.indigo, minHeight: 10, borderRadius: BorderRadius.circular(5)),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Saldo Prepago Extra:", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("$_extraBalance Facturas", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildExtraPackages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Paquetes de Facturas Extra", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            // Precios calculados a 500 por factura
            Expanded(child: _packageCard(title: "+50", price: 25000, id: 'PKG-50')),
            const SizedBox(width: 8),
            Expanded(child: _packageCard(title: "+200", price: 100000, id: 'PKG-200', isPopular: true)),
            const SizedBox(width: 8),
            Expanded(child: _packageCard(title: "+500", price: 250000, id: 'PKG-500')),
          ],
        ),
        const SizedBox(height: 15),
        // Mensaje para pedidos grandes
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
          child: const Text(
            "📧 Si requieres más de 500 facturas, escribe a servicioalcliente@kontanegocios.com y te daremos precios especiales.",
            style: TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _packageCard({required String title, required double price, required String id, bool isPopular = false}) {
    // Formateador de moneda profesional sin decimales (Ej: $25.000)
    final formattedPrice = "\$${price.toInt().toString().replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), '.')}";

    return InkWell(
      // 1. Toda la tarjeta ahora responde al toque
      onTap: () => _buyExtraPackage(id, int.parse(title.replaceAll('+', '')), price),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.only(top: 20, bottom: 15, left: 10, right: 10),
        decoration: BoxDecoration(
          color: isPopular ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isPopular ? Colors.indigo : Colors.grey.shade300, width: 2),
          // Sombra sutil para el paquete popular para que resalte más
          boxShadow: isPopular ? [const BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))] : null,
        ),
        child: Column(
          children: [
            // 2. Textos mucho más grandes y legibles
            Text(title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isPopular ? Colors.white : Colors.indigo)),
            Text("Facturas", style: TextStyle(fontSize: 14, color: isPopular ? Colors.indigo.shade100 : Colors.grey[600])),
            const SizedBox(height: 15),
            
            // 3. Precio formateado correctamente
            Text(formattedPrice, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isPopular ? Colors.amberAccent : Colors.black87)),
            const SizedBox(height: 15),
            
            // 4. Botón gigante y con alto contraste
            SizedBox(
              width: double.infinity, // Ocupa todo el ancho disponible
              child: ElevatedButton(
                onPressed: () => _buyExtraPackage(id, int.parse(title.replaceAll('+', '')), price), 
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPopular ? Colors.amber : Colors.indigo.shade50,
                  foregroundColor: isPopular ? Colors.indigo.shade900 : Colors.indigo,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                ),
                child: const Text("COMPRAR", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalConfig() {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Configuración de la DIAN", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 30),
            
            // --- GUÍA PARA EL USUARIO ---
            _buildDianGuide(),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: TextFormField(
                  controller: _prefixCtrl, 
                  decoration: const InputDecoration(labelText: "Prefijo (Ej: FE)", border: OutlineInputBorder(), hintText: "Ej: SETT"),
                  validator: (v) => v!.isEmpty ? 'Obligatorio' : null,
                )),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: TextFormField(
                  controller: _resolutionCtrl, 
                  decoration: const InputDecoration(labelText: "No. Resolución", border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (v) => v!.isEmpty ? 'Obligatorio' : null,
                )),
              ],
            ),
            const SizedBox(height: 20),
            
            // 🟢 NUEVO: Letrero informativo fijo en lugar del switch de pruebas
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50, 
                borderRadius: BorderRadius.circular(8), 
                border: Border.all(color: Colors.green.shade300)
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.green, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Producción Activa. Al guardar, tus facturas se emitirán con total validez legal ante la DIAN.", 
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)
                    )
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: _isSaving ? null : _saveConfig,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.indigo),
              child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("GUARDAR DATOS", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDianGuide() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [Icon(Icons.help_center, size: 18, color: Colors.blue), SizedBox(width: 5), Text("¿Cómo obtengo estos datos?", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))],
          ),
          const SizedBox(height: 8),
          _guideItem("1", "Entra al portal MUISCA de la DIAN."),
          _guideItem("2", "Busca 'Numeración de Facturación' > 'Solicitar Numeración'."),
          _guideItem("3", "En tu documento PDF oficial de la DIAN, el 'Prefijo' son las letras iniciales y el 'No. Resolución' es el número largo de 18 dígitos."),
        ],
      ),
    );
  }

  Widget _guideItem(String step, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$step. ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }
}