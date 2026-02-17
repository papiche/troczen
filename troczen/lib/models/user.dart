class User {
  final String npub;           // Clé publique Nostr (hex)
  final String nsec;           // Clé privée Nostr (hex) - stockée de manière sécurisée
  final String displayName;
  final DateTime createdAt;

  User({
    required this.npub,
    required this.nsec,
    required this.displayName,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'npub': npub,
      'nsec': nsec,
      'displayName': displayName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      npub: json['npub'],
      nsec: json['nsec'],
      displayName: json['displayName'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
