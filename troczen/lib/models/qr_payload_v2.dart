import 'dart:typed_data';

/// Payload QR Code format v2 (240 octets)
/// Extension pour fonctionnement offline avec métadonnées complètes
///
/// ✅ CORRECTION HANDSHAKE: Ajout des champs challenge (16 octets) et signature (64 octets)
/// Whitepaper (§3.2 Étape 1): Le Donneur génère un challenge aléatoire
/// que le Receveur doit signer pour prouver la possession du bon.
/// Le QR doit être signé par le Donneur pour prouver la propriété du bon.
///
/// Structure (240 octets):
/// - Magic + version: 4 octets (0x5A454E02)
/// - bonId: 32 octets
/// - value: 4 octets (uint32, centimes)
/// - issuerNpub: 32 octets
/// - encryptedP2: 32 octets
/// - p2Nonce: 12 octets
/// - p2Tag: 16 octets
/// - challenge: 16 octets ✅ NOUVEAU
/// - issuerName: 20 octets
/// - timestamp: 4 octets
/// - signature: 64 octets ✅ NOUVEAU (signature Schnorr du Donneur)
/// - checksum: 4 octets
class QrPayloadV2 {
  final String bonId;           // bonId hex (32 octets)
  final int valueInCentimes;    // Valeur en centimes de Ẑ (uint32)
  final String issuerNpub;      // npub hex de l'émetteur (32 octets, x-only)
  final String issuerName;      // Nom commercial (max 20 octets UTF-8)
  final Uint8List encryptedP2;  // P2 chiffré AES-GCM (32 octets)
  final Uint8List p2Nonce;      // Nonce AES-GCM (12 octets)
  final Uint8List p2Tag;        // Tag d'authentification AES-GCM (16 octets)
  final Uint8List challenge;    // ✅ NOUVEAU: Challenge aléatoire du Donneur (16 octets)
  final Uint8List signature;    // ✅ NOUVEAU: Signature Schnorr du Donneur (64 octets)
  final DateTime emittedAt;     // Timestamp d'émission

  QrPayloadV2({
    required this.bonId,
    required this.valueInCentimes,
    required this.issuerNpub,
    required this.issuerName,
    required this.encryptedP2,
    required this.p2Nonce,
    required this.p2Tag,
    required this.challenge,    // ✅ NOUVEAU
    required this.signature,    // ✅ NOUVEAU
    required this.emittedAt,
  });

  /// Valeur en Ẑ (double)
  double get value => valueInCentimes / 100.0;

  /// Challenge en hex string pour faciliter l'usage
  String get challengeHex => challenge
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toLowerCase();

  /// Signature en hex string pour faciliter la vérification
  String get signatureHex => signature
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toLowerCase();

  /// Validation des tailles
  bool get isValid {
    return bonId.length == 64 &&  // 32 octets hex
           issuerNpub.length == 64 &&  // 32 octets hex
           encryptedP2.length == 32 &&
           p2Nonce.length == 12 &&
           p2Tag.length == 16 &&
           challenge.length == 16 &&  // ✅ NOUVEAU
           signature.length == 64 &&  // ✅ NOUVEAU
           issuerName.isNotEmpty &&
           valueInCentimes > 0;
  }

  @override
  String toString() {
    return 'QrPayloadV2(bonId: ${bonId.substring(0, 8)}..., value: ${value.toStringAsFixed(2)} Ẑ, issuer: $issuerName)';
  }
}
