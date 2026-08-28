import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../settings/data/settings_repository.dart'; 
import 'dashboard_provider.dart';
import 'dart:convert';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStreamProvider);
    final companyProfile = ref.watch(companyProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Un fondo gris-azulado muy moderno y limpio
      body: statsAsync.when(
        data: (stats) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER Y TARJETA FLOTANTE DE VENTAS
              _buildHeaderAndSales(context, stats, companyProfile),

              // ALERTA DE STOCK BAJO (Si existe)
              if (stats.lowStockCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: InkWell(
                    onTap: () => context.push('/reports'),
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade50, Colors.white],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                        boxShadow: [
                          BoxShadow(color: Colors.red.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                        ]
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.warning_rounded, color: Colors.red),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Alerta de Inventario", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                Text("${stats.lowStockCount} productos con stock bajo", style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.red),
                        ],
                      ),
                    ),
                  ),
                ),

              // ACCESOS RÁPIDOS
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text("Acciones Rápidas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF2D3748))),
              ),
              const SizedBox(height: 15),
              _buildQuickActions(context),

              const SizedBox(height: 30),

              // --- NUEVO BANNER DE CATÁLOGOS ---
              _buildCatalogBanner(context),

              const SizedBox(height: 30),

              // TARJETAS DE DEUDA
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text("Resumen de Cartera", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF2D3748))),
              ),
              const SizedBox(height: 15),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildDebtCard(
                        context, 
                        "Por Cobrar", 
                        stats.accountsReceivable, 
                        const Color(0xFF10B981), // Verde esmeralda moderno
                        Icons.arrow_downward_rounded,
                        '/history', 
                        targetTab: 1
                      )
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildDebtCard(
                        context,
                        "Por Pagar", 
                        stats.accountsPayable, 
                        const Color(0xFFEF4444), // Rojo vibrante moderno
                        Icons.arrow_upward_rounded,
                        '/expenses', 
                        targetTab: 1
                      )
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _buildWeeklyChart(context, stats.weeklySales),
              const SizedBox(height: 50),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _buildCatalogBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        onTap: () => context.push('/catalogs'), // Usa GoRouter
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Tonos violetas modernos
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
            ]
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Catálogo Digital", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    Text(
                      "Crea y comparte tu vitrina virtual con tus clientes en un solo clic.", 
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.storefront_outlined, color: Colors.white, size: 36),
              )
            ],
          ),
        ),
      ),
    );
  }

  // HEADER Y TARJETA SUPERPUESTA
  Widget _buildHeaderAndSales(BuildContext context, DashboardStats stats, AsyncValue companyProfile) {
    final profile = companyProfile.value;
    final companyName = profile?.name ?? 'Konta Gestor';
    final initial = companyName.isNotEmpty ? companyName[0].toUpperCase() : 'K';
    final bool isMobile = MediaQuery.of(context).size.width <= 800;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // 1. FONDO AZUL DEL HEADER
        Container(
          width: double.infinity,
          height: 240, // Altura fija para el fondo
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)], // Tonos azules premium
              begin: Alignment.topLeft, 
              end: Alignment.bottomRight
            ),
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                IconButton(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.topCenter,
                  icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
                const SizedBox(width: 10),
              ],
              
              // TEXTOS ALINEADOS A LA IZQUIERDA
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("¡Hola de nuevo!", style: TextStyle(color: Colors.blue.shade100, fontSize: 15, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(companyName, 
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // FOTO DE PERFIL A LA DERECHA
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white24,
                  backgroundImage: (profile?.imageBase64 != null && profile!.imageBase64!.isNotEmpty)
                      ? MemoryImage(base64Decode(profile.imageBase64!))
                      : null,
                  child: (profile?.imageBase64 == null || profile!.imageBase64!.isEmpty)
                      ? Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22))
                      : null,
                ),
              )
            ],
          ),
        ),

        // 2. TARJETA FLOTANTE DE VENTAS
        Padding(
          padding: const EdgeInsets.only(top: 150), // La empujamos hacia abajo para que se monte en el borde
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.blue.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))
              ]
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.trending_up, color: Colors.green, size: 16),
                        ),
                        const SizedBox(width: 8),
                        const Text("Ventas de Hoy", style: TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      CurrencyFormatter.format(stats.salesToday), 
                      style: const TextStyle(color: Color(0xFF1E293B), fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)
                    ),
                  ],
                ),
                // Gráfico o ícono decorativo (¡Ahora es un botón de Ventas!)
                Material(
                  color: Colors.blue.shade50,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    // AQUÍ PONES LA RUTA DE TU PANTALLA DE VENTAS (Ej: '/pos', '/sales', '/new-sale')
                    onTap: () => context.push('/pos'), 
                    child: SizedBox(
                      height: 60,
                      width: 60,
                      child: Icon(Icons.point_of_sale, color: Colors.blue.shade600, size: 30),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
        children: [
          _ActionButton(
            icon: Icons.inventory_2_rounded, 
            label: "Inventario", 
            color: const Color(0xFF8B5CF6), // Violeta moderno
            onTap: () => context.push('/inventory') 
          ),
          _ActionButton(
            icon: Icons.people_alt_rounded, 
            label: "Contactos", 
            color: const Color(0xFFF59E0B), // Naranja moderno
            onTap: () => context.push('/clients')
          ),
          _ActionButton(
            icon: Icons.bar_chart_rounded, 
            label: "Reportes", 
            color: const Color(0xFF3B82F6), // Azul moderno
            onTap: () => context.push('/reports')
          ),
          _ActionButton(
            icon: Icons.account_balance_outlined, 
            label: "Tesorería", 
            color: const Color(0xFF10B981), // Verde Esmeralda
            onTap: () => context.push('/finance') 
          ),
        ],
      ),
    );
  }

  Widget _buildDebtCard(BuildContext context, String title, double amount, Color color, IconData icon, String route, {int targetTab = 0}) {
    return InkWell(
      onTap: () => context.push(route, extra: targetTab),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))
          ]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 5),
            Text(
              CurrencyFormatter.format(amount), 
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5)
            ),
          ],
        ),
      ),
    );
  }
}

  // --- GRÁFICO DE BARRAS (CONECTADO A BD) ---
  Widget _buildWeeklyChart(BuildContext context, List<Map<String, dynamic>> weeklyData) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))
          ]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Actividad de la Semana", 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF2D3748))
            ),
            const SizedBox(height: 5),
            Text(
              "Toca una barra para ver el valor exacto", 
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)
            ),
            const SizedBox(height: 25),
            
            // Contenedor de las barras
            SizedBox(
              height: 140, 
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: weeklyData.map((data) {
                  final bool isToday = data['isToday'] as bool; // Validamos usando la variable de BD
                  final double amount = data['amount'] as double;
                  
                  // Formateo resumido (Ej: 450000 -> 450k,  1500000 -> 1.5M)
                  String shortValue = '';
                  if (amount > 0) {
                     shortValue = amount >= 1000000 
                        ? '${(amount / 1000000).toStringAsFixed(1)}M' 
                        : '${(amount / 1000).toStringAsFixed(0)}k';
                  } else {
                     shortValue = '0'; // Si es 0 ventas, mostramos un pequeño 0
                  }

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // TEXTO RESUMIDO ENCIMA DE LA BARRA
                      Text(
                        shortValue,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isToday ? const Color(0xFF3B82F6) : Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(height: 6),
                      
                      // BARRA INTERACTIVA
                      Tooltip(
                        message: 'Ventas del día: ${CurrencyFormatter.format(amount)}',
                        triggerMode: TooltipTriggerMode.tap, 
                        preferBelow: false, 
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B), 
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        child: Container(
                          width: 32, 
                          // Altura mínima garantizada para que se vea un puntito gris si hubo 0 ventas
                          height: amount == 0 ? 5 : 90 * (data['value'] as double), 
                          decoration: BoxDecoration(
                            color: isToday ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 10),
                      // TEXTO DEL DÍA ABAJO
                      Text(
                        data['day'], 
                        style: TextStyle(
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: isToday ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
                          fontSize: 12
                        )
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  class _ActionButton extends StatelessWidget {
    final IconData icon;
    final String label;
    final Color color;
    final VoidCallback onTap;

    const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20), // Squircles (cuadrados redondeados)
          elevation: 0,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 75,
              width: 75,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 5))
                ]
              ),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle
                ),
                child: Icon(icon, color: color, size: 30),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
      ],
    );
  }
}