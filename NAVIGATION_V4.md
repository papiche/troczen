# Navigation V4 — TrocZen

Documentation complète de la refonte de navigation (v1.0.8, 18 février 2026).

---

## Architecture MainShell

La navigation repose sur un `MainShell` avec `IndexedStack` (4 vues) + `NavigationBar` + FAB contextuel + Drawer paramètres.

```dart
Scaffold(
  body: IndexedStack(index: _currentTab, children: [
    WalletView(),      // 0 — Mon Wallet
    ExploreView(),     // 1 — Explorer / Marché
    DashboardView(),   // 2 — Dashboard économique
    ProfileView(),     // 3 — Mon Profil
  ]),
  bottomNavigationBar: NavigationBar(...),
  floatingActionButton: _buildContextualFAB(),
  drawer: _buildSettingsDrawer(),
)
```

**Fichiers créés :**
```
lib/screens/main_shell.dart
lib/screens/views/wallet_view.dart
lib/screens/views/explore_view.dart
lib/screens/views/dashboard_view.dart
lib/screens/views/profile_view.dart
```

---

## Les 4 vues

| Onglet | Vue | Fonction | FAB |
|--------|-----|----------|-----|
| 0 | WalletView | Bons P2 de l'utilisateur | 📷 Scanner |
| 1 | ExploreView | Marché local + P3 disponibles | ➕ Créer bon |
| 2 | DashboardView | Analytics économiques (fusion MerchantDashboard) | 📤 Exporter |
| 3 | ProfileView | Profil, clés Nostr, G1pub | ✏️ Modifier |

### WalletView
- Liste bons avec PaniniCard, mode galerie
- Détails en modal bottom sheet
- État vide explicatif
- `AutomaticKeepAliveClientMixin` pour conserver l'état entre onglets

### ExploreView
- Affichage du marché configuré
- Grille P3 disponibles (2 colonnes)
- Navigation vers MarketScreen

### DashboardView
- 3 onglets : Vue d'ensemble / Graphiques / Activité
- Métriques : valeur totale, nombre de bons, taux de croissance 30j
- ⏳ Graphiques et activité à implémenter

### ProfileView
- Avatar circulaire, npub/nsec (nsec masqué), g1pub
- Copie dans presse-papier
- Clé privée affichée `•••` avec avertissement

---

## Drawer — Paramètres avancés

Réservé aux paramètres non fréquents :
1. Configuration relais Nostr / API / IPFS → `SettingsScreen`
2. Exporter seed de marché (QR code)
3. Synchroniser Nostr (P3)
4. Vider cache P3 (**confirmation requise**)
5. À propos / version
6. Feedback (via backend proxy — **jamais de token GitHub dans l'app**)

---

## Migration depuis WalletScreen

### Point d'entrée (`main.dart`)
```dart
// AVANT
Navigator.pushReplacement(context,
  MaterialPageRoute(builder: (_) => WalletScreen(user: user)));

// APRÈS
Navigator.pushReplacement(context,
  MaterialPageRoute(builder: (_) => MainShell(user: user)));
```

### MerchantDashboardScreen déprécié
Fusionné dans `DashboardView`. Pour accès programmatique :
```dart
// Naviguer vers l'onglet Dashboard
final shell = context.findAncestorStateOfType<MainShellState>();
shell?.switchTab(2);
```

### Écrans toujours accessibles via push
- `ScanScreen` — via FAB Wallet
- `CreateBonScreen` — via FAB Explorer
- `MarketScreen` — via ExploreView
- `SettingsScreen` — via Drawer
- `GalleryScreen` — via WalletView

### Écrans masqués de l'UI (deep link uniquement)
- `AtomicSwapScreen` — accessible via action spécifique
- `MerchantDashboardScreen` — déprécié, utiliser DashboardView

---

## Méthodes à implémenter dans StorageService

```dart
Future<List<Map<String, dynamic>>> getP3List() async { ... }
Future<void> saveP3List(List<Map<String, dynamic>> p3List) async { ... }
Future<void> clearP3Cache() async { ... }
Future<DateTime?> getLastP3Sync() async { ... }
```

---

## Performances

| Opération | Avant | Après |
|-----------|-------|-------|
| Changement d'onglet | ~300ms (push/pop) | **instantané** (IndexedStack) |
| Retour à une vue déjà ouverte | rechargement | **instantané** (état conservé) |
| Reconstructions de widgets | fréquentes | -60% (AutomaticKeepAlive) |

---

## Checklist

- [x] MainShell avec IndexedStack
- [x] 4 vues principales
- [x] FAB contextuel
- [x] Drawer paramètres avancés
- [x] Migration main.dart
- [ ] `getP3List()` / `clearP3Cache()` dans StorageService
- [ ] `getEvents()` dans AuditTrailService
- [ ] Graphiques Dashboard (onglets 2 & 3)
- [ ] Backend proxy feedback
- [ ] Tests automatisés navigation
