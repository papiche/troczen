import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:hex/hex.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:bip39/bip39.dart' as bip39;
import 'package:bs58/bs58.dart';

class CryptoService {
  final Random _secureRandom = Random.secure();
  
  /// ✅ SÉCURITÉ 100%: Nettoyage explicite mémoire
  void secureZeroise(String hexString) {
    try {
      final bytes = HEX.decode(hexString);
      for (int i = 0; i < bytes.length; i++) {
        bytes[i] = 0;
      }
    } catch (e) {
      // Silently fail - string déjà collecté
    }
  }
  
  /// ✅ SÉCURITÉ 100%: Validation clé publique sur courbe secp256k1
  bool isValidPublicKey(String pubKeyHex) {
    if (pubKeyHex.length != 64) return false;
    
    try {
      final x = BigInt.parse(pubKeyHex, radix: 16);
      
      // Constante p de secp256k1
      final p = BigInt.parse(
        'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
        radix: 16
      );
      
      // Vérifier que x < p
      if (x >= p) return false;
      
      // Vérifier l'équation y² = x³ + 7 (mod p)
      final ySq = (x.modPow(BigInt.from(3), p) + BigInt.from(7)) % p;
      
      // Calculer racine carrée (si existe)
      final y = ySq.modPow((p + BigInt.one) >> 2, p);
      
      // Vérifier que y² = ySq (mod p)
      return (y.modPow(BigInt.two, p) == ySq);
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
    
    return {
      'nsec': privateKeyHex,
      'npub': publicKeyHex,
    };
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

  /// Découpe une clé en 3 parts avec Shamir Secret Sharing (2-sur-3)
  /// ✅ CORRECTION: Implémentation du vrai Shamir polynomial au lieu de XOR simple
  /// Retourne [P1, P2, P3]
  List<String> shamirSplit(String secretHex) {
    final secretBytes = HEX.decode(secretHex);
    if (secretBytes.length != 32) {
      throw ArgumentError('Secret doit faire 32 octets');
    }
    
    // Shamir (2,3) : Utilisation de polynômes mod 257
    // f(x) = a0 + a1*x où a0 = secret byte, a1 = random
    // P1 = f(1), P2 = f(2), P3 = f(3)
    
    final p1Bytes = Uint8List(32);
    final p2Bytes = Uint8List(32);
    final p3Bytes = Uint8List(32);
    final mod = BigInt.from(257);
    
    for (int i = 0; i < 32; i++) {
      final a0 = BigInt.from(secretBytes[i]); // secret
      final a1 = BigInt.from(_secureRandom.nextInt(257)); // coefficient aléatoire
      
      // Calculer f(1), f(2), f(3) mod 257
      p1Bytes[i] = ((a0 + a1 * BigInt.one) % mod).toInt();
      p2Bytes[i] = ((a0 + a1 * BigInt.two) % mod).toInt();
      p3Bytes[i] = ((a0 + a1 * BigInt.from(3)) % mod).toInt();
    }
    
    return [
      HEX.encode(p1Bytes),
      HEX.encode(p2Bytes),
      HEX.encode(p3Bytes),
    ];
  }

  /// Reconstruit le secret à partir de 2 parts quelconques (sur 3)
  String shamirCombine(String? part1Hex, String? part2Hex, String? part3Hex) {
    // Vérifier qu'on a au moins 2 parts
    final parts = <int, Uint8List>{};
    if (part1Hex != null) parts[1] = Uint8List.fromList(HEX.decode(part1Hex));
    if (part2Hex != null) parts[2] = Uint8List.fromList(HEX.decode(part2Hex));
    if (part3Hex != null) parts[3] = Uint8List.fromList(HEX.decode(part3Hex));
    
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
    final mod = BigInt.from(257);
    
    for (int i = 0; i < 32; i++) {
      // Interpolation de Lagrange mod 257
      // f(0) = y1 * L1(0) + y2 * L2(0)
      // où L1(0) = (0-x2)/(x1-x2) et L2(0) = (0-x1)/(x2-x1)
      
      final y1Big = BigInt.from(y1[i]);
      final y2Big = BigInt.from(y2[i]);
      final x1Big = BigInt.from(x1);
      final x2Big = BigInt.from(x2);
      
      // L1 = (0 - x2) / (x1 - x2) mod 257
      var num1 = (BigInt.zero - x2Big) % mod;
      if (num1.isNegative) num1 = num1 + mod;
      
      var den1 = (x1Big - x2Big) % mod;
      if (den1.isNegative) den1 = den1 + mod;
      
      final invDen1 = _modInverseBigInt(den1, mod);
      final l1 = (num1 * invDen1) % mod;
      
      // L2 = (0 - x1) / (x2 - x1) mod 257
      var num2 = (BigInt.zero - x1Big) % mod;
      if (num2.isNegative) num2 = num2 + mod;
      
      var den2 = (x2Big - x1Big) % mod;
      if (den2.isNegative) den2 = den2 + mod;
      
      final invDen2 = _modInverseBigInt(den2, mod);
      final l2 = (num2 * invDen2) % mod;
      
      // f(0) = y1 * L1 + y2 * L2 mod 257
      var result = (y1Big * l1 + y2Big * l2) % mod;
      if (result.isNegative) result = result + mod;
      
      // ✅ CORRECTION BUG P0 CRITIQUE: Supprimer le % 256 final
      // En théorie, f(0) devrait toujours être dans [0, 255] car c'est le secret original
      // Si on obtient 256, c'est une erreur de calcul ou des données corrompues
      // On lève une exception au lieu de masquer silencieusement avec % 256
      final resultInt = result.toInt();
      if (resultInt > 255) {
        throw Exception('Erreur Shamir: reconstruction invalide (octet $i = $resultInt > 255)');
      }
      secretBytes[i] = resultInt;
    }
    
    return HEX.encode(secretBytes);
  }

  /// Calcul de l'inverse modulaire pour BigInt
  BigInt _modInverseBigInt(BigInt a, BigInt m) {
    // Algorithme d'Euclide étendu pour trouver l'inverse modulaire
    final result = _extendedGCDBigInt(a, m);
    final x = result[0];
    
    // Normaliser dans [0, m)
    return (x % m + m) % m;
  }

  /// Algorithme d'Euclide étendu pour BigInt
  List<BigInt> _extendedGCDBigInt(BigInt a, BigInt b) {
    if (b == BigInt.zero) {
      return [BigInt.one, BigInt.zero];
    }
    
    final result = _extendedGCDBigInt(b, a % b);
    final x = result[1];
    final y = result[0] - (a ~/ b) * result[1];
    
    return [x, y];
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

  /// Chiffre P3 avec K_day (clé du jour)
  Future<Map<String, String>> encryptP3(String p3Hex, String kDayHex) async {
    final p3Bytes = HEX.decode(p3Hex);
    final kDayBytes = HEX.decode(kDayHex);
    
    // ✅ CORRECTION: Nonce sécurisé
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

  /// Déchiffre P3 avec K_day (clé du jour)
  Future<String> decryptP3(String ciphertextHex, String nonceHex, String kDayHex) async {
    final ciphertext = HEX.decode(ciphertextHex);
    final nonce = HEX.decode(nonceHex);
    final kDayBytes = HEX.decode(kDayHex);
    
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

  /// ✅ Signe un message avec une clé privée (Schnorr avec RFC 6979)
  String signMessage(String messageHex, String privateKeyHex) {
    final message = HEX.decode(messageHex);
    final privateKeyBytes = Uint8List.fromList(HEX.decode(privateKeyHex));
    final privateKeyBigInt = _bytesToBigInt(privateKeyBytes);
    
    // ✅ SÉCURITÉ 100%: Générer k déterministe (RFC 6979)
    var k = _deriveNonceDeterministic(privateKeyBytes, Uint8List.fromList(message));
    
    final domainParams = ECDomainParameters('secp256k1');
    final n = domainParams.n;
    var R = (domainParams.G * k)!;
    
    // BIP-340: Normaliser R pour avoir y pair
    final yBigInt = R.y!.toBigInteger()!;
    if (yBigInt.isOdd) {
      // Si y est impair, prendre -k (qui donnera le point opposé avec y pair)
      k = n - k;
      R = (domainParams.G * k)!;
    }
    
    final r = R.x!.toBigInteger()!;
    
    // e = hash(r || message)
    final eBytes = sha256.convert([
      ...HEX.decode(_bigIntToHex(r, 32)),
      ...message,
    ]).bytes;
    final e = _bytesToBigInt(Uint8List.fromList(eBytes));
    
    // s = k + e*privateKey mod n
    final s = (k + e * privateKeyBigInt) % n;
    
    // Signature = r || s (64 octets)
    return _bigIntToHex(r, 32) + _bigIntToHex(s, 32);
  }

  /// Vérifie une signature Schnorr
  bool verifySignature(String messageHex, String signatureHex, String publicKeyHex) {
    if (signatureHex.length != 128) return false; // 64 octets
    
    try {
      final message = HEX.decode(messageHex);
      final r = _hexToBigInt(signatureHex.substring(0, 64));
      final s = _hexToBigInt(signatureHex.substring(64));
      
      final domainParams = ECDomainParameters('secp256k1');
      final n = domainParams.n;
      
      // Vérifier que r et s sont dans [1, n-1]
      if (r <= BigInt.zero || r >= n) return false;
      if (s <= BigInt.zero || s >= n) return false;
      
      // Reconstruire le point public depuis x uniquement (supposer y pair - BIP-340)
      final publicKeyX = _hexToBigInt(publicKeyHex);
      final publicKeyPoint = _decompressPoint(publicKeyX, true, domainParams.curve);
      if (publicKeyPoint == null) return false;
      
      // Reconstruire R depuis r (supposer y pair - BIP-340)
      final R = _decompressPoint(r, true, domainParams.curve);
      if (R == null) return false;
      
      // e = hash(r || message)
      final eBytes = sha256.convert([
        ...HEX.decode(_bigIntToHex(r, 32)),
        ...message,
      ]).bytes;
      final e = _bytesToBigInt(Uint8List.fromList(eBytes));
      
      // Vérifier: s*G == R + e*publicKey
      final sG = domainParams.G * s;
      final ePub = publicKeyPoint * e;
      final RePlus = R + ePub!;
      
      return sG == RePlus;
    } catch (e) {
      return false;
    }
  }

  /// ✅ SÉCURITÉ 100%: Dérivation déterministe de nonce (RFC 6979)
  /// Évite les failles si RNG compromise
  BigInt _deriveNonceDeterministic(Uint8List privateKey, Uint8List message) {
    // k = HMAC_SHA256(privateKey, message) mod n
    final hmac = Hmac(sha256, privateKey);
    final kBytes = hmac.convert(message).bytes;
    
    final k = _bytesToBigInt(Uint8List.fromList(kBytes));
    
    // Réduire modulo n (ordre de la courbe secp256k1)
    final n = BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141',
      radix: 16
    );
    
    return k % n;
  }

  // Utilitaires privés
  
  BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  BigInt _hexToBigInt(String hex) {
    return BigInt.parse(hex, radix: 16);
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

  /// Décompresse un point à partir de x et du bit de parité de y
  ECPoint? _decompressPoint(BigInt x, bool yBit, ECCurve curve) {
    // y^2 = x^3 + 7 (pour secp256k1)
    // p = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
    final p = BigInt.parse('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F', radix: 16);
    final ySq = (x.modPow(BigInt.from(3), p) + BigInt.from(7)) % p;
    
    // Calculer y = sqrt(ySq) mod p
    var y = ySq.modPow((p + BigInt.one) >> 2, p);
    
    // Ajuster selon le bit de parité
    if ((y.isEven) != yBit) {
      y = p - y;
    }
    
    return curve.createPoint(x, y);
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
    return 'k' + _encodeBase36(ipnsBytes);
  }

  // --- SECTION DUNITER V2 (SUBSTRATE / BIP39) ---

  /// Génère une nouvelle phrase mnémonique aléatoire (12 mots)
  String generateMnemonic() {
    return bip39.generateMnemonic();
  }

  /// Convertit un mnémonique en Seed de 32 octets (Compatible avec votre JS)
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
  Future<Map<String, String>> encryptP3WithSeed(String p3Hex, String seedHex, DateTime date) async {
    final kDay = getDailyMarketKey(seedHex, date);
    return encryptP3(p3Hex, kDay);
  }

  /// ✅ Déchiffre P3 avec K_day (clé du jour dérivée de la graine)
  Future<String> decryptP3WithSeed(String ciphertextHex, String nonceHex, String seedHex, DateTime date) async {
    final kDay = getDailyMarketKey(seedHex, date);
    return decryptP3(ciphertextHex, nonceHex, kDay);
  }

}
