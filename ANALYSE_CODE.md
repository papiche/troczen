# Analyse du Code - TrocZen

## 📊 Vue d'ensemble

**TrocZen** est une application Flutter de monnaie locale (ẐEN) utilisant une architecture cryptographique sophistiquée basée sur le partage de secret de Shamir (SSSS), le chiffrement AES-GCM et le protocole Nostr.

**Date d'analyse** : 16 février 2026  
**Version** : 1.0.0-alpha  
**Lignes de code** : ~2500 lignes Dart  
**Fichiers analysés** : 17 fichiers principaux

---

## 🏗️ Architecture Globale

### Structure des dossiers

```
troczen/lib/
├── main.dart                          # Point d'entrée + écran de login
├── models/                            # Modèles de données (3 fichiers)
│   ├── user.dart                      # Utilisateur Nostr
│   ├── bon.dart                       # Bon ẐEN avec SSSS
│   └── market.dart                    # Configuration marché
├── services/                          # Logique métier (6 fichiers)
│   ├── crypto_service.dart            # Cryptographie SSSS + AES
│   ├── qr_service.dart                # Codage QR binaire
│   ├── storage_service.dart           # Stockage sécurisé
│   ├── nostr_service.dart             # Publication Nostr (stub)
│   ├── nfc_service.dart               # NFC (futur)
│   └── audit_trail_service.dart       # Audit (futur)
├── screens/                           # Interfaces utilisateur (7 fichiers)
│   ├── wallet_screen.dart             # Portefeuille principal
│   ├── create_bon_screen.dart         # Création de bons
│   ├── offer_screen.dart              # Affichage QR offre
│   ├── scan_screen.dart               # Scanner QR
│   ├── market_screen.dart             # Configuration marché
│   ├── ack_screen.dart                # Confirmation (stub)
│   ├── atomic_swap_screen.dart        # Swap atomique (stub)
│   └── merchant_dashboard_screen.dart # Dashboard marchand (stub)
└── widgets/
    └── panini_card.dart               # Carte de bon style Panini
```

### Pattern architectural

- **Architecture en couches** : UI → Services → Models → Storage
- **Séparation des préoccupations** : Bonne isolation des responsabilités
- **State management** : StatefulWidget (pas de Provider/Bloc)
- **Design pattern** : Repository pattern pour le storage

---

## 📦 Modèles de données

### 1. User ([`user.dart`](troczen/lib/models/user.dart))

```dart
class User {
  final String npub;           // Clé publique Nostr (hex)
  final String nsec;           // Clé privée Nostr (hex)
  final String displayName;
  final DateTime createdAt;
}
```

**✅ Points forts** :
- Modèle simple et clair
- Sérialisation JSON bien implémentée
- Compatible Nostr (secp256k1)

**⚠️ Points à améliorer** :
- Les clés sont en hex brut (pas de format bech32 standard Nostr)
- Pas de validation des clés
- Méthode de dérivation login/password non utilisée (ligne 76-80 main.dart)

### 2. Bon ([`bon.dart`](troczen/lib/models/bon.dart))

```dart
class Bon {
  final String bonId;          // npub_bon
  final String bonNsec;        // nsec_bon (reconstitué temporairement)
  final double value;
  final String issuerName;
  final String issuerNpub;
  final BonStatus status;
  final String? p1, p2, p3;    // Parts SSSS
  final String marketName;
  final String? rarity;        // 'common', 'rare', 'legendary'
  final int? transferCount;
  // ...
}
```

**✅ Points forts** :
- Enum `BonStatus` bien défini (issued, pending, active, spent, expired, burned)
- Système de rareté ludique (1% legendary, 5% rare, 15% uncommon)
- Méthodes utilitaires : `isExpired`, `isValid`, `isRare`
- Méthode `copyWith()` pour immutabilité
- Support de métadonnées (logo, couleur, profil Nostr)

**⚠️ Points à améliorer** :
- `bonNsec` stocké en clair (devrait être reconstruit à la volée)
- P3 devrait toujours être dans le cache, jamais dans le modèle
- Pas de validation de cohérence entre P1/P2/P3

### 3. Market ([`market.dart`](troczen/lib/models/market.dart))

