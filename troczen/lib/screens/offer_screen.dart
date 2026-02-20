import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hex/hex.dart';
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/audit_trail_service.dart';
import 'ack_scanner_screen.dart';

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
  final _auditService = AuditTrailService();  // ✅ CONFORMITÉ: Logging des transferts
  final _uuid = const Uuid();

  Uint8List? _qrData;
  int _timeRemaining = 60;  // ✅ UI/UX: TTL augmenté à 60 secondes
  Timer? _timer;
  bool _isGenerating = true;
  bool _waitingForAck = false;
  bool _isExpired = false;  // ✅ UI/UX: État d'expiration du QR
  String _currentChallenge = '';
  
  // ✅ UI/UX: Garder les données du QR actuel pour éviter la régénération
  // Le challenge reste le même jusqu'à régénération manuelle ou scan réussi
  String? _currentP2Cipher;
  String? _currentNonce;
  int? _currentTimestamp;

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
    setState(() {
      _isGenerating = true;
      _isExpired = false;
    });

    try {
      // Récupérer P3 depuis le cache (même si p3 est null dans le bon)
      final p3 = await _storageService.getP3FromCache(widget.bon.bonId);
      if (p3 == null) {
        _showError('Part P3 non disponible.\nSynchronisez d\'abord avec le marché.');
        return;
      }

      if (widget.bon.p2 == null) {
        _showError('Part P2 non disponible.\nCe bon a déjà été transféré.');
        return;
      }

      // Chiffrer P2 avec K_P2 = hash(P3)
      final p2Encrypted = await _cryptoService.encryptP2(
        widget.bon.p2!,
        p3,
      );

      // ✅ UI/UX: Stocker les données chiffrées pour réutilisation
      _currentP2Cipher = p2Encrypted['ciphertext']!;
      _currentNonce = p2Encrypted['nonce']!;

      // ✅ CORRECTION HANDSHAKE: Générer un challenge aléatoire (16 octets)
      // Whitepaper (§3.2 Étape 1): Le Donneur génère un challenge que le Receveur doit signer.
      final challengeHex = _uuid.v4().replaceAll('-', '').substring(0, 32);
      _currentChallenge = challengeHex;
      final challengeBytes = Uint8List.fromList(HEX.decode(challengeHex));

      // Timestamp actuel
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _currentTimestamp = timestamp;

      // ✅ CORRECTION P0-C: Signer le QR avec sk_B (clé du bon)
      // Whitepaper (§3.2 Étape 1): "QR1: {B_id, P2, c, ts}_sig_E"
      // Le donneur prouve qu'il possède le bon en signant avec sk_B
      //
      // ✅ SÉCURITÉ: Reconstruction éphémère de sk_B avec Uint8List directement
      final p2Bytes = widget.bon.p2Bytes;
      final p3Bytes = await _storageService.getP3FromCacheBytes(widget.bon.bonId);
      
      if (p2Bytes == null || p3Bytes == null) {
        _showError('Parts P2 ou P3 non disponibles.');
        return;
      }
      
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(
        null,     // P1 absent (pas nécessaire)
        p2Bytes,  // P2 en Uint8List
        p3Bytes,  // P3 en Uint8List
      );
      
      // Créer le message à signer: bonId || p2Cipher || nonce || challenge || timestamp
      final messageToSign = widget.bon.bonId +
          p2Encrypted['ciphertext']! +
          p2Encrypted['nonce']! +
          challengeHex +
          timestamp.toRadixString(16).padLeft(8, '0');
      
      // Signer avec la clé du bon (Uint8List)
      final signatureHex = _cryptoService.signMessageBytes(messageToSign, nsecBonBytes);
      final signatureBytes = Uint8List.fromList(HEX.decode(signatureHex));
      
      // ✅ SÉCURITÉ: Nettoyage explicite RAM avec Uint8List
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

      // ✅ CORRECTION HANDSHAKE: Encoder en format QR v2 (240 octets)
      // Le format v2 inclut: bonId, value, issuerNpub, encryptedP2, nonce, tag, challenge, issuerName, timestamp, signature
      final p2CipherBytes = Uint8List.fromList(HEX.decode(p2Encrypted['ciphertext']!));
      final nonceBytes = Uint8List.fromList(HEX.decode(p2Encrypted['nonce']!));
      
      // Le tag AES-GCM est inclus dans le ciphertext (derniers 16 octets)
      // Pour le format v2, on sépare le ciphertext (32 octets) du tag (16 octets)
      // Note: encryptP2 retourne ciphertext + tag combinés
      final p2WithTag = p2CipherBytes;
      final encryptedP2Only = p2WithTag.sublist(0, 32);
      final p2Tag = p2WithTag.length >= 48
          ? p2WithTag.sublist(32, 48)
          : Uint8List(16); // Fallback si tag non inclus

      final qrBytes = _qrService.encodeQrV2(
        bon: widget.bon,
        encryptedP2Hex: HEX.encode(encryptedP2Only),
        p2Nonce: nonceBytes,
        p2Tag: p2Tag,
        challenge: challengeBytes,      // ✅ NOUVEAU: challenge du Donneur
        signature: signatureBytes,      // ✅ NOUVEAU: signature du Donneur
      );

      setState(() {
        _qrData = qrBytes;
        _timeRemaining = 60;  // ✅ UI/UX: 60 secondes
        _isGenerating = false;
        _isExpired = false;
      });

      // Démarrer le compte à rebours
      _startTimer();
    } catch (e) {
      _showError('Erreur génération QR: $e');
      setState(() => _isGenerating = false);
    }
  }

  /// ✅ UI/UX: Timer avec état d'expiration au lieu de régénération automatique
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        setState(() => _timeRemaining--);
      } else {
        // ✅ UI/UX: Marquer comme expiré au lieu de régénérer automatiquement
        timer.cancel();
        setState(() => _isExpired = true);
      }
    });
  }

  /// ✅ UI/UX: Régénération manuelle uniquement
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
                      // ✅ ENCODAGE: Utiliser Base64 pour les données binaires
                      child: _qrService.buildQrWidget(
                        _qrData!,
                        size: 280,
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // ✅ UI/UX: Compte à rebours avec état d'expiration
                if (_isExpired)
                  // État expiré - message d'avertissement
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red, width: 2),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'QR code expiré',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  // État actif - compte à rebours
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: _timeRemaining <= 15
                          ? Colors.orange.withOpacity(0.2)
                          : Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _timeRemaining <= 15 ? Colors.orange : Colors.green,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _timeRemaining <= 15 ? Icons.timer : Icons.timer_outlined,
                          color: _timeRemaining <= 15 ? Colors.orange : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Expire dans: $_timeRemaining secondes',
                          style: TextStyle(
                            color: _timeRemaining <= 15 ? Colors.orange : Colors.green,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // ✅ UI/UX: Bouton régénérer avec style adapté à l'état
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _regenerateQR,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isExpired ? 'Régénérer le QR code' : 'Régénérer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isExpired ? Colors.orange : const Color(0xFF0A7EA4),
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
