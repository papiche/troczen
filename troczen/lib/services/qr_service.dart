import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/qr_payload_v2.dart';
import '../models/bon.dart';

class QRService {
  // Magic number pour format QR v2: "ZEN" + version 0x02
  static const int _magicV2 = 0x5A454E02;
  
  /// ✅ CORRECTION P0-C: Taille du QR Offre avec signature (177 octets)
  /// Ancien format sans signature: 113 octets
  /// Nouveau format avec signature: 113 + 64 = 177 octets
  ///
  /// Whitepaper (007.md §3.2 Étape 1 — Offre):
  /// "QR1: {B_id, P2, c, ts}_sig_E"
  /// Le QR doit être signé par le donneur pour prouver la propriété du bon.
  
  /// Encode une offre en format binaire compact avec signature (177 octets)
  /// ✅ CORRECTION P0-C: Ajout de la signature du donneur
  /// Structure:
  /// - bon_id: 32 octets
  /// - p2_cipher: 48 octets
  /// - nonce: 12 octets
  /// - challenge: 16 octets
  /// - timestamp: 4 octets (uint32)
  /// - ttl: 1 octet (uint8)
  /// - signature: 64 octets (Schnorr) ✅ NOUVEAU
  Uint8List encodeOffer({
    required String bonIdHex,
    required String p2CipherHex,
    required String nonceHex,
    required String challengeHex,
    required int timestamp,
    required int ttl,
    String? signatureHex,  // ✅ NOUVEAU: signature du donneur (64 octets = 128 hex chars)
  }) {
    final bonId = HEX.decode(bonIdHex);
    final p2Cipher = HEX.decode(p2CipherHex);
    final nonce = HEX.decode(nonceHex);
    final challenge = HEX.decode(challengeHex);
    
    // ✅ CORRECTION P0-C: Taille variable selon présence de signature
    final hasSignature = signatureHex != null && signatureHex.isNotEmpty;
    final totalSize = hasSignature ? 177 : 113;
    
    final buffer = ByteData(totalSize);
    int offset = 0;
    
    // bon_id (32 octets)
    for (int i = 0; i < 32; i++) {
      buffer.setUint8(offset++, bonId[i]);
    }
    
    // p2_cipher (48 octets)
    for (int i = 0; i < 48; i++) {
      buffer.setUint8(offset++, p2Cipher[i]);
    }
    
    // nonce (12 octets)
    for (int i = 0; i < 12; i++) {
      buffer.setUint8(offset++, nonce[i]);
    }
    
    // challenge (16 octets)
    for (int i = 0; i < 16; i++) {
      buffer.setUint8(offset++, challenge[i]);
    }
    
    // timestamp (4 octets, big-endian)
    buffer.setUint32(offset, timestamp, Endian.big);
    offset += 4;
    
    // ttl (1 octet)
    buffer.setUint8(offset++, ttl);
    
    // ✅ CORRECTION P0-C: signature (64 octets) - NOUVEAU
    if (hasSignature) {
      final signature = HEX.decode(signatureHex);
      for (int i = 0; i < 64; i++) {
        buffer.setUint8(offset++, signature[i]);
      }
    }
    
    return buffer.buffer.asUint8List();
  }

  /// Décode une offre depuis le format binaire
  /// ✅ CORRECTION P0-C: Supporte les deux formats (avec/sans signature)
  Map<String, dynamic> decodeOffer(Uint8List data) {
    // ✅ CORRECTION P0-C: Accepter les deux tailles
    if (data.length != 113 && data.length != 177) {
      throw Exception('Format invalide: taille attendue 113 ou 177 octets, reçu ${data.length}');
    }
    
    final hasSignature = data.length == 177;
    final buffer = ByteData.sublistView(data);
    int offset = 0;
    
    // bon_id
    final bonId = data.sublist(offset, offset + 32);
    offset += 32;
    
    // p2_cipher
    final p2Cipher = data.sublist(offset, offset + 48);
    offset += 48;
    
    // nonce
    final nonce = data.sublist(offset, offset + 12);
    offset += 12;
    
    // challenge
    final challenge = data.sublist(offset, offset + 16);
    offset += 16;
    
    // timestamp
    final timestamp = buffer.getUint32(offset, Endian.big);
    offset += 4;
    
    // ttl
    final ttl = buffer.getUint8(offset);
    offset += 1;
    
    // ✅ CORRECTION P0-C: signature (optionnel)
    String? signature;
    if (hasSignature) {
      final sigBytes = data.sublist(offset, offset + 64);
      signature = HEX.encode(sigBytes);
    }
    
    return {
      'bonId': HEX.encode(bonId),
      'p2Cipher': HEX.encode(p2Cipher),
      'nonce': HEX.encode(nonce),
      'challenge': HEX.encode(challenge),
      'timestamp': timestamp,
      'ttl': ttl,
      'signature': signature,  // ✅ NOUVEAU
    };
  }

