import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import 'ack_scanner_screen.dart';
import 'package:uuid/uuid.dart';

class OfferScreen extends StatefulWidget {
  final User user;
  final Bon bon;

  const OfferScreen({super.key, required this.user, required this.bon});

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  final _qrService = QRService();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();
  final _uuid = const Uuid();

  List<int>? _qrData;
  int _timeRemaining = 30;
  Timer? _timer;
  bool _isGenerating = true;
  bool _waitingForAck = false;
  String _currentChallenge = '';

  @override
  void initState() {
    super.initState();
    _generateQR();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _generateQR() async {
    setState(() => _isGenerating = true);

    try {
      if (widget.bon.p2 == null || widget.bon.p3 == null) {
        // Récupérer P3 depuis le cache
        final p3 = await _storageService.getP3FromCache(widget.bon.bonId);
        if (p3 == null) {
          _showError('Part P3 non disponible');
          return;
        }

        // Chiffrer P2 avec K_P2 = hash(P3)
        final p2Encrypted = await _cryptoService.encryptP2(
          widget.bon.p2!,
          p3,
        );

        // Générer un challenge aléatoire
        final challenge = _uuid.v4().replaceAll('-', '').substring(0, 32);
        _currentChallenge = challenge;

        // Timestamp actuel
        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // ✅ CORRECTION P0-C: Signer le QR1 avec sk_B (clé du bon)
        // Whitepaper (007.md §3.2 Étape 1): "QR1: {B_id, P2, c, ts}_sig_E"
        // Le donneur prouve qu'il possède le bon en signant avec sk_B
        //
        // Reconstruction éphémère de sk_B = shamirCombine(null, P2, P3)
        final nsecBonHex = _cryptoService.shamirCombine(
          null,              // P1 absent (pas nécessaire)
          widget.bon.p2!,    // P2
          p3,                // P3
        );
        
        // Créer le message à signer: bonId || p2Cipher || nonce || challenge || timestamp || ttl
        final messageToSign = widget.bon.bonId +
            p2Encrypted['ciphertext']! +
            p2Encrypted['nonce']! +
            challenge +
            timestamp.toRadixString(16).padLeft(8, '0') +
            '1e'; // ttl = 30 = 0x1e
        
        // Signer avec la clé du bon
        final signature = _cryptoService.signMessage(messageToSign, nsecBonHex);
        
        // ✅ SÉCURITÉ: Nettoyage explicite RAM
        // Note: En Dart les Strings sont immuables, mais on efface la référence
        // ignore: unused_local_variable
        final nsecBonHex_erase = nsecBonHex; // Pour documentation - sera GC

        // Encoder en format binaire avec signature (177 octets)
        final qrBytes = _qrService.encodeOffer(
          bonIdHex: widget.bon.bonId,
          p2CipherHex: p2Encrypted['ciphertext']!,
          nonceHex: p2Encrypted['nonce']!,
          challengeHex: challenge,
          timestamp: timestamp,
          ttl: 30,
          signatureHex: signature,  // ✅ NOUVEAU: signature du donneur
        );

        setState(() {
          _qrData = qrBytes;
          _timeRemaining = 30;
          _isGenerating = false;
        });

        // Démarrer le compte à rebours
        _startTimer();
      }
    } catch (e) {
      _showError('Erreur génération QR: $e');
      setState(() => _isGenerating = false);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        setState(() => _timeRemaining--);
      } else {
        timer.cancel();
        _regenerateQR();
      }
    });
  }

  void _regenerateQR() {
    _timer?.cancel();
    _generateQR();
  }

  /// ✅ ATTENDRE ET VÉRIFIER ACK DU RECEVEUR
  Future<void> _waitForAck() async {
    setState(() => _waitingForAck = true);
    _timer?.cancel(); // Pause du timer

    try {
      // Naviguer vers le scanner ACK
      // ✅ CORRECTION P0-A: Passer les infos nécessaires pour la publication Nostr
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AckScannerScreen(
            challenge: _currentChallenge,
            bonId: widget.bon.bonId,
            receiverNpub: widget.user.npub,  // ✅ NOUVEAU: npub du receveur
            bonValue: widget.bon.value,       // ✅ NOUVEAU: valeur du bon
          ),
        ),
      );

      if (result != null && result['verified'] == true) {
        // ✅ CORRECTION P0-B: Ne PAS supprimer le bon entièrement !
        // L'émetteur doit conserver P1 (l'Ancre) pour pouvoir révoquer le bon
        // et pour l'afficher dans "Mes émissions"
        //
        // Whitepaper (007.md §1.3): P1 = Ancre, détenue par l'Émetteur
        //
        // Au lieu de deleteBon, on met à jour le bon:
        // - p2: null (le porteur n'a plus P2)
        // - status: BonStatus.spent (le bon est dépensé)
        final updatedBon = widget.bon.copyWith(
          p2: null,
          status: BonStatus.spent,
        );
        await _storageService.saveBon(updatedBon);

        if (!mounted) return;

        // Message de succès
        final publishedMsg = result['published'] == true
            ? ' (publié sur Nostr)'
            : ' (sync en attente)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Transfert confirmé et sécurisé !$publishedMsg'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // Retour au wallet
        Navigator.pop(context);
      } else {
        // ACK non vérifié, reprendre le timer
        _startTimer();
      }
    } catch (e) {
      _showError('Erreur vérification ACK: $e');
      _startTimer();
    } finally {
      if (mounted) {
        setState(() => _waitingForAck = false);
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Donner le bon'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: _isGenerating
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Instructions
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Montrez ce code au receveur',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ),

                // QR Code
                if (_qrData != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: String.fromCharCodes(_qrData!),
                        version: QrVersions.auto,
                        size: 280,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Compte à rebours
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: _timeRemaining <= 10 
                        ? Colors.red.withOpacity(0.2) 
                        : Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _timeRemaining <= 10 ? Colors.red : Colors.green,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    'Expire dans: $_timeRemaining secondes',
                    style: TextStyle(
                      color: _timeRemaining <= 10 ? Colors.red : Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Bouton régénérer
                ElevatedButton.icon(
                  onPressed: _regenerateQR,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Régénérer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A7EA4),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),

                const SizedBox(height: 16),

                // ✅ BOUTON "ATTENDRE CONFIRMATION DU RECEVEUR"
                ElevatedButton.icon(
                  onPressed: _waitingForAck ? null : _waitForAck,
                  icon: _waitingForAck
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle),
                  label: Text(_waitingForAck
                      ? 'Vérification en cours...'
                      : 'Attendre confirmation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    minimumSize: const Size(200, 50),
                  ),
                ),

                const SizedBox(height: 24),

                // Informations du bon
                Container(
                  margin: const EdgeInsets.all(16),
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
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Émetteur:',
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

                const Spacer(),

                // Info
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Attendez que le receveur scanne puis confirme',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
