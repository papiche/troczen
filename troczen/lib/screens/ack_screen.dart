import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
// ❌ CORRECTION P0-A: nostr_service.dart supprimé - la publication est maintenant côté Donneur

/// Écran d'acquittement (ACK) après réception d'un bon
/// Génère un QR code ACK signé pour confirmer la réception
///
/// ✅ CORRECTION P0-A: Ce screen ne publie PLUS le transfert sur Nostr.
/// C'est le Donneur qui publie après avoir vérifié l'ACK (voir ack_scanner_screen.dart)
/// Conformément au Whitepaper (007.md §3.2 Étape 3 — Finalisation)
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
  
  Uint8List? _ackQrData;  // ✅ CORRECTION: Utiliser Uint8List au lieu de List<int>
  bool _isGenerating = true;
  // ❌ CORRECTION P0-A: _transferPublished supprimé - plus besoin
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
      // ✅ CORRECTION BUG P0: Récupérer P3 depuis le cache en Uint8List directement
      // widget.bon.p3 est presque toujours null (P3 est dans le cache, pas dans l'objet Bon)
      final p3Bytes = await _storageService.getP3FromCacheBytes(widget.bon.bonId);
      
      if (p3Bytes == null) {
        _showError('Erreur: P3 non trouvée dans le cache.\nSynchronisez avec le marché.');
        return;
      }
      
      // ✅ SÉCURITÉ: Récupérer P2 en Uint8List directement depuis le Bon
      final p2Bytes = widget.bon.p2Bytes;
      if (p2Bytes == null) {
        _cryptoService.secureZeroiseBytes(p3Bytes);
        _showError('Erreur: P2 non trouvée pour ce bon.');
        return;
      }
      
      // ✅ SÉCURITÉ: Utiliser shamirCombineBytesDirect avec Uint8List
      // Évite complètement les String en RAM
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(
        null,    // P1 est absent
        p2Bytes, // P2 en Uint8List
        p3Bytes, // P3 en Uint8List
      );

      // ✅ SÉCURITÉ: Utiliser signMessageBytes qui accepte Uint8List
      final signature = _cryptoService.signMessageBytes(widget.challenge, nsecBonBytes);
      
      // ✅ SÉCURITÉ: Nettoyage explicite RAM avec Uint8List
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

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

      // ❌ CORRECTION P0-A: SUPPRIMÉ - La publication Nostr doit être faite par le DONNEUR
      // après vérification de l'ACK, pas par le receveur avant même de montrer son QR !
      //
      // Le Whitepaper (007.md §3.2 Étape 3) est clair:
      // "Donneur: 1. Vérifie response, 2. Supprime définitivement P2, 3. Publie événement TRANSFER"
      //
      // La publication est maintenant dans ack_scanner_screen.dart côté Donneur.

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

  // ❌ CORRECTION P0-A: Méthode _publishTransferToNostr() supprimée
  // La publication du transfert sur Nostr est maintenant faite par le DONNEUR
  // dans ack_scanner_screen.dart, APRÈS vérification de l'ACK.
  // Conformément au Whitepaper (007.md §3.2 Étape 3 — Finalisation)

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
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
        if (shouldPop == true && mounted) Navigator.of(context).pop();
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
                          // ✅ CORRECTION ENCODAGE: Utiliser Base64 pour les données binaires
                          child: _qrService.buildQrWidget(
                            _ackQrData!,
                            size: 280,
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
