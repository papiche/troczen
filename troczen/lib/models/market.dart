import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Modèle représentant un marché ẐEN
/// 
/// Un marché est un espace de confiance où les commerçants peuvent
/// émettre et accepter des bons ẐEN. Chaque marché a sa propre graine
/// de chiffrement (seed_market) pour sécuriser les transactions.
/// 
/// ✅ IDENTIFIANT UNIQUE: marketId
/// Le marketId est un checksum de 4 caractères hex dérivé du SHA256 de la seed.
/// Cela garantit l'unicité même si deux marchés ont le même nom.
/// Exemple: seed = "abc123..." → SHA256 → "a1b2c3d4..." → marketId = "A1B2"
class Market {
  final String name;           // Nom du marché (ex: "Marche_Toulouse") - peut être dupliqué
  final String seedMarket;     // Graine du marché (hex 64 chars) - dérivée ou aléatoire
  final DateTime validUntil;   // Date d'expiration de la graine
  final String? relayUrl;      // URL du relais Nostr local
  final bool isActive;         // Marché actif par défaut pour l'UI
  final DateTime joinedAt;     // Date d'adhésion au marché
  
  // ✅ v2.0.1: Métadonnées de profil Nostr (Kind 0) pour l'affichage UI
  final String? about;         // Description du marché
  final String? picture;       // URL du logo/avatar du marché
  final String? banner;        // URL de la bannière du marché
  final int? merchantCount;    // Nombre de commerçants actifs (cache local)

  Market({
    required this.name,
    required this.seedMarket,
    required this.validUntil,
    this.relayUrl,
    this.isActive = false,
    DateTime? joinedAt,
    this.about,
    this.picture,
    this.banner,
    this.merchantCount,
  }) : joinedAt = joinedAt ?? DateTime.now();

  /// ✅ NOUVEAU: Identifiant unique du marché (checksum 4 chars)
  /// Dérivé du SHA256 de la seed pour garantir l'unicité
  String get marketId {
    // Prendre les 4 premiers caractères hex du SHA256 de la seed
    final bytes = utf8.encode(seedMarket);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 4).toUpperCase();
  }
  
  /// ✅ NOUVEAU: Nom complet avec checksum pour affichage unique
  /// Format: "Nom du Marché [A1B2]"
  String get fullName => '$displayName [$marketId]';
  
  /// ✅ NOUVEAU: Identifiant complet pour Nostr et stockage
  /// Format: "marketName_marketId" (ex: "Marche_Toulouse_A1B2")
  String get uniqueId => '${name}_$marketId';

  /// Vérifie si la graine du marché est expirée
  bool get isExpired => DateTime.now().isAfter(validUntil);

  /// Vérifie si le marché est encore valide (non expiré)
  bool get isValid => !isExpired;

  /// Retourne le nom formaté pour l'affichage (sans underscores)
  String get displayName {
    return name.replaceAll('_', ' ');
  }

  /// Retourne le temps restant avant expiration
  Duration get remainingTime {
    final now = DateTime.now();
    if (now.isAfter(validUntil)) return Duration.zero;
    return validUntil.difference(now);
  }

  /// Retourne une description lisible du temps restant
  String get remainingTimeDescription {
    final remaining = remainingTime;
    if (remaining == Duration.zero) return 'Expiré';
    
    final days = remaining.inDays;
    if (days > 0) return '$days jour${days > 1 ? 's' : ''} restant${days > 1 ? 's' : ''}';
    
    final hours = remaining.inHours;
    if (hours > 0) return '$hours heure${hours > 1 ? 's' : ''} restante${hours > 1 ? 's' : ''}';
    
    final minutes = remaining.inMinutes;
    return '$minutes minute${minutes > 1 ? 's' : ''} restante${minutes > 1 ? 's' : ''}';
  }

  /// ✅ NOUVEAU: Crée une copie du marché avec des propriétés modifiées
  Market copyWith({
    String? name,
    String? seedMarket,
    DateTime? validUntil,
    String? relayUrl,
    bool? isActive,
    DateTime? joinedAt,
    String? about,
    String? picture,
    String? banner,
    int? merchantCount,
  }) {
    return Market(
      name: name ?? this.name,
      seedMarket: seedMarket ?? this.seedMarket,
      validUntil: validUntil ?? this.validUntil,
      relayUrl: relayUrl ?? this.relayUrl,
      isActive: isActive ?? this.isActive,
      joinedAt: joinedAt ?? this.joinedAt,
      about: about ?? this.about,
      picture: picture ?? this.picture,
      banner: banner ?? this.banner,
      merchantCount: merchantCount ?? this.merchantCount,
    );
  }

  /// ✅ STATIQUE: Génère un marketId depuis une seed (sans créer l'objet)
  static String generateMarketId(String seedMarket) {
    final bytes = utf8.encode(seedMarket);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 4).toUpperCase();
  }
  
  /// ✅ STATIQUE: Vérifie si un marketId correspond à une seed
  static bool verifyMarketId(String seedMarket, String marketId) {
    return generateMarketId(seedMarket) == marketId.toUpperCase();
  }

  /// Sérialisation JSON pour le stockage
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'seedMarket': seedMarket,
      'validUntil': validUntil.toIso8601String(),
      'relayUrl': relayUrl,
      'isActive': isActive,
      'joinedAt': joinedAt.toIso8601String(),
      // ✅ NOUVEAU: Inclure le marketId pour vérification
      'marketId': marketId,
      // ✅ v2.0.1: Métadonnées de profil Nostr
      'about': about,
      'picture': picture,
      'banner': banner,
      'merchantCount': merchantCount,
    };
  }

  /// Désérialisation JSON depuis le stockage
  factory Market.fromJson(Map<String, dynamic> json) {
    final market = Market(
      name: json['name'],
      seedMarket: json['seedMarket'],
      validUntil: DateTime.parse(json['validUntil']),
      relayUrl: json['relayUrl'],
      isActive: json['isActive'] ?? false,
      joinedAt: json['joinedAt'] != null
          ? DateTime.parse(json['joinedAt'])
          : DateTime.now(),
      // ✅ v2.0.1: Métadonnées de profil Nostr
      about: json['about'],
      picture: json['picture'],
      banner: json['banner'],
      merchantCount: json['merchantCount'],
    );
    
    // ✅ NOUVEAU: Vérifier la cohérence du marketId si présent
    if (json['marketId'] != null) {
      final storedId = json['marketId'] as String;
      if (storedId.toUpperCase() != market.marketId) {
        // Warning: incohérence détectée - on continue mais on log
        // En production, on pourrait vouloir rejeter ce marché
        print('WARNING: Market ID mismatch for ${market.name}');
      }
    }
    
    return market;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    // ✅ MODIFIÉ: Comparaison par marketId (unique) au lieu du nom
    return other is Market && other.marketId == marketId;
  }

  @override
  int get hashCode => marketId.hashCode;

  @override
  String toString() {
    return 'Market(name: $name, marketId: $marketId, isActive: $isActive, validUntil: $validUntil)';
  }
}
