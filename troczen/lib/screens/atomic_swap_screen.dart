import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hex/hex.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../config/app_config.dart';
import '../services/nfc_service.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../widgets/panini_card.dart';

/// Écran d'échange atomique avec NFC prioritaire et fallback QR
/// Animations 3D, sons zen, feedback visuel/sonore complet
class AtomicSwapScreen extends StatefulWidget {
  final User user;
  final Bon bon;
  final bool isDonor; // true = donneur, false = receveur

  const AtomicSwapScreen({
    super.key,
    required this.user,
    required this.bon,
    required this.isDonor,
  });

  @override
  State<AtomicSwapScreen> createState() => _AtomicSwapScreenState();
}

class _AtomicSwapScreenState extends State<AtomicSwapScreen>
    with TickerProviderStateMixin {
  // Services
  final _nfcService = NfcService(
    qrService: QRService(),
  );
  final _qrService = QRService();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();
  final _audioPlayer = AudioPlayer();
  final _qrScannerController = MobileScannerController();

  // État
  SwapStatus _status = SwapStatus.initializing;
  String _statusMessage = 'Initialisation...';
  bool _nfcAvailable = false;
  bool _useNfc = true;
  int _timeRemaining = 120; // 2 minutes timeout
  Timer? _timeoutTimer;
  bool _animationsEnabled = true;
  bool _soundsEnabled = true;

  // Animation flip 3D
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  // Animation particules
  late AnimationController _particlesController;
  List<Particle> _particles = [];

  // QR data (fallback)
  List<int>? _qrData;
  String? _challenge;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _checkNfcAvailability();
    _startTimeout();
  }

  @override
  void dispose() {
    _flipController.dispose();
    _particlesController.dispose();
    _timeoutTimer?.cancel();
    _audioPlayer.dispose();
    _qrScannerController.dispose();
    _nfcService.stopSession();
    super.dispose();
  }

  void _initAnimations() {
    // Flip 3D
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _flipAnimation = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    // Particules
    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(() {
        if (mounted) setState(() {});
      });
  }

  Future<void> _checkNfcAvailability() async {
    setState(() => _status = SwapStatus.initializing);

    // Vérifier si NFC est activé via feature flag
    if (!AppConfig.nfcEnabled) {
      // NFC désactivé - utiliser QR directement
      setState(() {
        _nfcAvailable = false;
        _useNfc = false;
      });
      _switchToQrMode();
      return;
    }

    try {
      _nfcAvailable = await _nfcService.checkAvailability();

      if (_nfcAvailable) {
        setState(() {
          _status = SwapStatus.waitingNfc;
          _statusMessage = widget.isDonor
              ? 'Approchez les téléphones pour donner'
              : 'Approchez votre téléphone pour recevoir';
        });

        // Démarrer session NFC
        if (widget.isDonor) {
          await _startNfcDonor();
        } else {
          await _startNfcReceiver();
        }
      } else {
        // Fallback QR immédiat
        _switchToQrMode();
      }
    } catch (e) {
      _handleError('Erreur NFC: $e');
      _switchToQrMode();
    }
  }

  void _startTimeout() {
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        setState(() => _timeRemaining--);
      } else {
        timer.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (_status != SwapStatus.completed && _status != SwapStatus.failed) {
      setState(() {
        _status = SwapStatus.failed;
        _statusMessage = 'Échange annulé (timeout)';
      });
      _nfcService.stopSession();
      _playSound('error');
      _vibrateError();
      // ✅ WAL: Annuler le verrou en cas de timeout
      if (widget.isDonor) {
        _storageService.cancelTransferLock(widget.bon.bonId);
      }
    }
  }

  void _switchToQrMode() {
    setState(() {
      _useNfc = false;
      _status = SwapStatus.waitingQr;
      _statusMessage = widget.isDonor
          ? 'Montrez le QR code au receveur'
          : 'Scannez le QR code du donneur';
    });

    if (widget.isDonor) {
      _generateQrOffer();
    }
  }

  // ==================== NFC DONOR ====================

  Future<void> _startNfcDonor() async {
    try {
      // ✅ WAL: Verrouiller le bon AVANT toute opération
      _challenge = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
      final lockedBon = await _storageService.lockBonForTransfer(
        widget.bon.bonId,
        challenge: _challenge,
        ttlSeconds: 180, // 3 minutes pour NFC
      );
      
      if (lockedBon == null) {
        throw Exception('Impossible de verrouiller le bon. Il est peut-être déjà en cours de transfert.');
      }

      // ✅ OPTIMISATION: Récupérer directement les bytes P3
      final p3Bytes = await _storageService.getP3FromCacheBytes(widget.bon.bonId);
      if (p3Bytes == null) {
        // ✅ WAL: Annuler le verrou en cas d'erreur
        await _storageService.cancelTransferLock(widget.bon.bonId);
        throw Exception('P3 non disponible');
      }
      
      // ✅ OPTIMISATION: Récupérer directement les bytes P2
      final p2Bytes = lockedBon.p2Bytes;
      if (p2Bytes == null) {
        await _storageService.cancelTransferLock(widget.bon.bonId);
        throw Exception('P2 non disponible');
      }

      // ✅ OPTIMISATION: Utiliser encryptP2Bytes pour éviter les conversions hex
      final p2Encrypted = await _cryptoService.encryptP2Bytes(p2Bytes, p3Bytes);

      _nfcService.onStatusChange = (message) {
        if (mounted) setState(() => _statusMessage = message);
      };

      _nfcService.onAckReceived = (ackData) async {
        await _handleReceivedAck(ackData);
      };

      _nfcService.onError = (error) {
        _handleError(error);
        // ✅ WAL: Annuler le verrou en cas d'erreur
        _storageService.cancelTransferLock(widget.bon.bonId);
        _switchToQrMode();
      };

      await _nfcService.startOfferSession(
        bonId: lockedBon.bonId,
        p2Encrypted: HEX.encode(p2Encrypted.ciphertext),
        nonce: HEX.encode(p2Encrypted.nonce),
        challenge: _challenge!,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    } catch (e) {
      _handleError('Erreur préparation NFC: $e');
      // ✅ WAL: Annuler le verrou en cas d'erreur
      await _storageService.cancelTransferLock(widget.bon.bonId);
      _switchToQrMode();
    }
  }

  // ==================== NFC RECEIVER ====================

  Future<void> _startNfcReceiver() async {
    _nfcService.onOfferReceived = (offerData) async {
      await _handleReceivedOffer(offerData);
    };

    _nfcService.onError = (error) {
      _handleError(error);
      _switchToQrMode();
    };

    await _nfcService.startReceiveSession();
  }

  Future<void> _handleReceivedOffer(Map<String, dynamic> offerData) async {
    setState(() {
      _status = SwapStatus.validating;
      _statusMessage = 'Validation du bon...';
    });

    try {
      // Vérifier TTL
      if (_qrService.isExpired(offerData['timestamp'], offerData['ttl'])) {
        throw Exception('Offre expirée');
      }

      // ✅ OPTIMISATION: Récupérer directement les bytes P3
      final p3Bytes = await _storageService.getP3FromCacheBytes(offerData['bonId']);
      if (p3Bytes == null) {
        throw Exception('Part P3 non trouvée.\nSynchronisez avec le marché.');
      }

      // ✅ OPTIMISATION: Déchiffrer P2 avec les méthodes binaires
      final p2Bytes = await _cryptoService.decryptP2Bytes(
        Uint8List.fromList(HEX.decode(offerData['p2Cipher'])),
        Uint8List.fromList(HEX.decode(offerData['nonce'])),
        p3Bytes,
      );

      // TODO: Vérifier signature avec P2+P3 reconstruit

      setState(() {
        _status = SwapStatus.validated;
        _statusMessage = 'Bon validé ! Envoi confirmation...';
      });

      // Jouer son et vibration succès
      _playSound('success');
      _vibrateSuccess();

      // Générer et envoyer ACK
      final signature = _generateAckSignature(offerData['challenge']);
      await _nfcService.sendAck(
        bonId: offerData['bonId'],
        signature: signature,
      );

      // Sauvegarder bon (convertir en hex pour le modèle)
      final p2 = HEX.encode(p2Bytes);
      final receivedBon = widget.bon.copyWith(
        status: BonStatus.active,
        p2: p2,
        transferCount: (widget.bon.transferCount ?? 0) + 1,
      );
      await _storageService.saveBon(receivedBon);

      // Animation succès
      _playSuccessAnimation();

      setState(() {
        _status = SwapStatus.completed;
        _statusMessage = 'Bon reçu avec succès !';
      });

      // Retour auto après 3s
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      _handleError('Validation échouée: $e');
    }
  }

  // ==================== ACK HANDLING (DONOR) ====================

  Future<void> _handleReceivedAck(Map<String, dynamic> ackData) async {
    setState(() {
      _status = SwapStatus.validating;
      _statusMessage = 'Vérification confirmation...';
    });

    try {
      // Vérifier signature ACK
      // TODO: Implémenter vérification Schnorr réelle
      final isValid = ackData['signature'].length == 128;
      if (!isValid) throw Exception('Signature ACK invalide');

      // ✅ WAL: Utiliser la méthode atomique pour confirmer le transfert
      // Cette méthode vérifie le challenge et supprime P2 de manière atomique
      final success = await _storageService.confirmTransferAndRemoveP2(
        widget.bon.bonId,
        _challenge!,
      );
      
      if (!success) {
        throw Exception('Échec de la confirmation du transfert. Le bon n\'était peut-être pas verrouillé.');
      }

      // Succès
      _playSound('success');
      _vibrateSuccess();
      _playSuccessAnimation();

      setState(() {
        _status = SwapStatus.completed;
        _statusMessage = 'Transfert confirmé !';
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      _handleError('Vérification ACK échouée: $e');
      // ✅ WAL: Annuler le verrou en cas d'erreur
      await _storageService.cancelTransferLock(widget.bon.bonId);
    }
  }

  // ==================== QR FALLBACK ====================

  Future<void> _generateQrOffer() async {
    try {
      // ✅ WAL: Verrouiller le bon AVANT de générer le QR
      _challenge = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
      final lockedBon = await _storageService.lockBonForTransfer(
        widget.bon.bonId,
        challenge: _challenge,
        ttlSeconds: 150, // 2.5 minutes pour QR (TTL QR = 120s)
      );
      
      if (lockedBon == null) {
        throw Exception('Impossible de verrouiller le bon. Il est peut-être déjà en cours de transfert.');
      }

      // ✅ OPTIMISATION: Récupérer directement les bytes P3
      final p3Bytes = await _storageService.getP3FromCacheBytes(lockedBon.bonId);
      if (p3Bytes == null) {
        await _storageService.cancelTransferLock(lockedBon.bonId);
        throw Exception('P3 non disponible');
      }

      // Signer le QR avec la clé du bon
      final p2Bytes = lockedBon.p2Bytes;
      
      if (p2Bytes == null) {
        await _storageService.cancelTransferLock(lockedBon.bonId);
        throw Exception('Part P2 non disponible');
      }

      // ✅ OPTIMISATION: Utiliser encryptP2Bytes
      final p2Encrypted = await _cryptoService.encryptP2Bytes(p2Bytes, p3Bytes);
      
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(
        null,
        p2Bytes,
        p3Bytes,
      );
      
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      // ✅ OPTIMISATION: Construire le message en bytes et signer directement
      final bonIdBytes = Uint8List.fromList(HEX.decode(lockedBon.bonId));
      final challengeBytes = Uint8List.fromList(HEX.decode(_challenge!));
      final timestampBytes = ByteData(4);
      timestampBytes.setUint32(0, timestamp, Endian.big);
      
      final messageBytes = Uint8List.fromList([
        ...bonIdBytes,
        ...p2Encrypted.ciphertext,
        ...p2Encrypted.nonce,
        ...challengeBytes,
        ...timestampBytes.buffer.asUint8List(),
      ]);
          
      final signatureBytes = _cryptoService.signMessageBytesDirect(messageBytes, nsecBonBytes);
      
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

      // ✅ CORRECTION P0-A: Utiliser encodeQrV2Bytes (240 octets)
      final qrBytes = _qrService.encodeQrV2Bytes(
        bonId: bonIdBytes,
        valueInCentimes: (widget.bon.value * 100).round(),
        issuerNpub: Uint8List.fromList(HEX.decode(widget.bon.issuerNpub)),
        issuerName: widget.bon.issuerName,
        encryptedP2: p2Encrypted.ciphertext,
        p2Nonce: p2Encrypted.nonce,
        p2Tag: p2Encrypted.tag,
        challenge: challengeBytes,
        signature: signatureBytes,
      );

      setState(() => _qrData = qrBytes);
    } catch (e) {
      _handleError('Erreur génération QR: $e');
    }
  }

  // ==================== SOUNDS & HAPTICS ====================

  Future<void> _playSound(String type) async {
    if (!_soundsEnabled) return;

    try {
      final soundPath = {
        'tap': 'sounds/tap.mp3',
        'success': 'sounds/bowl.mp3', // Bol tibétain
        'buzz': 'sounds/buzz.mp3', // Bourdonnement
        'error': 'sounds/error.mp3',
      }[type];

      if (soundPath != null) {
        await _audioPlayer.play(AssetSource(soundPath));
      }
    } catch (e) {
      // Ignorer erreurs audio
    }
  }

  void _vibrateSuccess() {
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.mediumImpact();
    });
  }

  void _vibrateError() {
    HapticFeedback.heavyImpact();
  }

  void _playSuccessAnimation() {
    // Flip 3D de la carte
    _flipController.forward();

    // Générer particules dorées
    _particles = List.generate(50, (i) {
      final random = math.Random();
      return Particle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: random.nextDouble() * 4 + 2,
        speed: random.nextDouble() * 2 + 1,
      );
    });

    _particlesController.forward(from: 0);
  }

  void _handleError(String error) {
    setState(() {
      _status = SwapStatus.failed;
      _statusMessage = error;
    });
    _playSound('error');
    _vibrateError();
  }

  String _generateAckSignature(String challenge) {
    // TODO: Implémenter signature Schnorr réelle
    return '0' * 128; // Signature simulée
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _status != SwapStatus.validating,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_status == SwapStatus.validating) {
          final shouldPop = await _showCancelDialog() ?? false;
          if (shouldPop && mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: Text(widget.isDonor ? 'Donner un bon' : 'Recevoir un bon'),
          backgroundColor: const Color(0xFF1E1E1E),
          actions: [
            // Toggle animations
            IconButton(
              icon: Icon(
                _animationsEnabled ? Icons.animation : Icons.animation_outlined,
              ),
              onPressed: () {
                setState(() => _animationsEnabled = !_animationsEnabled);
              },
              tooltip: 'Animations',
            ),
            // Toggle sons
            IconButton(
              icon: Icon(_soundsEnabled ? Icons.volume_up : Icons.volume_off),
              onPressed: () {
                setState(() => _soundsEnabled = !_soundsEnabled);
              },
              tooltip: 'Sons',
            ),
          ],
        ),
        body: Stack(
          children: [
            // Particules animées
            if (_animationsEnabled && _particles.isNotEmpty)
              ...particles_widgets,

            // Contenu principal
            SafeArea(
              child: Column(
                children: [
                  // Indicateur mode (NFC ou QR)
                  _buildModeIndicator(),

                  // Carte Panini avec flip
                  Expanded(
                    child: Center(
                      child: _animationsEnabled
                          ? _buildAnimatedCard()
                          : _buildStaticCard(),
                    ),
                  ),

                  // Zone NFC/QR
                  if (_useNfc)
                    _buildNfcZone()
                  else if (widget.isDonor)
                    _buildQrDisplay()
                  else
                    _buildQrScanner(),

                  // Status et timer
                  _buildStatusBar(),

                  const SizedBox(height: 20),
                ],
              ),
            ),

            // Overlay de confirmation (montants élevés)
            if (_status == SwapStatus.validated && widget.bon.value >= 20)
              _buildConfirmationOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildModeIndicator() {
    // Si NFC est désactivé via feature flag, afficher uniquement QR
    if (!AppConfig.nfcEnabled) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code, color: Colors.orange),
            const SizedBox(width: 8),
            const Text(
              'Mode QR Code',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.nfc, size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    AppConfig.nfcUnavailableMessage,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _useNfc
            ? Colors.blue.withOpacity(0.2)
            : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _useNfc ? Colors.blue : Colors.orange,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _useNfc ? Icons.nfc : Icons.qr_code,
            color: _useNfc ? Colors.blue : Colors.orange,
          ),
          const SizedBox(width: 8),
          Text(
            _useNfc ? 'Mode NFC Actif' : 'Mode QR Code',
            style: TextStyle(
              color: _useNfc ? Colors.blue : Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_nfcAvailable && !_useNfc) ...[
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: () => setState(() => _useNfc = true),
              icon: const Icon(Icons.nfc, size: 16),
              label: const Text('Utiliser NFC'),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimatedCard() {
    return AnimatedBuilder(
      animation: _flipAnimation,
      builder: (context, child) {
        final angle = _flipAnimation.value;
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(angle);

        return Transform(
          transform: transform,
          alignment: Alignment.center,
          child: angle > math.pi / 2
              ? Transform(
                  transform: Matrix4.identity()..rotateY(math.pi),
                  alignment: Alignment.center,
                  child: _buildCardBack(),
                )
              : PaniniCard(bon: widget.bon),
        );
      },
    );
  }

  Widget _buildStaticCard() {
    return PaniniCard(bon: widget.bon);
  }

  Widget _buildCardBack() {
    return Container(
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Icon(
          Icons.check_circle,
          size: 100,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildNfcZone() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.nfc,
            size: 80,
            color: Colors.blue.withOpacity(0.8),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isDonor
                ? 'Approchez les téléphones'
                : 'Approchez votre téléphone',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Distance : < 5 cm',
            style: TextStyle(color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildQrDisplay() {
    // QR code display implementation
    return Container(); // Placeholder
  }

  Widget _buildQrScanner() {
    // QR scanner implementation
    return Container(); // Placeholder
  }

  Widget _buildStatusBar() {
    final progress = _timeRemaining / 120;
    final color = progress > 0.5
        ? Colors.green
        : progress > 0.25
            ? Colors.orange
            : Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Barre de progression
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[800],
              color: color,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          // Status message
          Row(
            children: [
              _buildStatusIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              Text(
                '${_timeRemaining}s',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;

    switch (_status) {
      case SwapStatus.initializing:
        icon = Icons.hourglass_empty;
        color = Colors.grey;
        break;
      case SwapStatus.waitingNfc:
      case SwapStatus.waitingQr:
        icon = Icons.bluetooth_searching;
        color = Colors.blue;
        break;
      case SwapStatus.validating:
        icon = Icons.lock_clock;
        color = Colors.orange;
        break;
      case SwapStatus.validated:
        icon = Icons.verified;
        color = Colors.green;
        break;
      case SwapStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case SwapStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    return Icon(icon, color: color, size: 24);
  }

  Widget _buildConfirmationOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning, color: Colors.orange, size: 60),
              const SizedBox(height: 16),
              const Text(
                'Confirmer l\'échange ?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Valeur : ${widget.bon.value} ẐEN',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _status = SwapStatus.failed);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Continuer le transfert
                        setState(() => _status = SwapStatus.completed);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      child: const Text('Confirmer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showCancelDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Annuler l\'échange ?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'L\'échange est en cours. Êtes-vous sûr de vouloir annuler ?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  List<Widget> get particles_widgets {
    return _particles.map((particle) {
      final animation = _particlesController.value;
      final x = particle.x * MediaQuery.of(context).size.width;
      final y = particle.y * MediaQuery.of(context).size.height -
          (animation * particle.speed * 500);

      return Positioned(
        left: x,
        top: y,
        child: Opacity(
          opacity: 1 - animation,
          child: Container(
            width: particle.size,
            height: particle.size,
            decoration: const BoxDecoration(
              color: Color(0xFFFFB347),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }).toList();
  }
}

// ==================== ENUMS & MODELS ====================

enum SwapStatus {
  initializing,
  waitingNfc,
  waitingQr,
  validating,
  validated,
  completed,
  failed,
}

class Particle {
  final double x;
  final double y;
  final double size;
  final double speed;

  Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
  });
}
