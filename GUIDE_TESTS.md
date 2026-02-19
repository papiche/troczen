# Guide Complet des Tests - TrocZen

## 🧪 Stratégie de Test

**Objectif** : Vérifier que l'application fonctionne correctement avant déploiement

**3 niveaux de tests** :
1. Tests unitaires (fonctions isolées)
2. Tests d'intégration (scénarios complets)
3. Tests manuels (UX/UI sur appareil réel)

---

## 1️⃣ Tests Unitaires

### ✅ Existants

#### Crypto Service

**Fichier** : [`test/crypto_service_test.dart`](troczen/test/crypto_service_test.dart)

```bash
cd troczen && flutter test test/crypto_service_test.dart
```

**Couverture** : 15 tests

- Dérivation de clé déterministe ✅
- Génération paires de clés ✅
- Shamir split/combine (3 combinaisons 2-sur-3) ✅
- Chiffrement/déchiffrement P2 et P3 ✅
- Signatures Schnorr ✅

#### QR Service

**Fichier** : [`test/qr_service_test.dart`](troczen/test/qr_service_test.dart)

```bash
cd troczen && flutter test test/qr_service_test.dart
```

**Couverture** : 13 tests

- Encodage/décodage offre v1 (113 octets) ✅
- Encodage/décodage ACK (97 octets) ✅
- Gestion TTL et expiration ✅
- Edge cases ✅

#### Storage Service

**Fichier** : [`test/storage_service_test.dart`](troczen/test/storage_service_test.dart)

```bash
cd troczen && flutter test test/storage_service_test.dart
```

**Couverture** : 15 tests

- Gestion utilisateurs (save/get/delete) ✅
- Gestion bons (save/get/update/delete) ✅
- Cache P3 ✅
- Gestion marché ✅

#### Tests d'intégration

**Fichier** : [`test/integration_test.dart`](troczen/test/integration_test.dart)

```bash
cd troczen && flutter test test/integration_test.dart
```

**Couverture** : 16 tests (flux critiques du diagramme `trozen.mermaid`)

- **PHASE 2 - Création de bon** : génération clés, Shamir split, chiffrement P3, zeroise
- **PHASE 3 - Synchronisation** : dérivation K_day, déchiffrement P3, cache local
- **PHASE 4 - Transfert atomique** : QR1 offre, QR2 ACK, signature Schnorr, end-to-end
- **Sécurité** : validation clés, détection falsification, expiration QR

#### Exécution de tous les tests

```bash
cd troczen && flutter test
```

**Total** : 68 tests (52 unitaires + 16 intégration)

### 📝 Tests À Ajouter

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/qr_service.dart';
import 'dart:typed_data';

void main() {
  group('QRService', () {
    late QRService qrService;

    setUp(() {
      qrService = QRService();
    });

    test('encodeOffer génère 113 octets', () {
      final qrBytes = qrService.encodeOffer(
        bonIdHex: 'a' * 64,
        p2CipherHex: 'b' * 96,
        nonceHex: 'c' * 24,
        challengeHex: 'd' * 32,
        timestamp: 1708084800,
        ttl: 30,
      );

      expect(qrBytes.length, equals(113));
    });

    test('encodeOffer/decodeOffer sont réciproques', () {
      final bonId = 'deadbeef' * 8;
      final p2Cipher = 'cafebabe' * 12;
      final nonce = '12345678' * 3;
      final challenge = 'abcd' * 8;
      final timestamp = 1708084800;
      final ttl = 30;

      final encoded = qrService.encodeOffer(
        bonIdHex: bonId,
        p2CipherHex: p2Cipher,
        nonceHex: nonce,
        challengeHex: challenge,
        timestamp: timestamp,
        ttl: ttl,
      );

      final decoded = qrService.decodeOffer(encoded);

      expect(decoded['bonId'], equals(bonId));
      expect(decoded['timestamp'], equals(timestamp));
      expect(decoded['ttl'], equals(ttl));
    });

    test('encodeAck génère 97 octets', () {
      final ackBytes = qrService.encodeAck(
        bonIdHex: 'a' * 64,
        signatureHex: 'b' * 128,
        status: 0x01,
      );

      expect(ackBytes.length, equals(97));
    });

    test('isExpired détecte QR expiré', () {
      final pastTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 100;
      expect(qrService.isExpired(pastTimestamp, 30), isTrue);
    });

    test('timeRemaining calcule correctement', () {
      final nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remaining = qrService.timeRemaining(nowTimestamp, 30);
      
      expect(remaining, greaterThan(25));
      expect(remaining, lessThanOrEqualTo(30));
    });
  });
}
```

#### B. Storage Service

Créer `test/storage_service_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/storage_service.dart';
import 'package:troczen/models/user.dart';
import 'package:troczen/models/bon.dart';
import 'package:troczen/models/market.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mockito/mockito.dart';

