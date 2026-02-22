/// Modèle pour le mode d'utilisation de l'application
///
/// Implémente le principe de Progressive Disclosure pour adapter
/// l'interface selon le profil utilisateur et réduire la charge cognitive
enum AppMode {
  /// 🚶‍♂️ Mode Flâneur (Client / Acheteur)
  /// C'est le mode par défaut. M. et Mme Tout-le-monde qui viennent au marché.
  /// - Objectif : Recevoir, stocker et dépenser des bons ẐEN. Zéro friction.
  /// - Navigation réduite (2 onglets) : Wallet, Profil
  /// - Ce qui est caché : Dashboard économique, création de bons avancée, attestations
  flaneur(0, '🚶‍♂️ Flâneur', 'Client / Acheteur'),
  
  /// 🧑‍🌾 Mode Artisan (Commerçant / Producteur)
  /// L'acteur économique local qui vend ses produits et fidélise.
  /// - Objectif : Émettre des bons, gérer sa caisse, voir si la journée a été bonne.
  /// - Navigation standard (4 onglets) : Wallet, Explorer, Dashboard Simple, Profil
  /// - Ce qui est caché : Les mathématiques de la TRM (C², alpha), le WoTx2 complexe
  artisan(1, '🧑‍🌾 Artisan', 'Commerçant / Producteur'),
  
  /// 🧙‍♂️ Mode Alchimiste (Tisseur / Expert Économique)
  /// Les passionnés, les fondateurs du marché, les capitaines de la TrocZen Box.
  /// - Objectif : Analyser les boucles de valeur, certifier les pairs, piloter la santé de la monnaie.
  /// - Navigation complète (4 onglets) : Wallet, Explorer, Dashboard Avancé, Profil
  /// - Tout est visible : C², Alpha, WoTx2, exports IPFS/Nostr
  alchimiste(2, '🧙‍♂️ Alchimiste', 'Tisseur / Expert');

  final int value;
  final String label;
  final String description;

  const AppMode(this.value, this.label, this.description);

  /// Récupère le mode depuis son index
  static AppMode fromIndex(int index) {
    return AppMode.values.firstWhere(
      (mode) => mode.value == index,
      orElse: () => AppMode.flaneur,
    );
  }

  /// Retourne vrai si c'est le mode Flâneur
  bool get isFlaneur => this == AppMode.flaneur;

  /// Retourne vrai si c'est le mode Artisan
  bool get isArtisan => this == AppMode.artisan;

  /// Retourne vrai si c'est le mode Alchimiste
  bool get isAlchimiste => this == AppMode.alchimiste;

  /// Retourne vrai si le dashboard simple doit être affiché (Artisan)
  bool get showSimpleDashboard => this == AppMode.artisan;

  /// Retourne vrai si le dashboard avancé doit être affiché (Alchimiste)
  bool get showAdvancedDashboard => this == AppMode.alchimiste;

  /// Retourne vrai si l'utilisateur peut créer des bons (Artisan ou Alchimiste)
  bool get canCreateBons => this == AppMode.artisan || this == AppMode.alchimiste;

  /// Retourne vrai si l'utilisateur peut voir les métriques économiques avancées
  bool get canSeeAdvancedMetrics => this == AppMode.alchimiste;

  /// Retourne le nombre d'onglets à afficher dans la navigation
  int get navigationTabsCount {
    switch (this) {
      case AppMode.flaneur:
        return 2; // Wallet, Profil
      case AppMode.artisan:
      case AppMode.alchimiste:
        return 4; // Wallet, Explorer, Dashboard, Profil
    }
  }
}
