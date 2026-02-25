import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user.dart';
import '../services/qr_service.dart';
import 'controllers/mirror_receive_controller.dart';

/// Écran "Mode Miroir" pour le Receveur (Bob)
/// Haut: Affiche le QR Code de l'ACK (QR2) une fois généré
/// Bas: Caméra active pour scanner l'offre (QR1)
class MirrorReceiveScreen extends StatefulWidget {
  final User user;

  const MirrorReceiveScreen({super.key, required this.user});

  @override
  State<MirrorReceiveScreen> createState() => _MirrorReceiveScreenState();
}

class _MirrorReceiveScreenState extends State<MirrorReceiveScreen> {
  late MirrorReceiveController _controller;
  final _qrService = QRService();

  @override
  void initState() {
    super.initState();
    _controller = MirrorReceiveController(user: widget.user);
    _controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _controller.isSuccess ? Colors.green : Colors.black,
      appBar: AppBar(
        title: const Text('Recevoir (Mode Miroir)'),
        backgroundColor: _controller.isSuccess ? Colors.green[700] : const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: _controller.isSuccess ? _buildSuccessView() : _buildMirrorView(),
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.check_circle, color: Colors.white, size: 120),
          SizedBox(height: 24),
          Text(
            'Bon Reçu !',
            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMirrorView() {
    return Column(
      children: [
        // Moitié HAUT : Le QR Code ACK à montrer (ou attente)
        // Fond blanc pour maximiser le contraste et aider l'exposition de la caméra adverse
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            color: _controller.ackQrData != null ? Colors.white : const Color(0xFF121212),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_controller.ackQrData != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                    ),
                    child: _qrService.buildQrWidget(_controller.ackQrData!, size: 240),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Confirmation générée',
                    style: TextStyle(color: Colors.green, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Laissez le donneur scanner',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                ] else ...[
                  const Icon(Icons.qr_code_scanner, color: Colors.grey, size: 80),
                  const SizedBox(height: 16),
                  const Text(
                    'En attente du bon...',
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                ],
              ],
            ),
          ),
        ),
        
        // Séparateur
        Container(
          height: 4,
          color: _controller.ackQrData != null ? Colors.green : Colors.orange,
        ),

        // Moitié BAS : La caméra pour scanner l'offre
        Expanded(
          flex: 1,
          child: Stack(
            children: [
              if (_controller.isCheckingPermission)
                const Center(child: CircularProgressIndicator())
              else if (!_controller.permissionGranted)
                const Center(child: Text('Caméra requise', style: TextStyle(color: Colors.white)))
              else if (_controller.scannerController != null && _controller.ackQrData == null)
                MobileScanner(
                  controller: _controller.scannerController!,
                  onDetect: (capture) => _controller.handleOfferScan(capture, () {
                    if (mounted) Navigator.pop(context);
                  }),
                )
              else if (_controller.ackQrData != null)
                Container(color: Colors.black87, child: const Center(child: Text('Scan terminé', style: TextStyle(color: Colors.white)))),
              
              // Overlay sombre pour ne pas polluer la détection de l'autre téléphone avec la lumière de l'écran
              if (_controller.ackQrData == null)
                Container(
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              
              if (_controller.ackQrData == null)
                Center(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.8), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _controller.statusMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
