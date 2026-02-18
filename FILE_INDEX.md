# Index des Documents — TrocZen

## Documents principaux

| Fichier | Contenu |
|---------|---------|
| [README.md](README.md) | Point d'entrée : installation, architecture, utilisation |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Architecture technique détaillée, flux de données, formats |
| [007.md](007.md) | Whitepaper formel : modèle cryptographique, Tamarin/ProVerif, annexe comparative |
| [docs/technical_whitepaper.md](docs/technical_whitepaper.md) | Livre blanc pédagogique : jeu de post-it, analogies Ğ1/ẐEN/Euro |

## Projet & état d'avancement

| Fichier | Contenu |
|---------|---------|
| [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) | Résumé exécutif, état fonctionnel, roadmap, commandes essentielles |
| [CHANGELOG_SECURITE.md](CHANGELOG_SECURITE.md) | 3 vagues de corrections sécurité (16–18 fév 2026) |
| [GUIDE_TESTS.md](GUIDE_TESTS.md) | Stratégie de test, tests unitaires, intégration, terrain |

## Fonctionnalités spécifiques

| Fichier | Contenu |
|---------|---------|
| [DASHBOARD_MARCHAND_DOC.md](DASHBOARD_MARCHAND_DOC.md) | Analytics économiques P3, formules, dashboard |
| [NOUVELLES_FEATURES.md](NOUVELLES_FEATURES.md) | NFC, ACK, échanges atomiques, gamification |

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
| [CHANGELOG_V1008.md](CHANGELOG_V1008.md) | v1.008 : avatars, upload IPFS, sync P3 réelle |

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
        ├── services/
        ├── screens/
        └── widgets/
```

## Documents supprimés (archivés dans ce commit)

Ces fichiers ont été fusionnés pour éviter la redondance :

- `SYNTHESE_FINALE.md` → [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)
- `IMPLEMENTATION_FINALE.md` → [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)
- `AUDIT_SECURITE_FINAL.md` → [CHANGELOG_SECURITE.md](CHANGELOG_SECURITE.md)
- `CORRECTIONS_SECURITE.md` → [CHANGELOG_SECURITE.md](CHANGELOG_SECURITE.md)
- `CORRECTIONS_APPLIQUEES.md` → [CHANGELOG_SECURITE.md](CHANGELOG_SECURITE.md)
- `CORRECTIONS_BUGS_P0.md` → [CHANGELOG_SECURITE.md](CHANGELOG_SECURITE.md)
- `VERIFICATION_CONFORMITE.md` → absorbé dans [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)
- `troczen/RECAPITULATIF_FINAL.md` → [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)
- `troczen/NAVIGATION_V4_GUIDE.md` → [NAVIGATION_V4.md](NAVIGATION_V4.md)
- `troczen/MIGRATION_NAVIGATION_V4.md` → [NAVIGATION_V4.md](NAVIGATION_V4.md)
- `troczen/PARTIE_4_REFONTE_NAVIGATION_RESUME.md` → [NAVIGATION_V4.md](NAVIGATION_V4.md)
- `troczen/V1008_IMPLEMENTATION_COMPLETE.md` → [CHANGELOG_V1008.md](CHANGELOG_V1008.md)
- `troczen/V1008_AVATAR_SYNC_IMPLEMENTATION.md` → [CHANGELOG_V1008.md](CHANGELOG_V1008.md)