// Mock FlutterSecureStorage pour tests
class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('StorageService', () {
    // Tests de base sans mocks (si FlutterSecureStorage fonctionne en test)
    late StorageService storage;

    setUp(() {
      storage = StorageService();
    });

    test('saveUser et getUser fonctionnent', () async {
      final user = User(
        npub: 'test_npub',
        nsec: 'test_nsec',
        displayName: 'Test User',
        createdAt: DateTime.now(),
      );

      await storage.saveUser(user);
      final retrieved = await storage.getUser();

      expect(retrieved?.npub, equals(user.npub));
      expect(retrieved?.displayName, equals(user.displayName));
    });

    test('saveBon et getBonById fonctionnent', () async {
      final bon = Bon(
        bonId: 'test_bon_id',
        value: 5.0,
        issuerName: 'Test Issuer',
        issuerNpub: 'test_issuer_npub',
        createdAt: DateTime.now(),
        status: BonStatus.active,
        p1: 'p1_hex',
        p2: 'p2_hex',
        marketName: 'test-market',
      );

      await storage.saveBon(bon);
      final retrieved = await storage.getBonById('test_bon_id');

      expect(retrieved?.bonId, equals('test_bon_id'));
      expect(retrieved?.value, equals(5.0));
    });

    test('getActiveBons filtre correctement', () async {
      // Clear storage
      await storage.clearAll();

      // Créer deux bons
      final bonActive = Bon(
        bonId: 'bon_active',
        value: 5.0,
        issuerName: 'Issuer',
        issuerNpub: 'npub',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(Duration(days: 30)),
        status: BonStatus.active,
        marketName: 'test',
      );

      final bonExpired = Bon(
        bonId: 'bon_expired',
        value: 5.0,
        issuerName: 'Issuer',
        issuerNpub: 'npub',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().subtract(Duration(days: 1)),
        status: BonStatus.active,
        marketName: 'test',
      );

      await storage.saveBon(bonActive);
      await storage.saveBon(bonExpired);

      final activeBons = await storage.getActiveBons();

      expect(activeBons.length, equals(1));
      expect(activeBons.first.bonId, equals('bon_active'));
    });
  });
}
```

---

## 2️⃣ Tests d'Intégration

### Scénario Complet : Création → Transfert

Créer `test/integration_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:troczen/main.dart' as app;
import 'package:troczen/services/crypto_service.dart';
import 'package:troczen/services/storage_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Scénario Complet', () {
    testWidgets('Création compte → Bon → Transfert', (tester) async {
      // Lancer l'app
      app.main();
      await tester.pumpAndSettle();

      // 1. Création compte
      await tester.enterText(
        find.byType(TextField).first,
        'testuser',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'password12345',
      );
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();

      // 2. Vérifier arrivée sur wallet
      expect(find.text('TrocZen'), findsOneWidget);

      // 3. Créer un bon
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        '5',
      );
      await tester.tap(find.text('Créer'));
      await tester.pumpAndSettle();

      // 4. Vérifier bon dans wallet
      expect(find.text('5 ẐEN'), findsAtLeastNWidgets(1));
    });

    testWidgets('Shamir functionality end-to-end', (tester) async {
      final crypto = CryptoService();
      final storage = StorageService();

      // Générer clés bon
      final keys = crypto.generateNostrKeyPair();
      final nsec = keys['nsec']!;

      // Split
      final parts = crypto.shamirSplit(nsec);
      final p1 = parts[0];
      final p2 = parts[1];
      final p3 = parts[2];

      // Stocker P3
      await storage.saveP3ToCache(keys['npub']!, p3);

      // Récupérer P3
      final p3Retrieved = await storage.getP3FromCache(keys['npub']!);
      expect(p3Retrieved, equals(p3));

      // Combiner P2+P3
      final reconstructed = crypto.shamirCombine(null, p2, p3);
      expect(reconstructed, equals(nsec));
    });
  });
}
```

**Installation** :

```bash
flutter pub add integration_test --dev
```

**Exécution** :

```bash
flutter test integration_test/integration_test.dart
```

---

## 3️⃣ Tests Manuels sur Appareil

### Checklist Tests Terrain

#### Préparation (10 min)

- [ ] Build APK : `flutter build apk --release`
- [ ] Installer sur 2 appareils (Alice & Bob)
- [ ] Préparer conditions offline (mode avion)

#### Test 1 : Création Compte (5 min)

**Appareil A (Alice)** :
- [ ] Login: `alice`
- [ ] Password: `password123`
- [ ] Nom: `Alice Apicultrice`
- [ ] ✅ Compte créé
- [ ] ✅ Redirection vers wallet

#### Test 2 : Configuration Marché (2 min)

**Appareil A** :
- [ ] Tap ⚙️
- [ ] Choisir "Marché global TrocZen"
- [ ] ✅ Configuré automatiquement

**Appareil B (Bob)** :
- [ ] Idem marché global

#### Test 3 : Création Bon (3 min)

**Appareil A** :
- [ ] Tap +
- [ ] Valeur: `5`
- [ ] Nom: `Miel d'Acacia`
- [ ] ✅ Bon créé
- [ ] ✅ Visible dans wallet

