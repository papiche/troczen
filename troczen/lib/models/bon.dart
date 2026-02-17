import 'package:flutter/foundation.dart';

enum BonStatus { 
  issued,    // Créé
  pending,   // En attente de confirmation
  active,    // Actif dans le wallet
  spent,     // Dépensé
  expired,   // Expiré
  burned     // Détruit
}

class Bon {
  final String bonId;           // npub_bon (clé publique du bon en hex)
  // ✅ SÉCURITÉ: bonNsec supprimé - reconstruction éphémère uniquement
  // final String bonNsec;      // ❌ NE PLUS STOCKER - voir crypto_service.shamirCombine()
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
  final int? color;             // Couleur dominante (ARGB)
  final String? rarity;         // 'common', 'uncommon', 'rare', 'legendary'
  final int? transferCount;     // Nombre de transferts effectués
  final String? issuerNostrProfile; // URL profil Nostr du commerçant

  Bon({
    required this.bonId,
    // bonNsec retiré
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
    this.color,
    this.rarity = 'common',
    this.transferCount = 0,
    this.issuerNostrProfile,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isValid => status == BonStatus.active && !isExpired;
  bool get isRare => rarity != null && rarity != 'common';
  
  // Probabilités de rareté (à utiliser lors de la création)
  static String generateRarity() {
    final random = DateTime.now().millisecondsSinceEpoch % 100;
    if (random < 1) return 'legendary';  // 1%
    if (random < 6) return 'rare';       // 5%
    if (random < 21) return 'uncommon';  // 15%
    return 'common';                     // 79%
  }

  Bon copyWith({
    String? bonId,
    // bonNsec retiré
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
    int? color,
    String? rarity,
    int? transferCount,
    String? issuerNostrProfile,
  }) {
    return Bon(
      bonId: bonId ?? this.bonId,
      // bonNsec retiré
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
      color: color ?? this.color,
      rarity: rarity ?? this.rarity,
      transferCount: transferCount ?? this.transferCount,
      issuerNostrProfile: issuerNostrProfile ?? this.issuerNostrProfile,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bonId': bonId,
      // 'bonNsec' retiré pour ne jamais stocker sk_B
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
      'color': color,
      'rarity': rarity,
      'transferCount': transferCount,
      'issuerNostrProfile': issuerNostrProfile,
    };
  }

  factory Bon.fromJson(Map<String, dynamic> json) {
    return Bon(
      bonId: json['bonId'],
      // bonNsec retiré
      value: json['value'].toDouble(),
      issuerName: json['issuerName'],
      issuerNpub: json['issuerNpub'],
      createdAt: DateTime.parse(json['createdAt']),
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
      status: BonStatus.values.firstWhere((e) => e.name == json['status']),
      p1: json['p1'],
      p2: json['p2'],
      p3: json['p3'],
      marketName: json['marketName'],
      logoUrl: json['logoUrl'],
      color: json['color'],
      rarity: json['rarity'] ?? 'common',
      transferCount: json['transferCount'] ?? 0,
      issuerNostrProfile: json['issuerNostrProfile'],
    );
  }

}
