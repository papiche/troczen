# Index des Documents — TrocZen

## Documents principaux

| Fichier | Contenu |
|---------|---------|
| [README.md](README.md) | Point d'entrée : installation, architecture, utilisation |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Architecture technique détaillée, flux de données, formats |
| [007.md](007.md) | Whitepaper formel : modèle cryptographique, Tamarin/ProVerif, annexe comparative |
| [docs/technical_whitepaper.md](docs/technical_whitepaper.md) | Livre blanc pédagogique : jeu de post-it, DU Nostr P2P/ẐEN/Euro |
| [docs/TROCZEN_BOX_GUIDE.md](docs/TROCZEN_BOX_GUIDE.md) | Guide d'installation de la TrocZen Box (Raspberry Pi Solaire) |
| [docs/DU_NOSTR_P2P_FLOW.md](docs/DU_NOSTR_P2P_FLOW.md) | Schéma de flux expérimental : Calcul du DU via le graphe social Nostr |
| [docs/ARTICLE_FORUM_ML.md](docs/ARTICLE_FORUM_ML.md) | Article de présentation complet pour les forums Monnaie Libre et Duniter |
| [docs/ASTROPORT_PAF_INTEGRATION.md](docs/ASTROPORT_PAF_INTEGRATION.md) | Architecture technique pour l'intégration de la PAF (Armateur/Capitaine) |

## Projet & état d'avancement

| Fichier | Contenu |
|---------|---------|
| [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) | Résumé exécutif, état fonctionnel, roadmap, commandes essentielles |
| [CHANGELOG_SECURITE.md](CHANGELOG_SECURITE.md) | plusieurs vagues de corrections sécurité (16–20 fév 2026) |
| [GUIDE_TESTS.md](GUIDE_TESTS.md) | Stratégie de test, tests unitaires, intégration, terrain |

## Fonctionnalités spécifiques

| Fichier | Contenu |
|---------|---------|
| [DASHBOARD_MARCHAND_DOC.md](DASHBOARD_MARCHAND_DOC.md) | Analytics économiques P3, formules, dashboard |

## API & Backend

| Fichier | Contenu |
|---------|---------|
| [api/README.md](api/README.md) | API Flask : endpoints, installation, déploiement |
| [api/IPFS_CONFIG.md](api/IPFS_CONFIG.md) | Configuration IPFS, passerelle, workflow upload |

## Sous-projet Flutter (`troczen/`)

| Fichier | Contenu |
|---------|---------|
| [troczen/ONBOARDING_GUIDE.md](troczen/ONBOARDING_GUIDE.md) | Parcours d'onboarding 5 étapes |
| [NAVIGATION_V4.md](NAVIGATION_V4.md) | Refonte navigation : MainShell, 4 vues, migration |

---

## Structure des fichiers source

```
/
├── README.md
├── ARCHITECTURE.md
├── 007.md
├── PROJECT_SUMMARY.md
├── CHANGELOG_SECURITE.md
├── GUIDE_TESTS.md
├── DASHBOARD_MARCHAND_DOC.md
├── NOUVELLES_FEATURES.md
├── FILE_INDEX.md
├── ANALYSE_DOC_CODE.md
├── docs/
│   └── technical_whitepaper.md
├── api/
│   ├── README.md
│   ├── IPFS_CONFIG.md
│   ├── api_backend.py
│   ├── nostr_client.py
│   ├── requirements.txt
│   └── templates/
└── troczen/
    ├── ONBOARDING_GUIDE.md
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── models/
        │   ├── user.dart
        │   ├── bon.dart
        │   ├── market.dart
        │   ├── nostr_profile.dart      # Profil Nostr (kind 0)
        │   ├── onboarding_state.dart   # État onboarding Provider
        │   └── qr_payload_v2.dart      # Payload QR v2 (160 octets)
        ├── services/
        │   ├── crypto_service.dart
        │   ├── qr_service.dart
        │   ├── storage_service.dart
        │   ├── nostr_service.dart
        │   ├── api_service.dart
        │   ├── audit_trail_service.dart
        │   ├── burn_service.dart
        │   ├── nfc_service.dart            # ⚠️ Expérimental
        │   ├── feedback_service.dart       # Envoi feedback GitHub
        │   └── image_cache_service.dart    # Cache images profils
        ├── screens/
        │   ├── main_shell.dart
        │   ├── views/ (wallet, explore, dashboard, profile)
        │   ├── onboarding/ (5 étapes)
        │   └── ... (15+ écrans)
        └── widgets/
            ├── panini_card.dart
            ├── bon_reception_confirm_sheet.dart
            └── cached_profile_image.dart
    └── test/
        ├── crypto_service_test.dart      # 15 tests unitaires
        ├── qr_service_test.dart          # 13 tests unitaires
        ├── storage_service_test.dart     # 15 tests unitaires
        ├── nostr_service_test.dart       # 6 tests unitaires
        └── integration_test.dart         # 16 tests d'intégration (flux critiques)
```