  /// Encode un ACK en format binaire (97 octets)
  /// Structure:
  /// - bon_id: 32 octets
  /// - signature: 64 octets
  /// - status: 1 octet
  Uint8List encodeAck({
    required String bonIdHex,
    required String signatureHex,
    int status = 0x01, // 0x01 = RECEIVED
  }) {
    final bonId = HEX.decode(bonIdHex);
    final signature = HEX.decode(signatureHex);
    
    final buffer = ByteData(97);
    int offset = 0;
    
    // bon_id
    for (int i = 0; i < 32; i++) {
      buffer.setUint8(offset++, bonId[i]);
    }
    
    // signature
    for (int i = 0; i < 64; i++) {
      buffer.setUint8(offset++, signature[i]);
    }
    
    // status
    buffer.setUint8(offset, status);
    
    return buffer.buffer.asUint8List();
  }

  /// Décode un ACK depuis le format binaire
  Map<String, dynamic> decodeAck(Uint8List data) {
    if (data.length != 97) {
      throw Exception('Format ACK invalide: taille attendue 97 octets, reçu ${data.length}');
    }
    
    final buffer = ByteData.sublistView(data);
    int offset = 0;
    
    // bon_id
    final bonId = data.sublist(offset, offset + 32);
    offset += 32;
    
    // signature
    final signature = data.sublist(offset, offset + 64);
    offset += 64;
    
    // status
    final status = buffer.getUint8(offset);
    
    return {
      'bonId': HEX.encode(bonId),
      'signature': HEX.encode(signature),
      'status': status,
    };
  }

