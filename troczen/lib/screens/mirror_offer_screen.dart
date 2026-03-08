import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../services/qr_service.dart';
import 'controllers/mirror_offer_controller.dart';

/// Écran "Mode Miroir" pour le Donneur (Alice)
/// Haut: Affiche le QR Code de l'offre (QR1)
/// Bas: Caméra active pour scanner l'ACK (QR2)
class MirrorOfferScreen extends StatefulWidget {
  final User user;
  final Bon bon;

  const MirrorOfferScreen({super.key, required this.user, required this.bon});

  @override
  State<MirrorOfferScreen> createState() => _MirrorOfferScreenState();
}

class _MirrorOfferScreenState extends State<MirrorOfferScreen> {
  late MirrorOfferController _controller;
  final _qrService = QRService();

  @override
  void initState() {
    super.initState();
    _controller = MirrorOfferController(user: widget.user, bon: widget.bon);
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

  Future<void> _showFollowPrompt(String receiverNpub) async {
    final shouldFollow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.handshake, color: Colors.orange),
            SizedBox(width: 12),
            Expanded(
              child: Text('Tisser un lien ?', style: TextStyle(color: Colors.white, fontSize: 18)),
            ),
          ],
        ),
        content: const Text(
          'Échange réussi ! Voulez-vous ajouter ce commerçant à votre réseau de confiance ?\n\n'
          'Avec 5 liens réciproques, vous participerez à la création monétaire (DU).',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Plus tard', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Tisser le lien'),
          ),
        ],
      ),
    );

    if (shouldFollow == true) {
      await _controller.handleFollow(receiverNpub);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _controller.isSuccess ? Colors.green : Colors.black,
      appBar: AppBar(
        title: const Text('Donner (Mode Miroir)'),
        backgroundColor: _controller.isSuccess ? Colors.green[700] : Theme.of(context).colorScheme.surface,
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
            'Transfert Réussi !',
            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMirrorView() {
    if (_controller.step == OfferStep.presenting) {
      return Container(
        width: double.infinity,
        color: Colors.white,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              if (_controller.isGenerating)
                const CircularProgressIndicator(color: Colors.orange)
              else if (_controller.qrData != null)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  child: _qrService.buildQrWidget(_controller.qrData!, size: 300),
                ),
              const SizedBox(height: 24),
              Text(
                '${widget.bon.value} ẐEN',
                style: const TextStyle(color: Colors.black, fontSize: 36, fontWeight: FontWeight.bold),
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
                  onPressed: _controller.switchToScanning,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'J\'ai montré le code',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return Stack(
        children: [
          if (_controller.isCheckingPermission)
            const Center(child: CircularProgressIndicator())
          else if (!_controller.permissionGranted)
            const Center(child: Text('Caméra requise', style: TextStyle(color: Colors.white)))
          else if (_controller.scannerController != null)
            MobileScanner(
              controller: _controller.scannerController!,
              onDetect: (capture) => _controller.handleAckScan(capture, _showFollowPrompt),
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
    }
  }
}
