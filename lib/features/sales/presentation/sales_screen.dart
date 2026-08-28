import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// Importamos las dos pantallas que irán adentro
import 'sales_history_screen.dart';
import 'accounts_receivable_screen.dart'; 
import '../../home/presentation/dashboard_shell.dart';

class SalesScreen extends StatefulWidget {
  final int initialIndex;
  const SalesScreen({super.key, this.initialIndex = 0});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2, 
      vsync: this, 
      initialIndex: widget.initialIndex // <--- EL CAMBIO IMPORTANTE
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    return Scaffold(
      appBar: AppBar(
        leading: isMobile ?IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            // Usamos el "Control Remoto" para abrir el menú principal
            DashboardShell.scaffoldKey.currentState?.openDrawer();
          },
        ): null,
        title: const Text('Gestión de Ventas'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color.fromARGB(255, 3, 3, 3),
          indicatorWeight: 3,
          labelColor: const Color.fromARGB(255, 0, 0, 0),
          unselectedLabelColor: const Color.fromARGB(153, 55, 123, 212),
          tabs: const [
            Tab(text: 'HISTORIAL', icon: Icon(Icons.history)),
            Tab(text: 'POR COBRAR', icon: Icon(Icons.account_balance_wallet)),
          ],
        ),
      ),
      // Solo mostramos el botón de "Nueva Venta" si estamos en la pestaña 1 (Historial)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/pos'), // O la ruta que uses para ir al POS
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Nueva Venta'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          // Pestaña 1: Tu historial de siempre
          SalesHistoryTab(), 
          // Pestaña 2: La nueva sección de cobros
          AccountsReceivableScreen(), 
        ],
      ),
    );
  }
}