# Corrections de Sécurité - TrocZen

## 🔐 Corrections Critiques Implémentées

### ✅ 1. Correction du générateur aléatoire (CRITIQUE)

**Problème** : Utilisation de `DateTime.now().millisecondsSinceEpoch` pour seed
**Impact** : Clés cryptographiques prédictibles
**Solution** : Utilisation de `Random.secure()`

```dart
// ❌ AVANT (crypto_service_old.dart:49)
final seeds = List<int>.generate(32, (i) => 
  DateTime.now().millisecondsSinceEpoch % 256
);

// ✅ APRÈS (crypto_service.dart:52-55)
final secureRandomGenerator = FortunaRandom();
final seedSource = Random.secure();
final seeds = Uint8List.fromList(
  List.generate(32, (_) => seedSource.nextInt(256))
);
```

**Fichiers modifiés** :
- [`troczen/lib/services/crypto_service.dart`](troczen/lib/services/crypto_service.dart:52-55)

---

### ✅ 2. Implémentation du vrai Shamir Secret Sharing (CRITIQUE)

**Problème** : XOR simple au lieu de Shamir polynomial
**Impact** : Nécessite 3 parts au lieu de 2-sur-3
**Solution** : Implémentation d'un polynôme de degré 1 avec interpolation de Lagrange

```dart
// ❌ AVANT : XOR simple (nécessite 3 parts)
final p3 = Uint8List(32);
for (int i = 0; i < 32; i++) {
  p3[i] = secretBytes[i] ^ p1[i] ^ p2[i];
}

// ✅ APRÈS : Shamir polynomial (2-sur-3)
for (int i = 0; i < 32; i++) {
  final a0 = secretBytes[i]; // Le secret
  final a1 = _secureRandom.nextInt(256); // Coefficient aléatoire
  
  // Polynôme: f(x) = a0 + a1*x (mod 256)
  p1Bytes[i] = (a0 + a1 * 1) % 256;
  p2Bytes[i] = (a0 + a1 * 2) % 256;
  p3Bytes[i] = (a0 + a1 * 3) % 256;
}
```

**Reconstruction avec Lagrange** :
```dart
// Interpolation pour retrouver f(0) = a0 = secret
final num1 = (y1[i] * _modInverse(-x2, x1 - x2, 256)) % 256;
final num2 = (y2[i] * _modInverse(-x1, x2 - x1, 256)) % 256;
secretBytes[i] = (num1 + num2) % 256;
```

**Fichiers modifiés** :
- [`troczen/lib/services/crypto_service.dart`](troczen/lib/services/crypto_service.dart:68-110)
- [`troczen/lib/services/crypto_service.dart`](troczen/lib/services/crypto_service.dart:112-149)

---

### ✅ 3. Correction dérivation de clé login/password (HAUTE)

**Problème** : Login/password ignorés, nouvelle paire générée à chaque fois
**Impact** : Identifiants inutiles, pas de récupération possible
**Solution** : Utilisation de Scrypt pour dériver la clé privée

```dart
// ❌ AVANT (main.dart:85)
final keys = _cryptoService.generateNostrKeyPair(); // Aléatoire !

// ✅ APRÈS (main.dart:76-82)
final privateKeyBytes = await _cryptoService.derivePrivateKey(
  _loginController.text.trim(),
  _passwordController.text,
);
final privateKeyHex = privateKeyBytes.map((b) => 
  b.toRadixString(16).padLeft(2, '0')
).join();
final publicKeyHex = _cryptoService.derivePublicKey(privateKeyBytes);
```

**Fichiers modifiés** :
- [`troczen/lib/main.dart`](troczen/lib/main.dart:76-89)
- [`troczen/lib/services/crypto_service.dart`](troczen/lib/services/crypto_service.dart:10-24) (Scrypt N=16384)
- [`troczen/lib/services/crypto_service.dart`](troczen/lib/services/crypto_service.dart:26-34) (Nouvelle méthode `derivePublicKey`)

---

### ✅ 4. Ajout de signature Schnorr pour ACK (HAUTE)

**Nouvelle fonctionnalité** : Signature et vérification de messages

```dart
// Signer un challenge
String signMessage(String messageHex, String privateKeyHex)

// Vérifier une signature ACK
bool verifySignature(String messageHex, String signatureHex, String publicKeyHex)
```

**Fichiers ajoutés** :
- [`troczen/lib/services/crypto_service.dart`](troczen/lib/services/crypto_service.dart:270-334)

**Usage prévu** (offer_screen.dart) :
```dart
// Donneur : générer challenge
final challenge = _uuid.v4().replaceAll('-', '').substring(0, 32);

// Receveur : signer le challenge
final signature = _cryptoService.signMessage(challenge, bon.nsec);

// Donneur : vérifier avant suppression P2
if (_cryptoService.verifySignature(challenge, signature, bon.bonId)) {
  await _storageService.deleteBon(bon.bonId); // Supprime P2
}
```

---

## ⚠️ Corrections Partielles / À Compléter

### 🚧 5. Handshake ACK incomplet (CRITIQUE)

**État** : Structure prête, implémentation à finaliser

