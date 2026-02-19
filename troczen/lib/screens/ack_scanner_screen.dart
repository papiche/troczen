import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';
import '../models/market.dart';

/// Écran pour scanner le QR code ACK du receveur
///
/// ✅ CORRECTION P0-A: C'est le DONNEUR qui publie le transfert sur Nostr
/// après avoir vérifié l'ACK, conformément au Whitepaper (007.md §3.2)
class AckScannerScreen extends StatefulWidget {
  final String challenge;
  final String bonId;
  final String? receiverNpub;  // ✅ NOUVEAU: npub du receveur pour le transfert
  final double? bonValue;       // ✅ NOUVEAU: valeur du bon pour le transfert

  const AckScannerScreen({
    super.key,
    required this.challenge,
    required this.bonId,
    this.receiverNpub,
    this.bonValue,
  });

  @override
  State<AckScannerScreen> createState() => _AckScannerScreenState();
}

class _AckScannerScreenState extends State<AckScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );
  final _qrService = QRService();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();

  bool _isProcessing = false;
  bool _isPublishing = false;  // ✅ NOUVEAU: état de publication Nostr
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

      // ✅ CORRECTION P0-A: Signature valide = publication du transfert par le DONNEUR
      // Conformément au Whitepaper (007.md §3.2 Étape 3 — Finalisation)
      // "Donneur: 1. Vérifie response, 2. Supprime définitivement P2, 3. Publie événement TRANSFER"
      setState(() {
        _statusMessage = 'Publication du transfert...';
        _isPublishing = true;
      });

      final publishSuccess = await _publishTransferToNostr();

      if (!mounted) return;

      if (publishSuccess) {
        setState(() => _statusMessage = 'Transfert confirmé !');
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        // Retourner avec succès
        Navigator.pop(context, {'verified': true, 'published': true});
      } else {
        // Même si la publication échoue, le transfert local est validé
        // L'utilisateur pourra synchroniser plus tard
        setState(() => _statusMessage = 'Transfert local confirmé (sync en attente)');
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        Navigator.pop(context, {'verified': true, 'published': false});
      }

    } catch (e) {
      _showError('Erreur: $e');
    } finally {
      setState(() {
        _isProcessing = false;
        _isPublishing = false;
        _statusMessage = 'Scannez le QR code de confirmation du receveur';
      });
    }
  }

  /// ✅ CORRECTION P0-A: Publication du transfert sur Nostr par le DONNEUR
  /// Cette méthode est appelée APRÈS vérification de l'ACK
  /// Conformément au Whitepaper (007.md §3.2)
  Future<bool> _publishTransferToNostr() async {
    try {
      // Vérifier qu'on a les informations nécessaires
      if (widget.receiverNpub == null || widget.bonValue == null) {
        debugPrint('⚠️ Informations de transfert manquantes, skip publication Nostr');
        return false;
      }

      final market = await _storageService.getMarket();
      if (market == null) {
        debugPrint('⚠️ Marché non configuré, skip publication Nostr');
        return false;
      }

      // Récupérer P2 et P3 pour reconstruire sk_B éphémère
      final bon = await _storageService.getBonById(widget.bonId);
      if (bon == null || bon.p2 == null) {
        debugPrint('⚠️ Bon ou P2 non trouvé, skip publication Nostr');
        return false;
      }

      final p3 = await _storageService.getP3FromCache(widget.bonId);
      if (p3 == null) {
        debugPrint('⚠️ P3 non trouvé dans le cache, skip publication Nostr');
        return false;
      }

      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );

      final relayUrl = market.relayUrl ?? 'wss://relay.damus.io';
      final connected = await nostrService.connect(relayUrl);

      if (connected) {
        // ✅ Publication avec reconstruction éphémère sk_B (P2+P3)
        final success = await nostrService.publishTransfer(
          bonId: widget.bonId,
          bonP2: bon.p2!,
          bonP3: p3,
          receiverNpub: widget.receiverNpub!,
          value: widget.bonValue!,
          marketName: market.name,
        );

        await nostrService.disconnect();
        
        if (success) {
          debugPrint('✅ Transfert publié sur Nostr par le Donneur (conforme Whitepaper)');
        }
        return success;
      }

      return false;
    } catch (e) {
      debugPrint('⚠️ Erreur publication transfert Nostr: $e');
      return false;
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
