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


## 📱 Les 6 Étapes du Parcours (Code Actuel)

### Étape 1️⃣ : Création du Compte (Identifiants Cryptographiques)

**Fichier** : [`onboarding_account_screen.dart`](lib/screens/onboarding/onboarding_account_screen.dart)

**Objectif** : Générer l'identité cryptographique de l'utilisateur de manière déterministe via Scrypt.

**Fonctionnement** :
- **Login (Salt)** et **Mot de passe (Pepper)** saisis par l'utilisateur.
- La dérivation (Scrypt) se fait dans un **Isolate** en arrière-plan (`_deriveSeedInIsolate`) pour ne pas bloquer l'UI.
- **Génération automatique** des clés Nostr (`nsec`/`npub`) et de la clé publique Ğ1 (`g1pub`).
- **Création silencieuse du marché** : Le système initialise automatiquement le "Marché Libre" (seed `000...0`) en arrière-plan et configure l'état pour la suite du parcours.

**Code clé** :
```dart
final seedBytes = await compute(_deriveSeedInIsolate, {
  'salt': salt,
  'pepper': pepper,
});
final privateKeyBytes = await cryptoService.deriveNostrPrivateKey(seedBytes);
// Initialisation silencieuse du marché global
final market = await storageService.initializeDefaultMarket(name: 'Marché Libre');
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
- ✅ Test de connexion en temps réel pour chaque service
- ✅ Détection dynamique des configurations

---

### Étape 3️⃣ : Synchronisation P3 depuis Nostr

**Fichier** :[`onboarding_nostr_sync_screen.dart`](lib/screens/onboarding/onboarding_nostr_sync_screen.dart)

**Objectif** : Récupérer les P3 (preuves de provision) existantes sur le relais Nostr.

**États progressifs affichés** :
1. 🔗 Connexion au relais Nostr...
2. 📡 Requête des événements kind:30303...
3. 🔓 Déchiffrement et stockage des P3 dans SQLite (`CacheDatabaseService`)...
4. ✅ Synchronisation terminée — N bons trouvés

**Gestion d'erreur** :
- Bouton "Réessayer" en cas d'échec.
- Option "Passer (mode hors-ligne)".
- ❌ **Retour arrière désactivé** à partir d'ici pour éviter la corruption de l'état cryptographique.

---

### Étape 4️⃣ : Création du Profil Nostr

**Fichier** :[`onboarding_profile_screen.dart`](lib/screens/onboarding/onboarding_profile_screen.dart)

**Objectif** : Créer l'identité publique de l'utilisateur sur le marché. *(Note : La clé Ğ1 n'est plus demandée, elle a été dérivée automatiquement à l'Étape 1).*

#### Section A — Identité
- **Nom affiché** : Obligatoire.
- **Description** : Facultatif.
- **Avatar & Bannière** : Image picker. Compressions drastiques (< 4Ko) et génération instantanée des miniatures Base64 pour garantir une UX parfaite même en mode hors-ligne.

#### Section B — Tags d'Activité (Savoir-Faire)
- Sélection de tags par catégorie.
- **Normalisation stricte** (`NostrUtils.normalizeSkillTag`) pour éviter l'éparpillement sémantique ("Artisan" devient "artisan").
- Chargement dynamique des tags existants sur le réseau via `Kind 30500`.

---

### Étape 5️⃣ : Sélection du Mode d'Utilisation (Le Chapeau)

**Fichier** :[`onboarding_mode_selection_screen.dart`](lib/screens/onboarding/onboarding_mode_selection_screen.dart)

**Objectif** : Adapter l'interface au profil de l'utilisateur (*Progressive Disclosure*) pour réduire la surcharge cognitive.

**3 Profils Disponibles** :
- 🚶‍♂️ **Flâneur** : Interface ultra-simplifiée pour les clients (Scanner, Recevoir, Payer).
- 🧑‍🌾 **Artisan** : Interface métier pour les producteurs. Ajoute la création de bons et le "Dashboard Simple" (caisse, entrées, sorties).
- 🧙‍♂️ **Alchimiste** : Interface experte. Débloque le "Dashboard Avancé" (graphiques, C², Alpha, vitesse de circulation), les exports CSV, et la modération du réseau de confiance (WoTx2).

---

### Étape 6️⃣ : Écran de Bienvenue et Finalisation

**Fichier** :[`onboarding_complete_screen.dart`](lib/screens/onboarding/onboarding_complete_screen.dart)

**Objectif** : Récapitulatif et orchestration finale en arrière-plan.

**Actions finales déclenchées par le bouton "Entrer dans TrocZen"** :

1. Récupération de l'utilisateur généré à l'Étape 1.
2. **Upload IPFS Synchrone/Asynchrone** des images (Avatar et Bannière) via `ApiService`.
3. Publication du profil sur Nostr (`kind 0`) avec les URL IPFS finales.
4. Publication des demandes d'attestation de compétences (`kind 30501`) en arrière-plan.
5. **Génération du Bon Zéro** (0 ẐEN, TTL 28 jours) pour le bootstrap social.
6. Vérification du presse-papier : si un `npub` est détecté (via un lien d'invitation), la personne est suivie automatiquement (`kind 3`).
7. Marquage de l'onboarding comme terminé et redirection vers `MainShell`.

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

## 📞 Support

Pour toute question ou problème :
- 📧 Email : support@qo-op.com
- 🐛 Issues : GitHub Repository

---

**Version** : 1.008
**Date** : 2026-03-01  
**Auteur** : Équipe TrocZen  
**Licence** : AGPL-3.0
