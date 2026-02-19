import 'package:troczen/services/crypto_service.dart';

class User {
  final String npub;           // Clé publique Nostr (hex) - stockage interne
  final String nsec;           // Clé privée Nostr (hex) - stockée de manière sécurisée
  final String displayName;
  final DateTime createdAt;
  final String? website;       // Site web du profil
  final String? g1pub;         // Clé publique Ğ1 (Base58)
  final String? picture;       // URL de l'avatar

  User({
    required this.npub,
    required this.nsec,
    required this.displayName,
    required this.createdAt,
    this.website,
    this.g1pub,
    this.picture,
  });

  /// Retourne la clé publique en format Bech32 NIP-19 (npub1...)
  String get npubBech32 {
    final cryptoService = CryptoService();
    return cryptoService.encodeNpub(npub);
  }

  /// Retourne la clé privée en format Bech32 NIP-19 (nsec1...)
  String get nsecBech32 {
    final cryptoService = CryptoService();
    return cryptoService.encodeNsec(nsec);
  }

  Map<String, dynamic> toJson() {
    return {
      'npub': npub,
      'nsec': nsec,
      'displayName': displayName,
      'createdAt': createdAt.toIso8601String(),
      if (website != null) 'website': website,
      if (g1pub != null) 'g1pub': g1pub,
      if (picture != null) 'picture': picture,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      npub: json['npub'],
      nsec: json['nsec'],
      displayName: json['displayName'],
      createdAt: DateTime.parse(json['createdAt']),
      website: json['website'],
      g1pub: json['g1pub'],
      picture: json['picture'],
    );
  }
}
