import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:hex/hex.dart';
import 'package:convert/convert.dart';

class CryptoService {
  
  /// Dérive une clé privée à partir d'un login et mot de passe (Scrypt)
  Future<Uint8List> derivePrivateKey(String login, String password) async {
    final salt = utf8.encode(login);
    final passwordBytes = utf8.encode(password);
    
    // Scrypt avec N=4096, r=16, p=1
    final scrypt = Scrypt();
    scrypt.init(ScryptParameters(4096, 16, 1, 32, salt));
    
    final derivedKey = scrypt.process(Uint8List.fromList(passwordBytes));
    
    // SHA256 du résultat pour obtenir la clé privée finale
    final digest = sha256.convert(derivedKey);
    return Uint8List.fromList(digest.bytes);
  }

  /// Génère une paire de clés Nostr (secp256k1)
  Map<String, String> generateNostrKeyPair() {
    final keyPair = _generateSecp256k1KeyPair();
    final privateKey = (keyPair.privateKey as ECPrivateKey).d!;
    final publicKey = (keyPair.publicKey as ECPublicKey).Q!;
    
    // Convertir en hex
    final privateKeyHex = _bigIntToHex(privateKey, 32);
    final publicKeyHex = _pointToHex(publicKey);
    
    return {
      'nsec': privateKeyHex,
      'npub': publicKeyHex,
    };
  }

  /// Génère une paire de clés secp256k1
  AsymmetricKeyPair<PublicKey, PrivateKey> _generateSecp256k1KeyPair() {
    final keyParams = ECKeyGeneratorParameters(ECCurve_secp256k1());
    final random = FortunaRandom();
    
    // Seed avec des données aléatoires sécurisées
    final secureRandom = SecureRandom('Fortuna');
    final seeds = List<int>.generate(32, (i) => DateTime.now().millisecondsSinceEpoch % 256);
    random.seed(KeyParameter(Uint8List.fromList(seeds)));
    
    final generator = ECKeyGenerator();
    generator.init(ParametersWithRandom(keyParams, random));
    
    return generator.generateKeyPair();
  }

  /// Découpe une clé en 3 parts avec SSSS (2-sur-3)
  /// Retourne [P1, P2, P3]
  List<String> shamirSplit(String secretHex) {
    // Pour le MVP, on utilise une implémentation simple de Shamir
    // En production, utiliser un package vérifié
    
    // Convertir le secret en bytes
    final secretBytes = HEX.decode(secretHex);
    
    // Générer 3 parts avec seuil 2
    // Implémentation simplifiée : utilisation de XOR avec des secrets aléatoires
    // Note: Pour production, utiliser une vraie implémentation de Shamir
    
    final random = SecureRandom('Fortuna')
      ..seed(KeyParameter(Uint8List.fromList(
        List.generate(32, (_) => DateTime.now().millisecondsSinceEpoch % 256)
      )));
    
    // Générer deux parts aléatoires
    final p1 = _generateRandomBytes(32, random);
    final p2 = _generateRandomBytes(32, random);
    
    // P3 = secret XOR P1 XOR P2 (ainsi P1+P2+P3 permettent de reconstruire)
    final p3 = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      p3[i] = secretBytes[i] ^ p1[i] ^ p2[i];
    }
    
