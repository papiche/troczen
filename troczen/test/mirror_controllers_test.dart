import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/models/user.dart';
import 'package:troczen/models/bon.dart';
import 'package:troczen/models/qr_payload_v2.dart';
import 'package:troczen/screens/controllers/mirror_offer_controller.dart';
import 'package:troczen/screens/controllers/mirror_receive_controller.dart';
import 'package:troczen/services/qr_service.dart';
import 'package:troczen/services/crypto_service.dart';
import 'package:troczen/services/storage_service.dart';
import 'package:troczen/services/audit_trail_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:hex/hex.dart';
import 'package:flutter/services.dart';

// --- Fakes ---

class FakeQRService extends QRService {
  @override
  Uint8List encodeQrV2Bytes({
    required Uint8List bonId,
    required int valueInCentimes,
    required Uint8List issuerNpub,
    required String issuerName,
    required Uint8List encryptedP2,
    required Uint8List p2Nonce,
    required Uint8List p2Tag,
    required Uint8List challenge,
    required Uint8List signature,
  }) {
    return Uint8List.fromList([1, 2, 3]); // Fake QR data
  }

  @override
  Map<String, dynamic> decodeAck(Uint8List bytes) {
    return {
      'bonId': 'fake_bon_id',
      'status': 0x01,
      'signature': 'fake_signature',
      'receiverNpub': 'fake_receiver_npub',
    };
  }

  @override
  QrPayloadV2? decodeQr(Uint8List bytes) {
    return QrPayloadV2(
      bonId: 'fake_bon_id',
      valueInCentimes: 1000,
      issuerNpub: 'fake_issuer_npub',
      issuerName: 'Fake Issuer',
      encryptedP2: Uint8List(32),
      p2Nonce: Uint8List(12),
      p2Tag: Uint8List(16),
      challenge: Uint8List(16),
      signature: Uint8List(64),
      emittedAt: DateTime.now(),
    );
  }

  @override
  Uint8List encodeAckBytes({
    required Uint8List bonId,
    required Uint8List signature,
    int status = 0x01,
  }) {
    return Uint8List.fromList([4, 5, 6]); // Fake ACK QR data
  }
}

class FakeCryptoService extends CryptoService {
  @override
  Future<EncryptP2Result> encryptP2Bytes(Uint8List p2Bytes, Uint8List p3Bytes) async {
    return EncryptP2Result(ciphertext: Uint8List(48), nonce: Uint8List(12), tag: Uint8List(16));
  }

  @override
  Future<Uint8List> decryptP2Bytes(Uint8List encryptedP2WithTag, Uint8List nonce, Uint8List p3Bytes) async {
    return Uint8List(32);
  }

  @override
  Uint8List shamirCombineBytesDirect(Uint8List? p1, Uint8List? p2, Uint8List? p3) {
    return Uint8List(32);
  }

  @override
  Uint8List signMessageBytesDirect(Uint8List messageHash, Uint8List privateKey) {
    return Uint8List(64);
  }

  @override
  bool verifySignature(String messageHashHex, String signatureHex, String publicKeyHex) {
    return true; // Always valid for tests
  }

  @override
  bool isValidPublicKey(String publicKeyHex) {
    return true;
  }

  @override
  void secureZeroiseBytes(Uint8List bytes) {
    // Do nothing
  }
}

class FakeStorageService extends StorageService {
  @override
  Future<Uint8List?> getP3FromCacheBytes(String bonId) async {
    return Uint8List(32);
  }

  @override
  Future<void> saveBon(Bon bon) async {
    // Do nothing
  }

  @override
  Future<Bon?> getBonById(String bonId) async {
    return Bon(
      bonId: bonId,
      value: 10.0,
      issuerName: 'Fake Issuer',
      issuerNpub: 'fake_issuer_npub',
      p2: HEX.encode(Uint8List(32)),
      status: BonStatus.active,
      createdAt: DateTime.now(),
      marketName: 'Fake Market',
    );
  }

  @override
  Future<Map<String, dynamic>?> getMarketBonById(String bonId) async {
    return null;
  }
}

class FakeAuditTrailService extends AuditTrailService {
  @override
  Future<void> logTransfer({
    required String id,
    required DateTime timestamp,
    String? senderName,
    required String senderNpub,
    String? receiverName,
    required String receiverNpub,
    required double amount,
    required String bonId,
    required String method,
    required String status,
    String? marketName,
    String? rarity,
    int? transferCount,
    String? challenge,
    String? signature,
    String? deviceId,
    String? appVersion,
  }) async {
    // Do nothing
  }
}

