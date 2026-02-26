import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hex/hex.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../models/qr_payload_v2.dart';
import '../../services/qr_service.dart';
import '../../services/crypto_service.dart';
import '../../services/storage_service.dart';
import '../../services/audit_trail_service.dart';

class MirrorReceiveController extends ChangeNotifier {
  final User user;

  final QRService _qrService;
  final CryptoService _cryptoService;
  final StorageService _storageService;
  final AuditTrailService _auditService;
  final Uuid _uuid;

  MobileScannerController? scannerController;
  final AudioPlayer _audioPlayer;

  Uint8List? ackQrData;
  bool isProcessingOffer = false;
  bool isSuccess = false;
  String statusMessage = 'Scannez le QR du donneur';

  bool permissionGranted = false;
  bool isCheckingPermission = true;

  MirrorReceiveController({
    required this.user,
    QRService? qrService,
    CryptoService? cryptoService,
    StorageService? storageService,
    AuditTrailService? auditService,
    AudioPlayer? audioPlayer,
    Uuid? uuid,
  })  : _qrService = qrService ?? QRService(),
        _cryptoService = cryptoService ?? CryptoService(),
        _storageService = storageService ?? StorageService(),
        _auditService = auditService ?? AuditTrailService(),
        _audioPlayer = audioPlayer ?? AudioPlayer(),
        _uuid = uuid ?? const Uuid() {
    _checkCameraPermission();
  }

  @override
  void dispose() {
    scannerController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      _initScanner();
      permissionGranted = true;
      isCheckingPermission = false;
      notifyListeners();
    } else {
      final result = await Permission.camera.request();
      if (result.isGranted) {
        _initScanner();
        permissionGranted = true;
        isCheckingPermission = false;
        notifyListeners();
      } else {
        permissionGranted = false;
        isCheckingPermission = false;
        notifyListeners();
      }
    }
  }

  void _initScanner() {
    scannerController = MobileScannerController(
      facing: CameraFacing.front,
      formats: [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  Future<void> handleOfferScan(BarcodeCapture capture, VoidCallback onSuccess) async {
    if (isProcessingOffer || isSuccess || ackQrData != null) return;
    
    final barcode = capture.barcodes.first;
    final base64String = barcode.rawValue;
    if (base64String == null) return;

    isProcessingOffer = true;
    statusMessage = 'Traitement du bon...';
    notifyListeners();

    try {
      final decodedBytes = base64Decode(base64String);
      final qrV2Payload = _qrService.decodeQr(decodedBytes);
      
      if (qrV2Payload == null) {
        throw Exception('Format QR invalide ou obsolète (V1)');
      }

      await _processOffer(qrV2Payload, onSuccess);

    } catch (e) {
      isProcessingOffer = false;
      statusMessage = 'Erreur: $e';
      notifyListeners();
    }
  }

  Future<void> _processOffer(QrPayloadV2 payload, VoidCallback onSuccess) async {
    try {
      final p3Bytes = await _storageService.getP3FromCacheBytes(payload.bonId);
      if (p3Bytes == null) throw Exception('Bon introuvable localement. Connectez-vous à Internet et rafraîchissez votre wallet (⟳) pour synchroniser le marché, puis réessayez.');

      final encryptedP2WithTag = Uint8List.fromList([...payload.encryptedP2, ...payload.p2Tag]);
      final p2Bytes = await _cryptoService.decryptP2Bytes(
        encryptedP2WithTag,
        payload.p2Nonce,
        p3Bytes,
      );
      
      final p2 = HEX.encode(p2Bytes);

      final market = await _storageService.getMarket();
      final marketName = market?.name ?? 'Marché Local';

      final existingBon = await _storageService.getBonById(payload.bonId);
      
      DateTime? expiresAtFromMarket;
      final marketBonData = await _storageService.getMarketBonById(payload.bonId);
      if (marketBonData != null && marketBonData['expiresAt'] != null) {
        try {
          expiresAtFromMarket = DateTime.parse(marketBonData['expiresAt'] as String);
        } catch (e) {
          debugPrint('Erreur parsing expiresAt: $e');
        }
      }
      
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
        expiresAt: expiresAtFromMarket,
        picture: marketBonData?['picture'] as String?,
        banner: marketBonData?['banner'] as String?,
        picture64: marketBonData?['picture64'] as String?,
        banner64: marketBonData?['banner64'] as String?,
        logoUrl: marketBonData?['picture'] as String?,
        wish: marketBonData?['wish'] as String?,
        rarity: marketBonData?['rarity'] as String? ?? 'common',
        cardType: marketBonData?['category'] as String? ?? 'generic',
      );

      final updatedBon = existingBon != null
          ? existingBon.copyWith(
              status: BonStatus.active,
              p2: p2,
              expiresAt: existingBon.expiresAt ?? expiresAtFromMarket,
              picture: existingBon.picture ?? marketBonData?['picture'] as String?,
              banner: existingBon.banner ?? marketBonData?['banner'] as String?,
              picture64: existingBon.picture64 ?? marketBonData?['picture64'] as String?,
              banner64: existingBon.banner64 ?? marketBonData?['banner64'] as String?,
              logoUrl: existingBon.logoUrl ?? marketBonData?['picture'] as String?,
              wish: existingBon.wish ?? marketBonData?['wish'] as String?,
            )
          : bon;
      await _storageService.saveBon(updatedBon);

      await _logReceptionToAuditTrail(
        bonId: payload.bonId,
        value: payload.value,
        issuerNpub: payload.issuerNpub,
        issuerName: payload.issuerName,
        status: 'received',
      );

      final bonP2Bytes = updatedBon.p2Bytes;
      final bonP3Bytes = await _storageService.getP3FromCacheBytes(updatedBon.bonId);
      
      if (bonP2Bytes == null || bonP3Bytes == null) throw Exception('Erreur parts P2/P3');
      
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, bonP2Bytes, bonP3Bytes);
      
      final challengeHash = sha256.convert(payload.challenge).bytes;
      final challengeHashBytes = Uint8List.fromList(challengeHash);
      
      final signatureBytes = _cryptoService.signMessageBytesDirect(challengeHashBytes, nsecBonBytes);
      
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(bonP2Bytes);
      _cryptoService.secureZeroiseBytes(bonP3Bytes);
      
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

      Uint8List bonIdBytes;
      try {
        bonIdBytes = Uint8List.fromList(HEX.decode(updatedBon.bonId));
      } catch (e) {
        throw Exception('ID de bon invalide (non hexadécimal)');
      }
      final ackBytes = _qrService.encodeAckBytes(
        bonId: bonIdBytes,
        signature: signatureBytes,
      );

      HapticFeedback.mediumImpact();
      _audioPlayer.play(AssetSource('sounds/tap.mp3'));

      ackQrData = ackBytes;
      isProcessingOffer = false;
      statusMessage = 'Montrez ce QR au donneur';
      notifyListeners();

      Future.delayed(const Duration(seconds: 3), () {
        HapticFeedback.heavyImpact();
        _audioPlayer.play(AssetSource('sounds/bowl.mp3'));
        isSuccess = true;
        notifyListeners();
        Future.delayed(const Duration(seconds: 2), () {
          onSuccess();
        });
      });

    } catch (e) {
      rethrow;
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
        receiverName: user.displayName,
        receiverNpub: user.npub,
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
}
