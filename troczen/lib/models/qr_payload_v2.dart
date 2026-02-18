import 'dart:typed_data';

/// Payload QR Code format v2 (160 octets)
/// Extension pour fonctionnement offline avec métadonnées complètes
class QrPayloadV2 {
  final String bonId;           // bonId hex (32 octets)
  final int valueInCentimes;    // Valeur en centimes de Ẑ (uint32)
  final String issuerNpub;      // npub hex de l'émetteur (32 octets, x-only)
  final String issuerName;      // Nom commercial (max 20 octets UTF-8)
  final Uint8List encryptedP2;  // P2 chiffré AES-GCM (32 octets)
  final Uint8List p2Nonce;      // Nonce AES-GCM (12 octets)
  final Uint8List p2Tag;        // Tag d'authentification AES-GCM (16 octets)
  final DateTime emittedAt;     // Timestamp d'émission

  QrPayloadV2({
    required this.bonId,
    required this.valueInCentimes,
    required this.issuerNpub,
    required this.issuerName,
    required this.encryptedP2,
    required this.p2Nonce,
    required this.p2Tag,
    required this.emittedAt,
  });

  /// Valeur en Ẑ (double)
  double get value => valueInCentimes / 100.0;

  /// Validation des tailles
  bool get isValid {
    return bonId.length == 64 &&  // 32 octets hex
           issuerNpub.length == 64 &&  // 32 octets hex
           encryptedP2.length == 32 &&
           p2Nonce.length == 12 &&
           p2Tag.length == 16 &&
           issuerName.isNotEmpty &&
           valueInCentimes > 0;
  }

  @override
  String toString() {
    return 'QrPayloadV2(bonId: ${bonId.substring(0, 8)}..., value: ${value.toStringAsFixed(2)} Ẑ, issuer: $issuerName)';
  }
}
