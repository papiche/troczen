# Documentation Technique Avancée - TrocZen

**Retour à la [Documentation Principale](README.md)** | [Index des Fichiers](FILE_INDEX.md)

Ce document consolide les informations techniques avancées précédemment dispersées dans plusieurs fichiers. Il contient des détails d'implémentation, des exemples de code et des analyses techniques approfondies.

---

## 🔐 Implémentations de Sécurité Critiques

### 1. Signature Schnorr pour le Handshake ACK

**Contexte** : Système de confirmation sécurisé pour les transferts de bons.

**Implémentation** (`crypto_service.dart`) :

```dart
// Signer un challenge
String signMessage(String messageHex, String privateKeyHex)

// Vérifier une signature
bool verifySignature(String messageHex, String signatureHex, String publicKeyHex)
```

**Utilisation dans le workflow** :

```dart
// 1. Donneur (offer_screen.dart) génère un challenge
final challenge = _uuid.v4().replaceAll('-', '').substring(0, 32);

// 2. Receveur (ack_screen.dart) signe avec la clé du bon
final nsecBon = _cryptoService.shamirCombine(bon.p2, bon.p3, null);
final signature = _cryptoService.signMessage(challenge, nsecBon);

// 3. Donneur vérifie la signature avant de supprimer P2
if (_cryptoService.verifySignature(challenge, signature, bon.bonId)) {
  await _storageService.deleteBon(bon.bonId); // ✅ Suppression sécurisée
}
```

**Impact sécurité** : Empêche la falsification d'ACK sans possession de P2+P3.

---

### 2. Dérivation de Clé Déterministe (Scrypt)

**Problème résolu** : Login/password inutiles → Clés dérivées de manière sécurisée.

**Implémentation** :

```dart
// Dans main.dart
final salt = 'TrocZen-${login}'.padRight(16, '0');
final keyBytes = scrypt.hash(password, salt, n: 16384, r: 8, p: 1, dkLen: 32);
final privateKeyHex = hex.encode(keyBytes);
final publicKeyHex = _cryptoService.derivePublicKey(privateKeyBytes);
```

**Avantages** :
- Même identifiants → même clé (récupération possible)
- Résistance brute-force (Scrypt N=16384)
- Login/password maintenant fonctionnels

---

### 3. Service Nostr Complet

**Fonctionnalités implémentées** :
- Connexion WebSocket aux relais
- Publication kind 30303 (P3 chiffrées)
- Synchronisation automatique
- Gestion des erreurs et reconnexion

**Exemple d'utilisation** :

```dart
// Initialisation
final nostrService = NostrService(
  cryptoService: CryptoService(),
  storageService: StorageService(),
);

// Connexion
await nostrService.connect('wss://relay.copylaradio.com');

// Publication P3
await nostrService.publishP3(
  bonId: bon.bonId,
  p3Hex: p3,
  kmarketHex: market.kmarket,
  issuerNpub: user.npub,
  issuerNsec: user.nsec,
  marketName: market.name,
  value: bon.value,
);

// Synchronisation
final count = await nostrService.syncMarketP3s(market);
```

---

## 🧪 Tests Unitaires Complets

**15 tests implémentés** dans `crypto_service_test.dart` :

### Dérivation de clé
- ✅ Dérivation déterministe (même login/password = même clé)
- ✅ Clés différentes pour utilisateurs différents

### Génération de clés
- ✅ Paires de clés valides (64 caractères hexadécimaux)

### Shamir Secret Sharing
- ✅ Split génère 3 parts différentes
- ✅ Combine avec P1 + P2
- ✅ Combine avec P2 + P3
- ✅ Combine avec P1 + P3
- ✅ Erreur si moins de 2 parts

### Chiffrement AES-GCM
- ✅ Chiffrement/déchiffrement P2
- ✅ Vérification de l'authentification

### Signature Schnorr
- ✅ Signature valide
- ✅ Vérification de signature
- ✅ Rejet des signatures invalides

---

## 🎨 Analyse des Composants UI

### PaniniCard (`panini_card.dart`)

**Points forts** :
- Système de rareté (common, uncommon, rare, legendary)
- Animation shimmer pour bons rares
- Gradient holographique rotatif
- Badge de rareté avec icône
- Compteur de passages (transferCount)

**Points à améliorer** :
- Performance : animation continue même hors écran
- Optimisation : utiliser `RepaintBoundary`

### CreateBonScreen

**Points forts** :
- Prévisualisation en temps réel
- Validation marché avant création
- Gestion complète des erreurs

**Points à améliorer** :
- `rarity` non générée (fonction `Bon.generateRarity()` non utilisée)
- Pas de sélection de couleur
- Expiration fixe à 90 jours (non configurable)

### OfferScreen

**Points forts** :
- Compte à rebours visuel
- Régénération automatique à expiration
- QR binaire compact (113 octets)

**Points critiques corrigés** :
- Handshake ACK maintenant complet
- P2 supprimé après transfert confirmé
- Challenge signé pour vérification

---

## 📚 Références Techniques

