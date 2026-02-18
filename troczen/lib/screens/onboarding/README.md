# 📱 Parcours d'Onboarding TrocZen

Ce répertoire contient tous les écrans du parcours de première configuration de TrocZen.

## 📁 Structure

```
onboarding/
├── onboarding_flow.dart              # Orchestrateur principal (PageView)
├── onboarding_seed_screen.dart       # Étape 1: Seed du marché
├── onboarding_advanced_screen.dart   # Étape 2: Config avancée
├── onboarding_nostr_sync_screen.dart # Étape 3: Sync P3
├── onboarding_profile_screen.dart    # Étape 4: Profil utilisateur
└── onboarding_complete_screen.dart   # Étape 5: Récapitulatif
```

## 🎯 Workflow Complet

```
┌─────────────────────┐
│   Premier Lancement │
│   (main.dart)       │
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│  OnboardingFlow     │ ◄─── PageView avec 5 étapes
│  (Provider)         │
└──────────┬──────────┘
           │
           v
    ┌──────────────┐
    │   Étape 1    │  Scanner / Générer / Mode 000
    │   Seed       │
    └──────┬───────┘
           │
           v
    ┌──────────────┐
    │   Étape 2    │  Relais / API / IPFS (optionnel)
    │   Config     │
    └──────┬───────┘
           │
           v
    ┌──────────────┐
    │   Étape 3    │  Synchronisation P3 depuis Nostr
    │   Sync       │  (pas de retour après cette étape)
    └──────┬───────┘
           │
           v
    ┌──────────────┐
    │   Étape 4    │  Nom, tags, clé Ğ1
    │   Profil     │
    └──────┬───────┘
           │
           v
    ┌──────────────┐
    │   Étape 5    │  Récapitulatif + finalisation
    │   Complete   │
    └──────┬───────┘
           │
           v
    ┌──────────────┐
    │ WalletScreen │  Application principale
    └──────────────┘
```

## 🔑 Points Clés

### 1. Détection Premier Lancement

La détection se fait dans `main.dart` via `StorageService.isFirstLaunch()` :

```dart
final isFirstLaunch = await _storageService.isFirstLaunch();
if (isFirstLaunch) {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (_) => const OnboardingFlow()),
  );
}
```

### 2. Gestion d'État

Utilise `Provider` avec `OnboardingNotifier` :

```dart
ChangeNotifierProvider(
  create: (_) => OnboardingNotifier(),
  child: // PageView avec les 5 écrans
)
```

### 3. Navigation

- **Forward** : Boutons "Continuer" dans chaque écran
- **Backward** : Bouton "Retour" jusqu'à l'étape 3
- **Blocage** : Après l'étape 3 (seed générée), retour impossible

### 4. Sécurité Seed

**Mode Sécurisé** (recommandé) :
```dart
final secureRandom = Random.secure();
final seedBytes = Uint8List.fromList(
  List.generate(32, (_) => secureRandom.nextInt(256))
);
```

**Mode 000** (vulnérable, défi sécurité) :
- Double confirmation obligatoire
- Saisie manuelle "HACKATHON"
- Seed = "0" × 64

## 📊 Données Sauvegardées

À la fin de l'onboarding :

1. **Market** (Storage)
   - `name` : Nom du marché
   - `seedMarket` : Seed hex 64 chars
   - `relayUrl` : URL du relais Nostr
   - `validUntil` : Date d'expiration

2. **User** (Storage)
   - `npub` : Clé publique Nostr
   - `nsec` : Clé privée Nostr (chiffrée)
   - `displayName` : Nom affiché
   - `g1pub` : Clé publique Ğ1

3. **Profil Nostr** (Publié)
   - Event `kind: 0`
   - Extensions TrocZen : `zen_tags`, `g1_pubkey`

4. **Flag** (Storage)
   - `onboarding_complete` : true

## 🎨 Design Tokens

```dart
// Couleurs
const primaryColor = Color(0xFFFFB347);     // Orange zen
const backgroundColor = Color(0xFF121212);   // Dark
const cardColor = Color(0xFF2A2A2A);        // Cards

// Bordures
BorderRadius.circular(12)  // Boutons
BorderRadius.circular(16)  // Cards

// Animations
Duration(milliseconds: 300)  // Navigation
Duration(milliseconds: 1200) // Écran final
```

## 🧪 Tests Recommandés

1. ✅ Premier lancement → Onboarding affiché
2. ✅ Génération seed → QR exportable
3. ✅ Scan seed → Seed de 64 chars acceptée
4. ✅ Mode 000 → Double confirmation
5. ✅ Config avancée → Tests de connectivité
6. ✅ Sync échec → Boutons réessayer/passer
7. ✅ Profil → Validation nom obligatoire
8. ✅ Complete → Navigation vers wallet
9. ✅ Retour bloqué → Après étape 3
10. ✅ Flag onboarding → Pas de re-déclenchement

## 📦 Dépendances Utilisées

- `provider` : Gestion d'état
- `mobile_scanner` : Scanner QR
- `qr_flutter` : Générer QR
- `flutter_secure_storage` : Storage sécurisé
- `http` : Tests connectivité
- `web_socket_channel` : WebSocket Nostr
- `hex` : Conversion hex

## 🔄 Modifications Futures

Pour ajouter une étape :

1. Créer `onboarding_new_screen.dart`
2. Ajouter dans `OnboardingFlow.children[]`
3. Incrémenter le compteur d'étapes (5 → 6)
4. Mettre à jour `OnboardingState` si besoin
5. Ajouter méthode dans `OnboardingNotifier`

## 📝 Notes Importantes

⚠️ **IMPORTANT** :
- Ne jamais exposer la seed en logs
- Toujours utiliser `FlutterSecureStorage`
- Valider la seed (64 chars hex)
- Bloquer le retour après génération
- Tester sur vrais devices (NFC, caméra)

✨ **BEST PRACTICES** :
- UX fluide avec animations
- Messages d'erreur clairs
- Options de secours (mode hors-ligne)
- Tests de connectivité
- Feedback visuel en temps réel

---

**Version** : 1.007  
**Dernière mise à jour** : 2026-02-18
