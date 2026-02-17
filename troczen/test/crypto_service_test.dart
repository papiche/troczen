import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/crypto_service.dart';

void main() {
  group('CryptoService', () {
    late CryptoService cryptoService;

    setUp(() {
      cryptoService = CryptoService();
    });

    test('derivePrivateKey génère une clé déterministe', () async {
      final key1 = await cryptoService.derivePrivateKey('alice', 'password123');
      final key2 = await cryptoService.derivePrivateKey('alice', 'password123');
      
      expect(key1, equals(key2), reason: 'Même login/password = même clé');
    });

    test('derivePrivateKey génère des clés différentes pour différents utilisateurs', () async {
      final keyAlice = await cryptoService.derivePrivateKey('alice', 'password123');
      final keyBob = await cryptoService.derivePrivateKey('bob', 'password123');
      
      expect(keyAlice, isNot(equals(keyBob)), reason: 'Différents logins = différentes clés');
    });

    test('generateNostrKeyPair génère des clés valides', () {
      final keys = cryptoService.generateNostrKeyPair();
      
      expect(keys['nsec'], isNotNull);
      expect(keys['npub'], isNotNull);
      expect(keys['nsec']!.length, equals(64), reason: 'nsec = 32 bytes = 64 hex');
      expect(keys['npub']!.length, equals(64), reason: 'npub = 32 bytes = 64 hex');
    });

    test('Shamir split génère 3 parts différentes', () {
      final secret = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final parts = cryptoService.shamirSplit(secret);
      
      expect(parts.length, equals(3));
      expect(parts[0], isNot(equals(parts[1])));
      expect(parts[1], isNot(equals(parts[2])));
      expect(parts[0], isNot(equals(parts[2])));
    });

    test('Shamir combine reconstruit le secret avec P1 + P2', () {
      final secret = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
      final parts = cryptoService.shamirSplit(secret);
      
      final reconstructed = cryptoService.shamirCombine(parts[0], parts[1], null);
      
      expect(reconstructed, equals(secret), reason: 'P1 + P2 = secret');
    });

    test('Shamir combine reconstruit le secret avec P2 + P3', () {
      final secret = 'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd';
      final parts = cryptoService.shamirSplit(secret);
      
      final reconstructed = cryptoService.shamirCombine(null, parts[1], parts[2]);
      
      expect(reconstructed, equals(secret), reason: 'P2 + P3 = secret');
    });

    test('Shamir combine reconstruit le secret avec P1 + P3', () {
      final secret = '1111111111111111222222222222222233333333333333334444444444444444';
      final parts = cryptoService.shamirSplit(secret);
      
      final reconstructed = cryptoService.shamirCombine(parts[0], null, parts[2]);
      
      expect(reconstructed, equals(secret), reason: 'P1 + P3 = secret');
    });

    test('Shamir combine lance une erreur avec moins de 2 parts', () {
      expect(
        () => cryptoService.shamirCombine(null, null, null),
        throwsArgumentError,
        reason: 'Nécessite au moins 2 parts',
      );
    });

    test('encryptP2/decryptP2 fonctionne correctement', () async {
      final p2 = 'aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd';
      final p3 = '1122334411223344112233441122334411223344112233441122334411223344';
      
      // Chiffrer
      final encrypted = await cryptoService.encryptP2(p2, p3);
      expect(encrypted['ciphertext'], isNotNull);
      expect(encrypted['nonce'], isNotNull);
      expect(encrypted['nonce']!.length, equals(24), reason: 'Nonce = 12 bytes = 24 hex');
      
      // Déchiffrer
      final decrypted = await cryptoService.decryptP2(
        encrypted['ciphertext']!,
        encrypted['nonce']!,
        p3,
      );
      
      expect(decrypted, equals(p2), reason: 'Déchiffrement récupère P2 original');
    });

    test('encryptP3/decryptP3 fonctionne correctement', () async {
      final p3 = 'ffeeffffeeffffeeffffeeffffeeffffeeffffeeffffeeffffeeffffeeffffee';
      final kmarket = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      
      // Chiffrer
      final encrypted = await cryptoService.encryptP3(p3, kmarket);
      expect(encrypted['ciphertext'], isNotNull);
      expect(encrypted['nonce'], isNotNull);
      
      // Déchiffrer
      final decrypted = await cryptoService.decryptP3(
        encrypted['ciphertext']!,
        encrypted['nonce']!,
        kmarket,
      );
      
      expect(decrypted, equals(p3), reason: 'Déchiffrement récupère P3 original');
    });

    test('Chiffrement génère des ciphertexts différents avec nonces différents', () async {
      final p2 = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
      final p3 = 'cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe';
      
      final encrypted1 = await cryptoService.encryptP2(p2, p3);
      final encrypted2 = await cryptoService.encryptP2(p2, p3);
      
      expect(
        encrypted1['ciphertext'],
        isNot(equals(encrypted2['ciphertext'])),
        reason: 'Nonces différents = ciphertexts différents',
      );
    });

    test('signMessage génère une signature valide', () {
      final message = 'deadbeef';
      final privateKey = 'aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd';
      
      final signature = cryptoService.signMessage(message, privateKey);
      
      expect(signature.length, equals(128), reason: 'Signature Schnorr = 64 bytes = 128 hex');
    });

    test('verifySignature valide une signature correcte', () async {
      final message = 'cafebabe';
      
      // Générer une paire de clés
      final keys = cryptoService.generateNostrKeyPair();
      
      // Signer
      final signature = cryptoService.signMessage(message, keys['nsec']!);
      
      // Vérifier
      final isValid = cryptoService.verifySignature(message, signature, keys['npub']!);
      
      expect(isValid, isTrue, reason: 'Signature doit être valide');
    });

    test('verifySignature rejette une signature invalide', () {
      final message = 'deadbeef';
      final keys = cryptoService.generateNostrKeyPair();
      
      // Signature aléatoire
      final fakeSignature = '0' * 128;
      
      final isValid = cryptoService.verifySignature(message, fakeSignature, keys['npub']!);
      
      expect(isValid, isFalse, reason: 'Fausse signature doit être rejetée');
    });

    test('verifySignature rejette une signature pour un message différent', () {
      final message1 = 'deadbeef';
      final message2 = 'cafebabe';
      final keys = cryptoService.generateNostrKeyPair();
      
      final signature = cryptoService.signMessage(message1, keys['nsec']!);
      final isValid = cryptoService.verifySignature(message2, signature, keys['npub']!);
      
      expect(isValid, isFalse, reason: 'Signature pour message1 invalide pour message2');
    });
  });
}
