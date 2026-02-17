import 'dart:typed_data';
import 'package:hex/hex.dart';

class QRService {
  
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
}
