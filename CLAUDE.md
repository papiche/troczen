# CLAUDE.md — TrocZen

Application Flutter offline-first pour créer et échanger des bons ẐEN hors-ligne.
Implémente un système de monnaie locale basé sur NOSTR + cryptographie SSSS.
Author: Fred (support@qo-op.com). License: AGPL-3.0. Version: 3.6.1.

## Concept

- **Offline-first** : Fonctionne sans Internet après synchronisation matinale
- **Atomique** : Double scan (QR Offre → QR ACK) pour éviter la double dépense
- **Décentralisé** : Pas de serveur central — protocole NOSTR kind 30303/30304/30305
- **Sécurisé** : SSSS polynomial (2-sur-3), AES-GCM, secp256k1 (Schnorr BIP-340), Scrypt

## Architecture en couches

```
troczen/
└── lib/
    ├── main.dart           ← Init (SecureStorage, SQLite, Provider)
    ├── models/             ← User, Bon, Market, QRPayloadV2, OnboardingState
    ├── services/           ← Logique métier (crypto, qr, nostr, storage, api…)
    ├── screens/            ← Écrans UI (wallet, scan, créer bon, profil…)
    ├── widgets/            ← Composants réutilisables
    ├── providers/          ← State management (Provider)
    └── utils/              ← Fonctions utilitaires
```

## Cryptographie SSSS (Shamir Secret Sharing 2-sur-3)

La clé privée de chaque bon (`nsec_bon`) est divisée en 3 parts, seuil 2 :

```
nsec_bon → SSSS(2,3) → [P1, P2, P3]
Reconstruction : P1+P2 | P2+P3 | P1+P3
```

| Part | Nom      | Détenteur        | Stockage          |
|------|----------|------------------|-------------------|
| P1   | Ancre    | Émetteur         | SecureStorage     |
| P2   | Voyageur | Porteur courant  | QR code / Wallet  |
| P3   | Témoin   | Réseau/pairs     | Cache local       |

**Implémentation polynomiale (mod 257) :**
```
f(x) = a₀ + a₁·x  (mod 257)
Reconstruction : interpolation de Lagrange avec f(0) = a₀
```

**Chiffrement des parts** : AES-GCM 256 bits, clé dérivée via Scrypt.

## Format QR binaire v2

Format compact optimisé pour QR codes (240 octets maximum, version 2) :
- Défini dans `lib/models/qr_payload_v2.dart`
- Contient : montant, npub_bon (P2 encodée), signature, timestamp
- Images compressées WebP Base64 pour les Nostr media

## Écrans principaux (`lib/screens/`)

| Fichier | Rôle |
|---------|------|
| `main_shell.dart` | Shell principal (navigation) |
| `create_bon_screen.dart` | Créer un bon ẐEN |
| `bon_journey_screen.dart` | Historique / cycle de vie d'un bon |
| `mirror_offer_screen.dart` | QR Offre (émetteur) |
| `mirror_receive_screen.dart` | QR ACK (receveur) |
| `alliance_qr_screen.dart` | Génération QR alliance |
| `alliance_scanner_screen.dart` | Scan QR alliance |
| `user_profile_screen.dart` | Profil utilisateur |
| `public_profile_screen.dart` | Profil public (via npub) |
| `skill_swap_screen.dart` | Échange de compétences |
| `trust_web_screen.dart` | Web of trust |
| `settings_screen.dart` | Paramètres |

## Services clés (`lib/services/`)

| Fichier | Rôle |
|---------|------|
| `crypto_service.dart` | SSSS, AES-GCM, secp256k1, Scrypt |
| `qr_service.dart` | Encode/décode QR binaire v2 |
| `nostr_service.dart` | Publication/réception événements NOSTR |
| `nostr_connection_service.dart` | Connexion WebSocket relay |
| `nostr_market_service.dart` | Marchés et offres (kind 30303) |
| `storage_service.dart` | SQLite + SecureStorage |
| `cache_database_service.dart` | Cache local bons/profils |
| `api_service.dart` | Appels UPassport (54321) |
| `burn_service.dart` | Destruction de bons |
| `audit_trail_service.dart` | Journal d'audit |
| `image_compression_service.dart` | Compression WebP |
| `feedback_service.dart` | Retours utilisateur |

## Events NOSTR utilisés

| Kind  | Contenu |
|-------|---------|
| 0     | Profil utilisateur (metadata) |
| 1     | Note publique |
| 3     | Liste de contacts |
| 5     | Suppression d'événement |
| 7     | Réaction (like ẐEN) |
| 30303 | Offre de bon ẐEN (parameterized replaceable) |
| 30304 | Acceptation de bon (ACK) |
| 30305 | État du bon (lifecycle) |
| 30500+ | Données coopératives étendues |

## Commandes

```bash
cd TrocZen/troczen
flutter pub get                              # Installer les dépendances
flutter run                                  # Lancer en développement
flutter test                                 # Tous les tests (68 total)
flutter test test/crypto_service_test.dart   # Test crypto unitaire
flutter build apk --split-per-abi --release  # Build Android release
./build_apk.sh --push                        # Build + commit + push
```

## Dépendances clés

```yaml
# Crypto
pointycastle, bip39, pinenacl, bip340  # Schnorr/BIP-340 (éprouvé)
secp256k1 (via bip340)

# NOSTR
nostr_core_dart, web_socket_channel

# QR & NFC
qr_flutter, mobile_scanner, nfc_manager

# Storage
flutter_secure_storage, sqflite

# State Management
provider (pas Bloc/Cubit contrairement à Ẑelkova)

# UI
fl_chart, audioplayers, cached_network_image

# Utils
share_plus, graphview, rxdart, archive
```

## Modes d'application

Définis dans `lib/models/app_mode.dart` :
- **ORIGIN** : 1 Zen = 0.1 G1 (développement/test)
- **ẐEN** : 1 ẐEN = 1 EUR (production coopérative)

## Notes importantes

- Provider (pas BLoC/Cubit) pour la gestion d'état — différent de Ẑelkova
- NFC support disponible via `nfc_manager` (voir `nfc_manager: ^4.1.1`)
- `check_ssss.sh` à la racine UPassport : outil de vérification SSSS
- La sécurité cryptographique a été auditée (score: 98%)
