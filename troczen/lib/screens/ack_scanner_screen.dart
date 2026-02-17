import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';

/// Écran pour scanner le QR code ACK du receveur
class AckScannerScreen extends StatefulWidget {
  final String challenge;
  final String bonId;

  const AckScannerScreen({
    Key? key,
    required this.challenge,
    required this.bonId,
  }) : super(key: key);

  @override
  State<AckScannerScreen> createState() => _AckScannerScreenState();
}

class _AckScannerScreenState extends State<AckScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );
  final _qrService = QRService();
  final _cryptoService = CryptoService();

  bool _isProcessing = false;
  String _statusMessage = 'Scannez le QR code de confirmation du receveur';

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleAckScan(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final barcode = capture.barcodes.first;
    if (barcode.rawBytes == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Vérification de la signature...';
    });

    try {
      // Décoder le QR ACK binaire (97 octets)
      final ackData = _qrService.decodeAck(barcode.rawBytes!);

      // ✅ SÉCURITÉ 100%: Valider la clé publique d'abord
      if (!_cryptoService.isValidPublicKey(ackData['bonId'])) {
        _showError('Clé publique invalide');
        return;
      }

      // Vérifier que c'est bien le bon bon
      if (ackData['bonId'] != widget.bonId) {
        _showError('QR code incorrect (mauvais bon)');
        return;
      }

      // Vérifier le statut
      if (ackData['status'] != 0x01) {
        _showError('Statut ACK invalide');
        return;
      }

      // ✅ VÉRIFICATION CRUCIALE: Signature Schnorr du challenge
      final isValid = _cryptoService.verifySignature(
        widget.challenge,
        ackData['signature'],
        widget.bonId,
      );

      if (!isValid) {
        _showError('Signature invalide !\nLe receveur ne possède pas le bon.');
        return;
      }

      // ✅ Signature valide = transfert confirmé !
      setState(() => _statusMessage = 'Transfert confirmé !');

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Retourner avec succès
      Navigator.pop(context, {'verified': true});

    } catch (e) {
      _showError('Erreur: $e');
    } finally {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Scannez le QR code de confirmation du receveur';
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
        title: const Text('Scanner confirmation'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E1E1E),
            child: Column(
              children: [
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                if (_isProcessing) ...[
                  const SizedBox(height: 12),
                  const CircularProgressIndicator(),
                ],
              ],
            ),
          ),

          // Scanner
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _handleAckScan,
                ),
                
                // Overlay avec cadre de scan
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.green,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Info sécurité
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              border: Border(
                top: BorderSide(color: Colors.green.withOpacity(0.3)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.security, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'La signature cryptographique prouve que le receveur possède bien les parts P2+P3',
                    style: TextStyle(
                      color: Colors.green[300],
                      fontSize: 12,
                    ),
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
