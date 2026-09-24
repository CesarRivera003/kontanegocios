import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/network_connectivity_service.dart';
import '../../core/services/sync_queue_service.dart';

class NetworkStatusBanner extends ConsumerWidget {
  const NetworkStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netStatus = ref.watch(networkConnectivityProvider);
    final syncState = ref.watch(syncQueueServiceProvider);

    final bool isOffline = netStatus == NetworkStatus.offline;
    final bool isSyncing = syncState.status == SyncStatus.syncing;
    final bool isSuccess = syncState.status == SyncStatus.success || netStatus == NetworkStatus.restored;

    // Solo se muestra si estamos offline, sincronizando o confirmando éxito
    final bool isVisible = isOffline || isSyncing || (isSuccess && syncState.message != null);

    Color bgColor = const Color(0xFFE65100); // Naranja (offline)
    IconData icon = Icons.cloud_off_rounded;
    String message = 'Modo sin conexión activo • Las ventas se guardan localmente';

    if (isSyncing) {
      bgColor = const Color(0xFF1565C0); // Azul progreso
      icon = Icons.sync_rounded;
      message = syncState.message ?? 'Sincronizando ventas pendientes...';
    } else if (isSuccess && syncState.message != null) {
      bgColor = const Color(0xFF2E7D32); // Verde éxito
      icon = Icons.cloud_done_rounded;
      message = syncState.message!;
    }

    return AnimatedCrossFade(
      firstChild: const SizedBox(width: double.infinity, height: 0),
      secondChild: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        decoration: BoxDecoration(
          color: bgColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSyncing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            else
              Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
      crossFadeState: isVisible ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 300),
    );
  }
}