class FakeAudioPlayer extends AudioPlayer {
  @override
  Future<void> play(Source source, {double? volume, double? balance, AudioContext? ctx, Duration? position, PlayerMode? mode}) async {
    // Do nothing
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Mock permission_handler platform channel
    const MethodChannel('flutter.baseflow.com/permissions/methods')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'checkPermissionStatus') {
        return 1; // 1 = granted
      }
      if (methodCall.method == 'requestPermissions') {
        return {1: 1}; // 1 = camera, 1 = granted
      }
      return null;
    });

    // Mock audioplayers platform channel
    const MethodChannel('xyz.luan/audioplayers')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      return 1;
    });
    const MethodChannel('xyz.luan/audioplayers.global')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      return 1;
    });
  });

  group('MirrorOfferController Tests', () {
    late User testUser;
    late Bon testBon;
    late FakeQRService fakeQRService;
    late FakeCryptoService fakeCryptoService;
    late FakeStorageService fakeStorageService;
    late FakeAuditTrailService fakeAuditTrailService;
    late FakeAudioPlayer fakeAudioPlayer;

    setUp(() {
      testUser = User(
        npub: 'test_npub',
        nsec: 'test_nsec',
        displayName: 'Test User',
        createdAt: DateTime.now(),
      );

      testBon = Bon(
        bonId: HEX.encode(Uint8List(32)),
        value: 10.0,
        issuerName: 'Issuer',
        issuerNpub: HEX.encode(Uint8List(32)),
        p2: HEX.encode(Uint8List(32)),
        status: BonStatus.active,
        createdAt: DateTime.now(),
        marketName: 'Market',
      );

      fakeQRService = FakeQRService();
      fakeCryptoService = FakeCryptoService();
      fakeStorageService = FakeStorageService();
      fakeAuditTrailService = FakeAuditTrailService();
      fakeAudioPlayer = FakeAudioPlayer();
    });

    test('Initial state is generating', () {
      final controller = MirrorOfferController(
        user: testUser,
        bon: testBon,
        qrService: fakeQRService,
        cryptoService: fakeCryptoService,
        storageService: fakeStorageService,
        auditService: fakeAuditTrailService,
        audioPlayer: fakeAudioPlayer,
      );

      expect(controller.isGenerating, isTrue);
      expect(controller.statusMessage, 'Génération de l\'offre...');
    });

    test('QR generation success updates state', () async {
      final controller = MirrorOfferController(
        user: testUser,
        bon: testBon,
        qrService: fakeQRService,
        cryptoService: fakeCryptoService,
        storageService: fakeStorageService,
        auditService: fakeAuditTrailService,
        audioPlayer: fakeAudioPlayer,
      );

      // Wait for async generation to complete
      await Future.delayed(const Duration(milliseconds: 100));

      expect(controller.isGenerating, isFalse);
      expect(controller.qrData, isNotNull);
      expect(controller.statusMessage, 'Placez les téléphones face à face');
    });
  });

  group('MirrorReceiveController Tests', () {
    late User testUser;
    late FakeQRService fakeQRService;
    late FakeCryptoService fakeCryptoService;
    late FakeStorageService fakeStorageService;
    late FakeAuditTrailService fakeAuditTrailService;
    late FakeAudioPlayer fakeAudioPlayer;

    setUp(() {
      testUser = User(
        npub: 'test_npub',
        nsec: 'test_nsec',
        displayName: 'Test User',
        createdAt: DateTime.now(),
      );

      fakeQRService = FakeQRService();
      fakeCryptoService = FakeCryptoService();
      fakeStorageService = FakeStorageService();
      fakeAuditTrailService = FakeAuditTrailService();
      fakeAudioPlayer = FakeAudioPlayer();
    });

    test('Initial state is waiting for scan', () {
      final controller = MirrorReceiveController(
        user: testUser,
        qrService: fakeQRService,
        cryptoService: fakeCryptoService,
        storageService: fakeStorageService,
        auditService: fakeAuditTrailService,
        audioPlayer: fakeAudioPlayer,
      );

      expect(controller.isProcessingOffer, isFalse);
      expect(controller.ackQrData, isNull);
      expect(controller.statusMessage, 'Scannez le QR du donneur');
    });
  });
}
