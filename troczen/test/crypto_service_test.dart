import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/crypto_service.dart';
import 'package:hex/hex.dart';

void main() {
  group('CryptoService', () {
    late CryptoService cryptoService;

    setUp(() {
      cryptoService = CryptoService();
    });

    // --- TEST SCRYPT & DERIVATION ---
    
    test('deriveSeed génère une seed déterministe (Scrypt)', () async {
      final seed1 = await cryptoService.deriveSeed('alice', 'password123');
      final seed2 = await cryptoService.deriveSeed('alice', 'password123');
      
      expect(seed1, equals(seed2), reason: 'Même login/password = même seed');
      expect(seed1.length, equals(32), reason: 'La seed doit faire 32 octets');
    });

    test('deriveSeed et deriveNostrPrivateKey sont cohérents avec derivePrivateKey', () async {
      // derivePrivateKey (legacy) doit être égal à SHA256(deriveSeed)
      final legacyKey = await cryptoService.derivePrivateKey('bob', 'secret');
      
      final seed = await cryptoService.deriveSeed('bob', 'secret');
      final nostrKey = await cryptoService.deriveNostrPrivateKey(seed);
      
      expect(legacyKey, equals(nostrKey), reason: 'La clé privée Nostr doit correspondre à l\'ancienne méthode');
    });

    // --- TEST DUNITER G1 ---

    test('generateG1Pub génère une clé Base58 valide', () async {
      final seed = await cryptoService.deriveSeed('test', 'test');
      final pubKey = cryptoService.generateG1Pub(seed);
      
      // Vérifier format Base58 (caractères alphanumériques sauf 0, O, I, l)
      final base58Regex = RegExp(r'^[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]+$');
      expect(base58Regex.hasMatch(pubKey), isTrue);
      
      // Une clé publique Ed25519 fait 32 octets, encodée en Base58 elle fait environ 43-44 caractères
      expect(pubKey.length, inInclusiveRange(40, 50));
    });

    // --- TEST IPFS / IPNS ---

    test('generateIpnsKey génère un CIDv1 Base36 valide', () async {
      final seed = await cryptoService.deriveSeed('test', 'test');
      final ipnsKey = cryptoService.generateIpnsKey(seed);
      
      // Doit commencer par 'k' (code multibase pour base36)
      expect(ipnsKey.startsWith('k'), isTrue);
      
      // Le reste doit être alpanumérique minuscule (base36)
      final base36Regex = RegExp(r'^k[0-9a-z]+$');
      expect(base36Regex.hasMatch(ipnsKey), isTrue);
    });

    // --- TEST DUNITER V2 (SS58) ---

    test('Mnemonic -> Seed -> SS58 (Scénario complet v2)', () {
      // 1. Mnémonique valide (12 mots, checksum valide)
      // C'est un vecteur de test standard BIP39
      final mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
      
      // 2. Seed
      final seed = cryptoService.mnemonicToSeed(mnemonic);
      expect(seed.length, equals(32));
      
      // 3. Clé Publique (SS58)
      // On génère une clé factice pour tester le formatage, ou on dérive la vraie
      // Ici on teste juste que la fonction encodeSS58 ne plante pas
      final pubKeyBytes = Uint8List(32); 
      for(int i=0; i<32; i++) pubKeyBytes[i] = i; 
      
      final ss58 = cryptoService.encodeSS58(pubKeyBytes, prefix: 42);
      
      // Vérifier que c'est du Base58 (Caractères alphanumériques, pas de 0, O, I, l)
      final base58Regex = RegExp(r'^[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]+$');
      expect(base58Regex.hasMatch(ss58), isTrue);
      
      // Vérifier la longueur (une adresse SS58 standard fait environ 48-50 chars)
      expect(ss58.length, greaterThan(40));
    });

    // --- TEST NOSTR (SCHNORR & KEYS) ---

    test('generateNostrKeyPair génère des clés valides (Hex 64 chars)', () {
      final keys = cryptoService.generateNostrKeyPair();
      
      expect(keys['nsec']!.length, equals(64));
      expect(keys['npub']!.length, equals(64));
      
      // Vérifier que c'est bien de l'hexadécimal
      final hexRegex = RegExp(r'^[0-9a-fA-F]+$');
      expect(hexRegex.hasMatch(keys['nsec']!), isTrue);
      expect(hexRegex.hasMatch(keys['npub']!), isTrue);
    });

    test('signMessage et verifySignature fonctionnent ensemble', () {
      final keys = cryptoService.generateNostrKeyPair();
      final message = HEX.encode(Uint8List.fromList('Hello World'.codeUnits)); // Message en Hex
      
      // Signer
      final signature = cryptoService.signMessage(message, keys['nsec']!);
      expect(signature.length, equals(128)); // 64 bytes hex
      
      // Vérifier
      final isValid = cryptoService.verifySignature(message, signature, keys['npub']!);
      expect(isValid, isTrue);
    });
    
    test('verifySignature rejette une signature invalide', () {
      final keys = cryptoService.generateNostrKeyPair();
      final message = HEX.encode(Uint8List.fromList('Hello'.codeUnits));
      
      final fakeSig = 'a' * 128; // 64 bytes de 'aaaa...'
      final isValid = cryptoService.verifySignature(message, fakeSig, keys['npub']!);
      expect(isValid, isFalse);
    });

    // --- TEST SHAMIR SECRET SHARING ---

    test('Shamir split/combine (Cycle complet)', () {
      final secret = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final parts = cryptoService.shamirSplit(secret);
      
      expect(parts.length, equals(3));
      
      // Reconstruction avec toutes les combinaisons possibles
      expect(cryptoService.shamirCombine(parts[0], parts[1], null), equals(secret), reason: 'P1+P2');
      expect(cryptoService.shamirCombine(null, parts[1], parts[2]), equals(secret), reason: 'P2+P3');
      expect(cryptoService.shamirCombine(parts[0], null, parts[2]), equals(secret), reason: 'P1+P3');
    });

    test('Shamir combine échoue avec 1 seule part', () {
      final secret = '01' * 32;
      final parts = cryptoService.shamirSplit(secret);
      
      expect(
        () => cryptoService.shamirCombine(parts[0], null, null),
        throwsArgumentError,
      );
    });

    // --- TEST CHIFFREMENT AES-GCM (P2/P3) ---

    test('encryptP2/decryptP2 (AES-GCM)', () async {
      final p2 = 'aa' * 32;
      final p3 = 'bb' * 32; // Sert de clé de chiffrement (via SHA256)
      
      final encrypted = await cryptoService.encryptP2(p2, p3);
      
      expect(encrypted['ciphertext'], isNotNull);
      expect(encrypted['nonce'], isNotNull);
      
      final decrypted = await cryptoService.decryptP2(
        encrypted['ciphertext']!, 
        encrypted['nonce']!, 
        p3
      );
      
      expect(decrypted, equals(p2));
    });

    test('Chiffrement déterministe vs non-déterministe', () async {
      final p2 = 'aa' * 32;
      final p3 = 'bb' * 32;
      
      // Le chiffrement utilise un nonce aléatoire, donc 2 appels = 2 résultats différents
      final enc1 = await cryptoService.encryptP2(p2, p3);
      final enc2 = await cryptoService.encryptP2(p2, p3);
      
      expect(enc1['nonce'], isNot(equals(enc2['nonce'])));
      expect(enc1['ciphertext'], isNot(equals(enc2['ciphertext'])));
    });
  });
}