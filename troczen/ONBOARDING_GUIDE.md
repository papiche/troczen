# 🚀 Guide du Parcours d'Onboarding TrocZen

## Vue d'ensemble

Le parcours d'onboarding TrocZen est un processus guidé en 5 étapes qui permet aux utilisateurs de configurer leur application lors du premier lancement. Il détecte automatiquement l'absence de configuration et guide l'utilisateur de manière fluide et intuitive.

---

## 📋 Architecture

### Fichiers créés

```
lib/
├── models/
│   └── onboarding_state.dart          # Modèle d'état de l'onboarding
└── screens/
    └── onboarding/
        ├── onboarding_flow.dart        # Orchestrateur principal avec PageView
        ├── onboarding_seed_screen.dart       # Étape 1: Configuration de la seed
        ├── onboarding_advanced_screen.dart   # Étape 2: Configuration avancée
        ├── onboarding_nostr_sync_screen.dart # Étape 3: Synchronisation P3
        ├── onboarding_profile_screen.dart    # Étape 4: Création du profil
        └── onboarding_complete_screen.dart   # Étape 5: Récapitulatif
```

---

## 🎯 Détection du Premier Lancement

### Logique dans [`main.dart`](lib/main.dart)

La détection se fait dans la méthode `_checkExistingUser()` de `LoginScreen` :

```dart
Future<void> _checkExistingUser() async {
  // Vérifier d'abord si c'est un premier lancement
  final isFirstLaunch = await _storageService.isFirstLaunch();
  
  if (isFirstLaunch && mounted) {
    // Rediriger vers l'onboarding
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const OnboardingFlow(),
      ),
    );
    return;
  }
  
  // Sinon, vérifier l'utilisateur existant...
}
```

### Critères de Premier Lancement

Un premier lancement est détecté si :
- ✅ Aucune `seed_market` n'existe en stockage sécurisé
- ✅ Aucun utilisateur n'est enregistré
- ✅ Le flag `onboarding_complete` n'est pas défini

---

## 📱 Les 5 Étapes

### Étape 1️⃣ : Configuration de la Seed de Marché

**Fichier** : [`onboarding_seed_screen.dart`](lib/screens/onboarding/onboarding_seed_screen.dart)

**Objectif** : Choisir comment configurer la seed du marché local

**Options disponibles** :

#### 📷 Scanner une Seed
- Rejoindre un marché existant
- Scanner un QR code contenant une seed de 64 caractères hex
- Utilise `mobile_scanner`

#### 🎲 Générer une Seed
- Créer un nouveau marché
- Génération crypto-aléatoire avec `Random.secure()`
- 32 octets (64 caractères hex)
- Export QR pour partager avec d'autres participants
- Option de copie dans le presse-papiers

#### ☠️ Mode 000 (Hackathon)
- Seed de 32 zéros (intentionnellement vulnérable)
- **Double confirmation obligatoire** :
  1. Dialog d'avertissement
  2. Saisie manuelle du texte "HACKATHON"
- Réservé aux défis de sécurité et tests

**Code clé** :
```dart
void _generateSecureSeed() {
  final secureRandom = Random.secure();
  final seedBytes = Uint8List.fromList(
    List.generate(32, (_) => secureRandom.nextInt(256)),
  );
  final seedHex = HEX.encode(seedBytes);
  // Affichage QR et export...
}
```

---

### Étape 2️⃣ : Configuration Avancée (Optionnelle)

**Fichier** : [`onboarding_advanced_screen.dart`](lib/screens/onboarding/onboarding_advanced_screen.dart)

**Objectif** : Configurer les services réseau (relais Nostr, API, IPFS)

**Services configurables** :

| Service | Défaut | Box locale | Personnalisé |
|---------|--------|------------|--------------|
| **Relais Nostr** | `wss://relay.copylaradio.com` | `ws://zen.local:7777` | URL manuelle |
| **API REST** | `https://zen.copylaradio.com` | `http://zen.local:5000` | URL manuelle |
| **IPFS Gateway** | `https://ipfs.copylaradio.com` | `http://zen.local:8080` | URL manuelle |

**Fonctionnalités** :
- ✅ Bouton "Passer" pour utiliser les valeurs par défaut
- ✅ Test de connexion pour chaque service
- ✅ RadioListTile pour chaque option
- ✅ TextField conditionnel pour URLs personnalisées

**Tests de connectivité** :
```dart
// Relais Nostr - WebSocket
final channel = WebSocketChannel.connect(Uri.parse(url));

// API REST - HTTP HEAD
final response = await http.head(Uri.parse('$url/health'));

// IPFS - HTTP HEAD
final response = await http.head(Uri.parse(url));
```

---

### Étape 3️⃣ : Synchronisation P3 depuis Nostr

**Fichier** : [`onboarding_nostr_sync_screen.dart`](lib/screens/onboarding/onboarding_nostr_sync_screen.dart)

**Objectif** : Récupérer les P3 (preuves de provision) depuis le relais Nostr

