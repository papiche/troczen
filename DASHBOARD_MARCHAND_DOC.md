# 📊 Dashboard Marchand TrocZen - Documentation Technique

## Vue d'ensemble

Le Dashboard Marchand est un outil d'analytics économique **100% offline** basé uniquement sur les métadonnées P3 (kind 30303 Nostr). Il ne nécessite **aucune donnée client** et respecte totalement la vie privée.

### ✨ Deux dashboards selon le profil utilisateur

L'application propose **deux interfaces de dashboard** adaptées aux différents profils :

#### 📊 Dashboard Commerçant (`dashboard_view.dart`)
- **Public cible** : Commerçants, Ambassadeurs, Organisateurs
- **Niveau** : Analytics avancées avec graphiques et statistiques détaillées
- **Fonctionnalités** :
  - 3 onglets (TabController) : Vue globale, Circulation, Réseau
  - Support multi-marchés avec filtres
  - Graphiques fl_chart (LineChart, BarChart)
  - Métriques économiques avancées
  - Analyse temporelle et géographique

#### 📋 Dashboard Artisan (`dashboard_simple_view.dart`)
- **Public cible** : Artisans, nouveaux utilisateurs
- **Niveau** : Vision comptable simple et claire
- **Fonctionnalités** :
  - Solde total en ẐEN
  - Entrées/sorties hebdomadaires
  - Compteurs simples (actifs, expirés, utilisés)
  - Liste des dernières transactions
  - Interface épurée sans complexité

> 💡 **Sélection automatique** : Le dashboard affiché dépend du `AppMode` de l'utilisateur défini lors de l'onboarding.

### 🌍 Support Multi-Marchés

Les dashboards supportent désormais **plusieurs marchés simultanés** :

- **Filtre global** : Voir tous les marchés combinés (`_filterMode = 'all'`)
- **Filtre par marché** : Isoler les métriques d'un marché spécifique
- **Méthodes de filtrage** :
  - `_getFilteredMarketBons()` : Filtre les événements kind 30303
  - `_getFilteredLocalBons()` : Filtre les bons du wallet local
- **Chargement parallèle** : Markets chargés via `Future.wait()`

---

## 🎯 Principes Fondamentaux

### Règle d'Or
> **Si un calcul nécessite P2 ou une identité client → il est interdit.**

### Sources de Données Autorisées
- ✅ Events **kind 30303** (P3 chiffrés)
- ✅ Events **kind 1** (transferts anonymes)
- ✅ Timestamps locaux
- ❌ Identités clients
- ❌ Parts P2 (possession)
- ❌ Parts P1 (ancre privée)

---

## 📐 Formules Mathématiques

### 0️⃣ Notations

#### Ensembles
- `B` = ensemble des bons observés (events kind 30303 déchiffrés)
- `B_active ⊂ B` = bons non expirés
- `T` = ensemble des events kind 1 liés aux bons
- `T(b)` = events kind 1 référençant le bon `b`

#### Champs P3
Pour un bon `b ∈ B` :

| Champ | Notation | Description |
|-------|----------|-------------|
| `created_at` | `b.t0` | Timestamp création |
| `expiry` | `b.t_exp` | Timestamp expiration |
| `value` | `b.v` | Valeur en ẐEN |
| `market` | `b.m` | ID marché |
| `issuer` | `b.i` | npub émetteur |
| `category` | `b.c` | Catégorie produit |
| `rarity` | `b.r` | Niveau rareté |

#### Temps
- `now` = timestamp local courant
- `Δt(x,y) = y − x`

---

### 1️⃣ Bons Actifs

**Définition :**
```
B_active = { b ∈ B | b.t_exp > now }
```

**Nombre de bons actifs :**
```dart
N_active = |B_active|
```

**Code :**
```dart
final activeBons = bons.where((b) => 
  b.expiresAt != null && b.expiresAt!.isAfter(DateTime.now())
).toList();
```

---

### 2️⃣ Valeur Totale en Circulation

