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
/// ✅ WOTX2: Credential de compétence vérifié par l'Oracle (Kind 30503)
/// Ces credentials sont générés par le moteur Python de la TrocZen Box
class SkillCredential {
  final String permitId;     // ex: "PERMIT_MARAICHAGE_X2"
  final String skillTag;     // ex: "maraîchage"
  final int level;           // 1, 2, ou 3 (X1, X2, X3)
  final String? issuerNpub;  // Oracle qui a signé
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final bool verified;
  final String? eventId; // ID de l'événement Kind 30503

  SkillCredential({
    required this.permitId,
    required this.skillTag,
    required this.level,
    this.issuerNpub,
    this.issuedAt,
    this.expiresAt,
    this.verified = true,
    this.eventId,
  });

  /// Extrait le niveau depuis le permitId (ex: "PERMIT_MARAICHAGE_X2" → 2)
  static int extractLevel(String permitId) {
    final match = RegExp(r'_X(\d+)$').firstMatch(permitId);
    return match != null ? int.parse(match.group(1)!) : 1;
  }

  /// Extrait le tag de compétence depuis le permitId
  static String extractSkillTag(String permitId) {
    // "PERMIT_MARAICHAGE_X2" → "maraîchage"
    final parts = permitId.split('_');
    if (parts.length >= 2) {
      return parts[1].toLowerCase();
    }
    return permitId.toLowerCase();
  }

  factory SkillCredential.fromKind30503(Map<String, dynamic> event) {
    final permitId = event['tags']?.firstWhere(
      (t) => t[0] == 'permit_id',
      orElse: () => ['', ''],
    )?[1] ?? '';
    
    return SkillCredential(
      permitId: permitId,
      skillTag: extractSkillTag(permitId),
      level: extractLevel(permitId),
      issuerNpub: event['pubkey'],
      issuedAt: event['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch((event['created_at'] as int) * 1000)
          : null,
      verified: true,
      eventId: event['id'],
    );
  }

  /// Badge d'affichage (X1, X2, X3)
  String get badgeLabel => 'X$level';
  
  /// Couleur du badge selon le niveau
  String get badgeColor {
    switch (level) {
      case 1: return '#4CAF50'; // Vert
      case 2: return '#2196F3'; // Bleu
      case 3: return '#9C27B0'; // Violet
      default: return '#9E9E9E'; // Gris
    }
  }
}

class NostrProfile {
  final String npub;
  final String name;
  final String? displayName;
  final String? about;
  final String? picture;
  final String? banner;
  final String? picture64; // ✅ Fallback Base64
  final String? banner64;  // ✅ Fallback Base64
  final String? nip05;
  final String? lud16;
  final String? website;
  final String? g1pub;  // Clé publique Duniter Ğ1 en Base58
  
  // ✅ NIP-24: Tags d'activité/centres d'intérêt
  final List<String>? tags;
  
  // ✅ NIP-24 extended: Champs additionnels
  final String? activity;      // Activité professionnelle
  final String? profession;    // Métier
  
  // ✅ WOTX2: Credentials de compétences vérifiés (Kind 30503)
  final List<SkillCredential>? skillCredentials;

  // ✅ Données économiques (DU)
  final Map<String, dynamic>? economicData;

  NostrProfile({
    required this.npub,
    required this.name,
    this.displayName,
    this.about,
    this.picture,
    this.banner,
    this.picture64,
    this.banner64,
    this.nip05,
    this.lud16,
    this.website,
    this.g1pub,
    this.tags,
    this.activity,
    this.profession,
    this.skillCredentials,
    this.economicData,
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
      if (picture64 != null) 'picture64': picture64,
      if (banner64 != null) 'banner64': banner64,
      if (nip05 != null) 'nip05': nip05,
      if (lud16 != null) 'lud16': lud16,
      if (website != null) 'website': website,
      if (g1pub != null) 'g1pub': g1pub,
      // ✅ NIP-24: Tags dans le contenu JSON
      if (tags != null && tags!.isNotEmpty) 'tags': tags,
      // ✅ NIP-24 extended: Champs additionnels
      if (activity != null) 'activity': activity,
      if (profession != null) 'profession': profession,
      // ✅ WOTX2: Credentials de compétences
      if (skillCredentials != null && skillCredentials!.isNotEmpty)
        'skill_credentials': skillCredentials!.map((c) => {
          'permit_id': c.permitId,
          'skill_tag': c.skillTag,
          'level': c.level,
          'badge': c.badgeLabel,
          if (c.eventId != null) 'event_id': c.eventId,
        }).toList(),
      // ✅ Données économiques
      if (economicData != null) 'economic_data': economicData,
    };
  }

  factory NostrProfile.fromJson(Map<String, dynamic> json, String npub) {
    // ✅ WOTX2: Parsing des credentials
    List<SkillCredential>? credentials;
    if (json['skill_credentials'] != null) {
      credentials = (json['skill_credentials'] as List<dynamic>)
          .map((c) => SkillCredential(
            permitId: c['permit_id'] ?? '',
            skillTag: c['skill_tag'] ?? '',
            level: c['level'] ?? 1,
            eventId: c['event_id'],
          ))
          .toList();
    }
    
    return NostrProfile(
      npub: npub,
      name: json['name'] ?? '',
      displayName: json['display_name'],
      about: json['about'],
      picture: json['picture'],
      banner: json['banner'],
      picture64: json['picture64'],
      banner64: json['banner64'],
      nip05: json['nip05'],
      lud16: json['lud16'],
      website: json['website'],
      g1pub: json['g1pub'],
      // ✅ NIP-24: Parsing des tags
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      activity: json['activity'],
      profession: json['profession'],
      // ✅ WOTX2: Credentials
      skillCredentials: credentials,
      // ✅ Données économiques
      economicData: json['economic_data'] as Map<String, dynamic>?,
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
    String? picture64,
    String? banner64,
    String? nip05,
    String? lud16,
    String? website,
    String? g1pub,
    List<String>? tags,
    String? activity,
    String? profession,
    List<SkillCredential>? skillCredentials,
    Map<String, dynamic>? economicData,
  }) {
    return NostrProfile(
      npub: npub ?? this.npub,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      about: about ?? this.about,
      picture: picture ?? this.picture,
      banner: banner ?? this.banner,
      picture64: picture64 ?? this.picture64,
      banner64: banner64 ?? this.banner64,
      nip05: nip05 ?? this.nip05,
      lud16: lud16 ?? this.lud16,
      website: website ?? this.website,
      g1pub: g1pub ?? this.g1pub,
      tags: tags ?? this.tags,
      activity: activity ?? this.activity,
      profession: profession ?? this.profession,
      skillCredentials: skillCredentials ?? this.skillCredentials,
      economicData: economicData ?? this.economicData,
    );
  }
  
  /// ✅ WOTX2: Récupère le niveau max d'un credential pour une compétence donnée
  int? getMaxLevelForSkill(String skillTag) {
    if (skillCredentials == null || skillCredentials!.isEmpty) return null;
    
    final matching = skillCredentials!
        .where((c) => c.skillTag.toLowerCase() == skillTag.toLowerCase());
    if (matching.isEmpty) return null;
    
    return matching.map((c) => c.level).reduce((a, b) => a > b ? a : b);
  }
  
  /// ✅ WOTX2: Récupère tous les badges à afficher
  List<String> getSkillBadges() {
    if (skillCredentials == null || skillCredentials!.isEmpty) return [];
    return skillCredentials!.map((c) => '${c.skillTag} ${c.badgeLabel}').toList();
  }
}
