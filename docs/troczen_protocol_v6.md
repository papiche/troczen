


Voici la réécriture complète et fidèle de **`docs/troczen_protocol_v6.md`**. 

Ce document a été entièrement purgé de la vision "théorique" (Node.js, React Native, calculs côté serveur) pour refléter **l'architecture réelle et fonctionnelle implémentée dans le code Dart/Flutter, le backend Python et les bases de données SQLite locales**.

---

# Protocole TrocZen — Architecture v6 · Hyperrelativiste (Implémentation Réelle)

> La monnaie est un observatoire.  
> Chaque utilisateur voit l'économie depuis sa position unique dans l'espace-temps du réseau.  
> Les paramètres ne sont pas des réglages centraux — ce sont des lectures locales.

Cette version 6 (V6) concrétise le principe d'**hyper-relativisme**. Il n'y a plus de backend centralisé qui calcule la monnaie pour tout le monde. L'intégralité de la Théorie Relative de la Monnaie (TRM), la Toile de Confiance (WoT) et les métriques des Dashboards sont **calculées 100% localement (Offline-first)** par l'application Flutter via des agrégations SQLite sur les données du réseau Nostr.

---

## 1. L'Entropie du Marché (La `seed_market`)

Le marché n'est pas un serveur, c'est une **frontière cryptographique** définie par sa graine (`seed_market`).

### Le "Marché Libre" (Transparence totale)
Le marché global (identifié dans le code par `HACKATHON` ou `Marché Libre`) utilise une seed publique connue de tous : **32 octets à zéro** (`0000000000000000000000000000000000000000000000000000000000000000`).
- **P3 en clair** : La méthode `_isHackathonSeed` dans `crypto_service.dart` bypasse le chiffrement AES-GCM.
- **Auditabilité** : Toute personne qui se connecte au relais peut analyser les circuits (Graphe public).
- **Rôle** : C'est le socle de confiance universel, favorisant l'apprentissage et les audits ouverts.

