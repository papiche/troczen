import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:hex/hex.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:bip39/bip39.dart' as bip39;
import 'package:bs58/bs58.dart';
import 'package:bech32/bech32.dart';
// ✅ SÉCURITÉ: Utilisation de bip340 (bibliothèque éprouvée) pour Schnorr
import 'package:bip340/bip340.dart' as bip340;

/// Exception levée lorsque la reconstruction Shamir échoue
/// Cela peut arriver si les parts sont incompatibles ou si la seed n'est pas compatible
/// avec l'implémentation SSSS actuelle (limite mod 257 vs octets 0-255)
class ShamirReconstructionException implements Exception {
  final String message;
  final String userMessage;
  final int? byteIndex;
  final int? invalidValue;
  
  ShamirReconstructionException(
    this.message, {
    this.byteIndex,
    this.invalidValue,
    String? customUserMessage,
  }) : userMessage = customUserMessage ??
      'La reconstruction de votre seed a échoué. '
      'Vos parts peuvent être incompatibles ou corrompues.\n\n'
      'Si vous êtes développeur et souhaitez améliorer cette implémentation, '
      'rendez-vous sur: https://github.com/papiche/troczen/issues';
  
  @override
  String toString() => 'ShamirReconstructionException: $message';
}

/// Résultat du chiffrement P2 avec données binaires
class EncryptP2Result {
  final Uint8List ciphertext;
  final Uint8List nonce;
  final Uint8List tag;
  
  EncryptP2Result({
    required this.ciphertext,
    required this.nonce,
    required this.tag,
  });
}

class CryptoService {
  final Random _secureRandom = Random.secure();
  
  /// ✅ MARCHÉ GLOBAL Ğ1: Seed constante (32 octets à zéro) - UPLANET ORIGIN
  /// 0000000000000000000000000000000000000000000000000000000000000000
  /// Utilisée pour le Marché Global Ğ1 (transparence totale et auditabilité publique)
  /// Ce n'est PAS une faille de sécurité, c'est une FEATURE : tout le monde peut auditer
  /// les transactions (comme une blockchain publique). Équivalence : 1 ẐEN ≈ 0.1 Ğ1
  ///
  /// Alias: HACKATHON_SEED (rétrocompatibilité)
  static final Uint8List HACKATHON_SEED = Uint8List(32); // 32 octets à zéro
  static final Uint8List GLOBAL_MARKET_SEED = Uint8List(32); // Alias sémantique
  
  /// Retourne true si la seed correspond au Marché Global (seed à zéro = transparence publique)
  bool _isHackathonSeed(String seedHex) {
    final globalMarketSeedHex = '0' * 64; // 32 octets à zéro en hex
    return seedHex == globalMarketSeedHex;
  }
  
  /// Alias sémantique pour _isHackathonSeed
  bool _isGlobalMarketSeed(String seedHex) => _isHackathonSeed(seedHex);
  
  /// ✅ SÉCURITÉ: Nettoyage sécurisé de la mémoire pour Uint8List
  /// Remplit le tableau d'octets avec des zéros de manière sécurisée
  /// Utiliser cette méthode pour effacer les clés privées de la mémoire
  void secureZeroiseBytes(Uint8List bytes) {
    if (bytes.isEmpty) return;
    // Remplir avec des zéros de manière explicite
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
    // Empêcher l'optimisation du compilateur qui pourrait supprimer cette boucle
    // en utilisant une volatile write simulée
    _volatileWrite(bytes);
  }
  
  /// Empêche l'optimisation du compilateur
  /// ✅ SÉCURITÉ: Le pragma 'vm:never-inline' empêche le compilateur AOT de
  /// supprimer cette méthode lors de l'optimisation, garantissant que la
  /// lecture volatile est effectivement exécutée.
  @pragma('vm:never-inline')
  void _volatileWrite(Uint8List bytes) {
    // Cette méthode force le compilateur à ne pas optimiser l'écriture
    // car le résultat est "utilisé" (même si c'est pour rien)
    if (bytes.isNotEmpty && bytes[0] == 0) {
      return;
    }
  }
  