**Formule :**
```
V_total = Σ (b.v)  pour tout b ∈ B_active
```

**Code :**
```dart
final totalValue = activeBons.fold<double>(
  0.0,
  (sum, b) => sum + b.value,
);
```

**Interprétation UX :**
> "Valeur vivante sur le marché"

---

### 3️⃣ Bons Émis (sur période)

**Pour une période `[t1, t2]` :**
```
B_issued(t1,t2) = { b ∈ B | t1 ≤ b.t0 ≤ t2 }
N_issued = |B_issued|
V_issued = Σ(b.v) pour b ∈ B_issued
```

**Code :**
```dart
final issuedToday = bons.where((b) {
  final today = DateTime.now();
  return b.createdAt.day == today.day &&
         b.createdAt.month == today.month &&
         b.createdAt.year == today.year;
}).toList();
```

---

### 4️⃣ Encaissements (bons brûlés)

**Définition :**
Un bon `b` est considéré **encaissé** si :
```
∃ e ∈ T(b) tel que e.kind = 1 AND e.tag = "burn"
```

**Nombre encaissé :**
```
N_burn = |{ b ∈ B | burned(b) }|
```

**Valeur encaissée :**
```
V_burn = Σ(b.v) pour tout b encaissé
```

**Code :**
```dart
final burnedBons = bons.where((b) => 
  b.status == BonStatus.burned
).length;
```

---

### 5️⃣ Taux d'Encaissement

**Formule :**
```
Encash_rate = N_burn / |B|
```

**Ou en valeur :**
```
Encash_value_rate = V_burn / Σ(b.v)
```

**Code :**
```dart
final encashRate = bons.isNotEmpty 
  ? burnedBons / bons.length 
  : 0.0;
```

**UX :** Jauge 🟢🟡🔴
- 🟢 ≥ 70%
- 🟡 40-69%
- 🔴 < 40%

---

### 6️⃣ Bons Expirés

**Définition :**
```
b est expiré si: b.t_exp ≤ now AND NOT burned(b)
```

**Nombre :**
```
N_expired = |{ b ∈ B | expired(b) }|
```

**Taux d'expiration :**
```
Expire_rate = N_expired / |B|
```

**Code :**
```dart
final expiredBons = bons.where((b) => 
  b.expiresAt != null && 
  b.expiresAt!.isBefore(now) && 
  b.status != BonStatus.burned
).length;
```

---

### 7️⃣ Vitesse de Circulation

**Cas A — avec kind 1 (recommandé) :**

Pour chaque bon `b` :
```
t_last(b) = max( e.created_at ) pour e ∈ T(b)
Circulation_delay(b) = t_last(b) − b.t0
```

**Moyenne globale :**
```
Speed_avg = mean( Circulation_delay(b) )
```

**Interprétation UX :**
- 🟢 Rapide : < 30 min
- 🟡 Normal : 30-120 min
- 🔴 Lent : > 2h

**Code :**
```dart
final circulationSpeeds = <int>[];
for (final bon in bons) {
  if (bon.transferCount != null && bon.transferCount! > 0) {
    final age = DateTime.now().difference(bon.createdAt).inMinutes;
    final speed = age ~/ bon.transferCount!;
    circulationSpeeds.add(speed);
  }
}
final avgSpeed = circulationSpeeds.isNotEmpty
  ? circulationSpeeds.reduce((a, b) => a + b) / circulationSpeeds.length
  : 0.0;
```

---

### 8️⃣ Intensité Temporelle (Heures Chaudes)

**Pour une heure `h` (0-23) :**
```
Flow(h) = |{ b ∈ B | hour(b.t0) = h }|
```

**Ou avec encaissements :**
```
Flow_burn(h) = |{ e ∈ T | hour(e.created_at) = h }|
```

**Code :**
```dart
final hourlyFlow = List.generate(24, (_) => 0);
for (final bon in bons) {
  final hour = bon.createdAt.hour;
  hourlyFlow[hour]++;
}
```

**UX :** Heatmap horaire avec LineChart

