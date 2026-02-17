import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import 'ack_screen.dart';

class ScanScreen extends StatefulWidget {
  final User user;

  const ScanScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );
  final _qrService = QRService();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();

  bool _isProcessing = false;
  String _statusMessage = 'Scannez le QR code du bon';

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final barcode = capture.barcodes.first;
    if (barcode.rawBytes == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Vérification en cours...';
    });

    try {
      // Décoder le QR binaire
      final offerData = _qrService.decodeOffer(barcode.rawBytes!);

      // Vérifier le TTL
      if (_qrService.isExpired(offerData['timestamp'], offerData['ttl'])) {
        _showError('QR code expiré');
        return;
      }

      // Récupérer P3 depuis le cache
      final p3 = await _storageService.getP3FromCache(offerData['bonId']);
      if (p3 == null) {
        _showError('Part P3 non trouvée.\nSynchronisez d\'abord avec le marché.');
        return;
      }

      // Déchiffrer P2 avec K_P2 = hash(P3)
      final p2 = await _cryptoService.decryptP2(
        offerData['p2Cipher'],
        offerData['nonce'],
        p3,
      );

      setState(() => _statusMessage = 'Bon validé ! Génération de la confirmation...');

      // TODO: Reconstruire nsec_bon temporairement pour signer
      // final nsecBon = _cryptoService.shamirCombine(p2, p3, null);

      // Pour l'instant, on stocke le bon en pending
      final existingBon = await _storageService.getBonById(offerData['bonId']);
      if (existingBon != null) {
        // Mettre à jour
        final updatedBon = existingBon.copyWith(
          status: BonStatus.active,
          p2: p2,
        );
        await _storageService.saveBon(updatedBon);

        if (!mounted) return;

        // Naviguer vers l'écran ACK
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AckScreen(
              user: widget.user,
              bon: updatedBon,
              challenge: offerData['challenge'],
            ),
          ),
        );
      } else {
        _showError('Bon inconnu');
        return;
      }

    } catch (e) {
      _showError('Erreur: $e');
    } finally {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Scannez le QR code du bon';
      });
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Erreur', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Scanner un bon'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E1E1E),
            child: Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),

          // Scanner
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _handleScan,
                ),
                
                // Overlay
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 3),
                  ),
                  margin: const EdgeInsets.all(48),
                ),

                if (_isProcessing)
                  Container(
                    color: Colors.black.withOpacity(0.7),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFFB347),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Boutons
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _scannerController.toggleTorch(),
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Flash'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2A),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _scannerController.switchCamera(),
                  icon: const Icon(Icons.flip_camera_ios),
                  label: const Text('Caméra'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
