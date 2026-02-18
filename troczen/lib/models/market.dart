class Market {
  final String name;
  final String seedMarket;     // Graine du marché (hex) - dérivée ou aléatoire
  final DateTime validUntil;   // Date d'expiration de la graine
  final String? relayUrl;      // URL du relais Nostr local

  Market({
    required this.name,
    required this.seedMarket,
    required this.validUntil,
    this.relayUrl,
  });

  bool get isExpired => DateTime.now().isAfter(validUntil);

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'seedMarket': seedMarket,
      'validUntil': validUntil.toIso8601String(),
      'relayUrl': relayUrl,
    };
  }

  factory Market.fromJson(Map<String, dynamic> json) {
    return Market(
      name: json['name'],
      seedMarket: json['seedMarket'],
      validUntil: DateTime.parse(json['validUntil']),
      relayUrl: json['relayUrl'],
    );
  }
}
