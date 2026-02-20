import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/qr_service.dart';
import 'dart:typed_data';

void main() {
  late QRService qrService;

  setUp(() {
    qrService = QRService();
  });

  group('QRService - Offer Encoding/Decoding', () {
    test('encodeOffer génère exactement 177 octets', () {
      final qrData = qrService.encodeOffer(
        bonIdHex: '0' * 64,
        p2CipherHex: '1' * 96,
        nonceHex: '2' * 24,
        challengeHex: '3' * 32,
        timestamp: 1234567890,
        ttl: 30,
        signatureHex: '4' * 128,
      );

      expect(qrData.length, equals(177));
    });

    test('decodeOffer reconstruit les données correctement', () {
      final bonId = 'a' * 64;
      final p2Cipher = 'b' * 96;
      final nonce = 'c' * 24;
      final challenge = 'd' * 32;
      final timestamp = 1700000000;
      final ttl = 30;
      final signature = 'e' * 128;

      final encoded = qrService.encodeOffer(
        bonIdHex: bonId,
        p2CipherHex: p2Cipher,
        nonceHex: nonce,
        challengeHex: challenge,
        timestamp: timestamp,
        ttl: ttl,
        signatureHex: signature,
      );

      final decoded = qrService.decodeOffer(encoded);

      expect(decoded['bonId'], equals(bonId));
      expect(decoded['p2Cipher'], equals(p2Cipher));
      expect(decoded['nonce'], equals(nonce));
      expect(decoded['challenge'], equals(challenge));
      expect(decoded['timestamp'], equals(timestamp));
      expect(decoded['ttl'], equals(ttl));
      expect(decoded['signature'], equals(signature));
    });

    test('decodeOffer rejette les données de mauvaise taille', () {
      final badData = Uint8List(100); // Devrait être 177

      expect(
        () => qrService.decodeOffer(badData),
        throwsA(isA<Exception>()),
      );
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
  });

  group('QRService - Edge Cases', () {
    test('encode/decode avec valeurs hexadécimales variées', () {
      final testCases = [
        '0' * 64,
        'f' * 64,
        '0123456789abcdef' * 4,
        'ABCDEF0123456789' * 4,
      ];

      for (final bonId in testCases) {
        final encoded = qrService.encodeOffer(
          bonIdHex: bonId,
          p2CipherHex: '1' * 96,
          nonceHex: '2' * 24,
          challengeHex: '3' * 32,
          timestamp: 1234567890,
          ttl: 30,
          signatureHex: '4' * 128,
        );

        final decoded = qrService.decodeOffer(encoded);
        expect(decoded['bonId'].toLowerCase(), equals(bonId.toLowerCase()));
      }
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
