# Architecture Technique - TrocZen

**Retour à la [Documentation Principale](README.md)** | [Index des Fichiers](FILE_INDEX.md)

## 📐 Vue d'ensemble

TrocZen est une application Flutter qui implémente un système de monnaie locale (ẐEN) avec les caractéristiques suivantes :

- **Offline-first** : Fonctionne sans Internet après synchronisation
- **Cryptographiquement sécurisé** : SSSS, AES-GCM, secp256k1
- **Décentralisé** : Pas de serveur central, utilise Nostr
- **Atomique** : Handshake en deux étapes pour éviter la double dépense

> 📄 Pour une vue d'ensemble complète du projet, consultez le [README principal](README.md).
> 📊 Pour l'état d'avancement et la roadmap, voir le [Résumé du Projet](PROJECT_SUMMARY.md).

## 🏗️ Architecture en couches

```
┌─────────────────────────────────────────┐
│            UI Layer (Screens)           │
│  wallet_screen, create_bon, scan, etc.  │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│         Business Logic (Services)       │
│  crypto_service, qr_service, storage    │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│          Data Layer (Models)            │
│        User, Bon, Market                │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│      Storage & External Services        │
│  SecureStorage, SQLite, Nostr, Camera   │
└─────────────────────────────────────────┘
```

## 🔐 Cryptographie

### Identités Nostr

Chaque utilisateur et chaque bon possède une paire de clés secp256k1 :

```dart
User:
- npub: Clé publique (identifiant)
- nsec: Clé privée (jamais partagée)

Bon:
- npub_bon: Identifiant public du bon
- nsec_bon: Clé privée divisée en P1/P2/P3
```

### Découpage SSSS (Shamir Secret Sharing)

La clé privée du bon (`nsec_bon`) est divisée en 3 parts avec un seuil de 2 :

```
nsec_bon → SSSS(2,3) → [P1, P2, P3]

Reconstruction:
P1 + P2 → nsec_bon
P2 + P3 → nsec_bon
P1 + P3 → nsec_bon
```

**Rôles des parts :**

- **P1 (Ancre)** : Stockée chez l'émetteur, permet burn/revocation
- **P2 (Voyageur)** : Circule de téléphone en téléphone
- **P3 (Témoin)** : Distribuée via Nostr, permet validation

### Chiffrement des parts

**P2** (lors du transfert) :
```
K_P2 = SHA256(P3)
P2_encrypted = AES-GCM(K_P2, P2, nonce)
```

**P3** (avant publication Nostr) :
```
K_market = Clé symétrique du marché (AES-256)
P3_encrypted = AES-GCM(K_market, P3, nonce)
```

## 📊 Modèle de données

### User

```dart
{
  "npub": "hex_public_key",
  "nsec": "hex_private_key",
  "displayName": "Jean Dupont",
  "createdAt": "2025-02-16T12:00:00Z"
}
```

### Bon

```dart
{
  "bonId": "npub_bon",
  "bonNsec": "nsec_bon",
  "value": 5.0,
  "issuerName": "Rucher de Jean",
  "issuerNpub": "npub_issuer",
  "createdAt": "2025-02-16T12:00:00Z",
  "expiresAt": "2025-05-16T12:00:00Z",
  "status": "active",
  "p1": "part1_hex",
  "p2": "part2_hex",
  "p3": null,  // P3 dans le cache
  "marketName": "marche-toulouse",
  "color": 4294951751  // ARGB
}
```

### Market

```dart
{
  "name": "marche-toulouse",
  "kmarket": "64_hex_chars",
  "validUntil": "2025-02-17T12:00:00Z",
  "relayUrl": "wss://relay.example.com"
}
```

## 🔄 Flux de données

### 1. Création d'un bon

```
User → CreateBonScreen
  ↓
CryptoService.generateNostrKeyPair()
  ↓
CryptoService.shamirSplit(nsec_bon)
  ↓
[P1, P2, P3]
  ↓
CryptoService.encryptP3(P3, K_market)
  ↓
StorageService.saveBon(bon)
StorageService.saveP3ToCache(bonId, P3)
  ↓
(TODO) NostrService.publishP3(kind 30303)
```

### 2. Transfert atomique

```
Donneur:
  ↓
CryptoService.encryptP2(P2, P3)
  ↓
QRService.encodeOffer(bonId, P2_enc, nonce, challenge, ts, ttl)
  ↓
[QR binaire 113 octets]
  ↓
Affichage QR avec compte à rebours

Receveur:
  ↓
Scanner.scan() → [bytes]
  ↓
QRService.decodeOffer(bytes)
  ↓
StorageService.getP3FromCache(bonId)
  ↓
CryptoService.decryptP2(P2_enc, nonce, P3)
  ↓
CryptoService.shamirCombine(P2, P3)
  ↓
nsec_bon (en RAM temporaire)
  ↓
Signature de vérification
  ↓
QRService.encodeAck(bonId, signature)
  ↓
[QR ACK]

Donneur:
  ↓
Scanner.scan() → [ACK bytes]
  ↓
Vérification signature
  ↓
StorageService.deleteBon(bonId) // Suppression P2
```

## 🗄️ Stockage

### FlutterSecureStorage (chiffré)

```
user → User JSON
bons → List<Bon> JSON
market → Market JSON
p3_cache → Map<bonId, p3_hex>
```

### Sécurité du stockage