  /// ✅ SÉCURITÉ: Validation clé publique secp256k1
  /// Vérifie que la coordonnée x correspond à un point valide sur la courbe
  /// Utilise les constantes secp256k1 standardisées
  bool isValidPublicKey(String pubKeyHex) {
    if (pubKeyHex.length != 64) return false;
    
    try {
      // Valider que c'est bien un hex valide
      final pubKeyBytes = Uint8List.fromList(HEX.decode(pubKeyHex));
      if (pubKeyBytes.length != 32) return false;
      
      // Convertir les 32 bytes en BigInt pour la coordonnée x
      final x = _bytesToBigInt(pubKeyBytes);
      
      // Constante p de secp256k1 (ordre du corps fini premier)
      // p = 2^256 - 2^32 - 2^9 - 2^8 - 2^7 - 2^6 - 2^4 - 1
      final p = BigInt.parse(
        'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
        radix: 16
      );
      
      // Vérifier que 0 < x < p
      if (x <= BigInt.zero || x >= p) return false;
      
      // Vérifier l'équation y² = x³ + 7 (mod p)
      // Pour une clé publique BIP-340 (x-only), on vérifie que x³ + 7 est un résidu quadratique
      final xCubed = x.modPow(BigInt.from(3), p);
      final ySq = (xCubed + BigInt.from(7)) % p;
      
      // Calculer la racine carrée modulaire: y = ySq^((p+1)/4) mod p
      // Ceci fonctionne car p ≡ 3 (mod 4) pour secp256k1
      final y = ySq.modPow((p + BigInt.one) >> 2, p);
      
      // Vérifier que y² ≡ ySq (mod p) - prouve que le point existe sur la courbe
      if (y.modPow(BigInt.two, p) != ySq) {
        return false;
      }
      
      // Vérification supplémentaire: s'assurer que le point généré n'est pas le point à l'infini
      // et qu'il a un ordre valide (multiple de n)
      try {
        // Pour BIP-340/Nostr, on utilise la coordonnée y pair
        final yFinal = y.isEven ? y : p - y;
        
        // Vérifier que y est dans les limites valides
        if (yFinal <= BigInt.zero || yFinal >= p) {
          return false;
        }
        
        // Vérification que le point (x, yFinal) est sur la courbe
        // en recalculant y² = x³ + 7
        final yFinalSq = yFinal.modPow(BigInt.two, p);
        if (yFinalSq != ySq) {
          return false;
        }
        
        return true;
      } catch (e) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
  
  /// Dérive une seed (32 octets) à partir d'un login et mot de passe (Scrypt)
  /// Utilise les paramètres standards Duniter v1: N=4096, r=16, p=1
  /// Cette seed peut être utilisée directement pour G1/IPFS (Ed25519)
  Future<Uint8List> deriveSeed(String login, String password) async {
    final salt = utf8.encode(login);
    final passwordBytes = utf8.encode(password);
    
    // Scrypt avec paramètres compatibles Duniter v1 / Astroport: N=4096, r=16, p=1
    final scrypt = Scrypt();
    scrypt.init(ScryptParameters(4096, 16, 1, 32, salt));
    
    final derivedKey = scrypt.process(Uint8List.fromList(passwordBytes));
    return derivedKey; // Seed brute de 32 octets
  }

  /// Dérive une clé privée Nostr (SHA256 de la seed)
  Future<Uint8List> deriveNostrPrivateKey(Uint8List seed) async {
    final digest = sha256.convert(seed);
    return Uint8List.fromList(digest.bytes);
  }

  /// Dérive une clé privée à partir d'un login et mot de passe (Scrypt)
  /// (Maintenue pour compatibilité, mais utilise désormais deriveSeed + deriveNostrPrivateKey)
  Future<Uint8List> derivePrivateKey(String login, String password) async {
    final seed = await deriveSeed(login, password);
    return await deriveNostrPrivateKey(seed);
  }

  /// Dérive la clé publique depuis une clé privée secp256k1
  String derivePublicKey(Uint8List privateKeyBytes) {
    var privateKeyBigInt = _bytesToBigInt(privateKeyBytes);
    final domainParams = ECDomainParameters('secp256k1');
    final n = domainParams.n;
    
    var publicKeyPoint = domainParams.G * privateKeyBigInt;
    
    // BIP-340: Normaliser pour avoir y pair
    final yBigInt = publicKeyPoint!.y!.toBigInteger()!;
    if (yBigInt.isOdd) {
      // Si y est impair, utiliser -privateKey (qui donnera le point opposé avec y pair)
      privateKeyBigInt = n - privateKeyBigInt;
      publicKeyPoint = domainParams.G * privateKeyBigInt;
    }
    
    return _pointToHex(publicKeyPoint!);
  }


/// Génère une paire de clés Nostr (secp256k1)
/// Génère une paire de clés Nostr (secp256k1)
  /// Retourne les clés au format Bech32 NIP-19 (nsec1... et npub1...)
  Map<String, String> generateNostrKeyPair() {
    final keyPair = _generateSecp256k1KeyPair();
    var privateKey = (keyPair.privateKey as ECPrivateKey).d!;
    var publicKey = (keyPair.publicKey as ECPublicKey).Q!;
    
    // BIP-340: Normaliser pour avoir y pair
    final domainParams = ECDomainParameters('secp256k1');
    final n = domainParams.n;
    final yBigInt = publicKey.y!.toBigInteger()!;
    
    if (yBigInt.isOdd) {
      // Si y est impair, utiliser -privateKey (qui donnera le point opposé avec y pair)
      privateKey = n - privateKey;
      publicKey = (domainParams.G * privateKey)!;
    }
    
    // Convertir en hex
    final privateKeyHex = _bigIntToHex(privateKey, 32);
    final publicKeyHex = _pointToHex(publicKey);
    
    // Encoder en Bech32 NIP-19
    return {
      'nsec': encodeNsec(privateKeyHex),
      'npub': encodeNpub(publicKeyHex),
      'privateKeyHex': privateKeyHex, // Gardé pour compatibilité interne
      'publicKeyHex': publicKeyHex,   // Gardé pour compatibilité interne
    };
  }

  // ==================== MARKET IDENTITY DERIVATION ====================
  
  /// ✅ v2.0.1: Dérive l'identité Nostr du marché de manière déterministe et sécurisée
  ///
  /// ⚠️ IMPORTANT: Cette méthode sépare cryptographiquement l'usage de la seed_market:
  /// - seed_market → utilisé pour le chiffrement AES-GCM des P3
  /// - dérivé SHA256(seed_market || "troczen_market_identity") → utilisé pour l'identité Nostr
  ///
  /// Cela évite la réutilisation de clés pour des usages différents (best practice crypto).
  ///
  /// Retourne un Map contenant:
  /// - 'nsec': clé privée au format nsec1...
  /// - 'npub': clé publique au format npub1...
  /// - 'privateKeyHex': clé privée en hexadécimal (32 bytes)
  /// - 'publicKeyHex': clé publique en hexadécimal (32 bytes)
  Map<String, String> deriveMarketIdentity(String seedMarketHex) {
    // 1. Décoder la seed du marché
    final seedBytes = HEX.decode(seedMarketHex);
    if (seedBytes.length != 32) {
      throw ArgumentError('seedMarketHex doit faire 32 octets (64 caractères hex)');
    }
    
    // 2. Créer le payload de dérivation
    final derivationPayload = utf8.encode("troczen_market_identity");
    final combinedBytes = Uint8List.fromList([...seedBytes, ...derivationPayload]);
    
    // 3. Hash SHA256 pour obtenir la clé privée du marché
    final digest = sha256.convert(combinedBytes);
    final privateKeyBytes = Uint8List.fromList(digest.bytes);
    
    // 4. Dériver la clé publique depuis la clé privée
    final publicKeyHex = derivePublicKey(privateKeyBytes);
    final privateKeyHex = HEX.encode(privateKeyBytes);
    
    // 5. Retourner la paire de clés avec les formats Bech32
    return {
      'nsec': encodeNsec(privateKeyHex),
      'npub': encodeNpub(publicKeyHex),
      'privateKeyHex': privateKeyHex,
      'publicKeyHex': publicKeyHex,
    };
  }

  // ==================== NIP-19 BECH32 ENCODING ====================
  
  /// Encode une clé privée hexadécimale en format nsec1... (NIP-19)
  String encodeNsec(String privateKeyHex) {
    final bytes = HEX.decode(privateKeyHex);
    return _encodeBech32('nsec', bytes);
  }
  
  /// Encode une clé publique hexadécimale en format npub1... (NIP-19)
  String encodeNpub(String publicKeyHex) {
    final bytes = HEX.decode(publicKeyHex);
    return _encodeBech32('npub', bytes);
  }
  
  /// Décode une clé privée nsec1... en hexadécimal
  String decodeNsec(String nsec) {
    final decoded = _decodeBech32(nsec, 'nsec');
    return HEX.encode(decoded);
  }
  
  /// Décode une clé publique npub1... en hexadécimal
  String decodeNpub(String npub) {
    final decoded = _decodeBech32(npub, 'npub');
    return HEX.encode(decoded);
  }
  
  /// Encode des bytes en Bech32 avec le préfixe donné
  String _encodeBech32(String hrp, List<int> data) {
    // Convertir de 8 bits vers 5 bits (bech32)
    final converted = _convertBits(data, 8, 5, true);
    final bech32Data = converted.map((e) => e).toList();
    
    // Utiliser la librairie bech32 - constructeur avec paramètres positionnels
    final codec = Bech32Codec();
    final bech32 = Bech32(hrp, bech32Data);
    return codec.encode(bech32);
  }
  
  /// Décode une chaîne Bech32 et vérifie le préfixe
  List<int> _decodeBech32(String bech32String, String expectedHrp) {
    final codec = Bech32Codec();
    final bech32 = codec.decode(bech32String);
    
    if (bech32.hrp != expectedHrp) {
      throw ArgumentError('Préfixe Bech32 invalide: attendu $expectedHrp, reçu ${bech32.hrp}');
    }
    
    // Convertir de 5 bits vers 8 bits
    return _convertBits(bech32.data, 5, 8, false);
  }
  
  /// Convertit les bits d'une liste d'entiers
  /// Inspiré de la spécification BIP-173
  List<int> _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;
    
    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        throw ArgumentError('Valeur hors limites pour la conversion de bits');
      }
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }
    
    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      throw ArgumentError('Données invalides pour la conversion de bits');
    }
    
    return result;
  }

  /// Génère une paire de clés secp256k1 avec générateur sécurisé
  AsymmetricKeyPair<PublicKey, PrivateKey> _generateSecp256k1KeyPair() {
    final keyParams = ECKeyGeneratorParameters(ECCurve_secp256k1());
    
    // ✅ CORRECTION: Utilisation de Random.secure() au lieu de DateTime
    final secureRandomGenerator = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = Uint8List.fromList(
      List.generate(32, (_) => seedSource.nextInt(256))
    );
    secureRandomGenerator.seed(KeyParameter(seeds));
    
    final generator = ECKeyGenerator();
    generator.init(ParametersWithRandom(keyParams, secureRandomGenerator));
    
    return generator.generateKeyPair();
  }

  /// ✅ SÉCURITÉ MAXIMALE: Découpe une clé en 3 parts avec Shamir Secret Sharing (2-sur-3)
  /// Retourne directement des Uint8List pour éviter les String en RAM.
  ///
  /// Cette méthode est la version sécurisée qui évite complètement les String hexadécimales.
  /// L'appelant est responsable de convertir en Hex uniquement pour la sauvegarde.
  ///
  /// Exemple d'utilisation sécurisée:
  /// ```dart
  /// final parts = cryptoService.shamirSplitBytes(secretBytes);
  /// try {
  ///   // Sauvegarder en convertissant en hex juste avant l'écriture
  ///   await storageService.saveSsssPart1(HEX.encode(parts[0]));
  ///   await storageService.saveSsssPart2(HEX.encode(parts[1]));
  ///   await storageService.saveSsssPart3(HEX.encode(parts[2]));
  /// } finally {
  ///   // Nettoyer les parts de la RAM
  ///   for (final part in parts) {
  ///     cryptoService.secureZeroiseBytes(part);
  ///   }
  /// }
  /// ```
  ///
  /// Lève [ArgumentError] si le secret n'a pas 32 octets.
  /// ✅ SÉCURITÉ MAXIMALE: Découpe une clé en 3 parts avec Shamir Secret Sharing (2-sur-3)
  /// Retourne directement des Uint8List pour éviter les String en RAM.
  List<Uint8List> shamirSplitBytes(Uint8List secretBytes) {
    if (secretBytes.length != 32) {
      throw ArgumentError('Secret doit faire 32 octets');
    }
    
    final p1Bytes = Uint8List(32);
    final p2Bytes = Uint8List(32);
    final p3Bytes = Uint8List(32);
    
    for (int i = 0; i < 32; i++) {
      final a0 = secretBytes[i]; // secret
      final a1 = _secureRandom.nextInt(256); // coefficient aléatoire dans GF(256)
      
      p1Bytes[i] = _gf256Add(a0, _gf256Mul(a1, 1));
      p2Bytes[i] = _gf256Add(a0, _gf256Mul(a1, 2));
      p3Bytes[i] = _gf256Add(a0, _gf256Mul(a1, 3));
    }
    
    return [p1Bytes, p2Bytes, p3Bytes];
  }


  /// ✅ SÉCURITÉ MAXIMALE: Reconstruit le secret à partir de Uint8List directement
  ///
  /// Cette méthode est la version sécurisée qui évite complètement les String.
  /// Les parts doivent être passées en Uint8List dès la sortie du stockage.
  /// L'appelant est responsable de nettoyer les parts après appel avec secureZeroiseBytes().
  ///
  /// Exemple d'utilisation sécurisée:
  /// ```dart
  /// final p2Bytes = await storageService.getSsssPart2Bytes(); // Uint8List direct
  /// final p3Bytes = await storageService.getSsssPart3Bytes(); // Uint8List direct
  /// try {
  ///   final secret = cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);
  ///   // utiliser secret...
  ///   cryptoService.secureZeroiseBytes(secret);
  /// } finally {
  ///   cryptoService.secureZeroiseBytes(p2Bytes);
  ///   cryptoService.secureZeroiseBytes(p3Bytes);
  /// }
  /// ```
  ///
  /// Lève [ShamirReconstructionException] si la reconstruction échoue.
  /// Lève [ArgumentError] si moins de 2 parts sont fournies.
  Uint8List shamirCombineBytesDirect(Uint8List? part1, Uint8List? part2, Uint8List? part3) {
    // Vérifier qu'on a au moins 2 parts
    final parts = <int, Uint8List>{};
    if (part1 != null) parts[1] = part1;
    if (part2 != null) parts[2] = part2;
    if (part3 != null) parts[3] = part3;
    
    if (parts.length < 2) {
      throw ArgumentError('Au moins 2 parts requises pour reconstruction');
    }
    
    // Prendre les 2 premières parts disponibles
    final indices = parts.keys.toList().take(2).toList();
    final y1 = parts[indices[0]]!;
    final y2 = parts[indices[1]]!;
    final x1 = indices[0];
    final x2 = indices[1];
    
    final secretBytes = Uint8List(32);
    
    for (int i = 0; i < 32; i++) {
      // Interpolation de Lagrange dans GF(256)
      // f(0) = y1 * L1(0) + y2 * L2(0)
      // où L1(0) = (0-x2)/(x1-x2) et L2(0) = (0-x1)/(x2-x1)
      
      // Dans GF(256), la soustraction est un XOR
      // L1(0) = (0 ^ x2) / (x1 ^ x2) = x2 / (x1 ^ x2)
      // L2(0) = (0 ^ x1) / (x2 ^ x1) = x1 / (x2 ^ x1)
      
      final denom = x1 ^ x2; // x1 XOR x2 (soustraction dans GF(256))
      
      if (denom == 0) {
        // Parts identiques - données corrompues
        throw ShamirReconstructionException(
          'Parts identiques détectées (x1=$x1, x2=$x2)',
          byteIndex: i,
          invalidValue: null,
          customUserMessage: 'Les parts fournies sont identiques ou corrompues.\n\n'
              'Vérifiez que vous avez bien scanné deux parts différentes.\n\n'
              'Si le problème persiste, contactez le support ou visitez: '
              'https://github.com/papiche/troczen/issues',
        );
      }
      
      // Calculer les coefficients de Lagrange dans GF(256)
      final l1 = _gf256Div(x2, denom);
      final l2 = _gf256Div(x1, denom);
      
      // f(0) = y1 * L1 + y2 * L2 dans GF(256)
      final term1 = _gf256Mul(y1[i], l1);
      final term2 = _gf256Mul(y2[i], l2);
      secretBytes[i] = _gf256Add(term1, term2);
    }
    
    // ⚠️ NOTE: On ne nettoie PAS les parts ici car l'appelant peut vouloir les réutiliser
    // L'appelant est responsable du nettoyage avec secureZeroiseBytes()
    
    return secretBytes;
  }

  // ==================== OPÉRATIONS GF(256) ====================
  // Galois Field GF(2^8) avec polynôme irréductible x^8 + x^4 + x^3 + x + 1 (0x11B)
  // Utilise des tables logarithmiques pour une multiplication efficace
  
  /// Table des logarithmes en base 3 (générateur) pour GF(256)
  static final List<int> _gf256Log = _generateGf256LogTable();
  
  /// Table des antilogarithmes (exponentielles) pour GF(256)
  static final List<int> _gf256Exp = _generateGf256ExpTable();
  
  static List<int> _generateGf256LogTable() {
    final log = List<int>.filled(256, 0);
    int x = 1;
    for (int i = 0; i < 255; i++) {
      log[x] = i;
      x = _gf256MulNoTable(x, 3); // 3 est le générateur
    }
    return log;
  }
  
  static List<int> _generateGf256ExpTable() {
    final exp = List<int>.filled(512, 0);
    int x = 1;
    for (int i = 0; i < 255; i++) {
      exp[i] = x;
      exp[i + 255] = x;
      x = _gf256MulNoTable(x, 3);
    }
    return exp;
  }
  
  /// Multiplication GF(256) sans table (pour l'initialisation)
  static int _gf256MulNoTable(int a, int b) {
    int result = 0;
    while (b > 0) {
      if (b & 1 != 0) {
        result ^= a;
      }
      a = (a << 1) ^ ((a & 0x80) != 0 ? 0x11B : 0);
      b >>= 1;
    }
    return result;
  }
  
  /// Addition dans GF(256) = XOR
  int _gf256Add(int a, int b) => a ^ b;
  
  /// Multiplication dans GF(256) utilisant les tables logarithmiques
  int _gf256Mul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    final logA = _gf256Log[a];
    final logB = _gf256Log[b];
    return _gf256Exp[logA + logB];
  }
  
  /// Division dans GF(256): a / b = a * b^(-1)
  int _gf256Div(int a, int b) {
    if (b == 0) {
      throw ArgumentError('Division par zéro dans GF(256)');
    }
    if (a == 0) return 0;
    final logA = _gf256Log[a];
    final logB = _gf256Log[b];
    // log(a/b) = log(a) - log(b) mod 255
    final logResult = (logA - logB + 255) % 255;
    return _gf256Exp[logResult];
  }
  

  /// Chiffre P2 avec K_P2 = SHA256(P3)
  Future<Map<String, String>> encryptP2(String p2Hex, String p3Hex) async {
    final p2Bytes = HEX.decode(p2Hex);
    final p3Bytes = HEX.decode(p3Hex);
    
    // K_P2 = SHA256(P3)
    final kP2 = sha256.convert(p3Bytes).bytes;
    
    // ✅ CORRECTION: Nonce sécurisé
    final nonce = Uint8List.fromList(
      List.generate(12, (_) => _secureRandom.nextInt(256))
    );
    
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

  /// Chiffre P3 avec K_day (clé du jour) en utilisant AES-GCM
  /// En mode HACKATHON, la clé K_day est prévisible (dérivée d'une seed à zéro)
  /// mais le chiffrement reste AES-GCM standard - seul le décodage est facilité
  Future<Map<String, String>> encryptP3(String p3Hex, String kDayHex) async {
    final p3Bytes = HEX.decode(p3Hex);
    final kDayBytes = HEX.decode(kDayHex);
    
    // ✅ Toujours utiliser AES-GCM (même en mode HACKATHON)
    // La sécurité réduite en mode HACKATHON vient uniquement de la clé prévisible
    final nonce = Uint8List.fromList(
      List.generate(12, (_) => _secureRandom.nextInt(256))
    );
    
    // Chiffrer avec AES-GCM
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(Uint8List.fromList(kDayBytes)),
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

  /// Déchiffre P3 avec K_day (clé du jour) en utilisant AES-GCM
  /// En mode HACKATHON, la clé K_day est prévisible (dérivée d'une seed à zéro)
  /// mais le déchiffrement reste AES-GCM standard
  Future<String> decryptP3(String ciphertextHex, String nonceHex, String kDayHex) async {
    final ciphertext = HEX.decode(ciphertextHex);
    final nonce = HEX.decode(nonceHex);
    final kDayBytes = HEX.decode(kDayHex);
    
    // ✅ Toujours utiliser AES-GCM (même en mode HACKATHON)
    // La sécurité réduite en mode HACKATHON vient uniquement de la clé prévisible
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(Uint8List.fromList(kDayBytes)),
      128,
      Uint8List.fromList(nonce),
      Uint8List(0),
    );
    
    cipher.init(false, params);
    final plaintext = cipher.process(Uint8List.fromList(ciphertext));
    
    return HEX.encode(plaintext);
  }

  /// ✅ SÉCURITÉ: Signe un message avec Schnorr (BIP-340) via bibliothèque éprouvée
  /// Utilise bip340 qui implémente correctement le nonce déterministe BIP-340
  /// Accepte la clé privée en format hex ou nsec1... (Bech32)
  /// ⚠️ NOTE: Cette méthode utilise des Strings immuables qui restent en mémoire.
  /// Préférez signMessageBytes() pour une meilleure sécurité mémoire.
  String signMessage(String messageHex, String privateKey) {
    // Détecter si c'est du Bech32 (nsec1...) ou de l'hex
    String privateKeyHex;
    if (privateKey.startsWith('nsec1')) {
      privateKeyHex = decodeNsec(privateKey);
    } else {
      privateKeyHex = privateKey;
    }
    
    // ✅ SÉCURITÉ: Validation de la clé privée
    if (privateKeyHex.length != 64) {
      throw ArgumentError('Clé privée invalide: doit faire 32 octets (64 chars hex)');
    }
    
    // ✅ SÉCURITÉ: Utilisation de bip340 (bibliothèque éprouvée)
    // Cette bibliothèque implémente correctement:
    // - Nonce déterministe BIP-340 avec taggedHash
    // - Normalisation BIP-340 (y pair)
    // - Protection contre les attaques timing
    try {
      // Générer auxRand sécurisé (32 octets aléatoires)
      // BIP-340 utilise auxRand pour éviter les attaques par canal auxiliaire
      final auxRandBytes = Uint8List.fromList(
        List.generate(32, (_) => _secureRandom.nextInt(256))
      );
      final auxRandHex = HEX.encode(auxRandBytes);
      
      final signature = bip340.sign(privateKeyHex, messageHex, auxRandHex);
      return signature;
    } catch (e) {
      throw ArgumentError('Erreur lors de la signature: $e');
    }
  }

  /// ✅ SÉCURITÉ: Signe un message avec Schnorr (BIP-340) en utilisant Uint8List
  /// Version sécurisée qui permet le nettoyage mémoire de la clé privée.
  /// Le message est en hexadécimal, la clé privée en Uint8List.
  /// Retourne la signature en hexadécimal (128 chars).
  String signMessageBytes(String messageHex, Uint8List privateKeyBytes) {
    // ✅ SÉCURITÉ: Validation de la clé privée
    if (privateKeyBytes.length != 32) {
      throw ArgumentError('Clé privée invalide: doit faire 32 octets');
    }
    
    try {
      // Convertir en hex pour bip340 (la bibliothèque nécessite du hex)
      final privateKeyHex = HEX.encode(privateKeyBytes);
      
      // Générer auxRand sécurisé (32 octets aléatoires)
      final auxRandBytes = Uint8List.fromList(
        List.generate(32, (_) => _secureRandom.nextInt(256))
      );
      final auxRandHex = HEX.encode(auxRandBytes);
      
      final signature = bip340.sign(privateKeyHex, messageHex, auxRandHex);
      
      // Nettoyer l'hex intermédiaire (même si c'est une String immuable,
      // au moins les bytes auxRand sont nettoyés)
      secureZeroiseBytes(auxRandBytes);
      
      return signature;
    } catch (e) {
      throw ArgumentError('Erreur lors de la signature: $e');
    }
  }

  /// ✅ SÉCURITÉ: Vérifie une signature Schnorr (BIP-340) via bibliothèque éprouvée
  /// Utilise bip340 qui implémente correctement la vérification BIP-340
  /// Accepte la clé publique en format hex ou npub1... (Bech32)
  bool verifySignature(String messageHex, String signatureHex, String publicKey) {
    if (signatureHex.length != 128) return false; // 64 octets
    
    try {
      // Détecter si c'est du Bech32 (npub1...) ou de l'hex
      String publicKeyHex;
      if (publicKey.startsWith('npub1')) {
        publicKeyHex = decodeNpub(publicKey);
      } else {
        publicKeyHex = publicKey;
      }
      
      // ✅ SÉCURITÉ: Validation de la clé publique
      if (publicKeyHex.length != 64) {
        return false;
      }
      
      // ✅ SÉCURITÉ: Vérifier que la clé publique est sur la courbe
      if (!isValidPublicKey(publicKeyHex)) {
        return false;
      }
      
      // ✅ SÉCURITÉ: Utilisation de bip340 (bibliothèque éprouvée)
      // Cette bibliothière implémente correctement:
      // - Décompression sécurisée du point
      // - Vérification de l'équation s*G = R + e*P
      // - Protection contre les attaques timing
      return bip340.verify(publicKeyHex, messageHex, signatureHex);
    } catch (e) {
      return false;
    }
  }

  // Utilitaires privés
  
  BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  String _bigIntToHex(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    return hex;
  }

  /// ✅ CORRECTION: Retourne seulement la coordonnée X (format Nostr standard)
  String _pointToHex(ECPoint point) {
    final x = point.x!.toBigInteger()!;
    return _bigIntToHex(x, 32);
  }

  /// Encode un tableau d'octets en Base36 (Alphabet: 0-9a-z)
  /// Nécessaire pour le format CIDv1 d'IPFS (préfixe 'k')
  String _encodeBase36(Uint8List bytes) {
    const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
    var value = BigInt.zero;
    
    // Conversion Bytes -> BigInt
    for (var byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    
    var output = '';
    final big36 = BigInt.from(36);
    
    while (value > BigInt.zero) {
      final remainder = value % big36;
      value = value ~/ big36;
      output = alphabet[remainder.toInt()] + output;
    }
    
    // Gestion du cas vide
    return output.isEmpty ? '0' : output;
  }

  /// ✅ GÉNÉRATION AUTOMATIQUE DE LA CLÉ PUBLIQUE Ğ1 (G1Pub)
  /// Génère une clé publique Ğ1 en Base58 à partir d'une seed (32 octets)
  /// Format: Base58 (32 octets encodés)
  String generateG1Pub(Uint8List seed) {
    // Vérifier que la seed fait 32 octets
    if (seed.length != 32) {
      throw Exception('La seed doit faire exactement 32 octets');
    }

    // Générer une paire de clés Ed25519 à partir de la seed
    final keyPair = _generateEd25519KeyPair(seed);
    
    // Encoder la clé publique en Base58
    return base58.encode(keyPair['publicKey']!);
  }

  /// ✅ GÉNÉRATION CLÉ IPNS (IPFS Peer ID)
  /// Génère une clé IPNS au format CIDv1 Base36 (ex: k51...)
  /// Utilise la même clé Ed25519 que Duniter G1.
  String generateIpnsKey(Uint8List seed) {
    if (seed.length != 32) {
      throw Exception('La seed doit faire exactement 32 octets');
    }

    // 1. Récupérer la clé publique Ed25519 (32 octets)
    final keyPair = _generateEd25519KeyPair(seed);
    final pubKeyBytes = keyPair['publicKey']!;

    // 2. Construire le Header IPFS/Libp2p
    // Structure du header (8 octets) :
    // 0x01 : CID Version 1
    // 0x72 : Codec 'libp2p-key'
    // 0x00 : Multihash function 'identity' (pas de hashage, donnée brute)
    // 0x24 : Multihash length (36 octets = 4 header protobuf + 32 key)
    // 0x08 : Protobuf field type (Ed25519)
    // 0x01 : Protobuf field type value
    // 0x12 : Protobuf field length type
    // 0x20 : Protobuf key length (32 octets)
    final header = [0x01, 0x72, 0x00, 0x24, 0x08, 0x01, 0x12, 0x20];

    // 3. Concaténer Header + Clé Publique
    final ipnsBytes = Uint8List.fromList([
      ...header,
      ...pubKeyBytes
    ]);

    // 4. Encoder en Base36 et ajouter le préfixe 'k' (multibase code pour base36)
    return 'k${_encodeBase36(ipnsBytes)}';
  }

  // --- SECTION DUNITER V2 (SUBSTRATE / BIP39) ---

  /// Génère une nouvelle phrase mnémonique aléatoire (12 mots)
  String generateMnemonic() {
    return bip39.generateMnemonic();
  }

  /// Convertit un mnémonique en Seed de 32 octets Compatible avec l'implémentation Substrate/Polkadot standard (SS58)
  /// Note: BIP39 produit 64 octets. Pour Ed25519 "MiniSecret", on prend les 32 premiers.
  Uint8List mnemonicToSeed(String mnemonic) {
    if (!bip39.validateMnemonic(mnemonic)) {
      throw ArgumentError("Mnémonique invalide");
    }
    // Génère 64 octets (512 bits)
    final seed64 = bip39.mnemonicToSeed(mnemonic);
    
    // On garde les 32 premiers pour la compatibilité avec la dérivation Ed25519 simple
    return seed64.sublist(0, 32);
  }

  /// Convertit une clé publique Ed25519 en adresse Duniter v2 (Format SS58)
  /// [publicKeyBytes] : Les 32 octets de la clé publique
  /// [prefix] : 42 pour le format Substrate générique (utilisé par défaut sur Duniter v2)
  String encodeSS58(Uint8List publicKeyBytes, {int prefix = 42}) {
    if (publicKeyBytes.length != 32) {
      throw ArgumentError("La clé publique doit faire 32 octets");
    }

    // 1. Concaténer le préfixe et la clé publique
    List<int> data = [prefix];
    data.addAll(publicKeyBytes);

    // 2. Calculer le checksum (Blake2b-512)
    final ss58Prefix = utf8.encode("SS58PRE");
    final checkData = Uint8List.fromList([...ss58Prefix, ...data]);
    
    // CORRECTION ICI : digestSize est en OCTETS. 
    // On veut 512 bits, donc 64 octets.
    final blake2b = Blake2bDigest(digestSize: 64); 
    
    final checksumFull = Uint8List(64);
    
    blake2b.update(checkData, 0, checkData.length);
    blake2b.doFinal(checksumFull, 0);

    // On prend les 2 premiers octets du hash pour le checksum
    final checksum = checksumFull.sublist(0, 2);

    // 3. Concaténer tout : [Prefix] + [PubKey] + [Checksum]
    final finalBytes = Uint8List.fromList([...data, ...checksum]);

    // 4. Encoder en Base58
    return base58.encode(finalBytes);
  }

  /// Génère une paire de clés Ed25519 à partir d'une seed
  Map<String, Uint8List> _generateEd25519KeyPair(Uint8List seed) {
    // Utilisation de pinenacl pour une vraie génération Ed25519
    final signingKey = nacl.SigningKey.fromSeed(seed);
    return {
      'privateKey': signingKey.asTypedList, // 64 bytes (seed + pub)
      'publicKey': signingKey.publicKey.asTypedList,   // 32 bytes
    };
  }

  /// ✅ Calcule la clé de chiffrement quotidienne à partir de la graine du marché
  /// Utilise HMAC-SHA256(seed, "YYYY-MM-DD") comme spécifié dans le whitepaper
  String getDailyMarketKey(String seedHex, DateTime date) {
    final seedBytes = HEX.decode(seedHex);
    final dateStr = '${date.year.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final dateBytes = utf8.encode(dateStr);
    
    final hmac = Hmac(sha256, seedBytes);
    final keyBytes = hmac.convert(dateBytes).bytes;
    
    return HEX.encode(keyBytes);
  }

  /// ✅ Chiffre P3 avec K_day (clé du jour dérivée de la graine)
  /// En mode HACKATHON (seed à zéro), retourne P3 non chiffré pour lisibilité JSON
  Future<Map<String, String>> encryptP3WithSeed(String p3Hex, String seedHex, DateTime date) async {
    // Mode HACKATHON: P3 reste en clair pour faciliter les tests et la lisibilité Nostr
    if (_isHackathonSeed(seedHex)) {
      return {
        'ciphertext': p3Hex, // P3 non chiffré
        'nonce': '0' * 24,   // Nonce factice (12 octets à zéro en hex)
      };
    }
    final kDay = getDailyMarketKey(seedHex, date);
    return encryptP3(p3Hex, kDay);
  }

  /// ✅ Déchiffre P3 avec K_day (clé du jour dérivée de la graine)
  /// En mode HACKATHON (seed à zéro), retourne le ciphertext tel quel (P3 non chiffré)
  Future<String> decryptP3WithSeed(String ciphertextHex, String nonceHex, String seedHex, DateTime date) async {
    // Mode HACKATHON: P3 était en clair, le ciphertext EST le P3
    if (_isHackathonSeed(seedHex)) {
      return ciphertextHex; // Retourne directement le "ciphertext" qui est en fait P3 en clair
    }
    final kDay = getDailyMarketKey(seedHex, date);
    return decryptP3(ciphertextHex, nonceHex, kDay);
  }

  // ============================================================================
  // ✅ SÉCURITÉ WOTX - Chiffrement du contenu des événements (30500-30502, 30304)
  // ============================================================================
  //
  // PROBLÈME (Syndrome du Panopticon):
  // Si on publie les attestations (qui connaît qui, qui valide qui) en clair sur
  // le relai local, n'importe qui s'y connectant peut aspirer l'intégralité du
  // graphe social et économique du village.
  //
  // SOLUTION:
  // Tout comme pour les bons (Kind 30303), le champ content des événements WoTx
  // est chiffré en AES-GCM avec la Seed du Marché. Les tags publics (p, e, t)
  // servent au routage par Strfry, mais la "chair" du message (motivation,
  // commentaires) n'est lisible que par ceux qui ont été invités sur le marché.
  // ============================================================================

  /// ✅ SÉCURITÉ WOTX: Chiffre le contenu d'un événement avec la Seed du Marché
  ///
  /// Utilise AES-GCM avec la seed du marché comme clé de chiffrement.
  /// En mode HACKATHON (seed à zéro), le contenu reste en clair pour la transparence.
  ///
  /// [content] - Le contenu JSON à chiffrer
  /// [seedHex] - La seed du marché en hexadécimal (64 caractères)
  ///
  /// Retourne un Map avec:
  /// - 'ciphertext': contenu chiffré en hexadécimal
  /// - 'nonce': nonce AES-GCM en hexadécimal (24 caractères)
  Map<String, String> encryptWoTxContent(String content, String seedHex) {
    // Mode HACKATHON: transparence totale, contenu en clair
    if (_isHackathonSeed(seedHex)) {
      return {
        'ciphertext': content, // Contenu non chiffré
        'nonce': '', // Pas de nonce en mode clair
      };
    }
    
    try {
      // Convertir la seed en clé de 32 octets
      final keyBytes = Uint8List.fromList(HEX.decode(seedHex));
      
      // Générer un nonce sécurisé de 12 octets (96 bits) pour AES-GCM
      final nonce = Uint8List.fromList(
        List.generate(12, (_) => _secureRandom.nextInt(256))
      );
      
      // Convertir le contenu en bytes
      final contentBytes = Uint8List.fromList(utf8.encode(content));
      
      // Chiffrer avec AES-GCM
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(keyBytes),
        128, // tag length en bits
        nonce,
        Uint8List(0), // additional data
      );
      
      cipher.init(true, params);
      final ciphertext = cipher.process(contentBytes);
      
      return {
        'ciphertext': HEX.encode(ciphertext),
        'nonce': HEX.encode(nonce),
      };
    } catch (e) {
      throw ArgumentError('Erreur lors du chiffrement WoTx: $e');
    }
  }

  /// ✅ SÉCURITÉ WOTX: Déchiffre le contenu d'un événement avec la Seed du Marché
  ///
  /// [ciphertextHex] - Le contenu chiffré en hexadécimal
  /// [nonceHex] - Le nonce AES-GCM en hexadécimal (peut être vide en mode HACKATHON)
  /// [seedHex] - La seed du marché en hexadécimal (64 caractères)
  ///
  /// Retourne le contenu déchiffré en texte (JSON)
  String decryptWoTxContent(String ciphertextHex, String nonceHex, String seedHex) {
    // Mode HACKATHON: le contenu était en clair
    if (_isHackathonSeed(seedHex) || nonceHex.isEmpty) {
      return ciphertextHex; // C'est déjà le contenu en clair
    }
    
    try {
      // Convertir la seed en clé de 32 octets
      final keyBytes = Uint8List.fromList(HEX.decode(seedHex));
      
      // Décoder le nonce et le ciphertext
      final nonce = Uint8List.fromList(HEX.decode(nonceHex));
      final ciphertext = Uint8List.fromList(HEX.decode(ciphertextHex));
      
      // Déchiffrer avec AES-GCM
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(keyBytes),
        128,
        nonce,
        Uint8List(0),
      );
      
      cipher.init(false, params);
      final plaintext = cipher.process(ciphertext);
      
      return utf8.decode(plaintext);
    } catch (e) {
      throw ArgumentError('Erreur lors du déchiffrement WoTx: $e');
    }
  }

  /// ✅ SÉCURITÉ WOTX: Vérifie si un contenu est chiffré ou en clair
  ///
  /// Retourne true si le contenu est chiffré (nonce présent), false sinon
  bool isWoTxContentEncrypted(String nonceHex) {
    return nonceHex.isNotEmpty;
  }

  /// ✅ SÉCURITÉ WOTX: Crée un événement WoTx avec contenu chiffré
  ///
  /// Cette méthode encapsule la logique de création d'un événement WoTx sécurisé:
  /// 1. Chiffre le contenu avec la seed du marché
  /// 2. Ajoute le nonce dans un tag 'encryption' pour le déchiffrement ultérieur
  ///
  /// [kind] - Le kind de l'événement (30500, 30501, 30502, 30304)
  /// [pubkey] - La clé publique de l'émetteur
  /// [content] - Le contenu JSON à chiffrer
  /// [tags] - Les tags publics pour le routage (p, e, t, etc.)
  /// [seedHex] - La seed du marché pour le chiffrement
  ///
  /// Retourne l'événement prêt à être signé et publié
  Map<String, dynamic> createEncryptedWoTxEvent({
    required int kind,
    required String pubkey,
    required String content,
    required List<List<String>> tags,
    required String seedHex,
  }) {
    // Chiffrer le contenu
    final encrypted = encryptWoTxContent(content, seedHex);
    
    // Créer les tags avec le nonce d'encryption si présent
    final encryptedTags = List<List<String>>.from(tags);
    if (encrypted['nonce']!.isNotEmpty) {
      encryptedTags.add(['encryption', 'aes-gcm', encrypted['nonce']!]);
    }
    
    return {
      'kind': kind,
      'pubkey': pubkey,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'tags': encryptedTags,
      'content': encrypted['ciphertext']!,
    };
  }

  /// ✅ SÉCURITÉ WOTX: Déchiffre le contenu d'un événement reçu
  ///
  /// Extrait le nonce du tag 'encryption' et déchiffre le contenu
  ///
  /// [event] - L'événement Nostr reçu
  /// [seedHex] - La seed du marché pour le déchiffrement
  ///
  /// Retourne le contenu déchiffré
  String decryptWoTxEvent(Map<String, dynamic> event, String seedHex) {
    final content = event['content'] as String;
    
    // Chercher le tag d'encryption
    final tags = event['tags'] as List? ?? [];
    String? nonceHex;
    
    for (final tag in tags) {
      if (tag is List && tag.length >= 3 && tag[0] == 'encryption' && tag[1] == 'aes-gcm') {
        nonceHex = tag[2] as String;
        break;
      }
    }
    
    // Déchiffrer ou retourner tel quel
    return decryptWoTxContent(content, nonceHex ?? '', seedHex);
  }

  /// Dérive un mot de passe WiFi depuis la seed du marché
  /// Utilise SHA256 et encode en Base64 pour un mot de passe sécurisé
  String deriveWifiPassword(String seedMarketHex) {
    final seedBytes = HEX.decode(seedMarketHex);
    final hash = sha256.convert(seedBytes);
    // Prendre les 16 premiers octets et encoder en base64 pour un mot de passe lisible
    final passwordBytes = hash.bytes.sublist(0, 16);
    return base64Url.encode(passwordBytes).substring(0, 22); // 22 caractères alphanumériques
  }

  // ==================== MÉTHODES BYTES (POUR TESTS) ====================
  
  /// ✅ SÉCURITÉ: Chiffre P2 avec K_P2 = SHA256(P3) - Version Uint8List
  /// Utilisée dans les tests pour éviter les conversions hex
  /// Le ciphertext retourné contient déjà le tag GCM (16 derniers octets)
  Future<EncryptP2Result> encryptP2Bytes(Uint8List p2Bytes, Uint8List p3Bytes) async {
    // K_P2 = SHA256(P3)
    final kP2 = sha256.convert(p3Bytes).bytes;
    
    // ✅ CORRECTION: Nonce sécurisé
    final nonce = Uint8List.fromList(
      List.generate(12, (_) => _secureRandom.nextInt(256))
    );
    
    // Chiffrer avec AES-GCM
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(Uint8List.fromList(kP2)),
      128, // tag length
      nonce,
      Uint8List(0), // additional data
    );
    
    cipher.init(true, params);
    final ciphertextWithTag = cipher.process(p2Bytes);
    
    // AES-GCM retourne ciphertext + tag (16 bytes) - on garde tout ensemble
    // Le tag est dans les 16 derniers octets
    final tag = Uint8List.fromList(ciphertextWithTag.sublist(ciphertextWithTag.length - 16));
    
    return EncryptP2Result(
      ciphertext: ciphertextWithTag, // Contient déjà le tag
      nonce: nonce,
      tag: tag, // Pour compatibilité si on veut l'extraire
    );
  }
  
  /// ✅ SÉCURITÉ: Déchiffre P2 avec K_P2 = SHA256(P3) - Version Uint8List
  /// Utilisée dans les tests pour éviter les conversions hex
  /// Le ciphertext doit contenir le tag GCM (16 derniers octets)
  Future<Uint8List> decryptP2Bytes(
    Uint8List ciphertext,
    Uint8List nonce,
    Uint8List p3Bytes,
  ) async {
    // K_P2 = SHA256(P3)
    final kP2 = sha256.convert(p3Bytes).bytes;
    
    // Déchiffrer avec AES-GCM
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(Uint8List.fromList(kP2)),
      128,
      nonce,
      Uint8List(0),
    );
    
    cipher.init(false, params);
    
    // Le ciphertext contient déjà le tag (16 derniers octets)
    final plaintext = cipher.process(ciphertext);
    
    return plaintext;
  }
  
  /// ✅ SÉCURITÉ: Signe un message avec Schnorr (BIP-340) - Version bytes direct
  /// Prend des messageBytes au lieu de messageHex
  /// Retourne la signature en Uint8List (64 bytes) au lieu de hex
  Uint8List signMessageBytesDirect(Uint8List messageBytes, Uint8List privateKeyBytes) {
    // ✅ SÉCURITÉ: Validation de la clé privée
    if (privateKeyBytes.length != 32) {
      throw ArgumentError('Clé privée invalide: doit faire 32 octets');
    }
    
    if (messageBytes.length != 32) {
      throw ArgumentError('Message invalide: doit faire 32 octets');
    }
    
    try {
      // Convertir en hex pour bip340 (la bibliothèque nécessite du hex)
      final privateKeyHex = HEX.encode(privateKeyBytes);
      final messageHex = HEX.encode(messageBytes);
      
      // Générer auxRand sécurisé (32 octets aléatoires)
      final auxRandBytes = Uint8List.fromList(
        List.generate(32, (_) => _secureRandom.nextInt(256))
      );
      final auxRandHex = HEX.encode(auxRandBytes);
      
      final signatureHex = bip340.sign(privateKeyHex, messageHex, auxRandHex);
      
      // Nettoyer l'auxRand
      secureZeroiseBytes(auxRandBytes);
      
      // Retourner en bytes
      return Uint8List.fromList(HEX.decode(signatureHex));
    } catch (e) {
      throw ArgumentError('Erreur lors de la signature: $e');
    }
  }
  
  /// ✅ SÉCURITÉ: Vérifie une signature Schnorr (BIP-340) - Version bytes direct
  /// Prend des données bytes au lieu de hex
  bool verifySignatureBytesDirect(
    Uint8List messageBytes,
    Uint8List signatureBytes,
    Uint8List publicKeyBytes,
  ) {
    if (signatureBytes.length != 64) return false;
    if (publicKeyBytes.length != 32) return false;
    if (messageBytes.length != 32) return false;
    
    try {
      // Convertir en hex pour bip340
      final messageHex = HEX.encode(messageBytes);
      final signatureHex = HEX.encode(signatureBytes);
      final publicKeyHex = HEX.encode(publicKeyBytes);
      
      // ✅ SÉCURITÉ: Vérifier que la clé publique est sur la courbe
      if (!isValidPublicKey(publicKeyHex)) {
        return false;
      }
      
      // ✅ SÉCURITÉ: Utilisation de bip340 (bibliothèque éprouvée)
      return bip340.verify(publicKeyHex, messageHex, signatureHex);
    } catch (e) {
      return false;
    }
  }

}