```dart
class Market {
  final String name;
  final String kmarket;        // Clé AES-256 (hex)
  final DateTime validUntil;
  final String? relayUrl;
}
```

**✅ Points forts** :
- Simple et efficace
- Gestion d'expiration (`isExpired`)

**⚠️ Points à améliorer** :
- Pas de validation de la longueur de `kmarket` (devrait être 64 hex = 32 bytes)
- Pas de métadonnées (géolocalisation, logo du marché)

---

## 🔐 Services

### 1. CryptoService ([`crypto_service.dart`](troczen/lib/services/crypto_service.dart))

**Responsabilités** :
- Génération de paires de clés secp256k1
- SSSS (Shamir Secret Sharing Scheme)
- Chiffrement/déchiffrement AES-GCM

#### Méthodes clés

```dart
Future<Uint8List> derivePrivateKey(String login, String password)
Map<String, String> generateNostrKeyPair()
List<String> shamirSplit(String secretHex)
String shamirCombine(String p1, String p2, String? p3)
Future<Map<String, String>> encryptP2(String p2, String p3)
Future<String> decryptP2(String cipher, String nonce, String p3)
Future<Map<String, String>> encryptP3(String p3, String kmarket)
Future<String> decryptP3(String cipher, String nonce, String kmarket)
```

**✅ Points forts** :
- Utilisation de PointyCastle (bibliothèque éprouvée)
- Scrypt pour la dérivation de clé (N=4096, r=16, p=1)
- AES-GCM avec authentification (tag 128 bits)
- Nonces aléatoires de 12 octets (standard GCM)
- Séparation claire des responsabilités

**⚠️ Points critiques** :

1. **SSSS simplifié** (lignes 60-91) :
   ```dart
   // ❌ XOR basique au lieu de Shamir réel
   final p3 = Uint8List(32);
   for (int i = 0; i < 32; i++) {
     p3[i] = secretBytes[i] ^ p1[i] ^ p2[i];
   }
   ```
   - **Problème** : Ce n'est pas du vrai Shamir ! 
   - **Impact** : Nécessite les 3 parts au lieu de 2-sur-3
   - **Solution** : Utiliser un vrai package Shamir (ex: `shamir_secret_sharing`)

2. **Générateur aléatoire faible** (ligne 49) :
   ```dart
   final seeds = List<int>.generate(32, (i) => 
     DateTime.now().millisecondsSinceEpoch % 256
   );
   ```
   - **Problème** : Seed basé sur le temps, tous les octets identiques
   - **Impact** : Sécurité compromise
   - **Solution** : Utiliser `Random.secure()` ou package `crypto`

3. **Conversion clé publique incomplète** (ligne 239-241) :
   ```dart
   String _pointToHex(ECPoint point) {
     final x = point.x!.toBigInteger()!;
     return _bigIntToHex(x, 32); // ❌ Ignore y
   }
   ```
   - **Problème** : Seulement la coordonnée X (33 bytes avec préfixe manquant)
   - **Impact** : Non compatible format Nostr standard
   - **Solution** : Utiliser le format compressé (02/03 + x)

### 2. QRService ([`qr_service.dart`](troczen/lib/services/qr_service.dart))

**Format binaire compact** : 113 octets (offre) / 97 octets (ACK)

```
Offre (113 octets):
├── bon_id: 32 bytes
├── p2_cipher: 48 bytes (32 + 16 tag GCM)
├── nonce: 12 bytes
├── challenge: 16 bytes
├── timestamp: 4 bytes (uint32 big-endian)
└── ttl: 1 byte

ACK (97 octets):
├── bon_id: 32 bytes
├── signature: 64 bytes
└── status: 1 byte (0x01 = RECEIVED)
```

**✅ Points forts** :
- Format binaire optimal (vs JSON base64)
- Big-endian pour portabilité
- Méthodes `isExpired()` et `timeRemaining()`
- Gestion d'erreurs (vérification taille)

**⚠️ Points à améliorer** :
- Pas de checksum/CRC pour détecter corruption
- Signature ACK non implémentée (challenge non signé)

### 3. StorageService ([`storage_service.dart`](troczen/lib/services/storage_service.dart))

**Backend** : `FlutterSecureStorage` avec chiffrement matériel (Keystore Android / Keychain iOS)