- Android : Keystore (hardware-backed si disponible)
- iOS : Keychain
- Chiffrement AES-256
- Données jamais en clair sur le disque

## 📡 Protocole Nostr

### Event kind 30303 (Publication P3)

```json
{
  "kind": 30303,
  "pubkey": "npub_issuer",
  "created_at": 1708084800,
  "tags": [
    ["d", "zen-<npub_bon>"],
    ["market", "marche-toulouse"],
    ["p3", "<base64(AES(K_market, P3))>"],
    ["value", "5"],
    ["unit", "ZEN"],
    ["status", "issued"]
  ],
  "content": "",
  "sig": "schnorr_signature"
}
```

### Synchronisation

```dart
// Récupération des P3 depuis le relais
NostrService.subscribe(
  filters: [
    {
      "kinds": [30303],
      "tags": {"market": ["marche-toulouse"]},
      "since": last_sync_timestamp
    }
  ]
)
  ↓
Pour chaque event:
  CryptoService.decryptP3(event.tags.p3, K_market)
  ↓
  StorageService.saveP3ToCache(bonId, P3)
```

## 🔗 Format QR Code (Binaire)

### Offre (113 octets)

| Offset | Taille | Champ | Type | Description |
|--------|--------|-------|------|-------------|
| 0 | 32 | bon_id | bytes | Clé publique du bon |
| 32 | 48 | p2_cipher | bytes | P2 chiffré + tag AES-GCM |
| 80 | 12 | nonce | bytes | Nonce AES |
| 92 | 16 | challenge | bytes | Anti-rejeu |
| 108 | 4 | timestamp | uint32 | Unix timestamp (big-endian) |
| 112 | 1 | ttl | uint8 | Durée validité (secondes) |

### ACK (97 octets)

| Offset | Taille | Champ | Type | Description |
|--------|--------|-------|------|-------------|
| 0 | 32 | bon_id | bytes | Identique à l'offre |
| 32 | 64 | signature | bytes | Signature du challenge |
| 96 | 1 | status | uint8 | 0x01 = RECEIVED |

## 🎨 UI Components

### PaniniCard

Widget réutilisable pour afficher un bon :

```dart
PaniniCard(
  bon: bon,
  onTap: () => showOptions(),
  showActions: true
)
```

Couleurs par statut :
- Active : `#FFB347` (jaune miel)
- Pending : Gris
- Spent : Vert
- Expired : Orange
- Burned : Rouge

### Écrans principaux

1. **LoginScreen** : Dérivation de clé depuis login/password
2. **WalletScreen** : Liste des bons (RefreshIndicator)
3. **CreateBonScreen** : Formulaire + preview carte
4. **OfferScreen** : QR avec TTL countdown
5. **ScanScreen** : MobileScanner + overlay
6. **MarketScreen** : Configuration K_market

## 🧪 Tests

### Tests unitaires (à implémenter)

```dart
// crypto_service_test.dart
test('SSSS split/combine', () {
  final secret = "0123...";
  final parts = cryptoService.shamirSplit(secret);
  final reconstructed = cryptoService.shamirCombine(
    parts[0], parts[1], null
  );
  expect(reconstructed, equals(secret));
});

// qr_service_test.dart
test('QR encode/decode', () {
  final data = {...};
  final bytes = qrService.encodeOffer(data);
  final decoded = qrService.decodeOffer(bytes);
  expect(decoded['bonId'], equals(data['bonId']));
});
```

### Tests d'intégration

```dart
// Scénario complet
testWidgets('Transfer flow', (tester) async {
  // 1. Créer émetteur
  // 2. Créer bon
  // 3. Afficher QR
  // 4. Simuler scan
  // 5. Vérifier transfert
});
```

## 🔒 Sécurité - Checklist

- [ ] nsec_bon reconstruit uniquement en RAM
- [ ] P2 supprimé après transfert confirmé
- [ ] K_market rotation quotidienne
- [ ] Pas de logs sensibles en production
- [ ] Validation des entrées utilisateur
- [ ] TTL QR limité à 30s
- [ ] Challenge anti-rejeu
- [ ] Signature Schnorr pour events Nostr
- [ ] Stockage chiffré matériel si disponible

## 📈 Performance

### Optimisations

- Cache P3 en mémoire (Map<String, String>)
- Lazy loading des bons dans le wallet
- QR généré à la demande (pas pré-calculé)
- Reconstruction SSSS uniquement quand nécessaire

### Métriques cibles

- Génération bon : < 500ms
- Génération QR : < 200ms
- Scan + validation : < 1s
- Synchronisation 100 P3 : < 5s

## 🚀 Déploiement

### Android

```bash
flutter build apk --split-per-abi --release
```

Tailles typiques :
- arm64-v8a : ~15 MB
- armeabi-v7a : ~13 MB
- x86_64 : ~16 MB

### iOS

```bash
flutter build ios --release
```

Puis archiver via Xcode.

## 📝 TODO Technique

### Court terme
- [ ] Compléter handshake ACK
- [ ] Implémenter NostrService
- [ ] Tests unitaires crypto
- [ ] Gestion erreurs réseau

### Moyen terme
- [ ] Sync automatique en background
- [ ] Notifications push (optionnel)
- [ ] Export PDF transactions
- [ ] Multi-langues (i18n)

### Long terme
- [ ] Support multi-marchés
- [ ] Statistiques avancées
- [ ] Backup cloud (chiffré)
- [ ] PWA version

---

**Dernière mise à jour** : 16 février 2025
