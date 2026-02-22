# TrocZen — Application de Bons ẐEN

Application Flutter pour la création, le transfert et l'encaissement de bons de valeur locaux (ẐEN) en mode 100% offline.

## Caractéristiques

- **Offline-first** : Fonctionne sans Internet après la synchronisation matinale.
- **Cryptographie de pointe** : SSSS polynomial (2-sur-3), AES-GCM, Schnorr secp256k1 (via `bip340`), Scrypt, Nettoyage RAM (`secureZeroiseBytes`).
- **Handshake atomique** : Double scan (QR Offre → QR ACK) avec challenge aléatoire et signature empêchant la double dépense.
- **QR codes binaires optimisés** : Format compact v1 (177 octets) et **v2 offline-complet (240 octets)**.
- **Cartes visuelles** : Design type cartes à collectionner pour l'affichage des bons.
- **Révélation de Circuit** : Les bons retournés à l'émetteur publient une preuve économique chiffrée (Kind 30304) au lieu d'une simple destruction.
- **Décentralisé** : Synchronisation via protocole Nostr (kinds 0, 1, 3, 5, 30303, 30304, 30500+).
- **NFC** : Transfert de bons par approche des appareils (⚠️ à développer...)

## Prérequis

- Flutter SDK 3.0+ / Dart SDK 3.0+
- Android 5.0+ ou iOS 12+

## Installation

```bash
git clone https://github.com/papiche/troczen.git
cd troczen
flutter pub get
flutter run
```

## Build production

```bash
# Android — APK splitté par ABI (recommandé)
flutter build apk --split-per-abi --release
# → build/app/outputs/flutter-apk/

# iOS
flutter build ios --release
# → archiver via Xcode
```

## Architecture

```
lib/
├── main.dart
├── models/         user, bon, market, nostr_profile, onboarding_state
├── services/       crypto, qr, storage, nostr, api, image_upload,
│                   audit_trail, burn, nfc, feedback
├── screens/        main_shell, views/ (4 onglets), onboarding/ (5 étapes),
│                   wallet, create_bon, offer, scan, ack, market, dashboard…
└── widgets/        panini_card, cached_profile_image, bon_reception_confirm_sheet
```

Voir [ARCHITECTURE.md](ARCHITECTURE.md) pour le détail complet des flux, formats QR, protocole Nostr et analyse des composants UI.

## Sécurité

La clé privée de chaque bon (`nsec_bon`) est divisée en 3 parts (SSSS seuil 2) :

- **P1 (Ancre)** : chez l'émetteur, permet la révocation
- **P2 (Voyageur)** : circule de main en main, représente la valeur
- **P3 (Témoin)** : publiée chiffrée sur Nostr, permet la validation offline

La reconstruction de `nsec_bon` s'effectue uniquement en RAM le temps d'une signature, puis est effacée.

Voir [CHANGELOG_SECURITE.md](CHANGELOG_SECURITE.md) pour le détail des corrections (score sécurité : 98%).

## Utilisation rapide

### Premier lancement
L'onboarding en 5 étapes guide la configuration : seed de marché, relais Nostr, synchronisation P3, profil, récapitulatif. Voir [ONBOARDING_GUIDE.md](troczen/ONBOARDING_GUIDE.md).

### Donner un bon
1. Sélectionner un bon dans le wallet → "Donner"
2. L'écran se divise en deux (Mode Miroir) : le QR code s'affiche en haut, la caméra s'active en bas.
3. Mettez votre téléphone face à celui du receveur. Le transfert se fait automatiquement.

### Recevoir un bon
1. Cliquer sur "Recevoir" (Scanner)
2. L'écran se divise en deux (Mode Miroir). Scannez le QR du donneur avec la moitié basse.
3. Le QR de confirmation s'affiche automatiquement en haut. Laissez les téléphones face à face jusqu'au succès.

## Tests

```bash
# Tests unitaires crypto (15 tests)
flutter test test/crypto_service_test.dart

# Tests d'intégration - flux critiques (16 tests)
flutter test test/integration_test.dart

# Tous les tests (68 tests)
flutter test
```

**Couverture** : création de bon, transfert atomique, synchronisation P3, sécurité.

## Configuration avancée

La clé de marché (`seed_market`) est distribuée une seule fois hors ligne via QR code imprimé ou page web locale. Elle permet de dériver quotidiennement les clés de déchiffrement des P3 sans synchronisation supplémentaire.

```
K_day = HMAC-SHA256(seed_market, "daily-key-" || YYYY-MM-DD)
```

## Documentation

| Fichier | Contenu |
|---------|---------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Cryptographie, flux de données, formats QR, composants UI |
| [007.md](007.md) | Whitepaper formel : modèle de sécurité, Tamarin/ProVerif |
| [docs/technical_whitepaper.md](docs/technical_whitepaper.md) | Livre blanc pédagogique : jeu de post-it, DU Nostr P2P/ẐEN/Euro |
| [docs/DU_NOSTR_P2P_FLOW.md](docs/DU_NOSTR_P2P_FLOW.md) | Flux d'émission du DU via Nostr P2P (TRM adaptée) |
| [docs/TROCZEN_BOX_GUIDE.md](docs/TROCZEN_BOX_GUIDE.md) | Guide d'installation de la TrocZen Box (Raspberry Pi Solaire) |
| [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) | État du projet, métriques, roadmap, commandes |
| [CHANGELOG_SECURITE.md](CHANGELOG_SECURITE.md) | Corrections sécurité (3 vagues, fév. 2026) |
| [GUIDE_TESTS.md](GUIDE_TESTS.md) | Stratégie de tests, scénarios terrain |
| [DASHBOARD_MARCHAND_DOC.md](DASHBOARD_MARCHAND_DOC.md) | Analytics économiques P3, formules, dashboard |
| [NOUVELLES_FEATURES.md](NOUVELLES_FEATURES.md) | NFC, ACK, échanges atomiques, gamification |
| [troczen/ONBOARDING_GUIDE.md](troczen/ONBOARDING_GUIDE.md) | Parcours d'onboarding 5 étapes |
| [NAVIGATION_V4.md](NAVIGATION_V4.md) | MainShell, 4 vues, migration |
| [CHANGELOG_V1008.md](CHANGELOG_V1008.md) | v1.008 : avatars, IPFS, sync P3 réelle |
| [api/README.md](api/README.md) | API Flask : endpoints, déploiement |
| [api/IPFS_CONFIG.md](api/IPFS_CONFIG.md) | Configuration IPFS |
| [FILE_INDEX.md](FILE_INDEX.md) | Index complet + trace des fichiers supprimés |

## API Backend

```bash
cd api
pip install -r requirements.txt
python api_backend.py
# → http://localhost:5000
```

## Roadmap

**v4.0** : multi-marchés, PWA, DU Nostr P2P (création monétaire hyper-relativiste basée sur le graphe social), point de fork multi applicatif.

## Contribution

```bash
git checkout -b feature/amelioration
git commit -am 'Description'
git push origin feature/amelioration
# → Pull Request
```

## Liens

- Issues : https://github.com/papiche/troczen/issues
- Protocole Nostr : https://github.com/nostr-protocol/nostr
- Monnaie Libre Ğ1 : https://monnaie-libre.fr

## Licence

AGPL-3.0
