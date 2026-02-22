import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/qr_service.dart';
import 'package:hex/hex.dart';
import 'dart:typed_data';

void main() {
  late QRService qrService;

  setUp(() {
    qrService = QRService();
  });

  group('QRService - Offer Encoding/Decoding', () {
    test('encodeQrV2Bytes génère exactement 240 octets', () {
      final qrData = qrService.encodeQrV2Bytes(
        bonId: Uint8List(32),
        valueInCentimes: 1000,
        issuerNpub: Uint8List(32),
        issuerName: "Test Issuer",
        encryptedP2: Uint8List(32),
        p2Nonce: Uint8List(12),
        p2Tag: Uint8List(16),
        challenge: Uint8List(16),
        signature: Uint8List(64),
      );

      expect(qrData.length, equals(240));
    });

    test('decodeQr reconstruit les données correctement', () {
      final bonId = Uint8List.fromList(List.generate(32, (i) => i));
      final issuerNpub = Uint8List.fromList(List.generate(32, (i) => i + 50));
      final encryptedP2 = Uint8List.fromList(List.generate(32, (i) => i + 100));
      final p2Nonce = Uint8List.fromList(List.generate(12, (i) => i + 200));
      final p2Tag = Uint8List.fromList(List.generate(16, (i) => i + 150));
      final challenge = Uint8List.fromList(List.generate(16, (i) => i + 50));
      final signature = Uint8List.fromList(List.generate(64, (i) => i + 150));

      final encoded = qrService.encodeQrV2Bytes(
        bonId: bonId,
        valueInCentimes: 1000,
        issuerNpub: issuerNpub,
        issuerName: "Test Issuer",
        encryptedP2: encryptedP2,
        p2Nonce: p2Nonce,
        p2Tag: p2Tag,
        challenge: challenge,
        signature: signature,
      );

      final decoded = qrService.decodeQr(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.bonId, equals(HEX.encode(bonId)));
      expect(decoded.valueInCentimes, equals(1000));
      expect(decoded.issuerNpub, equals(HEX.encode(issuerNpub)));
      expect(decoded.issuerName, equals("Test Issuer"));
      expect(decoded.encryptedP2, equals(encryptedP2));
      expect(decoded.p2Nonce, equals(p2Nonce));
      expect(decoded.p2Tag, equals(p2Tag));
      expect(decoded.challenge, equals(challenge));
      expect(decoded.signature, equals(signature));
    });

    test('decodeQr rejette les données de mauvaise taille', () {
      final badData = Uint8List(100); // Devrait être 240

      expect(qrService.decodeQr(badData), isNull);
    });
  });

  group('QRService - ACK Encoding/Decoding', () {
    test('encodeAck génère exactement 97 octets', () {
      final ackData = qrService.encodeAck(
        bonIdHex: '0' * 64,
        signatureHex: '1' * 128,
        status: 0x01,
      );

      expect(ackData.length, equals(97));
    });

    test('decodeAck reconstruit les données correctement', () {
      final bonId = 'e' * 64;
      final signature = 'f' * 128;
      final status = 0x01;

      final encoded = qrService.encodeAck(
        bonIdHex: bonId,
        signatureHex: signature,
        status: status,
      );

      final decoded = qrService.decodeAck(encoded);

      expect(decoded['bonId'], equals(bonId));
      expect(decoded['signature'], equals(signature));
      expect(decoded['status'], equals(status));
    });

    test('decodeAck rejette les données de mauvaise taille', () {
      final badData = Uint8List(50); // Devrait être 97

      expect(
        () => qrService.decodeAck(badData),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('QRService - TTL Management', () {
    test('isExpired retourne false pour un QR valide', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timestamp = now - 10; // Il y a 10 secondes
      final ttl = 30; // Expire dans 20 secondes

      expect(qrService.isExpired(timestamp, ttl), isFalse);
    });

    test('isExpired retourne true pour un QR expiré', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timestamp = now - 40; // Il y a 40 secondes
      final ttl = 30; // Expiré depuis 10 secondes

      expect(qrService.isExpired(timestamp, ttl), isTrue);
    });

    test('timeRemaining calcule le temps restant correctement', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timestamp = now - 10; // Il y a 10 secondes
      final ttl = 30; // Expire dans 20 secondes

      final remaining = qrService.timeRemaining(timestamp, ttl);
      
      expect(remaining, greaterThanOrEqualTo(19));
      expect(remaining, lessThanOrEqualTo(21));
    });

    test('timeRemaining retourne 0 pour un QR expiré', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timestamp = now - 40;
      final ttl = 30;

      expect(qrService.timeRemaining(timestamp, ttl), equals(0));
    });

    test('TTL à 0 expire immédiatement', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(qrService.isExpired(now, 0), isTrue);
    });

    test('Timestamp futur est valide', () {
      final future = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 100;
      expect(qrService.isExpired(future, 30), isFalse);
    });
  });
}
