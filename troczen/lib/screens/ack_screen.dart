import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:hex/hex.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../models/nostr_profile.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';

/// Écran d'acquittement (ACK) après réception d'un bon
/// Génère un QR code ACK signé pour confirmer la réception
class AckScreen extends StatefulWidget {
  final User user;
  final Bon bon;
  final String challenge;

  const AckScreen({
    Key? key,
    required this.user,
    required this.bon,
    required this.challenge,
  }) : super(key: key);

  @override
  State<AckScreen> createState() => _AckScreenState();
}

class _AckScreenState extends State<AckScreen> with SingleTickerProviderStateMixin {
  final _qrService = QRService();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();
  
  List<int>? _ackQrData;
  bool _isGenerating = true;
  bool _transferPublished = false;
  late AnimationController _checkmarkController;

  @override
  void initState() {
    super.initState();
    _checkmarkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _generateAckQR();
  }

  @override
  void dispose() {
    _checkmarkController.dispose();
    super.dispose();
  }

  Future<void> _generateAckQR() async {
    setState(() => _isGenerating = true);

    try {
      // ✅ CORRECTION BUG P0: Récupérer P3 depuis le cache
      // widget.bon.p3 est presque toujours null (P3 est dans le cache, pas dans l'objet Bon)
      final p3 = await _storageService.getP3FromCache(widget.bon.bonId);
      
      if (p3 == null) {
        _showError('Erreur: P3 non trouvée dans le cache.\nSynchronisez avec le marché.');
        return;
      }
      
      // ✅ Reconstruire ÉPHÉMÈRE nsec_bon pour signer le challenge
      // CORRECTION BUG: P2 doit être en position 2, P3 en position 3
      final nsecBonHex = _cryptoService.shamirCombine(
        null,          // P1 est absent
        widget.bon.p2, // P2 est à sa bonne place
        p3,            // P3 est à sa bonne place
      );
      // ✅ SÉCURITÉ: Convertir en Uint8List pour permettre le nettoyage mémoire
      final nsecBonBytes = Uint8List.fromList(HEX.decode(nsecBonHex));

      // Signer le challenge avec la clé privée du bon
      final signature = _cryptoService.signMessage(widget.challenge, nsecBonHex);
      
      // ✅ SÉCURITÉ: Nettoyage explicite RAM avec Uint8List
      _cryptoService.secureZeroiseBytes(nsecBonBytes);

      // Encoder l'ACK en format binaire (97 octets)
      final ackBytes = _qrService.encodeAck(
        bonIdHex: widget.bon.bonId,
        signatureHex: signature,
        status: 0x01, // RECEIVED
      );

      setState(() {
        _ackQrData = ackBytes;
        _isGenerating = false;
      });

      // Animer le checkmark
      _checkmarkController.forward();

      // ✅ PUBLIER TRANSFERT SUR NOSTR (kind 1)
      _publishTransferToNostr();

    } on ShamirReconstructionException catch (e) {
      setState(() => _isGenerating = false);
      _showError(e.userMessage);
    } catch (e) {
      setState(() => _isGenerating = false);
      _showError('Erreur génération ACK: $e');
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
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// ✅ PUBLICATION DU TRANSFERT SUR NOSTR (kind 1)
  /// SIGNÉ PAR LE BON LUI-MÊME pour le dashboard économique
  Future<void> _publishTransferToNostr() async {
    if (_transferPublished) return;

    try {
      final market = await _storageService.getMarket();
      
      // ✅ CORRECTION BUG P0: Récupérer P3 depuis le cache
      final p3 = await _storageService.getP3FromCache(widget.bon.bonId);
      
      if (market == null || widget.bon.p2 == null || p3 == null) {
        return;
      }

      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );

      final relayUrl = market.relayUrl ?? NostrConstants.defaultRelay;
      final connected = await nostrService.connect(relayUrl);

      if (connected) {
        // ✅ Publication avec reconstruction éphémère sk_B (P2+P3)
        await nostrService.publishTransfer(
          bonId: widget.bon.bonId,
          bonP2: widget.bon.p2!,  // Pour reconstruction
          bonP3: p3,  // ✅ Utiliser P3 depuis le cache
          receiverNpub: widget.user.npub,
          value: widget.bon.value,
          marketName: market.name,
        );

        setState(() => _transferPublished = true);
        debugPrint('✅ Transfert publié sur Nostr (signé par le bon)');

        await nostrService.disconnect();
      }
    } catch (e) {
      debugPrint('⚠️ Erreur publication transfert Nostr: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Empêcher le retour avant que le donneur scanne
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              'Attention',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Le donneur doit scanner votre confirmation avant que vous partiez.\nQuitter maintenant ?',
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Rester'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Quitter'),
              ),
            ],
          ),
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: const Text('Confirmation de réception'),
          backgroundColor: const Color(0xFF1E1E1E),
          automaticallyImplyLeading: false,
        ),
        body: _isGenerating
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    // Checkmark animé
                    ScaleTransition(
                      scale: CurvedAnimation(
                        parent: _checkmarkController,
                        curve: Curves.elasticOut,
                      ),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Message de succès
                    const Text(
                      'Bon reçu avec succès !',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Détails du bon
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Valeur:',
                                style: TextStyle(color: Colors.white70),
                              ),
                              Text(
                                '${widget.bon.value} ẐEN',
                                style: const TextStyle(
                                  color: Color(0xFFFFB347),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'De:',
                                style: TextStyle(color: Colors.white70),
                              ),
                              Text(
                                widget.bon.issuerName,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Instructions
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Montrez ce QR code au donneur',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // QR Code ACK
                    if (_ackQrData != null)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: String.fromCharCodes(_ackQrData!),
                            version: QrVersions.auto,
                            size: 280,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),

                    const SizedBox(height: 32),

                    // Info sécurité
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.security, color: Colors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Ce code prouve cryptographiquement que vous avez bien reçu le bon',
                              style: TextStyle(
                                color: Colors.green[300],
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Bouton terminer
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ElevatedButton(
                        onPressed: () {
                          // Retour au wallet après scan donneur
                          Navigator.popUntil(context, (route) => route.isFirst);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Terminer',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}