**Structure de stockage** :
```
SecureStorage:
├── 'user' → User JSON
├── 'bons' → List<Bon> JSON
├── 'market' → Market JSON
└── 'p3_cache' → Map<bonId, p3_hex> JSON
```

**✅ Points forts** :
- Utilisation de FlutterSecureStorage (chiffrement hardware-backed)
- API claire et cohérente
- Cache P3 séparé (bonne pratique)
- Méthodes utilitaires : `getActiveBons()`, `getBonsByStatus()`

**⚠️ Points à améliorer** :
- Pas de compression (JSON peut être volumineux)
- Pas de migration de schéma (si évolution modèle)
- `clearAll()` trop brutal (pas de backup)

### 4. NostrService (stub, non implémenté)

**État** : Fichier présent mais vide, à implémenter

**TODO** :
- Publication kind 30303 (P3 chiffrées)
- Abonnement aux events du marché
- Synchronisation automatique
- Gestion de plusieurs relais

---

## 🎨 Écrans (UI)

### 1. LoginScreen ([`main.dart`](troczen/lib/main.dart:32-329))

**Flow** :
1. Vérifier si utilisateur existe → Rediriger vers wallet
2. Sinon, afficher formulaire de création compte

**✅ Points forts** :
- UI propre et professionnelle
- Validation des champs (password ≥ 8 caractères)
- Message d'avertissement sur la perte des identifiants
- Gestion du loading state

**⚠️ Points à améliorer** :
- Pas de mode "se connecter" (seulement création)
- Ligne 85 : Génère une **nouvelle** paire au lieu de dériver depuis password
  ```dart
  // ❌ Ignore la dérivation Scrypt !
  final keys = _cryptoService.generateNostrKeyPair();
  ```
- Pas de confirmation de mot de passe
- Pas de force du mot de passe (caractères spéciaux, etc.)

### 2. WalletScreen ([`wallet_screen.dart`](troczen/lib/screens/wallet_screen.dart))

**Fonctionnalités** :
- Liste des bons actifs + historique
- RefreshIndicator pour rafraîchir
- FAB pour scanner / créer bon
- BottomSheet avec options (donner, détails, burn)

**✅ Points forts** :
- Utilisation de `CustomScrollView` + `Sliver` (performance)
- Séparation bons actifs / historique
- UI vide élégante (aucun bon)
- Gestion du loading state

**⚠️ Points à améliorer** :
- Pas de tri (date, valeur, rareté)
- Pas de recherche/filtre
- Pas de pagination (si > 100 bons)

### 3. CreateBonScreen ([`create_bon_screen.dart`](troczen/lib/screens/create_bon_screen.dart))

**Flow** :
1. Vérifier que marché configuré
2. Générer paire de clés bon
3. SSSS split → P1, P2, P3
4. Chiffrer P3 avec K_market
5. Sauvegarder bon + P3 cache
6. (TODO) Publier P3 sur Nostr

**✅ Points forts** :
- Prévisualisation de la carte en temps réel
- Validation marché avant création
- Gestion erreurs complète
- Code cryptographique bien orchestré

**⚠️ Points à améliorer** :
- Ligne 90 : `rarity` non générée (non utilisé `Bon.generateRarity()`)
- Pas de sélection de couleur
- Expiration fixe à 90 jours (pas configurable)

### 4. OfferScreen ([`offer_screen.dart`](troczen/lib/screens/offer_screen.dart))

**Flow donneur** :
1. Récupérer P3 depuis cache
2. Chiffrer P2 avec SHA256(P3)
3. Générer challenge UUID
4. Encoder QR binaire 113 octets
5. Afficher avec TTL 30s
6. Attendre scan ACK (TODO)

**✅ Points forts** :
- Compte à rebours visuel (changement couleur à 10s)
- Régénération automatique à expiration
- QR binaire compact

**⚠️ Points critiques** :
- **Handshake ACK incomplet** (pas de scan retour)
- P2 **non supprimé** après transfert (double dépense possible !)
- Challenge non signé (pas de vérification ACK)

### 5. ScanScreen (non analysé en détail, mais présent)

**TODO** : Analyser l'implémentation complète

### 6. MarketScreen (non analysé en détail, mais présent)

**TODO** : Analyser l'implémentation complète

