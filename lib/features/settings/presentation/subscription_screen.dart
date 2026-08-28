import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart'; // <-- NUEVO: Para abrir Wompi

import '../../auth/presentation/auth_providers.dart'; 
import '../data/settings_repository.dart'; 
import '../data/subscription_provider.dart'; 
import 'package:go_router/go_router.dart';
import '../domain/company_model.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  final TextEditingController _referralCtrl = TextEditingController();
  bool _isRedeeming = false;

  @override
  void dispose() {
    _referralCtrl.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Código copiado al portapapeles'), backgroundColor: Colors.green),
    );
  }

  Future<void> _applyReferralCode() async {
    final code = _referralCtrl.text.trim();
    if (code.isEmpty) return;

    setState(() => _isRedeeming = true);
    FocusScope.of(context).unfocus();

    try {
      final myCompanyId = ref.read(companyIdProvider).value; 
      if (myCompanyId == null) throw Exception("Error de sesión");

      await ref.read(subscriptionRepositoryProvider).applyReferralCode(myCompanyId, code);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 ¡Éxito! Has recibido 15 días extra.'), backgroundColor: Colors.green),
        );
        _referralCtrl.clear();
      }
    } catch (e) {
      debugPrint("❌ ERROR DE FIREBASE: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.orange),
        );
      }
    } finally {
      if (mounted) setState(() => _isRedeeming = false);
    }
  }

  Future<void> _payWithWompi(String companyId, String planId, double amountToPay) async {
    // 1. TU LLAVE PÚBLICA DE PRUEBAS
    const String wompiPubKey = "pub_test_h1RQ72f6N14rK8tbrMoKFBAltSGEeNwS";
    
    // Wompi exige el valor en centavos
    final int amountInCents = (amountToPay * 100).toInt(); 
    
    // 2. LA REFERENCIA DINÁMICA (Ej: PRO-MENSUAL_abc123_17123123)
    // El backend leerá esto para saber qué plan dar y a quién
    final String uniqueReference = "${planId}_${companyId}_${DateTime.now().millisecondsSinceEpoch}";

    // 3. URL DE REDIRECCIÓN (A dónde vuelve cuando termine de pagar)
    final String redirectUrl = "https://kontanegocios.com"; 
    
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir la pasarela')));
      }
    } catch (e) {
      debugPrint("Error abriendo pasarela: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(companyProfileProvider);
    final realCompanyId = ref.watch(companyIdProvider).value;
    
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text("Error cargando perfil: $err")),
        data: (companyData) {
          if (companyData == null) return const Center(child: Text("No hay datos de empresa"));

          final myCode = companyData.referralCode.isNotEmpty ? companyData.referralCode : 'GENERANDO...';
          final hasUsedCode = companyData.referredBy != null && companyData.referredBy!.isNotEmpty;
          
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 120.0,
                floating: false,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text("Tu Suscripción", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2C2F33), Color(0xFF121212)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 20.0, top: 20),
                        child: Icon(Symbols.workspace_premium, size: 80, color: Color.fromARGB(255, 240, 197, 5)),
                      ),
                    ),
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/dashboard'); 
                    }
                  },
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusCard(companyData),
                      const SizedBox(height: 20),
                      const Text("🎁 Gana meses gratis", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      _buildReferralCard(myCode, hasUsedCode),
                      const SizedBox(height: 30),
                      if (realCompanyId != null) 
                        _buildRenewalSection(realCompanyId, companyData.subscriptionStatus),
                      const Text("🚀 Explorar otros planes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (realCompanyId != null) 
                        _buildPremiumPlans(realCompanyId),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              )
            ],
          );
        }
      ),
    );
  }

  Widget _buildStatusCard(CompanyProfile profile) {
    final status = profile.subscriptionStatus;
    final referrals = profile.referralCount;
    final sales = profile.currentMonthSales;
    final maxSales = 4000000.0; // Límite de 4.0M
    
    final isTimeExpired = profile.trialEndsAt != null && profile.trialEndsAt!.isBefore(DateTime.now());
    int daysLeft = profile.trialEndsAt != null ? profile.trialEndsAt!.difference(DateTime.now()).inDays : 0;
    if (daysLeft < 0) daysLeft = 0;

    // --- NUEVO: Widget para mostrar la fecha del próximo cobro ---
    Widget buildNextBillingWidget() {
      if (profile.trialEndsAt != null) {
        final fecha = "${profile.trialEndsAt!.day}/${profile.trialEndsAt!.month}/${profile.trialEndsAt!.year}";
        return Column(
          children: [
            const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider()),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_month, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  "Próximo cobro: $fecha", 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)
                ),
              ],
            )
          ],
        );
      }
      return const SizedBox.shrink();
    }

    if (status == 'empresarial') {
      return _buildCardBase(
        color: Colors.indigo, icon: Symbols.domain, title: "Plan Empresarial Activo",
        subtitle: "Acceso total con Facturación Electrónica DIAN y funciones corporativas.",
        child: buildNextBillingWidget(), // <-- APLICADO AQUÍ
      );
    }

    if (status == 'pro' || status == 'active') {
      return _buildCardBase(
        color: Colors.amber, icon: Symbols.workspace_premium, title: "Plan Pro Activo",
        subtitle: "Acceso total sin límites y múltiples usuarios.",
        child: buildNextBillingWidget(), // <-- APLICADO AQUÍ
      );
    }

    if (status == 'lifetime') {
      return _buildCardBase(
        color: Colors.purple, icon: Symbols.diamond, title: "VIP Vitalicio",
        subtitle: "Cuenta de cortesía con acceso total ilimitado a Konta Gestor.",
      );
    }

    final isFreemium = (referrals >= 2 && sales < maxSales) || status == 'freemium';
    if (isFreemium) {
      final salesProgress = sales / maxSales;
      return _buildCardBase(
        color: Colors.blue, icon: Symbols.handshake, title: "Plan Emprendedor (Gratis)",
        subtitle: "Acceso gratis por invitar amigos.",
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider()),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Ventas de este mes", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("\$${sales.toStringAsFixed(0)} / \$4.0M", style: TextStyle(color: salesProgress > 0.8 ? Colors.red : Colors.blue, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: salesProgress > 1.0 ? 1.0 : salesProgress,
              backgroundColor: Colors.grey[200],
              color: salesProgress > 0.8 ? Colors.red : Colors.blue,
              minHeight: 10, borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 8),
            const Text("El límite se reiniciará a cero el día 1 del próximo mes.", style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center)
          ],
        ),
      );
    }

    if (!isTimeExpired) {
      return _buildCardBase(
        color: Colors.orange, icon: Symbols.timer, title: "Periodo de Prueba",
        subtitle: "Te quedan $daysLeft días",
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider()),
            _buildReferralProgressBar(referrals),
          ],
        ),
      );
    }

    String blockReason = (referrals >= 2 && sales >= maxSales) 
        ? "¡Has superado el límite de ventas de \$4.0M este mes! Pásate a Premium para seguir facturando."
        : "Tu periodo de prueba ha expirado. Ingresa un código de invitado o pásate a Premium.";

    return _buildCardBase(
      color: Colors.red, icon: Symbols.block, title: "Suscripción Pausada",
      subtitle: blockReason, subtitleColor: Colors.red.shade700,
    );
  }
  
  Widget _buildCardBase({required Color color, required IconData icon, required String title, required String subtitle, Color? subtitleColor, Widget? child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
        border: Border.all(color: color.withOpacity(0.5), width: 2), 
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          Text(subtitle, style: TextStyle(fontSize: 14, color: subtitleColor ?? Colors.grey[700]), textAlign: TextAlign.center),
          if (child != null) child,
        ],
      ),
    );
  }

  Widget _buildReferralProgressBar(int referrals) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Plan Emprendedor (Gratis)", style: TextStyle(fontWeight: FontWeight.bold)),
            Text("$referrals/2 Amigos", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: referrals >= 2 ? 1.0 : (referrals / 2), 
          backgroundColor: Colors.grey[200], color: Colors.blue, minHeight: 8, borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        const Text("Invita a 2 amigos para usar la app gratis (límite mensual: \$4.0M).", style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center)
      ],
    );
  }

  Widget _buildReferralCard(String myCode, bool hasUsedCode) {
    return Card(
      elevation: 0,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("Comparte tu código y ambos reciben días extra cuando tu amigo se registre.", textAlign: TextAlign.center),
            const SizedBox(height: 15),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(myCode, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.indigo)),
                  IconButton(
                    icon: const Icon(Symbols.content_copy, color: Colors.indigo),
                    onPressed: () => _copyToClipboard(myCode),
                    tooltip: 'Copiar código',
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (!hasUsedCode) ...[
              const Divider(),
              const SizedBox(height: 10),
              const Text("¿Te invitó un amigo?", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _referralCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ingresa su código',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isRedeeming ? null : _applyReferralCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                    ),
                    child: _isRedeeming 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Canjear"),
                  )
                ],
              )
            ] else ...[
               const Text("✅ Ya ingresaste un código de invitado", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildRenewalSection(String companyId, String currentStatus) {
    // Si es un usuario de prueba o gratis, no mostramos esto, los dejamos ver la lista normal
    if (currentStatus != 'empresarial' && currentStatus != 'pro') {
      return const SizedBox.shrink(); 
    }

    // Identificamos cuál es su plan actual para adaptar los botones
    final isEmpresarial = currentStatus == 'empresarial';
    final planName = isEmpresarial ? 'Empresarial' : 'Pro';
    final monthlyId = isEmpresarial ? 'EMPRESARIAL-MENSUAL' : 'PRO-MENSUAL';
    final annualId = isEmpresarial ? 'EMPRESARIAL-ANUAL' : 'PRO-ANUAL';
    final monthlyPrice = isEmpresarial ? 89900.0 : 49900.0;
    final annualPrice = isEmpresarial ? 809100.0 : 499000.0;

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 30),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade200, width: 2),
      ),
      child: Column(
        children: [
          const Icon(Icons.autorenew, size: 40, color: Colors.indigo),
          const SizedBox(height: 10),
          Text("Renovar tu Plan $planName", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text("Mantén tu acceso activo sin interrupciones. Elige por cuánto tiempo deseas renovar:", textAlign: TextAlign.center, style: TextStyle(color: Colors.black87)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _payWithWompi(companyId, monthlyId, monthlyPrice),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.indigo, width: 2),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.indigo,
                  ),
                  child: const Text("Por 1 Mes", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _payWithWompi(companyId, annualId, annualPrice),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  child: const Text("Por 1 Año", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPremiumPlans(String companyId) {
    return Column(
      children: [
        _buildPlanCard(
          title: "Plan Pro", subtitle: "Acceso total sin límites y multiples usuarios",
          price: "\$49.900", period: "/mes", icon: Symbols.storefront, color: Colors.black87, isPopular: false,
          onTap: () => _payWithWompi(companyId, 'PRO-MENSUAL', 49900.0), // <- APLICADO
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          title: "Plan Empresarial", subtitle: "Todo lo del Plan Pro + Facturación Electrónica Dian",
          price: "\$89.900", period: "/mes", icon: Symbols.domain, color: Colors.black87, isPopular: false,
          onTap: () => _payWithWompi(companyId, 'EMPRESARIAL-MENSUAL', 89900.0), // <- APLICADO
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          title: "Plan Pro Anual", subtitle: "Ahorras 2 meses gratis",
          price: "\$499.000", period: "/año", icon: Symbols.star, color: Colors.white, isPopular: true, isDarkTheme: true,
          onTap: () => _payWithWompi(companyId, 'PRO-ANUAL', 499000.0), // <- APLICADO
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          title: "Plan Empresarial Anual", subtitle: "Ahorras 3 meses gratis",
          price: "\$809.100", period: "/año", icon: Symbols.corporate_fare, color: Colors.black87, isPopular: false,
          onTap: () => _payWithWompi(companyId, 'EMPRESARIAL-ANUAL', 809100.0), // <- APLICADO
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String subtitle,
    required String price,
    required String period,
    required IconData icon,
    required Color color,
    required bool isPopular,
    required VoidCallback onTap,
    bool isDarkTheme = false,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDarkTheme ? null : Colors.white,
            gradient: isDarkTheme ? const LinearGradient(colors: [Color(0xFF2C2F33), Color(0xFF121212)]) : null,
            borderRadius: BorderRadius.circular(16),
            border: isDarkTheme ? null : Border.all(color: Colors.grey.shade300),
            boxShadow: isDarkTheme ? const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))] : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: Icon(icon, size: 36, color: isDarkTheme ? Colors.amber : color),
            title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDarkTheme ? Colors.white : Colors.black87)),
            subtitle: Text(subtitle, style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.grey.shade600)),
            trailing: Text("$price\n$period", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDarkTheme ? Colors.greenAccent : Colors.black87)),
            onTap: onTap,
          ),
        ),
        if (isPopular)
          Positioned(
            top: -10,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(20)),
              child: const Text("MÁS POPULAR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
          )
      ],
    );
  }
}