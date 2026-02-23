# Navigation Adaptative (Progressive Disclosure) — TrocZen

Documentation complète de l'architecture de navigation adaptative (Février 2026).

---

## Architecture `MainShell` Dynamique

La navigation repose sur un `MainShell` utilisant un `IndexedStack` pour conserver l'état des vues. Cependant, contrairement à la V4 statique, la navigation s'adapte dynamiquement au **Mode d'Utilisation** (`AppMode`) choisi par l'utilisateur (Progressive Disclosure) pour réduire la surcharge cognitive.

```dart
Scaffold(
  body: IndexedStack(
    index: _currentTab, 
    children: _buildViews() // Dynamique : 2 ou 4 vues selon le mode
  ),
  bottomNavigationBar: NavigationBar(
    destinations: _buildDestinations() // S'adapte au mode
  ),
  floatingActionButton: _buildMainFAB(), // Contextuel au tab ET au mode
  drawer: _buildSettingsDrawer(), // Contenu filtré selon le mode
)
```

**Fichiers centraux :**
```text
lib/screens/main_shell.dart
lib/models/app_mode.dart
lib/providers/app_mode_provider.dart
```

---

## Les 3 Modes de Navigation

L'interface se métamorphose en fonction du "chapeau" porté par l'utilisateur :

| Mode | Nombre d'onglets | Vues intégrées |
| :--- | :---: | :--- |
| 🚶‍♂️ **Flâneur** | **2** | Wallet, Profil |
| 🧑‍🌾 **Artisan** | **4** | Wallet, Explorer, **Dashboard Simple**, Profil |
| 🧙‍♂️ **Alchimiste**| **4** | Wallet, Explorer, **Dashboard Avancé**, Profil |

---

## Détail des Vues

| Onglet | Vue | Fonction | FAB Associé |
|--------|-----|----------|-------------|
| **0** | `WalletView` | Bons P2 de l'utilisateur (galerie Panini). | 📷 Recevoir (Flâneur)<br>➕ Créer / 📷 Recevoir (Artisan+) |
| **1** | `ExploreView` | Marché local, P3 dispos et WoTx2 (Savoir-Faire). | *Aucun* |
| **2** | `DashboardSimpleView` | *[Artisan]* Métriques comptables simples (Solde, Entrées/Sorties, Historique). | 📤 Exporter |
| **2** | `DashboardView` | *[Alchimiste]* Analytics éco. (C², Alpha), requêtes au moteur DRAGON. | 📤 Exporter |
| **3** | `ProfileView` | Profil, clés Nostr, G1pub, Jauge Toile de Confiance (N1). | ✏️ Modifier |

*Note : `MerchantDashboardScreen` a été définitivement supprimé et remplacé par l'architecture à double dashboard (`DashboardSimpleView` / `DashboardView`).*

---

## Le Bouton d'Action Flottant (FAB) Contextuel

Le FAB change en fonction de l'onglet actif **et** du mode d'utilisation :

### En Mode Flâneur
- **Wallet (0)** : Uniquement le bouton "📷 Recevoir" (Scan QR).
- **Profil (1)** : Masqué.

### En Modes Artisan & Alchimiste
- **Wallet (0)** : **Double FAB** empilé.
  - "➕ Créer" (Ouvre `CreateBonScreen`)
  - "📷 Recevoir" (Ouvre `MirrorReceiveScreen`)
- **Explorer (1)** : Masqué.
- **Dashboard (2)** : "📤 Exporter" (les données comptables).
- **Profil (3)** : "✏️ Modifier" (Ouvre `UserProfileScreen`).

---

## Le Menu Latéral (Drawer) Adaptatif

Le Drawer centralise les paramètres avancés. Son contenu est filtré dynamiquement selon le mode :

### Toujours visible (Tous modes)
1. **Partager TrocZen** 📤 : Accès à `ApkShareScreen` (Serveur HTTP local + QR Code) pour distribution virale de l'APK.
2. **Changer de mode** 🔄 : Permet de basculer librement entre Flâneur, Artisan et Alchimiste.
3. **Envoyer un feedback** 💬 : Création automatique d'Issue GitHub via le backend proxy.
4. **Logs** 🐛 : Accès à l'historique technique (`LoggerService`).
5. **Relais Nostr / API** ⚙️ : Configuration des relais et de la graine.

### Fonctionnalités Avancées (Artisan + Alchimiste)
6. **Synchroniser Nostr** ⟳ : Déclenche le fetching des Kind 30303.

### Outils Techniques (Alchimiste uniquement)
7. **Exporter seed marché** 🔑 : Affiche le QR Code de la seed pour recruter.
8. **Vider cache P3** 🗑️ : Bouton d'urgence (avec confirmation).

---

## Écrans toujours accessibles via "Push"

Bien que non présents dans la barre de navigation, ces écrans restent accessibles contextuellement :
- `ScanScreen` / `MirrorReceiveScreen` — Via le FAB du Wallet.
- `CreateBonScreen` — Via le FAB du Wallet (Artisan+).
- `MarketScreen` — Via l'onglet Explorer (Rejoindre/Créer un marché).
- `BonJourneyScreen` — Via les détails d'un bon (Carnet de voyage / Révélation de circuit).
- `SettingsScreen` — Via le Drawer.

---

## Performances et UX

| Opération | Implémentation | Avantage |
|-----------|----------------|----------|
| **Changement d'onglet** | `IndexedStack` | **Instantané**, pas de rechargement des vues. |
| **Maintien d'état** | `AutomaticKeepAliveClientMixin` | Le scroll de la galerie de bons est conservé. |
| **Surcharge cognitive** | `AppModeProvider` | Les acheteurs ne voient pas les outils complexes des émetteurs. |
| **Sync massive** | Batching SQLite (`saveP3BatchToCache`) | Évite le Jank (freeze de l'UI) lors de la réception de centaines de bons. |

---

## État d'avancement (v1.0.9)

- [x] MainShell avec `IndexedStack` dynamique.
- [x] Implémentation du système `AppMode` (Progressive Disclosure).
- [x] Séparation `DashboardSimpleView` (Artisan) et `DashboardView` (Alchimiste).
- [x] Drawer adaptatif intégrant `ApkShareScreen`.
- [x] FAB empilé pour la vue Wallet.
- [x] Backend proxy feedback implémenté (`api_backend.py`).
- [x] Migration de `FlutterSecureStorage` vers SQLite pour le cache P3 (pour éviter les crashs OOM).
```

### Pourquoi ces modifications ?
1. **Cohérence totale avec le code :** Le fichier reflète maintenant l'utilisation de l'enum `AppMode`, du `MainShell` dynamique, du serveur d'APK (`ApkShareScreen`) et du double FAB empilé pour la création/réception de bons.
2. **Clarification de l'architecture :** Il explique pourquoi `MerchantDashboardScreen` n'existe plus (remplacé par les vues simples et avancées).
3. **Mise à jour des performances :** Mention du Batching SQLite qui a été mis en place pour régler les problèmes de freezes UI évoqués dans vos fichiers (`CacheDatabaseService`).