### 7. PaniniCard ([`panini_card.dart`](troczen/lib/widgets/panini_card.dart))

**Caractéristiques ludiques** :
- Système de rareté (common, uncommon, rare, legendary)
- Animation shimmer pour bons rares
- Gradient holographique rotatif
- Badge de rareté avec icône
- Compteur de passages (transferCount)

**✅ Points forts** :
- **Excellent design** : effet Panini très réussi
- Animation fluide (`AnimationController`)
- Code bien structuré et commenté
- Gestion des états (actif, expiré, dépensé)

**⚠️ Points à améliorer** :
- Performance : animation continue même hors écran
- Pourrait utiliser `RepaintBoundary` pour optimiser

---

## 📊 Analyse de sécurité

### ✅ Points forts sécurité

1. **Stockage chiffré** : FlutterSecureStorage avec hardware-backed encryption
2. **AES-GCM** : Mode authentifié (détecte tampering)
3. **Nonces uniques** : Générés aléatoirement pour chaque chiffrement
4. **TTL QR** : Limite à 30s pour éviter rejeu
5. **Challenge anti-rejeu** : UUID dans chaque offre

### 🚨 Vulnérabilités critiques

| Sévérité | Vulnérabilité | Impact | Ligne |
|----------|---------------|--------|-------|
| 🔴 **CRITIQUE** | SSSS simplifié (XOR au lieu de Shamir) | Reconstruction nécessite 3 parts | crypto_service.dart:60-91 |
| 🔴 **CRITIQUE** | P2 non supprimé après transfert | **Double dépense possible** | offer_screen.dart |
| 🔴 **CRITIQUE** | Générateur aléatoire faible | Clés prédictibles | crypto_service.dart:49 |
| 🟠 **HAUTE** | nsec_bon stocké en clair | Exposition de la clé privée complète | bon.dart:14 |
| 🟠 **HAUTE** | Pas de vérification signature ACK | Accepte n'importe quel ACK | offer_screen.dart |
| 🟡 **MOYENNE** | Clés Nostr non au format bech32 | Incompatibilité avec écosystème | user.dart |
| 🟡 **MOYENNE** | Login/password non utilisé pour dérivation | Identifiants inutiles | main.dart:85 |

### 🔒 Recommandations sécurité

1. **Urgent** :
   - Implémenter vrai Shamir (package `shamir_secret_sharing`)
   - Supprimer P2 après ACK confirmé
   - Utiliser `Random.secure()` pour génération aléatoire
   - Ne **jamais** stocker `bonNsec` complet

2. **Important** :
   - Implémenter signature Schnorr pour ACK
   - Vérifier challenge dans ACK
   - Rotation quotidienne K_market
   - Audit trail des opérations sensibles

3. **Améliorations** :
   - Format bech32 pour npub/nsec
   - Dérivation HD (BIP32) depuis login/password
   - Backup chiffré des clés
   - Rate limiting sur création de bons

---

## 📈 Qualité du code

### Métriques

| Critère | Score | Commentaire |
|---------|-------|-------------|
| **Lisibilité** | 8/10 | Code clair, bien commenté |
| **Maintenabilité** | 7/10 | Bonne structure, mais couplage |
| **Testabilité** | 5/10 | Pas de tests, pas d'injection de dépendances |
| **Performance** | 7/10 | Bon, mais animations non optimisées |
| **Sécurité** | 4/10 | Vulnérabilités critiques présentes |
| **Documentation** | 9/10 | Excellente doc (README, ARCHITECTURE) |

### ✅ Bonnes pratiques observées

- Utilisation de `const` pour widgets immuables
- Disposal des controllers (`dispose()`)
- Gestion des états de chargement
- Validation des entrées utilisateur
- Messages d'erreur clairs
- Séparation UI / logique métier

### ⚠️ Mauvaises pratiques détectées

- Pas de tests unitaires (couverture 0%)
- Pas d'injection de dépendances (DI)
- Services instanciés dans les widgets
- Pas de gestion d'erreurs réseau (Nostr)
- Logs potentiellement sensibles
- Pas de CI/CD

---

## 🚀 État d'implémentation

### ✅ Fonctionnalités complètes (MVP)