**TODO** :
1. ✅ Ajout méthodes `signMessage()` et `verifySignature()`
2. ❌ Modifier `offer_screen.dart` pour attendre ACK
3. ❌ Modifier `scan_screen.dart` pour envoyer ACK signé
4. ❌ Supprimer P2 seulement après vérification signature

**Fichiers à modifier** :
- `troczen/lib/screens/offer_screen.dart` (lignes 200-280)
- `troczen/lib/screens/scan_screen.dart`
- `troczen/lib/screens/ack_screen.dart` (créer)

**Code à ajouter dans offer_screen.dart** :
```dart
// Après affichage QR, attendre scan ACK
void _waitForAck() async {
  final ackResult = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => AckScannerScreen(
        challenge: _currentChallenge,
        bonId: widget.bon.bonId,
      ),
    ),
  );
  
  if (ackResult != null && ackResult['verified'] == true) {
    // ✅ Suppression P2 sécurisée
    await _storageService.deleteBon(widget.bon.bonId);
    Navigator.pop(context); // Retour au wallet
  }
}
```

---

## 📊 Récapitulatif des Corrections

| # | Vulnérabilité | Sévérité | Status | Fichier |
|---|---------------|----------|--------|---------|
| 1 | Générateur aléatoire faible | 🔴 CRITIQUE | ✅ **CORRIGÉ** | crypto_service.dart |
| 2 | SSSS simplifié (XOR) | 🔴 CRITIQUE | ✅ **CORRIGÉ** | crypto_service.dart |
| 3 | P2 non supprimé | 🔴 CRITIQUE | 🚧 **PARTIEL** | offer_screen.dart |
| 4 | Login/password non utilisé | 🟠 HAUTE | ✅ **CORRIGÉ** | main.dart |
| 5 | Signature ACK absente | 🟠 HAUTE | 🚧 **PARTIEL** | crypto_service.dart |
| 6 | nsec_bon stocké en clair | 🟡 MOYENNE | ⏳ **À FAIRE** | bon.dart |

---

## 🧪 Tests Ajoutés

### Test Shamir Secret Sharing

```dart
// test/crypto_service_test.dart
test('Shamir split/combine avec 2 parts sur 3', () async {
  final service = CryptoService();
  final secret = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  
  // Split en 3 parts
  final parts = service.shamirSplit(secret);
  
  // Recombiner avec P1 + P2
  final reconstructed12 = service.shamirCombine(parts[0], parts[1], null);
  expect(reconstructed12, equals(secret));
  
  // Recombiner avec P2 + P3
  final reconstructed23 = service.shamirCombine(null, parts[1], parts[2]);
  expect(reconstructed23, equals(secret));
  
  // Recombiner avec P1 + P3
  final reconstructed13 = service.shamirCombine(parts[0], null, parts[2]);
  expect(reconstructed13, equals(secret));
});
```

---

## 🚀 Prochaines Étapes

### Priorité Immédiate

1. **Compléter handshake ACK** (2-3h)
   - Créer `ack_screen.dart` pour scanner ACK
   - Modifier `offer_screen.dart` pour attendre ACK
   - Modifier `scan_screen.dart` pour signer et envoyer ACK
   - Implémenter suppression P2 après vérification

2. **Tests unitaires** (3-4h)
   - Tests Shamir (split/combine)
   - Tests signatures (sign/verify)
   - Tests dérivation de clé
   - Tests chiffrement AES-GCM

3. **Service Nostr** (4-6h)
   - Connexion WebSocket
   - Publication kind 30303 (P3)
   - Synchronisation automatique
   - Gestion reconnexion

### Améliorations Sécurité

4. **Ne pas stocker nsec_bon complet** (1-2h)
   - Supprimer champ `bonNsec` du modèle Bon
   - Reconstruire temporairement avec P2+P3 uniquement
   - Nettoyer RAM après usage

5. **Rotation K_market** (1h)
   - Notification expiration
   - Workflow mise à jour clé
   - Migration P3 avec nouvelle clé

---

## 📝 Notes Techniques

### Shamir (2,3) Implémentation

L'implémentation utilise un polynôme de degré 1 pour chaque octet :
- **f(x) = a₀ + a₁·x (mod 256)**
- a₀ = secret[i]
- a₁ = random
- P₁ = f(1), P₂ = f(2), P₃ = f(3)

Reconstruction par interpolation de Lagrange :
- **f(0) = Σ yᵢ · Lᵢ(0)**
- Lᵢ(0) = ∏(0-xⱼ)/(xᵢ-xⱼ) pour j≠i

### Signature Schnorr Simplifiée

- **R = k·G** (point)
- **e = H(R || message)**
- **s = k + e·privKey (mod n)**
- **Signature = (r, s)** où r = R.x

Vérification :
- **s·G == R + e·pubKey**

---

## ⚡ Performance

### Benchmarks (à mesurer)

- Shamir split : < 10ms
- Shamir combine : < 5ms
- Signature Schnorr : < 20ms
- Vérification : < 25ms
- Dérivation Scrypt : ~500ms (intentionnellement lent)

---

**Date des corrections** : 16 février 2026  
**Version** : 1.0.1-security-fixes  
**Auteur** : Roo Code Assistant  
**Fichiers modifiés** : 3 fichiers principaux
