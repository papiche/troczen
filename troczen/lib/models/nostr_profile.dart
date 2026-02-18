/// Constantes Nostr et API pour TrocZen
class NostrConstants {
  // API Backend
  static const String defaultApiUrl = 'https://https://zen.copylaradio.com';
  static const String localApiUrl = 'http://zen.local:5000';
  static const String localRelayUrl = 'ws://zen.local:7777';
  
  // Relay Nostr par défaut
  static const String defaultRelay = 'wss://relay.copylaradio.com';
  
  // Marché global (si pas de marché spécifique)
  static const String globalMarketName = 'troczen-global';
  static const String globalMarketKey = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
  
  // Types d'events Nostr
  static const int kindMetadata = 0;        // Profil utilisateur
  static const int kindText = 1;            // Transfert/transaction
  static const int kindBurn = 5;            // Destruction bon
  static const int kindP3Publication = 30303; // Publication P3 (NIP-33)
}

/// Profil utilisateur Nostr (kind 0 metadata)
class NostrProfile {
  final String npub;
  final String name;
  final String? displayName;
  final String? about;
  final String? picture;
  final String? banner;
  final String? nip05;
  final String? lud16;
  final String? website;
  final String? g1pub;  // Clé publique Duniter Ğ1 en Base58

  NostrProfile({
    required this.npub,
    required this.name,
    this.displayName,
    this.about,
    this.picture,
    this.banner,
    this.nip05,
    this.lud16,
    this.website,
    this.g1pub,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (displayName != null) 'display_name': displayName,
      if (about != null) 'about': about,
      if (picture != null) 'picture': picture,
      if (banner != null) 'banner': banner,
      if (nip05 != null) 'nip05': nip05,
      if (lud16 != null) 'lud16': lud16,
      if (website != null) 'website': website,
      if (g1pub != null) 'g1pub': g1pub,
    };
  }

  factory NostrProfile.fromJson(Map<String, dynamic> json, String npub) {
    return NostrProfile(
      npub: npub,
      name: json['name'] ?? '',
      displayName: json['display_name'],
      about: json['about'],
      picture: json['picture'],
      banner: json['banner'],
      nip05: json['nip05'],
      lud16: json['lud16'],
      website: json['website'],
      g1pub: json['g1pub'],
    );
  }
}
