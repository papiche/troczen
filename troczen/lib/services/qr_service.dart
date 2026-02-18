import 'dart:convert';
import 'dart:typed_data';
import 'package:hex/hex.dart';
import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/qr_payload_v2.dart';
import '../models/bon.dart';

class QRService {
  // Magic number pour format QR v2: "ZEN" + version 0x02
  static const int _magicV2 = 0x5A454E02;
  
  /// Encode une offre en format binaire compact (113 octets)
  /// Structure:
  /// - bon_id: 32 octets
  /// - p2_cipher: 48 octets
  /// - nonce: 12 octets
  /// - challenge: 16 octets
  /// - timestamp: 4 octets (uint32)
  /// - ttl: 1 octet (uint8)
  Uint8List encodeOffer({
    required String bonIdHex,
    required String p2CipherHex,
    required String nonceHex,
    required String challengeHex,
    required int timestamp,
    required int ttl,
  }) {
    final bonId = HEX.decode(bonIdHex);
    final p2Cipher = HEX.decode(p2CipherHex);
    final nonce = HEX.decode(nonceHex);
    final challenge = HEX.decode(challengeHex);
    
    final buffer = ByteData(113);
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
    buffer.setUint8(offset, ttl);
    
    return buffer.buffer.asUint8List();
  }

  /// Décode une offre depuis le format binaire
  Map<String, dynamic> decodeOffer(Uint8List data) {
    if (data.length != 113) {
      throw Exception('Format invalide: taille attendue 113 octets, reçu ${data.length}');
    }
    
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
    
    return {
      'bonId': HEX.encode(bonId),
      'p2Cipher': HEX.encode(p2Cipher),
      'nonce': HEX.encode(nonce),
      'challenge': HEX.encode(challenge),
      'timestamp': timestamp,
      'ttl': ttl,
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

  // ==================== FORMAT QR V2 (160 octets) ====================
  
  /// Encode un bon en payload QR v2 (160 octets) pour fonctionnement offline
  /// Inclut toutes les métadonnées nécessaires (valeur, émetteur, etc.)
  Uint8List encodeQrV2({
    required Bon bon,
    required String encryptedP2Hex,
    required Uint8List p2Nonce,
    required Uint8List p2Tag,
  }) {
    final buffer = ByteData(160);
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
    
    // 132-151: issuerName (20 octets UTF-8, tronqué/paddé)
    final nameBytes = _encodeNameFixed(bon.issuerName, 20);
    for (int i = 0; i < 20; i++) {
      buffer.setUint8(offset++, nameBytes[i]);
    }
    
    // 152-155: timestamp (uint32 big-endian, epoch Unix)
    final timestamp = bon.createdAt.millisecondsSinceEpoch ~/ 1000;
    buffer.setUint32(offset, timestamp, Endian.big);
    offset += 4;
    
    // 156-159: checksum CRC-32 des octets 0-155
    final dataForChecksum = buffer.buffer.asUint8List(0, 156);
    final checksum = _crc32(dataForChecksum);
    buffer.setUint32(offset, checksum, Endian.big);
    
    return buffer.buffer.asUint8List();
  }
  
  /// Décode un payload QR (détecte automatiquement v1 ou v2)
  /// Retourne null si checksum invalide
  QrPayloadV2? decodeQr(Uint8List bytes) {
    if (bytes.length < 4) return null;
    
    // Vérifier la version
    final buffer = ByteData.sublistView(bytes);
    final possibleMagic = buffer.getUint32(0, Endian.big);
    
    if (possibleMagic == _magicV2 && bytes.length == 160) {
      return _decodeQrV2(bytes);
    }
    
    // Format v1 ou invalide
    return null;
  }
  
  /// Décode spécifiquement un payload QR v2
  QrPayloadV2? _decodeQrV2(Uint8List bytes) {
    if (bytes.length != 160) return null;
    
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
    
    // 132-151: issuerName
    final nameBytes = bytes.sublist(offset, offset + 20);
    offset += 20;
    final issuerName = _decodeNameFixed(nameBytes);
    
    // 152-155: timestamp
    final timestamp = buffer.getUint32(offset, Endian.big);
    offset += 4;
    final emittedAt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    
    // 156-159: checksum
    final storedChecksum = buffer.getUint32(offset, Endian.big);
    
    // Vérifier le checksum
    final dataForChecksum = bytes.sublist(0, 156);
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
      emittedAt: emittedAt,
    );
  }
  
  /// Génère un widget QR code depuis le payload binaire
  Widget buildQrWidget(Uint8List payload, {double size = 280}) {
    return QrImageView(
      data: String.fromCharCodes(payload),
      version: QrVersions.auto,
      size: size,
      backgroundColor: const Color(0xFFFFFFFF),
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
  }
  
  // ==================== UTILITAIRES ====================
  
  /// Encode un nom en 20 octets fixes (UTF-8, tronqué/paddé avec des zéros)
  Uint8List _encodeNameFixed(String name, int length) {
    final bytes = utf8.encode(name);
    final result = Uint8List(length);
    
    // Copier jusqu'à min(bytes.length, length)
    final copyLength = bytes.length < length ? bytes.length : length;
    for (int i = 0; i < copyLength; i++) {
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
}
