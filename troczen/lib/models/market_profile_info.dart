/// ✅ v2.0.1: Modèle pour les informations de profil d'un marché
/// Utilisé pour afficher la carte d'invitation lors du scan QR
class MarketProfileInfo {
  final String? about;
  final String? picture;
  final String? banner;
  final String? picture64;
  final String? banner64;
  final int? merchantCount;

  const MarketProfileInfo({
    this.about,
    this.picture,
    this.banner,
    this.picture64,
    this.banner64,
    this.merchantCount,
  });

  factory MarketProfileInfo.fromJson(Map<String, dynamic> json) {
    return MarketProfileInfo(
      about: json['about'] as String?,
      picture: json['picture'] as String?,
      banner: json['banner'] as String?,
      picture64: json['picture64'] as String?,
      banner64: json['banner64'] as String?,
      merchantCount: json['merchantCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'about': about,
      'picture': picture,
      'banner': banner,
      'picture64': picture64,
      'banner64': banner64,
      'merchantCount': merchantCount,
    };
  }
}
