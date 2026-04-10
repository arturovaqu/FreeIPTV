import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/qr_service.dart';
import '../utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// QrScannerScreen
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen QR scanner.
///
/// Pops with a `({String url, String name})` record on success, or `null` if
/// the user cancelled.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _detected = false; // guard against multiple detections
  String? _errorMsg;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Detection callback ─────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;

    final raw = capture.barcodes
        .where((b) => b.rawValue != null && b.rawValue!.isNotEmpty)
        .map((b) => b.rawValue!)
        .firstOrNull;

    if (raw == null) return;

    final result = QrService.instance.decode(raw);
    if (result == null) {
      // Show error but keep scanning.
      setState(() => _errorMsg = 'QR no reconocido. Usa el generador web.');
      Future.delayed(const Duration(seconds: 3),
          () { if (mounted) setState(() => _errorMsg = null); });
      return;
    }

    _detected = true;
    Navigator.pop(context, result);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear QR de Playlist'),
        actions: [
          // Torch toggle
          IconButton(
            icon: const Icon(Icons.flashlight_on),
            tooltip: 'Linterna',
            onPressed: () => _controller.toggleTorch(),
          ),
          // Flip camera
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            tooltip: 'Cambiar cámara',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── 1. Camera preview ─────────────────────────────────────────────
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (ctx, error, child) => _NoCameraView(error: error),
          ),

          // ── 2. Scan-window overlay ────────────────────────────────────────
          _ScanOverlay(),

          // ── 3. Bottom hint ────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base, AppSpacing.lg, AppSpacing.base, AppSpacing.xl),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: AppDurations.normal,
                    child: _errorMsg != null
                        ? Container(
                            key: const ValueKey('err'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.base,
                                vertical: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.9),
                              borderRadius: AppRadius.cardRadius,
                            ),
                            child: Text(
                              _errorMsg!,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : const Text(
                            key: ValueKey('hint'),
                            'Apunta al código QR de tu playlist',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, null),
                    icon: const Icon(Icons.keyboard, color: Colors.white70),
                    label: const Text(
                      'Escribir URL manualmente',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ScanOverlay — darkened frame with bright scan window
// ─────────────────────────────────────────────────────────────────────────────

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final size   = constraints.biggest;
      final winSz  = size.width * 0.65;
      final left   = (size.width  - winSz) / 2;
      final top    = (size.height - winSz) / 2.2;

      return Stack(
        children: [
          // Semi-transparent dimmer with a transparent hole.
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
                Color(0x99000000), BlendMode.srcOut),
            child: Stack(
              children: [
                // Full-screen dark layer (blend source)
                Container(
                    decoration: const BoxDecoration(
                        color: Colors.transparent,
                        backgroundBlendMode: BlendMode.dstOut)),
                // Transparent window (punches a hole through the dimmer)
                Positioned(
                  left: left,
                  top: top,
                  child: Container(
                    width: winSz,
                    height: winSz,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: AppRadius.cardRadius,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Accent border around the scan window.
          Positioned(
            left: left,
            top: top,
            child: Container(
              width: winSz,
              height: winSz,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 2.5),
                borderRadius: AppRadius.cardRadius,
              ),
            ),
          ),

          // Corner accent marks.
          ..._corners(left: left, top: top, size: winSz),
        ],
      );
    });
  }

  static List<Widget> _corners(
      {required double left, required double top, required double size}) {
    const len = 24.0;
    const w   = 3.5;
    final col = AppColors.accent;

    Widget mark(double dx, double dy, double bx, double by) => Positioned(
          left: left + dx,
          top: top + dy,
          child: SizedBox(
            width: len,
            height: len,
            child: CustomPaint(
              painter: _CornerPainter(bx: bx, by: by, color: col, width: w),
            ),
          ),
        );

    return [
      mark(0,        0,        1, 1),   // top-left
      mark(size-len, 0,        0, 1),   // top-right
      mark(0,        size-len, 1, 0),   // bottom-left
      mark(size-len, size-len, 0, 0),   // bottom-right
    ];
  }
}

class _CornerPainter extends CustomPainter {
  final double bx, by, width;
  final Color  color;
  const _CornerPainter(
      {required this.bx, required this.by, required this.color,
       required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = width
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    final x = bx == 1 ? 0.0 : size.width;
    final y = by == 1 ? 0.0 : size.height;
    final ex = bx == 1 ? size.width : 0.0;
    final ey = by == 1 ? size.height : 0.0;

    canvas.drawLine(Offset(x, y), Offset(ex, y), paint); // horizontal
    canvas.drawLine(Offset(x, y), Offset(x, ey), paint); // vertical
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// _NoCameraView — shown when the camera is unavailable
// ─────────────────────────────────────────────────────────────────────────────

class _NoCameraView extends StatelessWidget {
  final MobileScannerException error;
  const _NoCameraView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.paddingXL,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography,
                size: 72, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Cámara no disponible',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Este dispositivo no tiene cámara o los permisos fueron denegados.\n'
              'Usa la opción manual para escribir la URL.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, null),
              icon: const Icon(Icons.keyboard),
              label: const Text('Escribir URL manualmente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
