import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  // Configuración del controlador para v7.x
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
    // Si necesitas ajustar la cámara por defecto:
    // cameraResolution: const Size(1280, 720),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear Código'),
        actions: [
          // BOTÓN FLASH (Corregido v7)
          // Escuchamos al 'controller' completo, que ahora contiene el estado
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: controller,
            builder: (context, state, child) {
              // Accedemos a torchState desde el estado global
              final isTorchOn = state.torchState == TorchState.on;
              
              return IconButton(
                icon: Icon(isTorchOn ? Icons.flash_on : Icons.flash_off),
                onPressed: () => controller.toggleTorch(),
              );
            },
          ),
          
          // BOTÓN CAMBIAR CÁMARA (Corregido v7)
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: controller,
            builder: (context, state, child) {
              // Accedemos a cameraDirection desde el estado global
              final isFront = state.cameraDirection == CameraFacing.front;
              
              return IconButton(
                icon: Icon(isFront ? Icons.camera_front : Icons.camera_rear),
                onPressed: () => controller.switchCamera(),
              );
            },
          ),
        ],
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (BarcodeCapture capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              // AL DETECTAR: Cerramos la pantalla y devolvemos el código
              context.pop(barcode.rawValue); 
              break; 
            }
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}