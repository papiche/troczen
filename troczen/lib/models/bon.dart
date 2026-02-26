
import 'dart:typed_data';
import 'package:hex/hex.dart';

enum BonStatus {
  issued,    // Créé
  pending,   // En attente de confirmation
  active,    // Actif dans le wallet
  lockedForTransfer, // ✅ WAL: Verrouillé pour transfert en cours
  spent,     // Dépensé
  expired,   // Expiré
  burned     // Détruit
}

class Bon {
  final String bonId;           // npub_bon (clé publique du bon en hex)
  final double value;           // Valeur en ẐEN
  final String issuerName;      // Nom de l'émetteur
  final String issuerNpub;      // npub de l'émetteur
  final DateTime createdAt;
  final DateTime? expiresAt;
  final BonStatus status;
  final String? p1;             // Part 1 (seulement pour l'émetteur)
  final String? p2;             // Part 2 (porteur actuel)
  final String? p3;             // Part 3 (témoin, vient du réseau)
  final String marketName;
  final String? logoUrl;        // URL du logo du commerçant
  final String? picture;        // URL de l'avatar de l'émetteur
  final String? picture64;      // ✅ Fallback Base64
  final String? banner;         // ✅ URL de la bannière paysage
  final String? banner64;       // ✅ Fallback Base64 bannière
  final int? color;             // Couleur dominante (ARGB) - Pour UI uniquement
  final int? transferCount;     // Nombre de transferts effectués
  final String? issuerNostrProfile; // URL profil Nostr du commerçant
  final double? duAtCreation;   // Valeur du DU le jour de la création (pour calcul relativiste)
  final String? wish;           // Vœu attaché au bon (ex: "De la graine à l'assiette")
  
  // ⚠️ DÉPRÉCIÉ v6: Champs Pokemon - gardés pour rétrocompatibilité uniquement
  @Deprecated('Non conforme protocole v6 - Ne plus utiliser pour nouveaux bons')
  final String? rarity;         // Ex: 'common', 'rare' - Plus généré depuis v6
  @Deprecated('Non conforme protocole v6 - Ne plus utiliser')
  final String? uniqueId;       // Ex: 'ZEN-ABC123'
  @Deprecated('Non conforme protocole v6 - Ne plus utiliser')
  final String? cardType;       // Ex: 'commerce', 'artisan'
  @Deprecated('Non conforme protocole v6 - Ne plus utiliser')
  final String? specialAbility; // Ex: 'Double valeur'
  @Deprecated('Non conforme protocole v6 - Ne plus utiliser')
  final Map<String, dynamic>? stats; // Ex: {"power": 5}
  
  // ✅ WAL (Write-Ahead Log) pour protection contre double-dépense
  final DateTime? transferLockTimestamp; // Quand le bon a été verrouillé
  final String? transferLockChallenge;   // Challenge du transfert en cours
  final int? transferLockTtlSeconds;     // TTL du verrou (défaut: 300s = 5min)