- **Shamir Secret Sharing** : [https://github.com/grempe/secrets.js](https://github.com/grempe/secrets.js)
- **Signature Schnorr** : BIP 340 (Bitcoin)
- **NIP-33** : Parameterized Replaceable Events
- **Scrypt** : RFC 7914

## 🎨 Améliorations PaniniCard (2026)

### Unicité des Cartes (Style Pokémon)

**Nouveaux champs ajoutés au modèle Bon** :
- `uniqueId` : Identifiant unique au format "ZEN-ABC123"
- `cardType` : Type de carte (commerce, service, artisan, culture, technologie, alimentation)
- `specialAbility` : Capacité spéciale basée sur la rareté
- `stats` : Statistiques (power, defense, speed, durability, valueMultiplier)

**Méthodes de génération automatique** :
- `Bon.generateUniqueId(bonId)` : Crée un ID unique à partir du bonId
- `Bon.generateCardType()` : Sélection aléatoire parmi 6 types de commerce
- `Bon.generateSpecialAbility(rarity)` : 4 niveaux de capacités uniques
- `Bon.generateStats(rarity)` : Statistiques équilibrées selon la rareté
- `Bon.getDurationRemaining()` : Calcul de la durée restante formatée
- `Bon.getCharacteristics()` : Retourne toutes les caractéristiques pour l'affichage

### Affichage des Caractéristiques

**Pour les détenteurs de P2 (utilisateurs normaux)** :
- Bouton d'œil bleu (👁️) en bas à droite de la carte
- Clic pour afficher/masquer les détails techniques
- Affichage complet des caractéristiques uniques :
  - ID Unique et type de carte
  - Capacité spéciale avec icône 🌟
  - Statistiques sous forme de graphique (Power, Defense, Speed, Durability)
  - Durée restante avec code couleur (vert/rouge)
  - Nombre de transfers effectués
  - Nom de l'émetteur

**Pour les détenteurs de P1 (émetteurs/administrateurs)** :
- Bouton d'œil vert (👁️) pour l'administration
- Accès aux mêmes informations que P2
- Bouton supplémentaire "Révoquer" pour annuler le bon
- Fonctionnalité de monitoring et gestion

### Optimisations Techniques

**RepaintBoundary** :
- Ajouté autour de chaque PaniniCard via `RepaintBoundary` widget
- Empêche les redessins inutiles lors du scroll
- Améliore significativement les performances sur les listes longues
- Réduction de la consommation mémoire

**Animations améliorées** :
- Animation shimmer uniquement pour les cartes rares (legendary/rare)
- Gestion propre du cycle de vie des AnimationController
- Désactivation automatique des animations pour les cartes non visibles
- Optimisation mémoire et CPU

**Gestion des états** :
- État local `_showDetails` pour afficher/masquer les détails
- Mise à jour réactive de l'interface
- Pas de redessins complets inutiles

### Interface de Création Améliorée (CreateBonScreen)

**Nouveaux champs de formulaire** :
- **Sélection de couleur** : 10 couleurs disponibles + aperçu visuel
- **Choix de la rareté** :
  - Mode automatique (génération aléatoire)
  - Mode manuel (sélection parmi common/uncommon/rare/legendary)
  - Aperçu visuel de la rareté sélectionnée
- **Configuration de l'expiration** :
  - Champ numérique configurable (1-365 jours)
  - Remplace l'expiration fixe de 90 jours
  - Validation intégrée

**Génération automatique des caractéristiques** :
- Utilisation systématique de `Bon.generateRarity()` pour la rareté
- Couleur par défaut basée sur le thème ou sélection utilisateur
- Expiration personnalisable au lieu des 90 jours fixes
- Génération des caractéristiques uniques à la création

**Aperçu en temps réel** :
- Mise à jour dynamique de la prévisualisation
- Affichage des caractéristiques générées
- Feedback visuel immédiat

### Exemple de Carte Générée

```dart
// Création d'un bon avec caractéristiques uniques
final bon = Bon(
  bonId: 'npub1...',
  value: 25.0,
  rarity: 'rare',
  uniqueId: 'ZEN-ABC123',
  cardType: 'artisan',
  specialAbility: 'Double valeur les week-ends',
  stats: {
    'power': 8,
    'defense': 6,
    'speed': 4,
    'durability': 7,
    'valueMultiplier': 1.8
  },
  color: Colors.blue.value,
  expiresAt: DateTime.now().add(Duration(days: 180)),
);

// Affichage des caractéristiques
print(bon.getCharacteristics());
// {
//   'ID Unique': 'ZEN-ABC123',
//   'Type': 'artisan',
//   'Rareté': 'rare',
//   'Valeur': '25 ẐEN',
//   'Durée': '6 mois restants',
//   'Transfers': '0',
//   'Capacité': 'Double valeur les week-ends',
//   'Émetteur': 'Artisan Local'
// }
```

### Impact sur l'Expérience Utilisateur

**Pour les utilisateurs (P2)** :
- Collection de cartes uniques comme des cartes Pokémon
- Découverte des caractéristiques spéciales
- Valorisation des cartes rares
- Expérience de collection ludique et engageante

**Pour les émetteurs (P1)** :
- Outils d'administration intégrés
- Monitoring des bons émis
- Possibilité de révocation
- Meilleure gestion du cycle de vie

**Pour les développeurs** :
- Code mieux organisé et documenté
- Performances améliorées
- Maintenance facilitée
- Extensibilité pour de nouvelles fonctionnalités

---

## 📚 Références Techniques (Mises à jour 2026)

- **Shamir Secret Sharing** : [https://github.com/grempe/secrets.js](https://github.com/grempe/secrets.js)
- **Signature Schnorr** : BIP 340 (Bitcoin)
- **NIP-33** : Parameterized Replaceable Events
- **Scrypt** : RFC 7914
- **Optimisation Flutter** : [https://docs.flutter.dev/perf](https://docs.flutter.dev/perf)
- **RepaintBoundary** : [https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)
- **Gestion d'état Flutter** : [https://docs.flutter.dev/development/data-and-backend/state-mgmt](https://docs.flutter.dev/development/data-and-backend/state-mgmt)

---

**Fin du document** - Retour à la [Documentation Principale](README.md)