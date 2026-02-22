import '../config/app_config.dart';

/// Constantes Nostr pour TrocZen
/// Les URLs API et Relay sont centralisées dans AppConfig
class NostrConstants {
  // Relay Nostr par défaut (délégué à AppConfig)
  static String get defaultRelay => AppConfig.defaultRelayUrl;
  
  // URLs locales (déléguées à AppConfig)
  static String get localApiUrl => AppConfig.localApiUrl;
  static String get localRelayUrl => AppConfig.localRelayUrl;
  
  // Marché global (si pas de marché spécifique)
  static const String globalMarketName = 'troczen-global';
  static const String globalMarketKey = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
  
  // Types d'events Nostr
  static const int kindMetadata = 0;        // Profil utilisateur
  static const int kindText = 1;            // Transfert/transaction
  static const int kindBurn = 5;            // Destruction bon
  static const int kindP3Publication = 30303; // Publication P3 (NIP-33)
  
  // WoTx - Savoir-faire (Kind 30xxx)
  static const int kindSkillPermit = 30500;  // Définition d'un savoir-faire
  static const int kindSkillRequest = 30501; // Demande d'attestation
  static const int kindSkillAttest = 30502;  // Attestation par un pair
  static const int kindSkillCredential = 30503; // Verifiable Credential (Oracle)
}

/// Profil utilisateur Nostr (kind 0 metadata)
///
/// ✅ NIP-24 Compliant: Supporte les champs étendus et les tags d'activité
/// - display_name, website, banner, about (NIP-24)
/// - tags/interests pour centres d'intérêt (NIP-24 extended)
///
/// Les tags sont sérialisés dans le contenu JSON ET comme tags 't' de l'event
/// pour une interopérabilité maximale avec les clients Nostr.
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
  
  // ✅ NIP-24: Tags d'activité/centres d'intérêt
  final List<String>? tags;
  
  // ✅ NIP-24 extended: Champs additionnels
  final String? activity;      // Activité professionnelle
  final String? profession;    // Métier

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
    this.tags,
    this.activity,
    this.profession,
  });

  /// Sérialisation JSON conforme NIP-24
  /// Les tags sont inclus dans le contenu pour les clients NIP-24
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
      // ✅ NIP-24: Tags dans le contenu JSON
      if (tags != null && tags!.isNotEmpty) 'tags': tags,
      // ✅ NIP-24 extended: Champs additionnels
      if (activity != null) 'activity': activity,
      if (profession != null) 'profession': profession,
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
      // ✅ NIP-24: Parsing des tags
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      activity: json['activity'],
      profession: json['profession'],
    );
  }
  
  /// Crée une copie avec des valeurs modifiées
  NostrProfile copyWith({
    String? npub,
    String? name,
    String? displayName,
    String? about,
    String? picture,
    String? banner,
    String? nip05,
    String? lud16,
    String? website,
    String? g1pub,
    List<String>? tags,
    String? activity,
    String? profession,
  }) {
    return NostrProfile(
      npub: npub ?? this.npub,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      about: about ?? this.about,
      picture: picture ?? this.picture,
      banner: banner ?? this.banner,
      nip05: nip05 ?? this.nip05,
      lud16: lud16 ?? this.lud16,
      website: website ?? this.website,
      g1pub: g1pub ?? this.g1pub,
      tags: tags ?? this.tags,
      activity: activity ?? this.activity,
      profession: profession ?? this.profession,
    );
  }
}
