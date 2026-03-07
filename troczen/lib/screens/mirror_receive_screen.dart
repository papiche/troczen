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
    if (_controller.step == ReceiveStep.scanning) {
      return Stack(
        children: [
          if (_controller.isCheckingPermission)
            const Center(child: CircularProgressIndicator())
          else if (!_controller.permissionGranted)
            const Center(child: Text('Caméra requise', style: TextStyle(color: Colors.white)))
          else if (_controller.scannerController != null)
            MobileScanner(
              controller: _controller.scannerController!,
              onDetect: (capture) => _controller.handleOfferScan(capture, () {
                if (mounted) Navigator.pop(context);
              }),
            ),
          
          // Cadre de visée
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.orange.withValues(alpha: 0.8), width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Status message
          Positioned(
            top: 48,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _controller.statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
          ),

          // Bouton pour changer de caméra
          Positioned(
            bottom: 32,
            right: 24,
            child: FloatingActionButton(
              backgroundColor: Colors.black54,
              onPressed: _controller.toggleCamera,
              child: const Icon(Icons.cameraswitch, color: Colors.white),
            ),
          ),
        ],
      );
    } else {
      return Container(
        width: double.infinity,
        color: Colors.white,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              if (_controller.ackQrData != null)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  child: _qrService.buildQrWidget(_controller.ackQrData!, size: 300),
                ),
              const SizedBox(height: 24),
              const Text(
                'Confirmation générée',
                style: TextStyle(color: Colors.green, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _controller.statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.w500),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ElevatedButton(
                  onPressed: () {
                    if (mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Terminer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}