---

### 9️⃣ Distribution par Valeur

**Pour une valeur `v` :**
```
Count(v) = |{ b ∈ B | b.v = v }|
Share(v) = Count(v) / |B|
```

**Code :**
```dart
final valueDistribution = <double, int>{};
for (final bon in bons) {
  valueDistribution[bon.value] = 
    (valueDistribution[bon.value] ?? 0) + 1;
}
```

**UX :** Barres horizontales avec pourcentages

---

### 🔟 Distribution par Catégorie

**Formule :**
```
Count(c) = |{ b ∈ B | b.c = c }|
```

**Code :**
```dart
final categoryDistribution = <String, int>{};
for (final bon in bons) {
  final category = bon.category ?? 'autre';
  categoryDistribution[category] = 
    (categoryDistribution[category] ?? 0) + 1;
}
```

---

### 1️⃣1️⃣ Indice de Rareté (Gamification)

**Définition locale simple :**
```
Rarity_index(b) = 1 / Count(b.r)
```

**Ou normalisé :**
```
Rarity_score(b) = 
  if b.r = "common" → 1
  if b.r = "uncommon" → 2
  if b.r = "rare" → 3
  if b.r = "legendary" → 5
```

**Code :**
```dart
int getRarityScore(String rarity) {
  switch (rarity) {
    case 'legendary': return 5;
    case 'rare': return 3;
    case 'uncommon': return 2;
    default: return 1;
  }
}
```

---

### 1️⃣2️⃣ Réseau Marchand (Acceptation Croisée)

**Définition :**
Si un bon `b` est brûlé par un autre marchand `i₂ ≠ b.i` :
```
Accepted_by_others(b) = true
```

**Taux réseau :**
```
Network_rate = |{ b | Accepted_by_others(b) }| / |B|
```

**Code :**
```dart
final acceptedByOthers = transfers.where((t) =>
  t['receiver_npub'] != merchantNpub &&
  bons.any((b) => b.bonId == t['bon_id'])
).length;

final networkRate = bons.isNotEmpty 
  ? acceptedByOthers / bons.length 
  : 0.0;
```

---

### 1️⃣3️⃣ Score "Santé du Stand"

**Score normalisé [0-100] :**
```
Health = 
  30 × norm(Encash_rate)
+ 30 × norm(1 / Speed_avg)
+ 20 × norm(1 − Expire_rate)
+ 20 × norm(Network_rate)
```

Où `norm(x)` ∈ [0,1] (clamp local).

**Code :**
```dart
double calculateHealthScore({
  required double encashRate,
  required double expireRate,
  required double avgSpeed,
  required double networkRate,
}) {
  final encashScore = encashRate * 30;
  final speedScore = avgSpeed > 0 
    ? (1 / (avgSpeed / 60)) * 30 
    : 0;
  final expireScore = (1 - expireRate) * 20;
  final networkScore = networkRate * 20;

  return (encashScore + speedScore + expireScore + networkScore)
    .clamp(0, 100);
}
```

**UX :**
- 🟢 ≥ 70 → Fluide
- 🟡 40-69 → Attention
- 🔴 < 40 → Problème

---

## 🎨 Architecture du Dashboard

### 3 Écrans Principaux

#### 1️⃣ Vue Live (Stand Live)
**Usage :** Ouvert en permanence sur tablette
**Fréquence MAJ :** Temps réel

**Métriques affichées :**
- Bons actifs
- Valeur totale
- Vitesse circulation (sparkline)
- Dernier encaissement
- Alertes (expirations proches)
- Score santé

---

#### 2️⃣ Analyse Détaillée
**Usage :** Fin de marché / moments calmes
**Fréquence MAJ :** À la demande

**Sections :**
- Flux temporel (graphique horaire)
- Taux d'encaissement (stats détaillées)
- Distribution par valeur (barres)
- Distribution par rareté
- Circulation réseau

---