- [x] Modèles de données (User, Bon, Market)
- [x] CryptoService (SSSS, AES-GCM)
- [x] QRService (encodage/décodage binaire)
- [x] StorageService (stockage sécurisé)
- [x] LoginScreen (création compte)
- [x] WalletScreen (liste bons)
- [x] CreateBonScreen (création bon)
- [x] OfferScreen (affichage QR)
- [x] PaniniCard (design ludique)

### 🚧 Fonctionnalités partielles

- [ ] ScanScreen (à vérifier)
- [ ] MarketScreen (à vérifier)
- [ ] Handshake ACK (incomplet)
- [ ] NostrService (stub)

### ❌ Fonctionnalités manquantes

- [ ] Tests unitaires
- [ ] Tests d'intégration
- [ ] Publication Nostr kind 30303
- [ ] Synchronisation automatique
- [ ] Vérification signature ACK
- [ ] Suppression P2 après transfert
- [ ] Gestion bons expirés
- [ ] Export PDF
- [ ] Multi-marchés
- [ ] Statistiques
- [ ] Backup/restore

---

## 💡 Recommandations prioritaires

### 🔴 Priorité 1 (Critique - Sécurité)

1. **Remplacer XOR par vrai Shamir**
   ```bash
   flutter pub add shamir_secret_sharing
   ```
   Réécrire `shamirSplit()` et `shamirCombine()`

2. **Implémenter handshake ACK complet**
   - Scanner QR ACK côté donneur
   - Vérifier signature Schnorr du challenge
   - Supprimer P2 seulement après ACK validé

3. **Corriger générateur aléatoire**
   ```dart
   import 'dart:math';
   final random = Random.secure();
   final seeds = Uint8List.fromList(
     List.generate(32, (_) => random.nextInt(256))
   );
   ```

### 🟠 Priorité 2 (Haute - Fonctionnalités)

4. **Implémenter NostrService**
   - Connexion WebSocket aux relais
   - Publication kind 30303
   - Synchronisation P3
   - Gestion reconnexion

5. **Ajouter tests unitaires**
   ```bash
   test/
   ├── crypto_service_test.dart
   ├── qr_service_test.dart
   └── models_test.dart
   ```

6. **Corriger dérivation de clé**
   - Utiliser réellement `derivePrivateKey()` dans LoginScreen
   - Dériver clé publique depuis privée (secp256k1)

### 🟡 Priorité 3 (Moyenne - Améliorations)

7. **Optimiser performance**
   - Lazy loading wallet (pagination)
   - Cache en mémoire pour P3
   - `RepaintBoundary` sur PaniniCard

8. **Format Nostr standard**
   - npub/nsec en bech32
   - Signature Schnorr
   - Events JSON standard

9. **UX améliorée**
   - Mode sombre
   - Internationalisation (i18n)
   - Animations de transition
   - Feedback haptique

---

## 📝 Conclusion

### Points forts du projet

✅ **Architecture solide** : Séparation claire des responsabilités  
✅ **Design exceptionnel** : Interface Panini très réussie  
✅ **Documentation complète** : README, ARCHITECTURE, QUICKSTART  
✅ **Cryptographie moderne** : AES-GCM, secp256k1, concept SSSS  
✅ **Offline-first** : Véritable autonomie locale  

### Points d'attention majeurs

🚨 **Faille double dépense** : P2 non supprimé après transfert  
🚨 **SSSS incorrect** : XOR simple au lieu de Shamir polynomial  
🚨 **Aléatoire faible** : Sécurité des clés compromise  
⚠️ **Tests absents** : Aucune couverture de code  
⚠️ **Nostr incomplet** : Service non implémenté  

### Verdict

**TrocZen est un excellent POC** (Proof of Concept) avec une architecture prometteuse et un design innovant. Cependant, **il n'est PAS prêt pour la production** en l'état actuel.

**Temps estimé pour MVP production** : 40-60h
- Sécurité : 15-20h
- Nostr : 10-15h
- Tests : 10-15h
- Polish : 5-10h

**Recommandation** : Corriger d'urgence les 3 vulnérabilités critiques avant tout déploiement test.

---

**Analyse réalisée le** : 16 février 2026  
**Analyseur** : Roo Code Assistant  
**Version code analysée** : 1.0.0-alpha
