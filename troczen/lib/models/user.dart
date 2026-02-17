class User {
  final String npub;           // Clé publique Nostr (hex)
  final String nsec;           // Clé privée Nostr (hex) - stockée de manière sécurisée
  final String displayName;
  final DateTime createdAt;
  final String? website;       // Site web du profil
  final String? g1pub;         // Clé publique Ğ1 (Base58)

  User({
    required this.npub,
    required this.nsec,
    required this.displayName,
    required this.createdAt,
    this.website,
    this.g1pub,
  });

  Map<String, dynamic> toJson() {
    return {
      'npub': npub,
      'nsec': nsec,
      'displayName': displayName,
      'createdAt': createdAt.toIso8601String(),
      if (website != null) 'website': website,
      if (g1pub != null) 'g1pub': g1pub,
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
    );
  }
}