  /// Vérifie si un QR a expiré
  bool isExpired(int timestamp, int ttl) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= (timestamp + ttl);
  }

  /// Calcule le temps restant en secondes
  int timeRemaining(int timestamp, int ttl) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = (timestamp + ttl) - now;
    return remaining > 0 ? remaining : 0;
  }

  // ==================== FORMAT QR V2 (240 octets) ====================
  // ✅ CORRECTION HANDSHAKE: Taille passée de 160 à 240 octets
  // Ajout du champ challenge (16 octets) pour le handshake cryptographique
  // Ajout du champ signature (64 octets) pour l'authentification du Donneur
  // Whitepaper (§3.2): Le Donneur génère un challenge que le Receveur doit signer.
  // Whitepaper (§3.2): Le QR doit être signé par le Donneur pour prouver la propriété.
  
  /// Taille du format QR v2 (avec challenge et signature)
  static const int _qrV2Size = 240;
  
  /// Encode un bon en payload QR v2 (240 octets) pour fonctionnement offline
  /// Inclut toutes les métadonnées nécessaires (valeur, émetteur, challenge, signature)
  ///
  /// ✅ CORRECTION HANDSHAKE: Ajout des paramètres challenge et signature
  /// Le challenge est généré par le Donneur et doit être signé par le Receveur.
  /// La signature prouve que le Donneur possède le bon (clé privée reconstituée).
  Uint8List encodeQrV2({
    required Bon bon,
    required String encryptedP2Hex,
    required Uint8List p2Nonce,
    required Uint8List p2Tag,
    required Uint8List challenge,   // ✅ NOUVEAU: challenge du Donneur (16 octets)
    required Uint8List signature,   // ✅ NOUVEAU: signature Schnorr du Donneur (64 octets)
  }) {
    final buffer = ByteData(_qrV2Size);
    int offset = 0;
    
    // 0-3: Magic + version (0x5A454E02 = "ZEN" + 0x02)
    buffer.setUint32(offset, _magicV2, Endian.big);
    offset += 4;
    
    // 4-35: bonId (32 octets)
    final bonIdBytes = HEX.decode(bon.bonId);
    for (int i = 0; i < 32; i++) {
      buffer.setUint8(offset++, bonIdBytes[i]);
    }
    
    // 36-39: value (uint32 big-endian, centimes)
    final valueInCentimes = (bon.value * 100).round();
    buffer.setUint32(offset, valueInCentimes, Endian.big);
    offset += 4;
    
    // 40-71: issuerNpub (32 octets)
    final issuerNpubBytes = HEX.decode(bon.issuerNpub);
    for (int i = 0; i < 32; i++) {
      buffer.setUint8(offset++, issuerNpubBytes[i]);
    }
    
    // 72-103: p2_encrypted (32 octets)
    final p2EncryptedBytes = HEX.decode(encryptedP2Hex);
    for (int i = 0; i < 32; i++) {
      buffer.setUint8(offset++, p2EncryptedBytes[i]);
    }
    
    // 104-115: p2_nonce (12 octets)
    for (int i = 0; i < 12; i++) {
      buffer.setUint8(offset++, p2Nonce[i]);
    }
    
    // 116-131: p2_tag (16 octets)
    for (int i = 0; i < 16; i++) {
      buffer.setUint8(offset++, p2Tag[i]);
    }
    
    // 132-147: challenge (16 octets) ✅ NOUVEAU
    for (int i = 0; i < 16; i++) {
      buffer.setUint8(offset++, challenge[i]);
    }
    
    // 148-167: issuerName (20 octets UTF-8, tronqué/paddé)
    final nameBytes = _encodeNameFixed(bon.issuerName, 20);
    for (int i = 0; i < 20; i++) {
      buffer.setUint8(offset++, nameBytes[i]);
    }
    
    // 168-171: timestamp (uint32 big-endian, epoch Unix)
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    buffer.setUint32(offset, timestamp, Endian.big);
    offset += 4;
    
    // 172-235: signature (64 octets) ✅ NOUVEAU
    for (int i = 0; i < 64; i++) {
      buffer.setUint8(offset++, signature[i]);
    }
    
    // 236-239: checksum CRC-32 des octets 0-235
    final dataForChecksum = buffer.buffer.asUint8List(0, 236);
    final checksum = _crc32(dataForChecksum);
    buffer.setUint32(offset, checksum, Endian.big);
    
    return buffer.buffer.asUint8List();
  }
  
  /// Décode un payload QR (détecte automatiquement v1 ou v2)
  /// Retourne null si checksum invalide
  ///
  /// ✅ CORRECTION HANDSHAKE: Supporte le format v2 avec challenge et signature (240 octets)
  QrPayloadV2? decodeQr(Uint8List bytes) {
    if (bytes.length < 4) return null;
    
    // Vérifier la version
    final buffer = ByteData.sublistView(bytes);
    final possibleMagic = buffer.getUint32(0, Endian.big);
    
    // ✅ CORRECTION HANDSHAKE: Accepter uniquement le format v2 complet (240 octets)
    if (possibleMagic == _magicV2 && bytes.length == _qrV2Size) {
      return _decodeQrV2(bytes);
    }
    
    // Format v1 ou invalide
    return null;
  }
  
  /// Décode spécifiquement un payload QR v2
  /// ✅ CORRECTION HANDSHAKE: Extrait le challenge et la signature du payload
  QrPayloadV2? _decodeQrV2(Uint8List bytes) {
    if (bytes.length != _qrV2Size) return null;
    
    final buffer = ByteData.sublistView(bytes);
    int offset = 0;
    
    // 0-3: Vérifier magic
    final magic = buffer.getUint32(offset, Endian.big);
    offset += 4;
    if (magic != _magicV2) return null;
    
    // 4-35: bonId
    final bonIdBytes = bytes.sublist(offset, offset + 32);
    offset += 32;
    final bonId = HEX.encode(bonIdBytes);
    
    // 36-39: value (centimes)
    final valueInCentimes = buffer.getUint32(offset, Endian.big);
    offset += 4;
    
    // 40-71: issuerNpub
    final issuerNpubBytes = bytes.sublist(offset, offset + 32);
    offset += 32;
    final issuerNpub = HEX.encode(issuerNpubBytes);
    
    // 72-103: p2_encrypted
    final encryptedP2 = bytes.sublist(offset, offset + 32);
    offset += 32;
    
    // 104-115: p2_nonce
    final p2Nonce = bytes.sublist(offset, offset + 12);
    offset += 12;
    
    // 116-131: p2_tag
    final p2Tag = bytes.sublist(offset, offset + 16);
    offset += 16;
    
    // 132-147: challenge ✅ NOUVEAU
    final challenge = bytes.sublist(offset, offset + 16);
    offset += 16;
    
    // 148-167: issuerName
    final nameBytes = bytes.sublist(offset, offset + 20);
    offset += 20;
    final issuerName = _decodeNameFixed(nameBytes);
    
    // 168-171: timestamp
    final timestamp = buffer.getUint32(offset, Endian.big);
    offset += 4;
    final emittedAt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    
    // 172-235: signature ✅ NOUVEAU
    final signature = bytes.sublist(offset, offset + 64);
    offset += 64;
    
    // 236-239: checksum
    final storedChecksum = buffer.getUint32(offset, Endian.big);
    
    // Vérifier le checksum
    final dataForChecksum = bytes.sublist(0, 236);
    final computedChecksum = _crc32(dataForChecksum);
    
    if (storedChecksum != computedChecksum) {
      return null; // Checksum invalide
    }
    
    return QrPayloadV2(
      bonId: bonId,
      valueInCentimes: valueInCentimes,
      issuerNpub: issuerNpub,
      issuerName: issuerName,
      encryptedP2: encryptedP2,
      p2Nonce: p2Nonce,
      p2Tag: p2Tag,
      challenge: challenge,   // ✅ NOUVEAU
      signature: signature,   // ✅ NOUVEAU
      emittedAt: emittedAt,
    );
  }
  
  /// Génère un widget QR code à partir de données binaires
  ///
  /// ✅ ENCODAGE: Utilise systématiquement Base64
  /// Les données binaires (0x00-0xFF) sont encodées en Base64 (A-Za-z0-9+/=)
  /// pour garantir des caractères valides pour les QR codes.
  /// Le scanner doit décoder en Base64 avant de traiter les bytes.
  Widget buildQrWidget(
    Uint8List payload, {
    double size = 280,
  }) {
    // Encoder en Base64 pour garantir des caractères valides
    final base64String = base64Encode(payload);
    
    return QrImageView(
      data: base64String,
      version: QrVersions.auto,
      size: size,
      backgroundColor: const Color(0xFFFFFFFF),
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
  }
  
  // ==================== UTILITAIRES ====================
  
  /// Encode un nom en 20 octets fixes (UTF-8, tronqué/paddé avec des zéros)
  /// ✅ CORRECTION: Troncature UTF-8 sécurisée via runes pour éviter
  /// de couper au milieu d'un caractère multi-octets
  Uint8List _encodeNameFixed(String name, int length) {
    // Convertir en runes, limiter, puis encoder
    var chars = name.runes.toList();
    var bytes = utf8.encode(String.fromCharCodes(chars));
    
    // Réduire progressivement si trop long, en respectant les caractères UTF-8
    while (bytes.length > length && chars.isNotEmpty) {
      chars.removeLast();
      bytes = utf8.encode(String.fromCharCodes(chars));
    }
    
    final result = Uint8List(length);
    for (int i = 0; i < bytes.length; i++) {
      result[i] = bytes[i];
    }
    // Le reste est déjà à zéro (Uint8List par défaut)
    return result;
  }
  
  /// Décode un nom depuis 20 octets fixes (retire le padding de zéros)
  String _decodeNameFixed(Uint8List bytes) {
    // Trouver le premier zéro pour retirer le padding
    int endIndex = bytes.length;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0) {
        endIndex = i;
        break;
      }
    }
    
    return utf8.decode(bytes.sublist(0, endIndex));
  }
  
  /// Calcule le CRC-32 (polynomial 0xEDB88320)
  int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    
    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc = crc >> 1;
        }
      }
    }
    
    return ~crc & 0xFFFFFFFF;
  }
  
  // ==================== QR PARTAGE DE MARCHÉ ====================
  // Format URI: troczen://market?name=Marche_Toulouse&seed=HEX64&relay=wss://...&validUntil=1708084800&mid=A1B2
  // ✅ AMÉLIORÉ: Ajout du marketId (checksum 4 chars) pour garantir l'unicité
  // Permet à un commerçant A de faire rentrer un commerçant B dans un marché via scan QR
  
  /// Magic number pour QR marché: "ZENM" (0x5A454E4D)
  static const int _magicMarket = 0x5A454E4D;
  
  /// Taille du format QR marché binaire
  /// - magic: 4 octets
  /// - marketId: 2 octets (4 chars hex)
  /// - nameLength: 1 octet
  /// - name: max 32 octets
  /// - seed: 32 octets (64 hex chars)
  /// - relayLength: 1 octet
  /// - relay: max 64 octets
  /// - validUntil: 4 octets (uint32 timestamp)
  /// - CRC32: 4 octets
  /// Total max: 4 + 2 + 1 + 32 + 32 + 1 + 64 + 4 + 4 = 144 octets
  static const int _qrMarketMaxSize = 144;
  
  /// Calcule le marketId (checksum 4 chars) depuis la seed
  /// Utilise SHA256 pour générer un identifiant unique
  String _calculateMarketId(String seedMarket) {
    final bytes = utf8.encode(seedMarket);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 4).toUpperCase();
  }
  
  /// Encode un marché en format URI pour QR code
  /// ✅ AMÉLIORÉ: Inclut le marketId pour vérification d'unicité
  /// Format: troczen://market?name=NAME&seed=HEX64&relay=URL&validUntil=TIMESTAMP&mid=MARKETID
  String encodeMarketUri({
    required String name,
    required String seedMarket,
    String? relayUrl,
    required DateTime validUntil,
    String? marketId,  // ✅ NOUVEAU: Optionnel, calculé si non fourni
  }) {
    // Calculer le marketId si non fourni
    final mid = marketId ?? _calculateMarketId(seedMarket);
    
    final uri = Uri(
      scheme: 'troczen',
      host: 'market',
      queryParameters: {
        'name': name,
        'seed': seedMarket,
        if (relayUrl != null && relayUrl.isNotEmpty) 'relay': relayUrl,
        'validUntil': validUntil.millisecondsSinceEpoch.toString(),
        'mid': mid,  // ✅ NOUVEAU: Checksum pour vérification
      },
    );
    return uri.toString();
  }
  
  /// Décode une URI de marché depuis un QR code scanné
  /// ✅ AMÉLIORÉ: Vérifie le marketId si présent
  /// Retourne null si le format est invalide ou si le marketId ne correspond pas
  Map<String, dynamic>? decodeMarketUri(String uriString) {
    try {
      final uri = Uri.tryParse(uriString);
      if (uri == null) return null;
      
      // Vérifier le schéma
      if (uri.scheme != 'troczen') return null;
      if (uri.host != 'market') return null;
      
      final params = uri.queryParameters;
      
      // Champs obligatoires
      final name = params['name'];
      final seed = params['seed'];
      final validUntilStr = params['validUntil'];
      
      if (name == null || seed == null || validUntilStr == null) {
        return null;
      }
      
      // Valider la seed (64 chars hex)
      if (seed.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(seed)) {
        return null;
      }
      
      final validUntil = int.tryParse(validUntilStr);
      if (validUntil == null) return null;
      
      // ✅ NOUVEAU: Calculer et vérifier le marketId
      final expectedMarketId = _calculateMarketId(seed);
      final providedMarketId = params['mid'];
      
      if (providedMarketId != null) {
        // Vérifier que le marketId correspond à la seed
        if (providedMarketId.toUpperCase() != expectedMarketId) {
          // Le marketId ne correspond pas - QR potentiellement corrompu ou falsifié
          return null;
        }
      }
      
      return {
        'name': name,
        'seedMarket': seed.toLowerCase(), // Normaliser en minuscules
        'relayUrl': params['relay'],
        'validUntil': DateTime.fromMillisecondsSinceEpoch(validUntil),
        'marketId': expectedMarketId,  // ✅ NOUVEAU: Inclure le marketId calculé
      };
    } catch (e) {
      return null;
    }
  }
  
  /// Encode un marché en format binaire compact (plus efficace pour QR)
  Uint8List encodeMarketBinary({
    required String name,
    required String seedMarket,
    String? relayUrl,
    required DateTime validUntil,
  }) {
    // Calculer la taille exacte
    final nameBytes = utf8.encode(name);
    final relayBytes = relayUrl != null ? utf8.encode(relayUrl) : <int>[];
    
    final nameLen = nameBytes.length.clamp(0, 32);
    final relayLen = relayBytes.length.clamp(0, 64);
    
    // Taille: 4 (magic) + 1 (nameLen) + nameLen + 32 (seed) + 1 (relayLen) + relayLen + 4 (validUntil) + 4 (CRC)
    final totalSize = 4 + 1 + nameLen + 32 + 1 + relayLen + 4 + 4;
    
    final buffer = ByteData(totalSize);
    int offset = 0;
    
    // Magic "ZENM"
    buffer.setUint32(offset, _magicMarket, Endian.big);
    offset += 4;
    
    // Nom du marché
    buffer.setUint8(offset++, nameLen);
    for (int i = 0; i < nameLen; i++) {
      buffer.setUint8(offset++, nameBytes[i]);
    }
    
    // Seed (32 octets binaires)
    final seedBytes = HEX.decode(seedMarket);
    for (int i = 0; i < 32; i++) {
      buffer.setUint8(offset++, seedBytes[i]);
    }
    
    // Relay URL
    buffer.setUint8(offset++, relayLen);
    for (int i = 0; i < relayLen; i++) {
      buffer.setUint8(offset++, relayBytes[i]);
    }
    
    // ValidUntil (timestamp Unix)
    buffer.setUint32(offset, validUntil.millisecondsSinceEpoch ~/ 1000, Endian.big);
    offset += 4;
    
    // CRC32
    final dataWithoutCrc = buffer.buffer.asUint8List(0, offset);
    final crc = _crc32(dataWithoutCrc);
    buffer.setUint32(offset, crc, Endian.big);
    
    return buffer.buffer.asUint8List();
  }
  
  /// Décode un marché depuis le format binaire
  Map<String, dynamic>? decodeMarketBinary(Uint8List data) {
    try {
      if (data.length < 10) return null; // Minimum: magic + nameLen + seed + relayLen + validUntil + crc
      
      final buffer = ByteData.sublistView(data);
      int offset = 0;
      
      // Vérifier magic
      final magic = buffer.getUint32(offset, Endian.big);
      if (magic != _magicMarket) return null;
      offset += 4;
      
      // Nom
      final nameLen = buffer.getUint8(offset++);
      if (nameLen > 32 || offset + nameLen > data.length - 4) return null;
      final name = utf8.decode(data.sublist(offset, offset + nameLen));
      offset += nameLen;
      
      // Seed
      if (offset + 32 > data.length - 4) return null;
      final seedBytes = data.sublist(offset, offset + 32);
      final seedMarket = HEX.encode(seedBytes);
      offset += 32;
      
      // Relay
      final relayLen = buffer.getUint8(offset++);
      String? relayUrl;
      if (relayLen > 0) {
        if (offset + relayLen > data.length - 4) return null;
        relayUrl = utf8.decode(data.sublist(offset, offset + relayLen));
        offset += relayLen;
      }
      
      // ValidUntil
      if (offset + 4 > data.length - 4) return null;
      final validUntilTimestamp = buffer.getUint32(offset, Endian.big);
      offset += 4;
      
      // Vérifier CRC
      final expectedCrc = buffer.getUint32(offset, Endian.big);
      final actualCrc = _crc32(data.sublist(0, offset));
      if (expectedCrc != actualCrc) {
        return null; // CRC invalide = données corrompues
      }
      
      return {
        'name': name,
        'seedMarket': seedMarket,
        'relayUrl': relayUrl,
        'validUntil': DateTime.fromMillisecondsSinceEpoch(validUntilTimestamp * 1000),
      };
    } catch (e) {
      return null;
    }
  }
  
  /// Tente de décoder automatiquement un QR marché (URI ou binaire)
  Map<String, dynamic>? decodeMarketQr(String scannedData) {
    // Essayer d'abord le format URI
    if (scannedData.startsWith('troczen://')) {
      return decodeMarketUri(scannedData);
    }
    
    // Essayer le format binaire (Base64)
    try {
      final bytes = base64Decode(scannedData);
      return decodeMarketBinary(bytes);
    } catch (e) {
      // Pas du Base64 valide
    }
    
    return null;
  }
  
  /// Génère un widget QR code pour partager un marché
  Widget buildMarketQrWidget({
    required String name,
    required String seedMarket,
    String? relayUrl,
    required DateTime validUntil,
    double size = 280,
    bool useBinary = true, // Utiliser le format binaire (plus compact)
  }) {
    String qrData;
    
    if (useBinary) {
      final binary = encodeMarketBinary(
        name: name,
        seedMarket: seedMarket,
        relayUrl: relayUrl,
        validUntil: validUntil,
      );
      qrData = base64Encode(binary);
    } else {
      qrData = encodeMarketUri(
        name: name,
        seedMarket: seedMarket,
        relayUrl: relayUrl,
        validUntil: validUntil,
      );
    }
    
    return QrImageView(
      data: qrData,
      version: QrVersions.auto,
      size: size,
      backgroundColor: const Color(0xFFFFFFFF),
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
  }
}