  Bon({
    required this.bonId,
    required this.value,
    required this.issuerName,
    required this.issuerNpub,
    required this.createdAt,
    this.expiresAt,
    required this.status,
    this.p1,
    this.p2,
    this.p3,
    required this.marketName,
    this.logoUrl,
    this.picture,
    this.picture64,
    this.banner,
    this.banner64,
    this.color,
    this.transferCount = 0,
    this.issuerNostrProfile,
    this.duAtCreation,
    this.wish,
    // ⚠️ DÉPRÉCIÉ: Paramètres Pokemon (rétrocompatibilité anciens bons)
    this.rarity,
    this.uniqueId,
    this.cardType,
    this.specialAbility,
    this.stats,
    // ✅ WAL (Write-Ahead Log)
    this.transferLockTimestamp,
    this.transferLockChallenge,
    this.transferLockTtlSeconds,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isValid => status == BonStatus.active && !isExpired;
  bool get isRare => rarity != null && rarity != 'common';
  
  /// ✅ WAL: Vérifie si le bon est verrouillé pour un transfert en cours
  /// Un verrou expiré est considéré comme non actif
  bool get isTransferLocked {
    if (status != BonStatus.lockedForTransfer) return false;
    if (transferLockTimestamp == null) return false;
    final ttl = transferLockTtlSeconds ?? 300; // 5 minutes par défaut
    final lockExpiry = transferLockTimestamp!.add(Duration(seconds: ttl));
    return DateTime.now().isBefore(lockExpiry);
  }
  
  /// ✅ WAL: Vérifie si le verrou a expiré (pour crash recovery)
  bool get isTransferLockExpired {
    if (transferLockTimestamp == null) return true;
    final ttl = transferLockTtlSeconds ?? 300;
    final lockExpiry = transferLockTimestamp!.add(Duration(seconds: ttl));
    return DateTime.now().isAfter(lockExpiry);
  }
  
  // Probabilités de rareté (à utiliser lors de la création)
  static String generateRarity() {
    final random = DateTime.now().millisecondsSinceEpoch % 100;
    if (random < 1) return 'legendary';  // 1%
    if (random < 6) return 'rare';       // 5%
    if (random < 21) return 'uncommon';  // 15%
    return 'common';                     // 79%
  }

  // Générer un identifiant unique pour la carte (style Pokémon)
  static String generateUniqueId(String bonId) {
    final hash = bonId.substring(0, 6).toUpperCase();
    return 'ZEN-$hash';
  }

  // Générer un type de carte aléatoire
  static String generateCardType() {
    final types = ['commerce', 'service', 'artisan', 'culture', 'technologie', 'alimentation'];
    final random = DateTime.now().millisecondsSinceEpoch % types.length;
    return types[random];
  }

  // Générer une capacité spéciale aléatoire
  static String generateSpecialAbility(String rarity) {
    final commonAbilities = [
      'Résistant aux copies',
      'Valable 2x plus longtemps',
      'Accepté partout',
    ];
    
    final uncommonAbilities = [
      'Double valeur les week-ends',
      'Résistant à l\'inflation',
      'Transférable instantanément',
      'Échangeable contre services',
    ];
    
    final rareAbilities = [
      'Triple valeur en période de fête',
      'Création de bons illimitée',
      'Accès VIP aux événements',
      'Immunité aux frais',
    ];
    
    final legendaryAbilities = [
      'Multiplicateur de valeur x10',
      'Création de marché autorisée',
      'Statut de super-utilisateur',
      'Bénéfices à vie',
    ];
    
    final random = DateTime.now().millisecondsSinceEpoch % 100;
    
    switch (rarity) {
      case 'legendary':
        return legendaryAbilities[random % legendaryAbilities.length];
      case 'rare':
        return rareAbilities[random % rareAbilities.length];
      case 'uncommon':
        return uncommonAbilities[random % uncommonAbilities.length];
      default:
        return commonAbilities[random % commonAbilities.length];
    }
  }

  // Générer des statistiques pour la carte
  static Map<String, dynamic> generateStats(String rarity) {
    final random = DateTime.now().millisecondsSinceEpoch;
    
    int basePower = 1;
    int baseDefense = 1;
    int baseSpeed = 1;
    
    switch (rarity) {
      case 'legendary':
        basePower = 10;
        baseDefense = 8;
        baseSpeed = 5;
        break;
      case 'rare':
        basePower = 7;
        baseDefense = 5;
        baseSpeed = 3;
        break;
      case 'uncommon':
        basePower = 4;
        baseDefense = 3;
        baseSpeed = 2;
        break;
      default:
        basePower = 2;
        baseDefense = 2;
        baseSpeed = 1;
    }
    
    // Ajouter une variation aléatoire
    final power = (basePower + (random % 3)).clamp(1, 15);
    final defense = (baseDefense + (random % 2)).clamp(1, 10);
    final speed = (baseSpeed + (random % 2)).clamp(1, 7);
    
    return {
      'power': power,
      'defense': defense,
      'speed': speed,
      'durability': (power + defense) ~/ 2,
      'valueMultiplier': 1.0 + (power * 0.1),
    };
  }

  // Calculer la durée restante du bon
  String getDurationRemaining() {
    if (expiresAt == null) return 'Illimité';
    
    final remaining = expiresAt!.difference(DateTime.now());
    if (remaining.isNegative) return 'Expiré';
    
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    
    if (days > 30) return '${(days/30).floor()} mois restants';
    if (days > 0) return '$days jours restants';
    if (hours > 0) return '$hours heures restantes';
    return '$minutes minutes restantes';
  }

  // Calcul dynamique de la valeur relative actuelle
  // Si le DU actuel n'est pas fourni, on utilise le DU à la création par défaut
  double getRelativeValue(double currentGlobalDu) {
    if (duAtCreation == null || duAtCreation == 0) return 0.0;
    // La valeur relative est la valeur quantitative divisée par le DU actuel
    return value / currentGlobalDu;
  }

  // Obtenir les caractéristiques pour l'affichage
  Map<String, String> getCharacteristics() {
    return {
      'ID Unique': uniqueId ?? 'Non défini',
      'Type': cardType ?? 'Standard',
      'Rareté': rarity ?? 'common',
      'Valeur': '${value.toStringAsFixed(0)} ẐEN',
      'Durée': getDurationRemaining(),
      'Transfers': '${transferCount ?? 0}',
      'Capacité': specialAbility ?? 'Aucune',
      'Émetteur': issuerName,
      if (wish != null && wish!.isNotEmpty) 'Vœu': wish!,
    };
  }

  // ==================== MÉTHODES SÉCURISÉES POUR PARTS SSSS ====================
  // ✅ SÉCURITÉ: Ces méthodes retournent Uint8List au lieu de String
  // pour permettre le nettoyage mémoire avec secureZeroiseBytes()
  
  /// ✅ SÉCURITÉ: Retourne P1 en Uint8List (null si absent)
  /// L'appelant DOIT appeler secureZeroiseBytes() après usage
  Uint8List? get p1Bytes {
    if (p1 == null || p1!.isEmpty) return null;
    try {
      return Uint8List.fromList(HEX.decode(p1!));
    } catch (e) {
      return null;
    }
  }
  
  /// ✅ SÉCURITÉ: Retourne P2 en Uint8List (null si absent)
  /// L'appelant DOIT appeler secureZeroiseBytes() après usage
  Uint8List? get p2Bytes {
    if (p2 == null || p2!.isEmpty) return null;
    try {
      return Uint8List.fromList(HEX.decode(p2!));
    } catch (e) {
      return null;
    }
  }
  
  /// ✅ SÉCURITÉ: Retourne P3 en Uint8List (null si absent)
  /// L'appelant DOIT appeler secureZeroiseBytes() après usage
  Uint8List? get p3Bytes {
    if (p3 == null || p3!.isEmpty) return null;
    try {
      return Uint8List.fromList(HEX.decode(p3!));
    } catch (e) {
      return null;
    }
  }

  Bon copyWith({
    String? bonId,
    double? value,
    String? issuerName,
    String? issuerNpub,
    DateTime? createdAt,
    DateTime? expiresAt,
    BonStatus? status,
    String? p1,
    String? p2,
    String? p3,
    String? marketName,
    String? logoUrl,
    String? picture,
    String? picture64,
    String? banner,
    String? banner64,
    int? color,
    String? rarity,
    int? transferCount,
    String? issuerNostrProfile,
    String? uniqueId,
    String? cardType,
    String? specialAbility,
    Map<String, dynamic>? stats,
    double? duAtCreation,
    String? wish,
    // ✅ WAL (Write-Ahead Log)
    DateTime? transferLockTimestamp,
    String? transferLockChallenge,
    int? transferLockTtlSeconds,
  }) {
    return Bon(
      bonId: bonId ?? this.bonId,
      value: value ?? this.value,
      issuerName: issuerName ?? this.issuerName,
      issuerNpub: issuerNpub ?? this.issuerNpub,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      p3: p3 ?? this.p3,
      marketName: marketName ?? this.marketName,
      logoUrl: logoUrl ?? this.logoUrl,
      picture: picture ?? this.picture,
      picture64: picture64 ?? this.picture64,
      banner: banner ?? this.banner,
      banner64: banner64 ?? this.banner64,
      color: color ?? this.color,
      rarity: rarity ?? this.rarity,
      transferCount: transferCount ?? this.transferCount,
      issuerNostrProfile: issuerNostrProfile ?? this.issuerNostrProfile,
      uniqueId: uniqueId ?? this.uniqueId,
      cardType: cardType ?? this.cardType,
      specialAbility: specialAbility ?? this.specialAbility,
      stats: stats ?? this.stats,
      duAtCreation: duAtCreation ?? this.duAtCreation,
      wish: wish ?? this.wish,
      // ✅ WAL
      transferLockTimestamp: transferLockTimestamp ?? this.transferLockTimestamp,
      transferLockChallenge: transferLockChallenge ?? this.transferLockChallenge,
      transferLockTtlSeconds: transferLockTtlSeconds ?? this.transferLockTtlSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bonId': bonId,
      'value': value,
      'issuerName': issuerName,
      'issuerNpub': issuerNpub,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'status': status.name,
      'p1': p1,
      'p2': p2,
      'p3': p3,
      'marketName': marketName,
      'logoUrl': logoUrl,
      'picture': picture,
      'picture64': picture64,
      'banner': banner,
      'banner64': banner64,
      'color': color,
      'rarity': rarity,
      'transferCount': transferCount,
      'issuerNostrProfile': issuerNostrProfile,
      'duAtCreation': duAtCreation,
      'wish': wish,
      // uniqueId, cardType, specialAbility, stats exclus du JSON (générés à la volée)
      // mais on les garde pour compatibilité si présents
      'uniqueId': uniqueId,
      'cardType': cardType,
      'specialAbility': specialAbility,
      'stats': stats,
      // WAL (Write-Ahead Log)
      'transferLockTimestamp': transferLockTimestamp?.toIso8601String(),
      'transferLockChallenge': transferLockChallenge,
      'transferLockTtlSeconds': transferLockTtlSeconds,
    };
  }

  factory Bon.fromJson(Map<String, dynamic> json) {
    return Bon(
      bonId: json['bonId'],
      value: (json['value'] as num).toDouble(),
      issuerName: json['issuerName'],
      issuerNpub: json['issuerNpub'],
      createdAt: DateTime.parse(json['createdAt']),
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
      status: BonStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => throw Exception("Statut de bon inconnu"),
      ),
      p1: json['p1'],
      p2: json['p2'],
      p3: json['p3'],
      marketName: json['marketName'],
      logoUrl: json['logoUrl'],
      picture: json['picture'],
      picture64: json['picture64'],
      banner: json['banner'],
      banner64: json['banner64'],
      color: json['color'],
      rarity: json['rarity'] ?? 'common',
      transferCount: json['transferCount'] ?? 0,
      issuerNostrProfile: json['issuerNostrProfile'],
      duAtCreation: json['duAtCreation']?.toDouble(),
      wish: json['wish'],
      uniqueId: json['uniqueId'],
      cardType: json['cardType'],
      specialAbility: json['specialAbility'],
      stats: json['stats'] != null
          ? Map<String, dynamic>.from(json['stats'])
          : null,
      // WAL (Write-Ahead Log)
      transferLockTimestamp: json['transferLockTimestamp'] != null
          ? DateTime.parse(json['transferLockTimestamp'])
          : null,
      transferLockChallenge: json['transferLockChallenge'],
      transferLockTtlSeconds: json['transferLockTtlSeconds'],
    );
  }

}