**États progressifs affichés** :

1. 🔗 Connexion au relais Nostr...
2. 📡 Requête des événements kind:30303...
3. 🔓 Déchiffrement et stockage des P3...
4. ✅ Synchronisation terminée — N bons trouvés

**Gestion d'erreur** :
- Bouton "Réessayer" en cas d'échec
- Option "Passer (mode hors-ligne)"
- Possibilité de continuer sans synchronisation

**Retour arrière** :
- ❌ **Désactivé** après cette étape (seed générée)
- Empêche la navigation accidentelle après configuration

---

### Étape 4️⃣ : Création du Profil Nostr (et DU local)

**Fichier** : [`onboarding_profile_screen.dart`](lib/screens/onboarding/onboarding_profile_screen.dart)

**Objectif** : Créer l'identité de l'utilisateur sur le marché

#### Section A — Identité

| Champ | Type | Obligatoire |
|-------|------|-------------|
| **Nom affiché** | TextField | ✅ Oui |
| **Description** | TextField (3 lignes) | ❌ Non |
| **Photo de profil** | Image picker → IPFS | ❌ Non (v1.008+) |

#### Section B — Tags d'Activité

Chips sélectionnables multi-choix par catégorie :

**Alimentation** : Boulanger, Maraîcher, Fromager, Traiteur, Épicerie

**Services** : Artisan, Plombier, Électricien, Coiffeur, Réparateur

**Culture & Bien-être** : Musicien, Thérapeute, Yoga, Librairie, Café

**Artisanat** : Potier, Tisserand, Bijoutier, Menuisier, Couturier

**Personnalisé** : Saisie libre (v1.008+)

#### Section C — Clé Ğ1 (Optionnelle)

- Format Base58
- Facultatif pour v2.0.1+
- **Non requis** : Le système utilise désormais le **DU Nostr P2P** (création monétaire basée sur le graphe social)
- Peut servir pour interopérabilité future avec l'écosystème Ğ1/Duniter

**Publication Nostr** :
```dart
// Event kind 0 (profile metadata)
{
  kind: 0,
  content: JSON.stringify({
    name: displayName,
    about: description,
    picture: ipfsUrl ?? '',
    zen_tags: selectedTags,        // Extension TrocZen
    g1_pubkey: g1PublicKey ?? '',  // Extension TrocZen
  }),
  tags: selectedTags.map(t => ['t', t]),
}
```

---

### Étape 5️⃣ : Écran de Bienvenue

**Fichier** : [`onboarding_complete_screen.dart`](lib/screens/onboarding/onboarding_complete_screen.dart)

**Objectif** : Récapitulatif et finalisation de la configuration

**Animations** :
- ✨ FadeTransition (0.0 → 1.0)
- 📈 ScaleTransition (0.8 → 1.0)
- ⏱️ Durée : 1200ms avec courbe easeOutBack

**Récapitulatif affiché** :
- 👤 Nom du profil
- ☁️ Relais Nostr configuré
- 🔄 Nombre de P3 synchronisés
- 🏷️ Tags d'activité (2 premiers + compteur)

**Actions finales** :

1. Sauvegarder le marché avec la seed
2. Créer un utilisateur avec credentials temporaires
3. Dériver clés Nostr (npub/nsec)
4. Générer clé Ğ1 (g1pub) — optionnel, pour interopérabilité
5. Publier le profil sur Nostr (kind 0)
6. **Créer le Bon Zéro de bootstrap** (0 ẐEN, validité 28 jours)
7. Initialiser le calcul du DU local (graphe social Nostr)
8. Marquer l'onboarding comme complété
9. Navigation vers `WalletScreen`

> **Note** : Le Bon Zéro (0 ẐEN, TTL 28j) sert de "ticket d'entrée" sur le marché. Il évite l'asymétrie monétaire tout en permettant à l'utilisateur de participer aux échanges. À chaque transfert, l'app propose de suivre l'émetteur pour activer le DU. Voir [`docs/DU_NOSTR_P2P_FLOW.md`](../../docs/DU_NOSTR_P2P_FLOW.md) pour les détails.

---

## 🔐 Sécurité

### Gestion de la Seed

- **Génération** : `Random.secure()` pour 32 octets crypto-aléatoires
- **Stockage** : `FlutterSecureStorage` avec chiffrement Android
- **Export** : QR code pour partage contrôlé

### Mode 000 - Sécurité Intentionnellement Faible

⚠️ **AVERTISSEMENT** : Ce mode est volontairement vulnérable

**Restrictions** :
- Double confirmation obligatoire
- Avertissement explicite
- Saisie manuelle "HACKATHON"
- Réservé aux défis de sécurité

**Utilité** :
- Tests de sécurité
- Hackathons
- Démonstrations de vulnérabilité
- Recherche en cryptographie

---

## 📊 Gestion de l'État

### OnboardingState

Modèle centralisé pour tout le parcours :

