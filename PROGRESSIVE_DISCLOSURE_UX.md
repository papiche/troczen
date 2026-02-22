# 🎨 Progressive Disclosure UX - Les 3 Modes d'Utilisation de TrocZen

## Vue d'ensemble

TrocZen implémente le principe de **Progressive Disclosure** (Divulgation Progressive) pour adapter l'interface selon le profil utilisateur et réduire la surcharge cognitive.

Au lieu de présenter toutes les fonctionnalités avancées (C², hyper-relativisme, WoTx2) à un utilisateur lambda qui veut juste "payer son pain", l'application propose **3 modes d'usage distincts** :

---

## 🚶‍♂️ Mode 1 : "Flâneur" (Client / Acheteur)

**C'est le mode par défaut.** M. et Mme Tout-le-monde qui viennent au marché.

### Objectif
Recevoir, stocker et dépenser des bons ẐEN. Zéro friction.

### Navigation réduite (2 onglets)
- 💳 **Mon Wallet** : Ses bons, et un gros bouton "Scanner pour Payer/Recevoir"
- 👤 **Mon Profil** : Son QR Code, et sa "Toile de confiance" basique (combien de commerçants il suit)

### Ce qui est caché
- Le Dashboard économique
- La création de bons avancée (sauf le Bon Zéro d'amorce)
- Les attestations de Savoir-Faire
- Les métriques économiques complexes (C², Alpha, etc.)

---

## 🧑‍🌾 Mode 2 : "Artisan" (Commerçant / Producteur)

L'acteur économique local qui vend ses produits et fidélise.

### Objectif
Émettre des bons, gérer sa caisse, voir si la journée a été bonne.

### Navigation standard (4 onglets)
- 💳 **Caisse (Wallet)** : Payer/Encaisser
- 🏷️ **Explorer** : Créer des bons (réductions, préventes)
- 📊 **Tableau de bord (Simple)** : Chiffre d'affaires en ẐEN, bons actifs, bons expirés. Des métriques "comptables" classiques
- 👤 **Profil** : Gérer son identité

### Ce qui est caché
- Les mathématiques de la TRM (C², alpha)
- Le WoTx2 complexe
- Les métriques économiques avancées

### Dashboard Simple
Le `DashboardSimpleView` affiche :
- **Solde total** en ẐEN avec nombre de bons actifs
- **Résumé hebdomadaire** : Bons reçus vs émis
- **État des bons** : Actifs, utilisés, expirés (avec code couleur)
- **Dernières transactions** : Liste des 10 dernières opérations

---

## 🧙‍♂️ Mode 3 : "Alchimiste" (Tisseur / Expert Économique)

Les passionnés, les fondateurs du marché, les capitaines de la TrocZen Box.

### Objectif
Analyser les boucles de valeur, certifier les pairs, piloter la santé de la monnaie.

### Navigation complète (4 onglets)
- 💳 **Wallet**
- 🌐 **Explorer & Savoir-Faire (WoTx2)** : Attester les compétences, voir le graphe
- 📈 **Observatoire (Dashboard Avancé)** : Vitesse de circulation, C², Multiplicateur Alpha, Taux inter-marchés
- ⚙️ **Profil Avancé** : Gestion de la seed, logs, export IPFS/Nostr

### Tout est visible
- Dashboard économique complet avec C², Alpha, graphes
- Métriques avancées de circulation monétaire
- Outils d'administration (exports, logs, etc.)

---

## 🛠 Architecture Technique

### 1. Modèle de données

**Fichier : `lib/models/app_mode.dart`**

```dart
enum AppMode {
  flaneur(0, '🚶‍♂️ Flâneur', 'Client / Acheteur'),
  artisan(1, '🧑‍🌾 Artisan', 'Commerçant / Producteur'),
  alchimiste(2, '🧙‍♂️ Alchimiste', 'Tisseur / Expert');
  
  final int value;
  final String label;
  final String description;
}
```

### 2. Stockage persistant

**Fichier : `lib/services/storage_service.dart`**

Méthodes ajoutées :
- `Future<void> setAppMode(int modeIndex)` : Sauvegarde le mode
- `Future<int> getAppMode()` : Récupère le mode (défaut: 0 = Flâneur)

### 3. Provider global (optionnel)

**Fichier : `lib/providers/app_mode_provider.dart`**

Un `ChangeNotifier` pour gérer le mode de façon réactive :
- Charge le mode au démarrage
- Permet de changer de mode dynamiquement
- Suggère des mises à niveau (gamification)

### 4. Navigation dynamique

**Fichier : `lib/screens/main_shell.dart`**

Le `MainShell` adapte dynamiquement :
- Le nombre d'onglets (2, 4 ou 4)
- Les vues affichées (avec ou sans Dashboard, simple ou avancé)
- Les destinations de navigation
- Le FAB contextuel

Méthodes clés :
- `List<Widget> _buildViews()` : Construit les vues selon le mode
- `List<NavigationDestination> _buildDestinations()` : Construit la barre de navigation

### 5. Dashboard simplifié

**Fichier : `lib/screens/views/dashboard_simple_view.dart`**

Version allégée du dashboard pour les Artisans :
- Métriques comptables simples
- Pas de formules mathématiques
- Interface claire et directe

### 6. Onboarding avec choix du mode

**Fichier : `lib/screens/onboarding/onboarding_mode_selection_screen.dart`**

Écran de sélection du "chapeau" au premier lancement :
- 3 cartes interactives pour chaque mode
- Description et fonctionnalités de chaque mode
- Sauvegarde automatique du choix

### 7. Paramètres avec changement de mode

**Fichier : `lib/screens/settings_screen.dart`**

Sélecteur visuel de mode :
- Affichage des 3 modes avec emoji et description
- Confirmation si passage à un mode inférieur
- Message de redémarrage après changement

---

## 🌟 Gamification : Passage de niveau organique

Pour rendre la transition fluide sans enfermer l'utilisateur :

### Déclencheurs automatiques

1. **Démarrage** : Tout le monde commence Flâneur
2. **Création du Bon Zéro** : Dès que N1 = 5 (5 contacts), suggestion de passer en mode Artisan
3. **Premier Circuit Fermé** : Lorsqu'un bon boucle (Kind 30304), proposition de découvrir l'Observatoire (Mode Alchimiste)

### Implémentation (à venir)

Le `AppModeProvider` fournit déjà :
- `shouldSuggestUpgrade({contactsCount, bonsCreated})` : Détecte si une suggestion est pertinente
- `getUpgradeSuggestionMessage()` : Message personnalisé pour encourager l'upgrade
- `upgradeMode()` : Passage au niveau supérieur

---

## 📊 Avantages UX

### Réduction de la charge cognitive
- **80% des utilisateurs** voient une app aussi simple que Lydia ou Apple Pay
- **20% des experts** accèdent à toute la puissance cypherpunk

### Progression naturelle
- L'utilisateur découvre les fonctionnalités au fur et à mesure
- Pas de "syndrome de l'usine à gaz"
- Sentiment d'accomplissement en progressant

### Adaptabilité
- L'utilisateur peut changer de mode à tout moment
- Possibilité de revenir en arrière si trop complexe
- Interface qui s'adapte à l'usage réel

---

## 🔄 Migration et compatibilité

### Comportement par défaut
- Tous les utilisateurs existants : Mode Flâneur (0)
- Nouveaux utilisateurs : Choix lors de l'onboarding

### Pas de perte de données
- Changer de mode ne supprime aucune donnée
- Seule l'interface change
- Les fonctionnalités restent accessibles dans les modes supérieurs

### Réversibilité
- On peut passer d'Alchimiste à Flâneur et vice-versa
- Confirmation demandée si passage à un mode inférieur
- Message explicatif sur ce qui sera masqué

---

## 🚀 Prochaines étapes

### Intégration dans l'onboarding
1. Ajouter l'écran de sélection du mode dans le flux onboarding
2. L'intégrer entre l'écran de profil et l'écran final

### Suggestions automatiques
1. Détecter N1 ≥ 5 et suggérer le mode Artisan
2. Détecter 10+ bons créés et suggérer le mode Alchimiste
3. Afficher des notifications non-intrusives

### Analytics
1. Mesurer la distribution des modes
2. Tracker les passages de niveau
3. Identifier les fonctionnalités critiques à simplifier

---

## 📝 Fichiers modifiés

- ✅ `lib/models/app_mode.dart` (nouveau)
- ✅ `lib/providers/app_mode_provider.dart` (nouveau)
- ✅ `lib/screens/views/dashboard_simple_view.dart` (nouveau)
- ✅ `lib/screens/onboarding/onboarding_mode_selection_screen.dart` (nouveau)
- ✅ `lib/services/storage_service.dart` (modifié)
- ✅ `lib/screens/main_shell.dart` (modifié)
- ✅ `lib/screens/settings_screen.dart` (modifié)

---

## 💡 Citation

> "La simplicité est la sophistication suprême." — Léonard de Vinci

En cachant la complexité par défaut et en la révélant progressivement, TrocZen devient accessible à tous tout en restant puissant pour les experts.
