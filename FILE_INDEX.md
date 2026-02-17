# TrocZen - Index des Fichiers

## 📁 Structure Complète du Projet

```
troczen/                                    # Racine du projet (181 KB)
│
├── 📄 Documentation (31 KB)
│   ├── README.md                           # Documentation principale (7.0 KB)
│   ├── PROJECT_SUMMARY.md                  # Synthèse du projet (9.0 KB)
│   ├── ARCHITECTURE.md                     # Architecture technique (9.5 KB)
│   ├── QUICKSTART.md                       # Démarrage rapide (3.5 KB)
│   └── FILE_INDEX.md                       # Ce fichier
│
├── 🛠️ Configuration (1.8 KB)
│   ├── pubspec.yaml                        # Dépendances Flutter (1.0 KB)
│   └── build.sh                            # Script de build (3.0 KB)
│
├── 📱 Android (18 KB)
│   └── android/app/src/main/
│       └── AndroidManifest.xml             # Permissions & config Android
│
├── 🖼️ Assets (8 KB)
│   └── assets/images/                      # Logos, icônes (vide pour l'instant)
│
└── 💻 Code Source Dart (118 KB - 2968 lignes)
    └── lib/
        ├── main.dart                       # Point d'entrée + LoginScreen (12 KB)
        │
        ├── models/ (3 fichiers - 9.5 KB)
        │   ├── user.dart                   # Modèle utilisateur
        │   ├── bon.dart                    # Modèle bon ẐEN
        │   └── market.dart                 # Modèle marché
        │
        ├── services/ (3 fichiers - 21 KB)
        │   ├── crypto_service.dart         # Cryptographie (SSSS, AES)
        │   ├── qr_service.dart             # QR binaire encode/decode
        │   └── storage_service.dart        # Stockage sécurisé
        │
        ├── screens/ (5 fichiers - 61 KB)
        │   ├── wallet_screen.dart          # Liste des bons
        │   ├── create_bon_screen.dart      # Création de bon
        │   ├── offer_screen.dart           # Affichage QR offre
        │   ├── scan_screen.dart            # Scanner QR
        │   └── market_screen.dart          # Config marché
        │
        └── widgets/ (1 fichier - 12 KB)
            └── panini_card.dart            # Carte Panini

TOTAL: 20 fichiers
       13 fichiers Dart
       ~2968 lignes de code
```

## 📋 Description Détaillée des Fichiers

### 📄 Documentation

#### README.md (Principal)
- **Contenu** : Documentation générale, installation, utilisation
- **Public** : Utilisateurs, contributeurs, nouveaux développeurs
- **Sections** : Caractéristiques, installation, architecture, usage, roadmap

#### PROJECT_SUMMARY.md (Synthèse Exécutive)
- **Contenu** : État du projet, métriques, workflow
- **Public** : Chefs de projet, managers, investisseurs
- **Sections** : État MVP, structure code, sécurité, démo, roadmap

#### ARCHITECTURE.md (Technique)
- **Contenu** : Architecture détaillée, cryptographie, protocoles
- **Public** : Développeurs avancés, auditeurs sécurité
- **Sections** : Couches, crypto, modèles, flux, Nostr, QR format

#### QUICKSTART.md (Démarrage Rapide)
- **Contenu** : Guide 5 minutes, scénarios de test
- **Public** : Nouveaux développeurs
- **Sections** : Installation, test, configuration, problèmes courants

---

### 💻 Code Source - Détails

#### 🏠 main.dart (Point d'Entrée)
```dart
Lignes: ~400
Classes:
  - TrocZenApp (MaterialApp)
  - LoginScreen (StatefulWidget)
    ├─ Dérivation clé Scrypt
    ├─ Génération identité Nostr
    └─ Navigation → WalletScreen

Dépendances:
  - services/crypto_service.dart
  - services/storage_service.dart
  - screens/wallet_screen.dart
```

---

#### 📦 Models (Modèles de Données)

**user.dart** (~90 lignes)
```dart
class User {
  - npub: String          // Clé publique Nostr
  - nsec: String          // Clé privée (sécurisée)
  - displayName: String
  - createdAt: DateTime
  + toJson() / fromJson()
}
```

**bon.dart** (~160 lignes)
```dart
enum BonStatus { issued, pending, active, spent, expired, burned }

class Bon {
  - bonId: String         // npub_bon
  - bonNsec: String       // nsec_bon divisé
  - value: double         // Valeur ẐEN
  - issuerName: String
  - status: BonStatus
  - p1, p2, p3: String?   // Parts SSSS
  - marketName: String
  - color: int?           // ARGB
  + isExpired / isValid
  + toJson() / fromJson()
}
```

