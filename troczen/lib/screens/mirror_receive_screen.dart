import 'dart:async';
import 'dart:convert';
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
import '../models/qr_payload_v2.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/audit_trail_service.dart';

/// Écran "Mode Miroir" pour le Receveur (Bob)
/// Haut: Affiche le QR Code de l'ACK (QR2) une fois généré
/// Bas: Caméra active pour scanner l'offre (QR1)
class MirrorReceiveScreen extends StatefulWidget {
  final User user;

  const MirrorReceiveScreen({super.key, required this.user});

  @override
  State<MirrorReceiveScreen> createState() => _MirrorReceiveScreenState();
}

class _MirrorReceiveScreenState extends State<MirrorReceiveScreen> {
  final _qrService = QRService();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();
  final _auditService = AuditTrailService();
  final _uuid = const Uuid();

  MobileScannerController? _scannerController;
  
  Uint8List? _ackQrData;
  bool _isProcessingOffer = false;
  bool _isSuccess = false;
  String _statusMessage = 'Scannez le QR du donneur';
  
  bool _permissionGranted = false;
  bool _isCheckingPermission = true;
  
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
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

  Future<void> _handleOfferScan(BarcodeCapture capture) async {
    if (_isProcessingOffer || _isSuccess || _ackQrData != null) return;
    
    final barcode = capture.barcodes.first;
    final base64String = barcode.rawValue;
    if (base64String == null) return;

    setState(() {
      _isProcessingOffer = true;
      _statusMessage = 'Traitement du bon...';
    });

    try {
      final decodedBytes = base64Decode(base64String);
      final qrV2Payload = _qrService.decodeQr(decodedBytes);
      
      if (qrV2Payload == null) {
        throw Exception('Format QR invalide ou obsolète (V1)');
      }

      await _processOffer(qrV2Payload);

    } catch (e) {
      setState(() {
        _isProcessingOffer = false;
        _statusMessage = 'Erreur: $e';
      });
    }
  }

  Future<void> _processOffer(QrPayloadV2 payload) async {
    try {
      final p3 = await _storageService.getP3FromCache(payload.bonId);
      if (p3 == null) throw Exception('Part P3 non trouvée. Synchronisez le marché.');

      final encryptedP2WithTag = Uint8List.fromList([...payload.encryptedP2, ...payload.p2Tag]);
      final p2 = await _cryptoService.decryptP2(
        HEX.encode(encryptedP2WithTag),
        HEX.encode(payload.p2Nonce),
        p3,
      );

      final market = await _storageService.getMarket();
      final marketName = market?.name ?? 'Marché Local';

      final existingBon = await _storageService.getBonById(payload.bonId);
      final bon = existingBon ?? Bon(
        bonId: payload.bonId,
        value: payload.value,
        issuerName: payload.issuerName,
        issuerNpub: payload.issuerNpub,
        p2: p2,
        p3: null,
        status: BonStatus.active,
        createdAt: payload.emittedAt,
        marketName: marketName,
        // ✅ RÈGLE ÉCONOMIQUE : Une fois échangé, le bon perd sa date d'expiration
        // (La monnaie fondante ne s'applique qu'au créateur initial pour forcer l'injection)
        expiresAt: null,
      );

      final updatedBon = existingBon != null ? existingBon.copyWith(status: BonStatus.active, p2: p2) : bon;
      await _storageService.saveBon(updatedBon);

      await _logReceptionToAuditTrail(
        bonId: payload.bonId,
        value: payload.value,
        issuerNpub: payload.issuerNpub,
        issuerName: payload.issuerName,
        status: 'received',
      );

      // Générer l'ACK
      final p2Bytes = updatedBon.p2Bytes;
      final p3Bytes = await _storageService.getP3FromCacheBytes(updatedBon.bonId);
      
      if (p2Bytes == null || p3Bytes == null) throw Exception('Erreur parts P2/P3');
      
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);
      final signatureHex = _cryptoService.signMessageBytes(payload.challengeHex, nsecBonBytes);
      
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

      final ackBytes = _qrService.encodeAck(
        bonIdHex: updatedBon.bonId,
        signatureHex: signatureHex,
      );

      // ✅ VIBRATION ET SON MAGIQUES (1ère étape: offre reçue)
      HapticFeedback.mediumImpact();
      _audioPlayer.play(AssetSource('sounds/tap.mp3'));

      setState(() {
        _ackQrData = ackBytes;
        _isProcessingOffer = false;
        _statusMessage = 'Montrez ce QR au donneur';
      });

      // On considère que c'est un succès pour le receveur une fois l'ACK généré
      // Le donneur validera de son côté
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          // ✅ VIBRATION ET SON MAGIQUES (2ème étape: succès final)
          HapticFeedback.heavyImpact();
          _audioPlayer.play(AssetSource('sounds/bowl.mp3'));
          setState(() {
            _isSuccess = true;
          });
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        }
      });

    } catch (e) {
      throw e;
    }
  }

  Future<void> _logReceptionToAuditTrail({
    required String bonId,
    required double value,
    required String issuerNpub,
    required String issuerName,
    required String status,
  }) async {
    try {
      final market = await _storageService.getMarket();
      await _auditService.logTransfer(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        senderName: issuerName,
        senderNpub: issuerNpub,
        receiverName: widget.user.displayName,
        receiverNpub: widget.user.npub,
        amount: value,
        bonId: bonId,
        method: 'QR_MIRROR',
        status: status,
        marketName: market?.name,
      );
    } catch (e) {
      debugPrint('Erreur logging: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isSuccess ? Colors.green : Colors.black,
      appBar: AppBar(
        title: const Text('Recevoir (Mode Miroir)'),
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
            'Bon Reçu !',
            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMirrorView() {
    return Column(
      children: [
        // Moitié HAUT : Le QR Code ACK à montrer (ou attente)
        // Fond blanc pour maximiser le contraste et aider l'exposition de la caméra adverse
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            color: _ackQrData != null ? Colors.white : const Color(0xFF121212),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_ackQrData != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                    ),
                    child: _qrService.buildQrWidget(_ackQrData!, size: 240),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Confirmation générée',
                    style: TextStyle(color: Colors.green, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Laissez le donneur scanner',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                ] else ...[
                  const Icon(Icons.qr_code_scanner, color: Colors.grey, size: 80),
                  const SizedBox(height: 16),
                  const Text(
                    'En attente du bon...',
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                ],
              ],
            ),
          ),
        ),
        
        // Séparateur
        Container(
          height: 4,
          color: _ackQrData != null ? Colors.green : Colors.orange,
        ),

        // Moitié BAS : La caméra pour scanner l'offre
        Expanded(
          flex: 1,
          child: Stack(
            children: [
              if (_isCheckingPermission)
                const Center(child: CircularProgressIndicator())
              else if (!_permissionGranted)
                const Center(child: Text('Caméra requise', style: TextStyle(color: Colors.white)))
              else if (_scannerController != null && _ackQrData == null)
                MobileScanner(
                  controller: _scannerController!,
                  onDetect: _handleOfferScan,
                )
              else if (_ackQrData != null)
                Container(color: Colors.black87, child: const Center(child: Text('Scan terminé', style: TextStyle(color: Colors.white)))),
              
              // Overlay sombre pour ne pas polluer la détection de l'autre téléphone avec la lumière de l'écran
              if (_ackQrData == null)
                Container(
                  color: Colors.black.withOpacity(0.6),
                ),
              
              if (_ackQrData == null)
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
