class Market {
  final String name;
  final String kmarket;        // Clé symétrique du marché (hex)
  final DateTime validUntil;   // Date d'expiration de la clé
  final String? relayUrl;      // URL du relais Nostr local

  Market({
    required this.name,
    required this.kmarket,
    required this.validUntil,
    this.relayUrl,
  });

  bool get isExpired => DateTime.now().isAfter(validUntil);

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'kmarket': kmarket,
      'validUntil': validUntil.toIso8601String(),
      'relayUrl': relayUrl,
    };
  }

  factory Market.fromJson(Map<String, dynamic> json) {
    return Market(
      name: json['name'],
      kmarket: json['kmarket'],
      validUntil: DateTime.parse(json['validUntil']),
      relayUrl: json['relayUrl'],
    );
  }
}