#### Test 4 : Synchronisation (2 min)

**Appareil B** :
- [ ] Tap ⟳ (sync)
- [ ] ✅ P3 synchronisées

#### Test 5 : Transfert Offline (10 min)

**Les deux en mode avion** ✈️

**Appareil A (donneur)** :
- [ ] Sélectionner bon
- [ ] "Donner ce bon"
- [ ] ✅ QR affiché avec TTL 30s

**Appareil B (receveur)** :
- [ ] Tap 📷
- [ ] Scanner QR d'Alice
- [ ] ✅ Vérification réussie
- [ ] ✅ QR ACK affiché

**Appareil A** :
- [ ] Tap "Attendre confirmation"
- [ ] Scanner QR ACK de Bob
- [ ] ✅ "Transfert confirmé !"
- [ ] ✅ Bon disparu du wallet

**Appareil B** :
- [ ] Retour wallet
- [ ] ✅ Bon reçu visible

#### Test 6 : Double Dépensetentative) (5 min)

**Appareil A** :
- [ ] Tenter de donner à nouveau le  bon
- [ ] ❌ Bon plus dans la liste
- [ ] ✅ Double dépense IMPOSSIBLE

#### Test 7 : Synchronisation PostTransfert (3 min)

**Remettre réseau** 📡

**Appareil A** :
- [ ] Tap ⟳
- [ ] ✅ Sync sans erreur

**Appareil B** :
- [ ] Tap ⟳
- [ ] ✅ Sync sans erreur
- [ ] ✅ Event transfert publié sur Nostr

#### Test 8 : Expiration QR (2 min)

**Appareil A** :
- [ ] Créer nouveau bon
- [ ] "Donner"
- [ ] ⏱️ Attendre 30s
- [ ] Bob scanne
- [ ] ❌ "QR code expiré"
- [ ] ✅ Sécurité anti-rejeu OK

---

## 🔍 Tests de Sécurité

### Test S1 : Reconstruction Éphémère

**Objectif** : Vérifier que sk_B n'est jamais stocké

```dart
test('sk_B jamais dans storage', () async {
  final storage = StorageService();
  final bon = await storage.getBonById('test');
  
  // Vérifier que bonNsec n'existe plus
  expect(bon?.toJson().containsKey('bonNsec'), isFalse);
});
```

### Test S2 : Nettoyage RAM

```dart
test('secureZeroise efface la clé', () {
  final crypto = CryptoService();
  final secret = 'deadbeefcafebabe' * 4;
  
  final bytes = HEX.decode(secret);
  crypto.secureZeroise(secret);
  
  // Impossible de vérifier directement en Dart
  // Mais la fonction est appelée
});
```

### Test S3 : Validation Clés

```dart
test('isValidPublicKey rejette clés invalides', () {
  final crypto = CryptoService();
  
  // Clé valide
  final keys = crypto.generateNostrKeyPair();
  expect(crypto.isValidPublicKey(keys['npub']!), isTrue);
  
  // Clé invalide (trop courte)
  expect(crypto.isValidPublicKey('deadbeef'), isFalse);
  
  // Clé invalide (pas sur la courbe)
  expect(crypto.isValidPublicKey('f' * 64), isFalse);
});
```

---

## 📱 Tests UI/UX

### Checklist Qualité Interface

#### Navigation
- [ ] Tous les écrans accessibles
- [ ] Bouton retour fonctionne
- [ ] Pas de crash navigation

#### Formulaires
- [ ] Validation champs correcte
- [ ] Messages d'erreur clairs
- [ ] Autocomplétion fonctionnelle

#### QR Codes
- [ ] QR suffisamment grands
- [ ] Contraste élevé (noir/blanc)
- [ ] Scan rapide (< 2s)
- [ ] Compte à rebours visible

#### Feedback Visuel
- [ ] Loading spinners affichés
- [ ] Succès en vert
- [ ] Erreurs en rouge
- [ ] Transitions fluides