**market.dart** (~70 lignes)
```dart
class Market {
  - name: String          // marche-toulouse
  - kmarket: String       // AES-256 key (hex)
  - validUntil: DateTime  // Expiration
  - relayUrl: String?     // wss://...
  + isExpired
  + toJson() / fromJson()
}
```

---

#### 🔐 Services (Logique Métier)

**crypto_service.dart** (~360 lignes)
```dart
class CryptoService {
  + derivePrivateKey(login, password)
    → Scrypt → SHA256 → nsec
  
  + generateNostrKeyPair()
    → secp256k1 keypair
  
  + shamirSplit(secret) → [P1, P2, P3]
    → SSSS 2-sur-3
  
  + shamirCombine(p1, p2, p3?) → secret
  
  + encryptP2(p2, p3) → {ciphertext, nonce}
    → K_P2 = SHA256(P3)
    → AES-GCM
  
  + decryptP2(cipher, nonce, p3) → p2
  
  + encryptP3(p3, kmarket) → {ciphertext, nonce}
    → AES-GCM
  
  + decryptP3(cipher, nonce, kmarket) → p3
}

Algorithmes:
  - Scrypt (N=4096, r=16, p=1)
  - SHA-256
  - secp256k1 (Nostr)
  - AES-GCM
  - SSSS (simplifié XOR pour MVP)
```

**qr_service.dart** (~180 lignes)
```dart
class QRService {
  + encodeOffer(...) → Uint8List (113 octets)
    ├─ bon_id (32)
    ├─ p2_cipher (48)
    ├─ nonce (12)
    ├─ challenge (16)
    ├─ timestamp (4)
    └─ ttl (1)
  
  + decodeOffer(data) → Map<String, dynamic>
  
  + encodeAck(...) → Uint8List (97 octets)
    ├─ bon_id (32)
    ├─ signature (64)
    └─ status (1)
  
  + decodeAck(data) → Map<String, dynamic>
  
  + isExpired(timestamp, ttl) → bool
  + timeRemaining(timestamp, ttl) → int
}
```

**storage_service.dart** (~200 lignes)
```dart
class StorageService {
  - _secureStorage: FlutterSecureStorage
  
  + saveUser(user) / getUser() / deleteUser()
  + saveBon(bon) / getBons() / getBonById(id)
  + deleteBon(id)
  + saveMarket(market) / getMarket() / deleteMarket()
  + saveP3ToCache(bonId, p3) / getP3Cache()
  + getP3FromCache(bonId)
  + getActiveBons() / getBonsByStatus(status)
  + clearAll()
}

Stockage:
  - user → JSON chiffré
  - bons → List<Bon> JSON
  - market → Market JSON
  - p3_cache → Map<bonId, p3>
```

---

#### 🖥️ Screens (Interface Utilisateur)

**wallet_screen.dart** (~350 lignes)
```dart
class WalletScreen extends StatefulWidget {
  UI:
  ├─ AppBar (Titre + Settings)
  ├─ Header (Bonjour + Stats)
  ├─ Bons actifs (PaniniCard list)
  ├─ Historique (bons dépensés/expirés)
  └─ FloatingActionButtons
      ├─ Scanner
      └─ Créer bon
  
  Actions:
  - _loadBons() → refresh liste
  - _showBonOptions(bon) → Modal bottom sheet
  - _showBonDetails(bon) → Dialog
}
```

**create_bon_screen.dart** (~380 lignes)
```dart
class CreateBonScreen extends StatefulWidget {
  UI:
  ├─ Preview Carte Panini (live)
  ├─ Form
  │   ├─ Valeur (ẐEN)
  │   └─ Nom émetteur
  └─ Bouton Créer
  
  Workflow:
  1. Générer keypair bon
  2. SSSS split → P1, P2, P3
  3. Chiffrer P3 avec K_market
  4. Sauvegarder bon + P3 cache
  5. (TODO) Publier P3 sur Nostr
}
```

**offer_screen.dart** (~270 lignes)
```dart
class OfferScreen extends StatefulWidget {
  UI:
  ├─ Instructions
  ├─ QR Code (280x280)
  ├─ Compte à rebours TTL (30s)
  ├─ Bouton Régénérer
  └─ Infos bon (valeur, émetteur)
  
  Workflow:
  1. Chiffrer P2 avec hash(P3)
  2. Générer QR binaire (113 octets)
  3. Timer 30s → auto-régénération
  4. (TODO) Scanner ACK confirmation
}
```

**scan_screen.dart** (~180 lignes)
```dart
class ScanScreen extends StatefulWidget {
  UI:
  ├─ Instructions (statut)
  ├─ MobileScanner (caméra)
  ├─ Overlay cadre
  └─ Boutons (Flash, Caméra)
  
  Workflow:
  1. Scanner QR binaire
  2. Décoder offre
  3. Récupérer P3 cache
  4. Déchiffrer P2
  5. Valider bon
  6. (TODO) Générer QR ACK
  7. (TODO) Confirmer transfert
}
```