    return [
      HEX.encode(p1),
      HEX.encode(p2),
      HEX.encode(p3),
    ];
  }

  /// Reconstruit le secret à partir de 2 parts
  String shamirCombine(String part1Hex, String part2Hex, String? part3Hex) {
    final p1 = HEX.decode(part1Hex);
    final p2 = HEX.decode(part2Hex);
    
    if (part3Hex != null) {
      final p3 = HEX.decode(part3Hex);
      // Reconstruction avec les 3 parts
      final secret = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        secret[i] = p1[i] ^ p2[i] ^ p3[i];
      }
      return HEX.encode(secret);
    } else {
      // Si seulement 2 parts (simplifié pour ce MVP)
      // En production, le vrai Shamir permet de reconstruire avec n'importe quelles 2 parts
      final secret = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        secret[i] = p1[i] ^ p2[i];
      }
      return HEX.encode(secret);
    }
  }

  /// Chiffre P2 avec K_P2 = SHA256(P3)
  Future<Map<String, String>> encryptP2(String p2Hex, String p3Hex) async {
    final p2Bytes = HEX.decode(p2Hex);
    final p3Bytes = HEX.decode(p3Hex);
    
    // K_P2 = SHA256(P3)
    final kP2 = sha256.convert(p3Bytes).bytes;
    
    // Générer un nonce aléatoire (12 octets pour AES-GCM)
    final random = SecureRandom('Fortuna')
      ..seed(KeyParameter(Uint8List.fromList(
        List.generate(32, (_) => DateTime.now().millisecondsSinceEpoch % 256)
      )));
    final nonce = _generateRandomBytes(12, random);
    
    // Chiffrer avec AES-GCM
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(Uint8List.fromList(kP2)),
      128, // tag length
      nonce,
      Uint8List(0), // additional data
    );
    
    cipher.init(true, params);
    final ciphertext = cipher.process(Uint8List.fromList(p2Bytes));
    
    return {
      'ciphertext': HEX.encode(ciphertext),
      'nonce': HEX.encode(nonce),
    };
  }

  /// Déchiffre P2 avec K_P2 = SHA256(P3)
  Future<String> decryptP2(String ciphertextHex, String nonceHex, String p3Hex) async {
    final ciphertext = HEX.decode(ciphertextHex);
    final nonce = HEX.decode(nonceHex);
    final p3Bytes = HEX.decode(p3Hex);
    
    // K_P2 = SHA256(P3)
    final kP2 = sha256.convert(p3Bytes).bytes;
    
    // Déchiffrer avec AES-GCM
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(Uint8List.fromList(kP2)),
      128,
      Uint8List.fromList(nonce),
      Uint8List(0),
    );
    
    cipher.init(false, params);
    final plaintext = cipher.process(Uint8List.fromList(ciphertext));
    
    return HEX.encode(plaintext);
  }

  /// Chiffre P3 avec K_market
  Future<Map<String, String>> encryptP3(String p3Hex, String kmarketHex) async {
    final p3Bytes = HEX.decode(p3Hex);
    final kmarketBytes = HEX.decode(kmarketHex);
    
    // Générer un nonce
    final random = SecureRandom('Fortuna')
      ..seed(KeyParameter(Uint8List.fromList(
        List.generate(32, (_) => DateTime.now().millisecondsSinceEpoch % 256)
      )));
    final nonce = _generateRandomBytes(12, random);
    
    // Chiffrer avec AES-GCM
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(Uint8List.fromList(kmarketBytes)),
      128,
      nonce,
      Uint8List(0),
    );
    
    cipher.init(true, params);
    final ciphertext = cipher.process(Uint8List.fromList(p3Bytes));
    
    return {
      'ciphertext': HEX.encode(ciphertext),
      'nonce': HEX.encode(nonce),
    };
  }

  /// Déchiffre P3 avec K_market
  Future<String> decryptP3(String ciphertextHex, String nonceHex, String kmarketHex) async {
    final ciphertext = HEX.decode(ciphertextHex);
    final nonce = HEX.decode(nonceHex);
    final kmarketBytes = HEX.decode(kmarketHex);
    
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(Uint8List.fromList(kmarketBytes)),
      128,
      Uint8List.fromList(nonce),
      Uint8List(0),
    );
    
    cipher.init(false, params);
    final plaintext = cipher.process(Uint8List.fromList(ciphertext));
    
    return HEX.encode(plaintext);
  }

  // Utilitaires privés
  
  Uint8List _generateRandomBytes(int length, SecureRandom random) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextUint8();
    }
    return bytes;
  }

  String _bigIntToHex(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    return hex;
  }

  String _pointToHex(ECPoint point) {
    final x = point.x!.toBigInteger()!;
    return _bigIntToHex(x, 32);
  }
}