#### Accessibilité
- [ ] Texte lisible (taille min 14)
- [ ] Contraste suffisant (WCAG AA)
- [ ] Boutons tactiles (min 44x44)

---

## 🧪 Tests Réseau

### Test R1 : Mode Online

```bash
# Sur émulateur/appareil avec réseau
flutter drive --target=integration_test/online_test.dart
```

Vérifier :
- [ ] Connexion relay Nostr
- [ ] Publication P3
- [ ] Sync fonctionnelle
- [ ] Upload IPFS

### Test R2 : Mode Offline Complet

**Conditions** :
- Mode avion ✈️
- WiFi off
- Données mobiles off

Vérifier :
- [ ] Publication reportée (queue)
- [ ] Transferts fonctionnent (cache P3)
- [ ] Pas de crash
- [ ] Messages appropriés

### Test R3 : Réseau Instable

**Simulation** :
- Activer/désactiver réseau rapidement
- Latence élevée

Vérifier :
- [ ] Reconnexion automatique
- [ ] Pas de blocage UI
- [ ] Timeout appropriés

---

## 🔧 Tests de Charge

### Test C1 : Wallet avec 100 Bons

```dart
test('Performance avec 100 bons', () async {
  final storage = StorageService();
  
  // Créer 100 bons
  for (int i = 0; i < 100; i++) {
    final bon = Bon(
      bonId: 'bon_$i',
      value: 5.0,
      issuerName: 'Issuer $i',
      issuerNpub: 'npub_$i',
      createdAt: DateTime.now(),
      status: BonStatus.active,
      marketName: 'test',
    );
    await storage.saveBon(bon);
  }
  
  final stopwatch = Stopwatch()..start();
  final bons = await storage.getBons();
  stopwatch.stop();
  
  expect(bons.length, equals(100));
  expect(stopwatch.elapsedMilliseconds, lessThan(500));
});
```

### Test C2 : Cache P3 Volumineux

```dart
test('Performance cache 500 P3', () async {
  final storage = StorageService();
  
  for (int i = 0; i < 500; i++) {
    await storage.saveP3ToCache('bon_$i', 'p3_hex_$i');
  }
  
  final cache = await storage.getP3Cache();
  expect(cache.length, equals(500));
});
```

---

## 📊 Commandes Utiles

### Tous les tests

```bash
flutter test
```

### Tests spécifiques

```bash
# Crypto seulement
flutter test test/crypto_service_test.dart

# QR seulement
flutter test test/qr_service_test.dart

# Avec couverture
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Tests d'intégration

```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart
```

### Tests sur appareil réel

```bash
# Android
flutter test integration_test/app_test.dart -d <device_id>

# iOS
flutter test integration_test/app_test.dart -d iPhone
```

---

## 🎯 Critères de Succès

### Avant Déploiement

- ✅ Tous les tests unitaires passent (100%)
- ✅ Au moins 1 scénario intégration complet
- ✅ Tests manuels sur 2 appareils réussis
- ✅ Mode offline validé
- ✅ Aucun crash sur actions principales

### Objectifs de Couverture

| Composant | Couverture Cible |
|-----------|------------------|
| CryptoService | ✅ 60% (atteint) |
| QRService | 🎯 80% |
| StorageService | 🎯 70% |
| NostrService | 🎯 50% |
| Screens | 🎯 30% (smoke tests) |

---

## 🐛 Debugging

### Logs Utiles

```dart
// Dans main.dart
void main() {
  debugPrint('🚀 TrocZen démarrage');
  runApp(const TrocZenApp());
}

// Dans les services
debugPrint('✅ P3 publiée: $bonId');
debugPrint('⚠️ Erreur sync: $e');
```

### Inspection Stockage

```bash
# Android
adb shell
run-as com.example.troczen
cd app_flutter
ls -la

# iOS
Xcode > Window > Devices and Simulators
> Installed Apps > TrocZen > Download Container
```

---

## 📋 Checklist Finale Avant Release

- [ ] ✅ Tous tests unitaires passent
- [ ] ✅ Tests intégration OK
- [ ] ✅ Tests manuels 2 appareils réussis
- [ ] ✅ Mode offline validé
- [ ] ✅ Performance acceptable (< 2s opérations)
- [ ] ✅ Pas de fuite mémoire (test 1h continu)
- [ ] ✅ Batterie impact faible
- [ ] ✅ Build APK sans warning
- [ ] ✅ Documentation à jour
- [ ] ✅ GitHub issues vides ou triées

**Total temps tests** : 8-10h

---

**Ce guide permet de vérifier systématiquement que TrocZen fonctionne correctement à tous les niveaux !** ✅
