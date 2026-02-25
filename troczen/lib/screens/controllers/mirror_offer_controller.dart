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
import 'package:crypto/crypto.dart';
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../services/qr_service.dart';
import '../../services/crypto_service.dart';
import '../../services/storage_service.dart';
import '../../services/audit_trail_service.dart';
import '../../services/nostr_service.dart';

class MirrorOfferController extends ChangeNotifier {
  final User user;
  final Bon bon;

  final QRService _qrService;
  final CryptoService _cryptoService;
  final StorageService _storageService;
  final AuditTrailService _auditService;
  final Uuid _uuid;

  MobileScannerController? scannerController;
  final AudioPlayer _audioPlayer;

  Uint8List? qrData;
  bool isGenerating = true;
  bool isProcessingAck = false;
  bool isSuccess = false;
  String statusMessage = 'Génération de l\'offre...';
  String currentChallenge = '';

  bool permissionGranted = false;
  bool isCheckingPermission = true;

  MirrorOfferController({
    required this.user,
    required this.bon,
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
    _generateQR();
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

  Future<void> _generateQR() async {
    try {
      final p2Bytes = bon.p2Bytes;
      final p3Bytes = await _storageService.getP3FromCacheBytes(bon.bonId);
      
      if (p2Bytes == null || p3Bytes == null) {
        throw Exception('Parts P2 ou P3 non disponibles.');
      }

      final encrypted = await _cryptoService.encryptP2Bytes(p2Bytes, p3Bytes);
      
      final challengeBytes = Uint8List.fromList(
        List.generate(16, (_) => Random.secure().nextInt(256))
      );
      currentChallenge = HEX.encode(challengeBytes);

      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);
      
      final bonIdBytes = Uint8List.fromList(HEX.decode(bon.bonId));
      final timestampBytes = ByteData(4);
      timestampBytes.setUint32(0, timestamp, Endian.big);
      
      final messageBytes = Uint8List.fromList([
        ...bonIdBytes,
        ...encrypted.ciphertext,
        ...encrypted.nonce,
        ...challengeBytes,
        ...timestampBytes.buffer.asUint8List(),
      ]);
      
      final messageHash = sha256.convert(messageBytes);
      final messageHashBytes = Uint8List.fromList(messageHash.bytes);
      
      final signatureBytes = _cryptoService.signMessageBytesDirect(messageHashBytes, nsecBonBytes);
      
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);
      
      final ciphertext = encrypted.ciphertext;
      final encryptedP2Only = ciphertext.length >= 32
          ? ciphertext.sublist(0, 32)
          : ciphertext;
      final p2Tag = ciphertext.length >= 48
          ? ciphertext.sublist(32, 48)
          : Uint8List(16);

      final issuerNpubBytes = Uint8List.fromList(HEX.decode(bon.issuerNpub));
      final qrBytes = _qrService.encodeQrV2Bytes(
        bonId: bonIdBytes,
        valueInCentimes: (bon.value * 100).round(),
        issuerNpub: issuerNpubBytes,
        issuerName: bon.issuerName,
        encryptedP2: encryptedP2Only,
        p2Nonce: encrypted.nonce,
        p2Tag: p2Tag,
        challenge: challengeBytes,
        signature: signatureBytes,
      );

      qrData = qrBytes;
      isGenerating = false;
      statusMessage = 'Placez les téléphones face à face';
      notifyListeners();
    } catch (e) {
      isGenerating = false;
      statusMessage = 'Erreur: $e';
      notifyListeners();
    }
  }

  Future<void> handleAckScan(BarcodeCapture capture, Function(String) onFollowPrompt) async {
    if (isProcessingAck || isSuccess) return;
    
    final barcode = capture.barcodes.first;
    final base64String = barcode.rawValue;
    if (base64String == null) return;

    isProcessingAck = true;
    statusMessage = 'Vérification...';
    notifyListeners();

    try {
      final decodedBytes = base64Decode(base64String);
      final ackData = _qrService.decodeAck(decodedBytes);

      if (!_cryptoService.isValidPublicKey(ackData['bonId']) ||
          ackData['bonId'] != bon.bonId ||
          ackData['status'] != 0x01) {
        throw Exception('QR code incorrect');
      }

      final challengeBytes = Uint8List.fromList(HEX.decode(currentChallenge));
      final challengeHash = sha256.convert(challengeBytes);
      final challengeHashHex = challengeHash.toString();
      
      final isValid = _cryptoService.verifySignature(
        challengeHashHex,
        ackData['signature'],
        bon.bonId,
      );

      if (!isValid) throw Exception('Signature invalide');

      final updatedBon = bon.copyWith(p2: null, status: BonStatus.spent);
      await _storageService.saveBon(updatedBon);

      HapticFeedback.heavyImpact();
      _audioPlayer.play(AssetSource('sounds/bowl.mp3'));

      isSuccess = true;
      statusMessage = 'Succès !';
      notifyListeners();

      _publishTransferToNostr(ackData['receiverNpub']);

      Future.delayed(const Duration(seconds: 2), () {
        onFollowPrompt(ackData['receiverNpub']);
      });

    } catch (e) {
      isProcessingAck = false;
      statusMessage = 'Erreur: $e. Réessayez.';
      notifyListeners();
    }
  }

  Future<void> _publishTransferToNostr(String? receiverNpub) async {
    if (receiverNpub == null) return;
    try {
      final market = await _storageService.getMarket();
      if (market == null || market.relayUrl == null) return;

      final p3 = await _storageService.getP3FromCache(bon.bonId);
      if (p3 == null) return;

      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );

      final connected = await nostrService.connect(market.relayUrl!);
      if (connected) {
        await nostrService.publishTransfer(
          bonId: bon.bonId,
          bonP2: bon.p2!,
          bonP3: p3,
          receiverNpub: receiverNpub,
          value: bon.value,
          marketName: market.name,
        );
        await nostrService.disconnect();
      }
      
      await _auditService.logTransfer(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        senderName: user.displayName,
        senderNpub: user.npub,
        receiverName: null,
        receiverNpub: receiverNpub,
        amount: bon.value,
        bonId: bon.bonId,
        method: 'QR_MIRROR',
        status: connected ? 'completed' : 'completed_offline',
        marketName: market.name,
        challenge: currentChallenge,
      );
    } catch (e) {
      debugPrint('Erreur publication: \$e');
    }
  }

  Future<void> handleFollow(String receiverNpub) async {
    await _storageService.addContact(receiverNpub);
    final market = await _storageService.getMarket();
    if (market != null && market.relayUrl != null) {
      final nostrService = NostrService(cryptoService: _cryptoService, storageService: _storageService);
      if (await nostrService.connect(market.relayUrl!)) {
        final contacts = await _storageService.getContacts();
        await nostrService.publishContactList(
          npub: user.npub,
          nsec: user.nsec,
          contactsNpubs: contacts,
        );
        await nostrService.disconnect();
      }
    }
  }
}
