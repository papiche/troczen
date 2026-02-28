import 'package:troczen/services/crypto_service.dart';

class User {
  final String npub;           // Clé publique Nostr (hex) - stockage interne
  final String nsec;           // Clé privée Nostr (hex) - stockée de manière sécurisée
  final String displayName;
  final DateTime createdAt;
  final String? website;       // Site web du profil
  final String? g1pub;         // Clé publique Ğ1 (Base58)
  final String? about;         // Description du profil
  final String? picture;       // URL de l'avatar
  final String? banner;        // ✅ NOUVEAU: URL de la bannière
  final String? picture64;     // Fallback Base64
  final String? banner64;      // Fallback Base64
  final String? relayUrl;      // URL du relai Nostr de l'utilisateur
  final List<String>? activityTags;  // Tags d'activité/savoir-faire (WoTx)

  User({
    required this.npub,
    required this.nsec,
    required this.displayName,
    required this.createdAt,
    this.website,
    this.g1pub,
    this.about,
    this.picture,
    this.banner,
    this.picture64,
    this.banner64,
    this.relayUrl,
    this.activityTags,
  });

// Ajoutez cette méthode
  User copyWith({
    String? npub,
    String? nsec,
    String? displayName,
    DateTime? createdAt,
    String? website,
    String? g1pub,
    String? about,
    String? picture,
    String? banner,
    String? picture64,
    String? banner64,
    String? relayUrl,
    List<String>? activityTags,
  }) {
    return User(
      npub: npub ?? this.npub,
      nsec: nsec ?? this.nsec,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      website: website ?? this.website,
      g1pub: g1pub ?? this.g1pub,
      about: about ?? this.about,
      picture: picture ?? this.picture,
      banner: banner ?? this.banner,
      picture64: picture64 ?? this.picture64,
      banner64: banner64 ?? this.banner64,
      relayUrl: relayUrl ?? this.relayUrl,
      activityTags: activityTags ?? this.activityTags,
    );
  }

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
      if (about != null) 'about': about,
      if (picture != null) 'picture': picture,
      if (banner != null) 'banner': banner,
      if (picture64 != null) 'picture64': picture64,
      if (banner64 != null) 'banner64': banner64,
      if (relayUrl != null) 'relayUrl': relayUrl,
      if (activityTags != null) 'activityTags': activityTags,
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
      about: json['about'],
      picture: json['picture'],
      banner: json['banner'],
      picture64: json['picture64'],
      banner64: json['banner64'],
      relayUrl: json['relayUrl'],
      activityTags: json['activityTags'] != null
          ? List<String>.from(json['activityTags'])
          : null,
    );
  }
}