### Les Marchés Locaux (Opacité et confidentialité)
Un marché créé pour un village ou un festival génère une seed sécurisée de 256 bits (`Random.secure()`).
- **P3 chiffré** : Les P3 (témoins des bons) sont chiffrés en AES-GCM avec une clé dérivée quotidiennement : `K_day = HMAC-SHA256(seed_market, "YYYY-MM-DD")`.
- **Rôle** : Le réseau relaie les données (les nœuds Nostr voient des blobs chiffrés), mais seuls les participants possédant la `seed_market` (via QR d'invitation) peuvent déchiffrer l'économie locale.

---

## 2. Architecture Technique Réelle (Local-First)

Contrairement aux approches classiques, **la TrocZen Box ne fait aucun calcul économique**. Elle n'est qu'un relais de communication et un point d'accès Wi-Fi. Toute l'intelligence est dans l'application mobile de l'utilisateur.

### 2.1. Topologie et Architecture "Pollinisateur" (Gossip)
```text
┌──────────────────────────────────────────────┐
│  Smartphone Utilisateur (App Flutter)        │
│                                              │
│  [ UI ] MainShell, Dashboards, PaniniCards   │
│  [ TRM ] DuCalculationService (Calcul DU)    │
│  [ Crypto ] SSSS (2/3), Schnorr, AES-GCM     │
│  [ SQLite ] CacheDatabaseService (Analytics) │
│  [ Audit ] AuditTrailService (Conformité)    │
│  [ Gossip ] outbox_gossip (Alchimistes)      │
└───────────────────────┬──────────────────────┘
                        │ WebSocket (Kind 0,1,3,5,7,30303-30503)
┌───────────────────────┴──────────────────────┐
│  TrocZen Box (Raspberry Pi Solaire)          │
│                                              │
│  [ Relais ] strfry (C++) - Ultra léger       │
│  [ API ] Python Flask (api_backend.py)       │
│[ Stockage ] IPFS (Images), apks/           │
│  [ Réseau ] Portail Captif Nginx + dnsmasq   │
└──────────────────────────────────────────────┘
```

**Le rôle des Alchimistes (Capitaines) :**
Pour relier des marchés isolés (ZenBOX) sans connexion Internet globale, TrocZen utilise une architecture "Pollinisateur" basée sur le protocole Gossip.
- **Aspiration** : Les Alchimistes agissent comme des "Light Nodes". Lors de leur synchronisation, ils aspirent tous les événements du marché et les stockent dans une table SQLite `outbox_gossip`.
- **Dissémination** : Lorsqu'un Alchimiste se connecte à une nouvelle ZenBOX (nouveau marché), son application détecte le changement et "vomit" silencieusement tout l'historique collecté vers le nouveau relais.
- **Alliances** : Les marchés peuvent partager la même `seed_market` via un "QR Code d'Alliance", permettant aux bons de voyager de manière transparente d'une vallée à l'autre.

### 2.2. Le Partage de Secret (SSSS) Réel
Dans l'application (`crypto_service.dart`), la clé privée du Bon (`nsec_bon`) est découpée en 3 via interpolation de Lagrange sur `GF(256)`. Il n'y a pas de "Capitaine" détenant P2, le modèle est un pur **Pair-à-Pair** :

1. **P1 (Ancre)** : Reste chez l'émetteur (`SecureStorage`).
2. **P2 (Voyageur)** : Est transféré d'un smartphone à l'autre hors-ligne via QR Code.
3. **P3 (Témoin)** : Est chiffré par la seed du marché et publié sur le relais Nostr (Kind 30303).

---

## 3. Le Moteur de DU P2P (Hyper-relativiste)

Le calcul du Dividende Universel n'est pas dicté par un nœud central. Il est calculé par chaque téléphone lors de la synchronisation matinale, via le `DuCalculationService.dart`.

### 3.1. Construction du Graphe Social (N1 / N2)
- L'app lit les contacts Nostr (Kind 3) de l'utilisateur. Un contact devient un **N1 (Lien Fort)** uniquement si le follow est **réciproque** (l'app le vérifie localement via `CacheDatabaseService`).
- L'app requête les contacts des N1 pour construire les **N2 (Réseau Étendu)**.
- **Seuil de bootstrap** : Si `N1 < 5`, le DU est désactivé. L'utilisateur doit utiliser des "Bons Zéro" pour tisser sa toile.

### 3.2. La Formule Implémentée
```dart
// Extrait de du_calculation_service.dart
final mn1 = await _storageService.calculateMonetaryMass(mutuals); // SQL SUM(value)
final n2Data = await _storageService.calculateOtherMonetaryMass(mutuals);
double mn2 = n2Data['mass'];
int n2Count = n2Data['count'];

final sqrtN2 = sqrt(n2Count);
final effectiveMass = mn1 + (mn2 / sqrtN2);
final effectivePopulation = mutuals.length + sqrtN2;

final duIncrement = cSquared * effectiveMass / effectivePopulation;
```
Ce `duIncrement` est ensuite publié sur le relais Nostr via le nouvel événement **Kind 30305**. Ainsi, tous les appareils de l'utilisateur partagent la même jauge de création.

---

## 4. Transfert Atomique 100% Offline (QR v2)

La double-dépense hors-ligne est rendue impossible par un *handshake* cryptographique visuel implémenté dans `MirrorOfferController` et `MirrorReceiveController`.

### Étape 1 : L'Offre (QR 1 — Donneur)
Format Binaire ultra-compact (240 octets, géré dans `qr_service.dart`) :
- `magic` (ZEN v2)
- `bonId` (Clé publique du bon)
- `p2_encrypted` (P2 chiffré en AES-GCM avec `K = SHA256(P3 local)`)
- `nonce`, `tag`
- **`challenge`** (16 octets générés aléatoirement par le donneur)
- **`signature`** (Signature Schnorr du Donneur pour prouver la propriété)

### Étape 2 : L'Acceptation et l'ACK (QR 2 — Receveur)
Le Receveur lit le QR, récupère son P3 en cache local (`SQLite`), déchiffre P2, et reconstitue la clé secrète du bon en RAM (`shamirCombineBytesDirect`). 
Il signe le `challenge` avec cette clé, et génère le QR 2 :
- Format Binaire (97 octets) : `bonId` + `Signature(Challenge)` + `status`.

### Étape 3 : La Finalisation (Donneur)
Le Donneur lit le QR 2. `verifySignature` avec `bip340` (Schnorr) garantit que le receveur a bien ouvert le bon. Le donneur **invalide instantanément son P2** dans SQLite. Le transfert est terminé. L'événement de transfert (Kind 1) sera envoyé au relais plus tard, en tâche de fond.

---

## 5. Révélation de Circuit et Modèles de Données

Quand un Bon ẐEN revient à son émetteur (celui qui détient P1), le bon meurt en tant que monnaie mais naît en tant qu'information. 

C'est géré par le `BurnService.dart` :
1. **Destruction Technique** : Publication d'un événement Nostr **Kind 5** (Burn) qui invalide les P3 sur le réseau.
2. **Preuve Économique** : Publication d'un événement **Kind 30304** (Circuit Revelation). Ce document chiffré contient le nombre de transferts (hops) et la durée de vie du bon. 

## 6. Anatomie des Événements Nostr (Kinds) et Workflows

TrocZen utilise le protocole Nostr comme un registre d'état (State Machine) asynchrone. L'architecture repose sur 3 piliers : **L'Identité (WoT)**, **L'Économie (Bons)**, et **La Compétence (WoTx2)**.

> 🔒 **Règle cryptographique fondamentale** :  
> - Les événements liés à l'utilisateur (Profil, DU, Contacts) sont signés par la **Clé Privée de l'Utilisateur** (`nsec_user`).
> - Les événements liés à la vie du Bon (Transfert, Révélation, Burn) sont signés par la **Clé Privée du Bon** (`nsec_bon`), reconstituée de manière éphémère en RAM (via `P2 + P3` ou `P1 + P3`).

### 5.1. Pilier 1 : Identité et Toile de Confiance (WoT)

Ces événements définissent qui est sur le marché et comment le DU est calculé.

#### `Kind 0` : Profil Utilisateur
- **Usage** : Publié lors de l'onboarding ou de la mise à jour du profil.
- **Payload** : Contient le `display_name`, la description, et les URL IPFS pour le `picture` (avatar) et le `banner`. La clé G1 (`g1pub`) est également incluse pour les ponts avec Duniter. Les tags d'activité (`t`) y sont indexés.
- **Workflow** : L'app upload les images sur le nœud IPFS (via l'API Python de la Box), récupère les CID, et publie le Kind 0. 

#### `Kind 3` : Contact List (La Toile de Confiance)
- **Usage** : Définit les liens **N1** de l'utilisateur.
- **Payload** : Liste de tags `p` contenant les clés publiques (`npub`) des personnes suivies.
- **Workflow** : Lorsqu'Alice scanne le QR-ID de Bob, l'app d'Alice ajoute Bob à sa base SQLite `followers_cache` et publie un nouveau Kind 3. Lors de la synchronisation matinale, l'app croise les Kind 3 reçus avec sa propre liste pour définir les **liens réciproques** qui serviront à générer le DU.

#### `Kind 30305` : DU Increment (Jauge de création)
- **Usage** : Synchronise la valeur de DU créée par un utilisateur entre tous ses appareils.
- **Tags** : `d` (`du-YYYY-MM-DD`), `amount` (ex: `14.20`).
- **Workflow** : Le matin, si `N1 >= 5`, le `DuCalculationService` calcule l'incrément, met à jour la base SQLite locale, et publie le Kind 30305. Si l'utilisateur ouvre TrocZen sur sa tablette, elle lira les Kind 30305 pour afficher le même "DU disponible à émettre".

---

### 5.2. Pilier 2 : Économie et Cycle de Vie des Bons ẐEN

C'est ici que s'opère la magie cryptographique de la monnaie hors-ligne.

#### `Kind 30303` : Publication du Bon (Création)
- **Signataire** : 👤 `nsec_user` (L'Émetteur)
- **Tags** : `d` (`zen-<bonId>`), `bon_id`, `value`, `expiration`, `p3_cipher`, `p3_nonce`.
- **Mécanique** : L'émetteur génère la paire de clés du Bon, fait le découpage Shamir (P1, P2, P3). Il chiffre **P3** en AES-GCM en utilisant une clé dérivée de la `seed_market`. 
- **Workflow (Sync)** : Le matin, les utilisateurs téléchargent les Kind 30303 du marché, déchiffrent les P3 avec la `seed_market` locale, et les stockent dans `CacheDatabaseService`. Sans cette étape, ils ne pourront pas accepter de bons hors-ligne dans la journée.

#### `Kind 1` : Transfert d'un Bon
- **Signataire** : 🎟️ `nsec_bon` (Reconstruite éphémèrement en RAM avec `P2 + P3`)
- **Tags** : `bon` (ID du bon), `from_npub`, `p` (to_npub), `value`, `t` (`troczen-transfer`).
- **Contenu** : Texte lisible par les humains (ex: *"💸 Un transfert de 10 ẐEN vient d'avoir lieu..."*).
- **Workflow** : L'échange se fait 100% offline via QR Code. Quand le receveur (qui a récupéré P2 via le QR d'offre) retrouve du réseau, l'application reconstruit discrètement la clé du Bon en RAM, signe l'événement Kind 1, l'envoie au relais, et nettoie la RAM (`secureZeroiseBytes`). Le Dashboard peut ainsi tracer la vélocité de la monnaie.

#### `Kind 30304` (Circuit) et `Kind 5` (Burn) : La Boucle Fermée
- **Signataire** : 🎟️ `nsec_bon` (Reconstruite éphémèrement en RAM avec `P1 + P3`)
- **Workflow** : Quand un bon revient chez son émetteur (qui possède toujours l'ancre `P1`), l'émetteur clique sur "Boucler le circuit".
  1. L'app reconstruit la clé du Bon (`P1 + P3_cache`).
  2. Elle publie un **Kind 30304 (BonCircuit)** dont le contenu est chiffré par la `seed_market`. Ce contenu inclut `hop_count` (nombre de transferts) et `age_days`.
  3. Elle publie un **Kind 5 (Burn)** ciblant l'ID du Kind 30303 initial pour signifier techniquement aux relais que ce bon n'est plus actif.
  4. L'app de l'émetteur supprime définitivement P1 de sa base de données. Le Bon est mort, la preuve économique est née.

---

### 5.3. Pilier 3 : Web of Trust eXtended (WoTx2)

Le système de compétence locale est conçu pour éviter le "Syndrome du Panopticon" (où un observateur externe pourrait cartographier tout le village). **Tout le contenu (motivation, détails) des événements WoTx2 est chiffré (AES-GCM) avec la `seed_market`.** Seuls les tags de routage sont en clair.

#### `Kind 30500` : Skill Permit (Définition)
- **Usage** : Déclare l'existence d'une compétence sur ce marché local (ex: *maraîchage*).
- **Tag d** : `PERMIT_MARAICHAGE_X1`
- **Workflow** : Souvent publié par l'application lors du démarrage initial (ensemencement) ou quand un utilisateur ajoute un tag personnalisé à son profil.

#### `Kind 30501` : Skill Request (Demande d'Attestation)
- **Usage** : Un utilisateur lève la main et dit "Je sais faire ça, certifiez-moi".
- **Workflow** : L'utilisateur publie cet événement. Il apparaîtra dans l'onglet "Savoir-Faire > Mode Expert" de ses contacts (N1).

#### `Kind 30502` : Skill Attestation (Validation par un Pair)
- **Usage** : Un pair valide la demande.
- **Tags** : `e` (ID de la demande 30501), `p` (npub du demandeur).
- **Workflow** : Via le scanner de compétences (`SkillSwapScreen`) ou l'onglet Expert, Bob signe cryptographiquement qu'il reconnait la compétence d'Alice. 

#### `Kind 30503` : Skill Achievement (Credential final)
- **Usage** : Passage au niveau supérieur (X2, X3).
- **Workflow** : Totalement décentralisé et calculé localement. Le `CacheDatabaseService` (méthode `checkLevelUpgrade`) compte les attestations (Kind 30502) et réactions (Kind 7) reçues. Si les conditions sont requises (ex: 3 validations de pairs distincts), l'application d'Alice **auto-émet** le Kind 30503, actant sa montée de niveau pour ce marché, ce qui augmentera son paramètre Alpha (multiplicateur de DU) lors du prochain calcul.

---

## 6. Dashboards et Analyse (Progressive Disclosure)

Il n'y a **pas d'API Dashboard**. Les données ne quittent pas le téléphone pour être analysées. C'est l'application qui agresse les données (Kind 30303 et Kind 1) stockées dans la base locale `troczen_cache.db`.

L'interface s'adapte au rôle de l'utilisateur (Progressive Disclosure) via le `AppModeProvider` :
- **Mode Artisan (`DashboardSimpleView.dart`)** : Vision comptable stricte. Solde, Entrées/Sorties, Bons actifs vs Bons expirés.
- **Mode Alchimiste (`DashboardView.dart` + `circuits_graph_view.dart`)** : 
  - Requêtes SQL lourdes (dans `cache_database_service.dart` : `getAggregatedMetrics()`).
  - Affichage de la **vitesse de circulation** ($\Delta t$ des transactions).
  - Graphique de la toile de confiance et du volume entrant/sortant par N1.
  - Export CSV direct depuis l'appareil pour analyses externes.

---

> *Protocole TrocZen · Bons ẐEN v6 · Implémentation Flutter/Dart/SQLite · Mars 2026*  
> *Conçu pour survivre sans internet, sans cloud, et sans confiance centrale.*