#### 3️⃣ Pilotage & Actions
**Usage :** Gestion opérationnelle
**Actions disponibles :**
- ➕ Émettre un bon
- ♻️ Réémettre un bon perdu
- 🔥 Révoquer un bon (P1 + event)
- 📤 Export PDF
- 📊 QR Statistiques publiques

---

## 🎨 Code Couleur UX

| Couleur | Usage | Sémantique |
|---------|-------|------------|
| 🟢 Vert | ≥ 70% | Circule bien |
| 🟡 Jaune | 40-69% | Attention |
| 🔴 Rouge | < 40% | Problème |
| 🔵 Bleu | Info | Neutre |
| 🟠 Orange | Alerte | Non critique |

---

## 📊 Widgets Utilisés

### Graphiques (fl_chart)
- **LineChart** : Flux temporel horaire
- **BarChart** : Distribution valeurs (si besoin)
- **PieChart** : Distribution rareté (optionnel)

### Indicateurs
- **LinearProgressIndicator** : Taux encaissement
- **Sparkline bars** : Vitesse circulation
- **Circular score** : Santé du stand

---

## 🔐 Conformité Vie Privée

### Ce qui est analysé ✅
- Nombre de bons
- Valeurs faciales
- Timestamps création
- Rareté (metadata)
- Catégories produits
- Expirations

### Ce qui n'est JAMAIS analysé ❌
- Identités clients
- Parts P2 (possession)
- Localisation GPS clients
- Historique achats personnels
- Données biométriques

---

## 📈 Performance

### Calculs Offline
- **Tous les calculs** : 100% local (SQLite)
- **Pas de serveur** requis
- **Pas de réseau** requis (hors sync P3)

### Complexité
- Bons actifs : O(n)
- Valeur totale : O(n)
- Distributions : O(n)
- Flux horaire : O(n)
- **Total dashboard** : O(n) où n = nombre de bons

### Optimisation
- Mise en cache des métriques
- Recalcul uniquement si nouveaux bons
- Index SQLite sur timestamps

---

## 🧪 Tests Recommandés

### Test 1 : Cohérence Métriques
```dart
test('Total bons = actifs + expirés + brûlés', () {
  expect(
    metrics.totalBons,
    equals(metrics.activeBons + metrics.expiredBons + metrics.burnedBons),
  );
});
```

### Test 2 : Taux dans [0,1]
```dart
test('Tous les taux entre 0 et 1', () {
  expect(metrics.encashRate, inRange(0, 1));
  expect(metrics.expireRate, inRange(0, 1));
  expect(metrics.networkRate, inRange(0, 1));
});
```

### Test 3 : Score santé [0,100]
```dart
test('Score santé entre 0 et 100', () {
  expect(metrics.healthScore, inRange(0, 100));
});
```

---

## 📖 Utilisation

### Navigation

L'affichage est géré dynamiquement par le MainShell selon l'AppMode :
Mode Artisan (1) -> DashboardSimpleView
Mode Alchimiste (2) -> DashboardView

---

## 🎯 Avantages Compétitifs

Ce dashboard donne aux marchands un **super-pouvoir que le cash n'a jamais eu** :

1. **Visibilité économique temps réel**
2. **Aucune dépendance serveur central**
3. **Respect total vie privée**
4. **Fonctionne 100% offline**
5. **Gamification sans spéculation**
6. **Analyse sans surveillance**

---

## 🚀 Évolutions Futures

### V2
- [ ] Export PDF automatique fin marché
- [ ] Notifications push (expirations)
- [ ] Comparaison avec autres marchands
- [ ] Prédiction flux (ML local)

### V3
- [ ] Mode multi-marchés
- [ ] Analyse saisonnière
- [ ] Recommandations IA
- [ ] Intégration comptabilité

---

## 📝 Conclusion

Le Dashboard Marchand transforme les **métadonnées P3 en intelligence économique locale** tout en respectant :
- ✅ L'offline-first
- ✅ L'anonymat client
- ✅ La décentralisation
- ✅ La vie privée

**Aucune donnée client. Juste de l'économie pure.** 🎯