```dart
class OnboardingState {
  String? seedMarket;        // Seed du marché (hex 64 chars)
  String? seedMode;          // 'scanned', 'generated', 'mode000'
  String relayUrl;           // URL du relais Nostr
  String apiUrl;             // URL de l'API REST
  String ipfsGateway;        // URL de la passerelle IPFS
  int p3Count;               // Nombre de P3 synchronisés
  bool syncCompleted;        // Flag de synchronisation
  String? displayName;       // Nom affiché
  String? about;             // Description
  List<String> activityTags; // Tags d'activité
  String? g1PublicKey;       // Clé publique Ğ1 (optionnelle, interopérabilité)
  String? marketName;        // Nom du marché
  // DU Nostr P2P : calculé dynamiquement via le graphe social (follows réciproques)
}
```

### OnboardingNotifier (ChangeNotifier)

Provider pour la gestion d'état réactif :

```dart
class OnboardingNotifier extends ChangeNotifier {
  void setSeedMarket(String seed, String mode);
  void setAdvancedConfig({String? relayUrl, ...});
  void setSyncCompleted(int p3Count);
  void setProfile({required String displayName, ...});
}
```

---

## 🎨 Interface Utilisateur

### Design System

**Couleurs** :
- Primary : `#FFB347` (orange zen)
- Secondary : `#0A7EA4` (bleu)
- Background : `#121212` (dark)
- Cards : `#2A2A2A`

**Typographie** :
- Titres : 28px, bold, orange
- Sous-titres : 16px, grey[400]
- Contenu : 14-18px, white

**Composants** :
- Cards arrondies (borderRadius: 16)
- Boutons primaires oranges
- Boutons secondaires outlined
- Progress indicator en haut (5 barres)

### Navigation

**PageView** avec contrôle programmatique :
- ✅ Swipe désactivé (`NeverScrollableScrollPhysics`)
- ✅ Navigation par boutons uniquement
- ✅ Retour arrière jusqu'à l'étape 3
- ❌ Retour bloqué après seed générée

---

## 🧪 Tests et Validation

### Scénarios de Test

#### Test 1 : Premier lancement complet
1. Lancer l'app sans données
2. Vérifier redirection vers onboarding
3. Générer une seed
4. Configurer les services (défaut)
5. Synchroniser les P3
6. Créer un profil
7. Vérifier navigation vers wallet

#### Test 2 : Scan de seed existante
1. Lancer l'onboarding
2. Scanner un QR code de seed
3. Vérifier la seed de 64 caractères
4. Continuer le parcours

#### Test 3 : Mode 000
1. Sélectionner "Mode 000"
2. Confirmer le premier dialog
3. Taper "HACKATHON"
4. Vérifier seed = "0" × 64

#### Test 4 : Configuration avancée
1. Tester chaque service
2. Saisir URL personnalisée
3. Tester la connectivité
4. Vérifier sauvegarde

#### Test 5 : Échec de synchronisation
1. Configurer avec relais invalide
2. Vérifier gestion d'erreur
3. Cliquer "Réessayer"
4. Tester "Passer (mode hors-ligne)"

---

## 📝 Notes d'Implémentation

### Dépendances Requises

Toutes déjà présentes dans `pubspec.yaml` :
- ✅ `provider` : Gestion d'état
- ✅ `mobile_scanner` : Scan QR
- ✅ `qr_flutter` : Génération QR
- ✅ `flutter_secure_storage` : Stockage sécurisé
- ✅ `http` : Tests de connectivité
- ✅ `web_socket_channel` : Nostr WebSocket
- ✅ `hex` : Conversion hex

### Améliorations Futures et en cours

- [ ] Upload photo de profil via IPFS
- [ ] Saisie libre de tags personnalisés
- [ ] Import/export complet de configuration
- [ ] Support multi-langues
- [ ] Animations Lottie pour les transitions
- [ ] Tutoriel interactif post-onboarding
- [ ] Sauvegarde backup de la seed
- [ ] Visualisation du graphe social (N1/N2) pour le DU
- [ ] Indicateur de confiance (nombre de follows réciproques)

---

## 🚨 Gestion d'Erreurs

### Erreurs Réseau

```dart
try {
  await nostrService.connect(relayUrl);
} catch (e) {
  // Afficher erreur + bouton réessayer
  // Option mode hors-ligne
}
```

### Erreurs de Validation

```dart
validator: (value) {
  if (value == null || value.isEmpty) {
    return 'Le nom est obligatoire';
  }
  return null;
}
```

### Erreurs de Scan

```dart
onDetect: (capture) {
  final seed = barcodes.first.rawValue;
  if (seed != null && seed.length == 64) {
    // Seed valide
  } else {
    // Afficher erreur format
  }
}
```

---

## 📞 Support

Pour toute question ou problème :
- 📧 Email : support@troczen.io
- 💬 Discord : TrocZen Community
- 🐛 Issues : GitHub Repository

---

**Version** : 1.007  
**Date** : 2026-02-18  
**Auteur** : Équipe TrocZen  
**Licence** : AGPL-3.0
