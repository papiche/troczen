/// ✅ v2.0.1: Modèle pour les informations de profil d'un marché
/// Utilisé pour afficher la carte d'invitation lors du scan QR
class MarketProfileInfo {
  final String? about;
  final String? picture;
  final String? banner;
  final int? merchantCount;

  const MarketProfileInfo({
    this.about,
    this.picture,
    this.banner,
    this.merchantCount,
  });

  factory MarketProfileInfo.fromJson(Map<String, dynamic> json) {
    return MarketProfileInfo(
      about: json['about'] as String?,
      picture: json['picture'] as String?,
      banner: json['banner'] as String?,
      merchantCount: json['merchantCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'about': about,
      'picture': picture,
      'banner': banner,
      'merchantCount': merchantCount,
    };
  }
}
