# Changelog

## [Unreleased]

### Added
- **Synchronisation multi-appareils de la jauge de DU** : Le calcul du DU disponible est désormais dérivé des événements Nostr (kind 30305) publiés sur le réseau, garantissant que tous les appareils d'un même utilisateur partagent le même solde de création de ẐEN.
- **Nouveau kind Nostr 30305** : Utilisé pour publier chaque incrément journalier de DU.
- **Cache local pour les incréments DU** : Ajout d'une table `du_increments` dans `CacheDatabaseService` pour permettre le calcul du solde en mode hors-ligne.

### Changed
- **Calcul du DU disponible** : Remplacement de la lecture locale `_storageService.getAvailableDuToEmit()` par un appel asynchrone à `_nostrService.computeAvailableDu()` avec un cache court de 5 minutes dans `CreateBonScreen`.
- **Publication des incréments DU** : Intégration de la publication sur Nostr après chaque calcul de DU dans `DuCalculationService`.
