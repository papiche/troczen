import '../config/app_config.dart';

/// Modèle pour gérer l'état du parcours d'onboarding
class OnboardingState {
  // Étape 1: Seed de marché
  String? seedMarket;
  String? seedMode; // 'scanned', 'generated', 'mode000'
  
  // Étape 2: Configuration avancée
  String relayUrl;
  String apiUrl;
  String ipfsGateway;
  
  // Étape 3: Synchronisation
  int p3Count;
  bool syncCompleted;
  
  // Étape 4: Profil utilisateur
  String? displayName;
  String? about;
  String? pictureUrl;
  List<String> activityTags;
  String? g1PublicKey;
  
  // Étape 5: Résumé
  String? marketName;
  
  OnboardingState({
    this.seedMarket,
    this.seedMode,
    this.relayUrl = AppConfig.defaultRelayUrl,
    this.apiUrl = AppConfig.defaultApiUrl,
    this.ipfsGateway = 'https://ipfs.copylaradio.com',
    this.p3Count = 0,
    this.syncCompleted = false,
    this.displayName,
    this.about,
    this.pictureUrl,
    this.activityTags = const [],
    this.g1PublicKey,
    this.marketName = 'Marché Local',
  });
  
  OnboardingState copyWith({
    String? seedMarket,
    String? seedMode,
    String? relayUrl,
    String? apiUrl,
    String? ipfsGateway,
    int? p3Count,
    bool? syncCompleted,
    String? displayName,
    String? about,
    String? pictureUrl,
    List<String>? activityTags,
    String? g1PublicKey,
    String? marketName,
  }) {
    return OnboardingState(
      seedMarket: seedMarket ?? this.seedMarket,
      seedMode: seedMode ?? this.seedMode,
      relayUrl: relayUrl ?? this.relayUrl,
      apiUrl: apiUrl ?? this.apiUrl,
      ipfsGateway: ipfsGateway ?? this.ipfsGateway,
      p3Count: p3Count ?? this.p3Count,
      syncCompleted: syncCompleted ?? this.syncCompleted,
      displayName: displayName ?? this.displayName,
      about: about ?? this.about,
      pictureUrl: pictureUrl ?? this.pictureUrl,
      activityTags: activityTags ?? this.activityTags,
      g1PublicKey: g1PublicKey ?? this.g1PublicKey,
      marketName: marketName ?? this.marketName,
    );
  }
  
  /// Vérifie si l'étape 1 est complète
  bool get isStep1Complete => seedMarket != null && seedMarket!.isNotEmpty;
  
  /// Vérifie si l'étape 2 est complète (toujours vrai car optionnelle)
  bool get isStep2Complete => true;
  
  /// Vérifie si l'étape 3 est complète
  bool get isStep3Complete => syncCompleted;
  
  /// Vérifie si l'étape 4 est complète
  bool get isStep4Complete => displayName != null && displayName!.isNotEmpty;
}
