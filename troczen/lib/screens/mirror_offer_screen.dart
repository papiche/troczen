import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hex/hex.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/audit_trail_service.dart';
import '../services/nostr_service.dart';

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
  final _qrService = QRService();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();
  final _auditService = AuditTrailService();
  final _uuid = const Uuid();

  MobileScannerController? _scannerController;
  
  Uint8List? _qrData;
  bool _isGenerating = true;
  bool _isProcessingAck = false;
  bool _isSuccess = false;
  String _statusMessage = 'Génération de l\'offre...';
  String _currentChallenge = '';
  
  bool _permissionGranted = false;
  bool _isCheckingPermission = true;
  
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
    _generateQR();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      _initScanner();
      setState(() {
        _permissionGranted = true;
        _isCheckingPermission = false;
      });
    } else {
      final result = await Permission.camera.request();
      if (result.isGranted) {
        _initScanner();
        setState(() {
          _permissionGranted = true;
          _isCheckingPermission = false;
        });
      } else {
        setState(() {
          _permissionGranted = false;
          _isCheckingPermission = false;
        });
      }
    }
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      facing: CameraFacing.front, // ✅ CRUCIAL: Caméra frontale pour le mode miroir face-à-face
      formats: [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  Future<void> _generateQR() async {
    try {
      // ✅ OPTIMISATION: Récupérer directement les bytes, éviter les conversions hex
      final p2Bytes = widget.bon.p2Bytes;
      final p3Bytes = await _storageService.getP3FromCacheBytes(widget.bon.bonId);
      
      if (p2Bytes == null || p3Bytes == null) {
        throw Exception('Parts P2 ou P3 non disponibles.');
      }

      // ✅ OPTIMISATION: Utiliser encryptP2Bytes pour éviter les conversions hex
      final encrypted = await _cryptoService.encryptP2Bytes(p2Bytes, p3Bytes);
      
      // Générer un challenge aléatoire (16 octets)
      final challengeBytes = Uint8List.fromList(
        List.generate(16, (_) => Random.secure().nextInt(256))
      );
      _currentChallenge = HEX.encode(challengeBytes);

      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      // Reconstituer la clé privée du bon pour signer
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);
      
      // ✅ OPTIMISATION: Construire le message en bytes et signer directement
      final bonIdBytes = Uint8List.fromList(HEX.decode(widget.bon.bonId));
      final timestampBytes = ByteData(4);
      timestampBytes.setUint32(0, timestamp, Endian.big);
      
      // Message = bonId || ciphertext || nonce || challenge || timestamp
      final messageBytes = Uint8List.fromList([
        ...bonIdBytes,
        ...encrypted.ciphertext,
        ...encrypted.nonce,
        ...challengeBytes,
        ...timestampBytes.buffer.asUint8List(),
      ]);
      
      final signatureBytes = _cryptoService.signMessageBytesDirect(messageBytes, nsecBonBytes);
      
      // Nettoyer les bytes sensibles immédiatement
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);
      
      // Extraire P2 chiffré et le tag (AES-GCM produit ciphertext + tag)
      final ciphertext = encrypted.ciphertext;
      final encryptedP2Only = ciphertext.length >= 32
          ? ciphertext.sublist(0, 32)
          : ciphertext;
      final p2Tag = ciphertext.length >= 48
          ? ciphertext.sublist(32, 48)
          : Uint8List(16);

      // ✅ OPTIMISATION: Utiliser encodeQrV2Bytes pour éviter les conversions hex
      final issuerNpubBytes = Uint8List.fromList(HEX.decode(widget.bon.issuerNpub));
      final qrBytes = _qrService.encodeQrV2Bytes(
        bonId: bonIdBytes,
        valueInCentimes: (widget.bon.value * 100).round(),
        issuerNpub: issuerNpubBytes,
        issuerName: widget.bon.issuerName,
        encryptedP2: encryptedP2Only,
        p2Nonce: encrypted.nonce,
        p2Tag: p2Tag,
        challenge: challengeBytes,
        signature: signatureBytes,
      );

      setState(() {
        _qrData = qrBytes;
        _isGenerating = false;
        _statusMessage = 'Placez les téléphones face à face';
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _statusMessage = 'Erreur: $e';
      });
    }
  }

  Future<void> _handleAckScan(BarcodeCapture capture) async {
    if (_isProcessingAck || _isSuccess) return;
    
    final barcode = capture.barcodes.first;
    final base64String = barcode.rawValue;
    if (base64String == null) return;

    setState(() {
      _isProcessingAck = true;
      _statusMessage = 'Vérification...';
    });

    try {
      final decodedBytes = base64Decode(base64String);
      final ackData = _qrService.decodeAck(decodedBytes);

      if (!_cryptoService.isValidPublicKey(ackData['bonId']) || 
          ackData['bonId'] != widget.bon.bonId || 
          ackData['status'] != 0x01) {
        throw Exception('QR code incorrect');
      }

      final isValid = _cryptoService.verifySignature(
        _currentChallenge,
        ackData['signature'],
        widget.bon.bonId,
      );

      if (!isValid) throw Exception('Signature invalide');

      // Succès local
      final updatedBon = widget.bon.copyWith(p2: null, status: BonStatus.spent);
      await _storageService.saveBon(updatedBon);

      // ✅ VIBRATION ET SON MAGIQUES
      HapticFeedback.heavyImpact();
      _audioPlayer.play(AssetSource('sounds/bowl.mp3'));

      setState(() {
        _isSuccess = true;
        _statusMessage = 'Succès !';
      });

      // Tenter la publication Nostr en arrière-plan
      _publishTransferToNostr(ackData['receiverNpub']);

      // Proposer le follow après un court délai
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _showFollowPrompt(ackData['receiverNpub']);
        }
      });

    } catch (e) {
      setState(() {
        _isProcessingAck = false;
        _statusMessage = 'Erreur: $e. Réessayez.';
      });
    }
  }

  Future<void> _publishTransferToNostr(String? receiverNpub) async {
    if (receiverNpub == null) return;
    try {
      final market = await _storageService.getMarket();
      if (market == null || market.relayUrl == null) return;

      final p3 = await _storageService.getP3FromCache(widget.bon.bonId);
      if (p3 == null) return;

      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );

      final connected = await nostrService.connect(market.relayUrl!);
      if (connected) {
        await nostrService.publishTransfer(
          bonId: widget.bon.bonId,
          bonP2: widget.bon.p2!,
          bonP3: p3,
          receiverNpub: receiverNpub,
          value: widget.bon.value,
          marketName: market.name,
        );
        await nostrService.disconnect();
      }
      
      await _auditService.logTransfer(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        senderName: widget.user.displayName,
        senderNpub: widget.user.npub,
        receiverName: null,
        receiverNpub: receiverNpub,
        amount: widget.bon.value,
        bonId: widget.bon.bonId,
        method: 'QR_MIRROR',
        status: connected ? 'completed' : 'completed_offline',
        marketName: market.name,
        challenge: _currentChallenge,
      );
    } catch (e) {
      debugPrint('Erreur publication: $e');
    }
  }

  Future<void> _showFollowPrompt(String? receiverNpub) async {
    if (receiverNpub == null) {
      Navigator.pop(context);
      return;
    }

    final shouldFollow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
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
      await _storageService.addContact(receiverNpub);
      final market = await _storageService.getMarket();
      if (market != null && market.relayUrl != null) {
        final nostrService = NostrService(cryptoService: _cryptoService, storageService: _storageService);
        if (await nostrService.connect(market.relayUrl!)) {
          final contacts = await _storageService.getContacts();
          await nostrService.publishContactList(
            npub: widget.user.npub,
            nsec: widget.user.nsec,
            contactsNpubs: contacts,
          );
          await nostrService.disconnect();
        }
      }
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isSuccess ? Colors.green : Colors.black,
      appBar: AppBar(
        title: const Text('Donner (Mode Miroir)'),
        backgroundColor: _isSuccess ? Colors.green[700] : const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: _isSuccess ? _buildSuccessView() : _buildMirrorView(),
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
    return Column(
      children: [
        // Moitié HAUT : Le QR Code à montrer
        // Fond blanc pour maximiser le contraste et aider l'exposition de la caméra adverse
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            color: Colors.white,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isGenerating)
                  const CircularProgressIndicator(color: Colors.orange)
                else if (_qrData != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                    ),
                    child: _qrService.buildQrWidget(_qrData!, size: 240),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${widget.bon.value} ẐEN',
                  style: const TextStyle(color: Colors.black, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Montrez ce code',
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        
        // Séparateur
        Container(
          height: 4,
          color: Colors.orange,
        ),

        // Moitié BAS : La caméra pour scanner
        Expanded(
          flex: 1,
          child: Stack(
            children: [
              if (_isCheckingPermission)
                const Center(child: CircularProgressIndicator())
              else if (!_permissionGranted)
                const Center(child: Text('Caméra requise', style: TextStyle(color: Colors.white)))
              else if (_scannerController != null)
                MobileScanner(
                  controller: _scannerController!,
                  onDetect: _handleAckScan,
                ),
              
              // Overlay sombre pour ne pas polluer la détection de l'autre téléphone avec la lumière de l'écran
              Container(
                color: Colors.black.withOpacity(0.6),
              ),
              
              // Cadre de visée
              Center(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange.withOpacity(0.8), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              // Status message
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