**market_screen.dart** (~340 lignes)
```dart
class MarketScreen extends StatefulWidget {
  UI:
  ├─ Info compte (npub)
  ├─ État marché (K_market expirée?)
  ├─ Form
  │   ├─ Nom marché
  │   ├─ K_market (64 hex)
  │   └─ URL relais (optionnel)
  ├─ Info obtention K_market
  └─ Boutons (Sauver, Supprimer)
  
  Actions:
  - _loadMarket() / _saveMarket()
  - _deleteMarket()
}
```

---

#### 🎨 Widgets (Composants Réutilisables)

**panini_card.dart** (~240 lignes)
```dart
class PaniniCard extends StatelessWidget {
  Props:
  - bon: Bon
  - onTap: VoidCallback?
  - showActions: bool
  
  UI:
  ├─ Container (carte physique)
  │   ├─ Header (icône + valeur)
  │   ├─ Corps (logo + nom émetteur)
  │   └─ Footer (marché + date)
  
  Couleurs dynamiques:
  - Active: #FFB347 (jaune miel)
  - Pending: Gris
  - Spent: Vert
  - Expired: Orange
  - Burned: Rouge
}
```

---

### 🛠️ Configuration & Scripts

**pubspec.yaml** (~30 lignes)
```yaml
name: troczen
dependencies:
  - pointycastle: ^3.7.3     # Crypto
  - crypto: ^3.0.3           # Hashing
  - flutter_secure_storage   # Stockage
  - mobile_scanner           # QR scan
  - qr_flutter               # QR gen
  - provider                 # State mgmt
  - uuid                     # IDs
```

**build.sh** (~70 lignes)
```bash
Fonctions:
  - clean_project()
  - build_android()
  - build_ios()
  - build_all()

Usage:
  ./build.sh [android|ios|all|clean]
```

**AndroidManifest.xml** (~45 lignes)
```xml
Permissions:
  - INTERNET
  - CAMERA
  - FLASHLIGHT

Features:
  - android.hardware.camera (optional)
```

---

## 🔍 Recherche Rapide

### Par Fonctionnalité

| Fonctionnalité | Fichier(s) |
|----------------|-----------|
| **Login/Auth** | `main.dart` |
| **Crypto SSSS** | `services/crypto_service.dart` |
| **QR Binaire** | `services/qr_service.dart` |
| **Stockage** | `services/storage_service.dart` |
| **Créer Bon** | `screens/create_bon_screen.dart` |
| **Transférer** | `screens/offer_screen.dart` |
| **Recevoir** | `screens/scan_screen.dart` |
| **Config Marché** | `screens/market_screen.dart` |
| **UI Carte** | `widgets/panini_card.dart` |

### Par Type de Code

| Type | Fichiers | Lignes |
|------|----------|--------|
| **UI** | 6 screens + 1 widget | ~1800 |
| **Logic** | 3 services | ~740 |
| **Data** | 3 models | ~320 |
| **Config** | 1 pubspec + 1 manifest | ~75 |
| **Docs** | 5 markdown | N/A |

---

## 📊 Statistiques Projet

```
Total fichiers: 20
  - Code Dart: 13 fichiers (2968 lignes)
  - Documentation: 5 fichiers
  - Configuration: 2 fichiers

Taille totale: 181 KB
  - Code: 118 KB (65%)
  - Docs: 31 KB (17%)
  - Config: 32 KB (18%)

Complexité:
  - Classes: 19
  - Services: 3
  - Screens: 6
  - Widgets: 1
  - Models: 3
  - Enums: 1

Dépendances externes: ~15 packages
```

---

## ✅ Checklist Fichiers

- [x] main.dart (Entry point)
- [x] Models (3/3)
- [x] Services (3/3)
- [x] Screens (5/5)
- [x] Widgets (1/1)
- [x] Documentation (5/5)
- [x] Configuration (2/2)
- [ ] Tests (0 - à implémenter)
- [ ] Assets images (0 - optionnel)
- [ ] CI/CD (0 - à implémenter)

---

## 🎯 Prochains Fichiers à Créer

1. **lib/services/nostr_service.dart** (~300 lignes)
   - Publication kind 30303
   - Synchronisation P3
   - WebSocket relay

2. **test/** (nouveau dossier)
   - crypto_service_test.dart
   - qr_service_test.dart
   - storage_service_test.dart

3. **lib/screens/ack_screen.dart** (~150 lignes)
   - Affichage QR ACK
   - Validation handshake

4. **.github/workflows/ci.yml**
   - CI/CD automatique
   - Tests + build

---

**Dernière mise à jour** : 16 février 2025  
**Version** : 1.0.0-alpha
