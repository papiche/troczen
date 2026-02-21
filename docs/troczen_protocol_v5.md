# Protocole TrocZen — Bons ẐEN v5

> Infrastructure de confiance à géométrie variable.  
> La monnaie est un cas d'usage. La compétence en est un autre.  
> Les deux s'alimentent mutuellement.

Ce document intègre la couche **WoTx2 / Oracle** (Astroport.ONE) au protocole TrocZen. Il décrit l'articulation entre la **WoT sociale** (graphe des personnes → DU), la **WoT de compétences** (graphe des savoir-faire → multiplicateur) et les **Bons ẐEN** (monnaie à TTL décroissant).

---

## Cinq couches Nostr — Une seule identité

```
npub  (identité unique de l'utilisateur)
│
├── Kind 0    → Profil public (nom, bio, photo, marchés, compétences auto-déclarées)
├── Kind 3    → Graphe social (follows réciproques → N1/N2 → DU quotidien)
├── Kind 30500–30503 → Graphe des compétences (WoTx2 → credentials → multiplicateur DU)
├── Kind 30303 → Bons ẐEN (valeur + TTL + path HMAC)
└── Kind 30304 → BonCircuit (boucle fermée + parcours révélé)
```

**Deux graphes, une seule vérité.** La WoT sociale dit *qui te fait confiance comme personne*. La WoT de compétences dit *qui valide ce que tu sais faire*. Ensemble, ils produisent un DU qui encode à la fois l'appartenance communautaire et la reconnaissance du savoir-faire.

---

## Concepts Fondateurs

### La seedMarket — frontière de confiance

La `seedMarket` est un **secret partagé entre les membres d'un marché**. Ce n'est pas un mot de passe technique — c'est une **déclaration d'appartenance**. La confiance commence hors-ligne, avant l'application.

```
seedMarket  →  définit un espace de confiance (un "marché")
Bon Zéro    →  circule dans cet espace, tisse le graphe social
N1 ≥ 5      →  débloque le DU de base (WoT sociale)
WoTx2 Xn    →  multiplie le DU selon le savoir-faire reconnu
```

### Le Bon Zéro — application de rencontre

Le Bon Zéro (`value = 0 ẐEN`, `TTL = 28j`, `kind: zero_bond`) ne porte pas de valeur monétaire. Il porte une **invitation** : accès au marché, à la seedMarket, au graphe social en construction. Il est détruit à retour ou expiration, révélant la carte des premiers liens.

### Les Bons ẐEN — monnaie à TTL décroissant

Valeur nominale + TTL choisi par l'émetteur (7j–365j) + path[] HMAC anonymisé. Détruits au retour émetteur, archivés silencieusement à expiration. Masse en équilibre : `M* = DU_journalier × TTL_moyen`.

---

## Calibration du DU(0) — DU de base = 10 ẐEN/jour

```
~300 ẐEN/mois  ←  membre au seuil minimal (N1=5, réseau moyen)
~450 ẐEN/mois  ←  membre actif (N1=10)
~600 ẐEN/mois  ←  Tisseur/Passeur (N2/N1 élevé)
~840 ẐEN/mois  ←  maximum réaliste (N1=25, N2/N1=15×)
```

L'ancrage psychologique ("bon salaire") est une **convention sociale** définie par la communauté, pas le protocole :
> *"Dans notre marché, 1 DU = 30 minutes de travail."*  
> → 300 ẐEN/mois = 150 heures = temps plein

---

## La WoT de Compétences — Intégration WoTx2 (v5)

### Pourquoi une deuxième WoT ?

La WoT sociale (Kind 3) est aveugle à la qualité. Un maraîcher expert et un débutant ont le même DU si leurs réseaux sont identiques. Pourtant la **rareté du savoir-faire** est réelle et doit être encodée.

La WoT de compétences (WoTx2) résout ceci par une **certification progressive entre pairs** :
- Niveau X1 = 1 attestation reçue
- Niveau Xn = n attestations + n compétences révélées
- Progression automatique, illimitée, sans autorité centrale

Elle répond aussi à l'espace de relativité de la valeur : une heure n'est pas une heure. Ce n'est pas le protocole qui fixe la différence — c'est la communauté qui reconnaît le niveau de maîtrise.

### Les événements WoTx2 sur Nostr

| Kind | Émis par | Contenu |
|---|---|---|
| `30500` | Créateur de la maîtrise (via Oracle) | Définition du permit (`PERMIT_[NOM]_X1`) |
| `30501` | Apprenti (MULTIPASS) | Demande d'attestation + compétence réclamée |
| `30502` | Maître certifié (MULTIPASS) | Attestation + compétences transférées + révélées |
| `30503` | Oracle (UPLANETNAME_G1) | Verifiable Credential W3C — signé, horodaté |

Les compétences ne sont **pas définies à la création** — elles sont **révélées progressivement** lors des attestations. Un maître nageur X1 ouvre l'espace "Natation". À X2, ses attesteurs révèlent "Sauvetage", "Aqua-fitness". Le savoir-faire se déploie organiquement.

### Progression automatique (Oracle.refresh.sh)

```
X1 (1 attestation)  →  automatiquement crée X2 (2 attestations requises)
X2 (2 attestations) →  automatiquement crée X3 (3 attestations requises)
...
X5–X10   : Expert
X11–X50  : Maître
X51–X100 : Grand Maître
X101+    : Maître Absolu
```

Chaque niveau Xn exige n compétences distinctes et n attestations croisées. Il est impossible de s'attester soi-même. La progression est donc une preuve sociale incorruptible.

---

## Formule DU v5 — Intégration du Multiplicateur de Compétence

### Formule complète

```
DU_i(t+1) = [DU_i(t) + C² × (M_n1 + M_n2/√N2) / (N1 + √N2)]  ×  (1 + α × S_i)
```

Où `S_i` est le **score de compétence local** de l'utilisateur i dans le marché considéré.

### Calcul du score S_i

```
S_i = Σ (niveau_Xn_compétence_k × poids_marché_k) / nombre_compétences_actives
```

- **niveau_Xn** : le niveau atteint dans la compétence k (ex: X3 → valeur 3)
- **poids_marché** : la pertinence de la compétence k pour ce marché spécifique (définie par la seedMarket ou votée en assemblée)
- `α` : facteur de pondération, borné entre 0 et 1 pour éviter la domination

### Exemple concret — Marché de Producteurs Alimentaires

```
Alice[maraîchage X3, transformation X1]
  poids_marché : maraîchage=0.8, transformation=0.4

S_Alice = (3×0.8 + 1×0.4) / 2 = (2.4 + 0.4) / 2 = 1.4
DU_Alice = DU_base × (1 + 0.3 × 1.4) = DU_base × 1.42
→ Alice reçoit 42% de DU en plus qu'un membre sans certification
```

```
Dave[maraîchage X1]  (débutant)
S_Dave = (1×0.8) / 1 = 0.8
DU_Dave = DU_base × (1 + 0.3 × 0.8) = DU_base × 1.24
→ Dave reçoit 24% de DU en plus qu'un membre sans certification
```

```
Bob[code X5] (compétence hors-marché)
poids_marché : code=0.0 (non pertinent pour ce marché)
S_Bob = 0
DU_Bob = DU_base × 1.0
→ La compétence code ne produit pas de DU sur le marché alimentaire
   mais produit du DU sur un marché numérique
```

### Paramètre α — Borne politique

`α ∈ [0.0, 1.0]` est défini par la seedMarket ou voté en assemblée.

| α | Signification | Dispersion DU |
|---|---|---|
| 0.0 | Compétence ignorée — pur TRM | 300–840 ẐEN/mois |
| 0.3 | Compétence modérée (défaut) | 300–1 100 ẐEN/mois |
| 0.6 | Compétence forte | 300–1 400 ẐEN/mois |
| 1.0 | Compétence maximale | 300–1 680 ẐEN/mois |

> **Règle politique** : α n'est jamais fixé par le protocole — c'est une décision communautaire. Un marché peut commencer à α=0 (pur TRM) et introduire la reconnaissance des compétences progressivement, au rythme de la confiance collective.

---

## Kind 0 — Profil Nostr étendu TrocZen

Le profil `Kind 0` est le **point d'entrée identitaire**. Il porte les informations publiques de l'utilisateur et ses auto-déclarations (non certifiées).

```json
{
  "kind": 0,
  "pubkey": "<npub_hex>",
  "content": {
    "name": "Alice Dubois",
    "about": "Maraîchère bio — Vallée de l'Hers",
    "picture": "https://...",
    "nip05": "alice@troczen.local",

    "troczen": {
      "markets": [
        { "seed_hash": "sha256(seedMarket_Prod)",  "name": "Marché des Producteurs" },
        { "seed_hash": "sha256(seedMarket_Artis)", "name": "Collectif Artisans" }
      ],
      "skills_declared": [
        { "tag": "maraîchage",    "self_level": 3 },
        { "tag": "transformation","self_level": 1 },
        { "tag": "permaculture",  "self_level": 2 }
      ],
      "bon_zero_active": true,
      "du_activation_date": "2026-01-15"
    }
  }
}
```

**Important :** `skills_declared` est une auto-déclaration non certifiée — elle n'entre PAS dans le calcul du DU. Seuls les credentials `Kind 30503` émis par l'Oracle entrent dans `S_i`. L'auto-déclaration sert à la découvrabilité sociale (qui cherche un maraîcher ? → trouver Alice).

### Distinction auto-déclaration / certification

| Source | Kind | Certifié ? | Impact DU | Usage |
|---|---|---|---|---|
| Auto-déclaration | 0 (`skills_declared`) | Non | Aucun | Découvrabilité, matching |
| Credential Oracle | 30503 | Oui (pairs + Oracle) | Multiplie S_i | Calcul DU, accès marchés |

---

## Schéma de Flux Complet v5

```mermaid
sequenceDiagram
    autonumber

    actor Alice
    actor Bob
    actor Oracle as Oracle (UPLANETNAME_G1)
    participant App as TrocZen App
    participant Box as TrocZen Box (Nostr)

    %% ÉTAPE 0 : IDENTITÉ ET PROFIL
    rect rgb(15, 25, 35)
    Note over Alice, Box: 0. Identité Nostr — Kind 0
    Alice->>App: Génère clé Nostr (npub/nsec)
    App->>Box: Publie Kind 0 (profil + markets[] + skills_declared[])
    Note over Box: Profil public — auto-déclaration non certifiée
    end

    %% ÉTAPE 1 : ENTRÉE DANS UN MARCHÉ
    rect rgb(15, 30, 25)
    Note over Alice, Box: 1. Rejoindre un marché — seedMarket
    Alice->>App: Saisit seedMarket (reçue physiquement)
    App->>App: Dérive espace de confiance + relais Box
    App->>App: Génère Bon Zéro (0 ẐEN · TTL 28j)
    end

    %% ÉTAPE 2 : AMORCE SOCIALE
    rect rgb(20, 35, 30)
    Note over Alice, Box: 2. Bon Zéro — tisse le graphe Kind 3
    Alice->>Bob: QR Bon Zéro — rencontre physique
    App->>Bob: "Veux-tu suivre Alice ?"
    Bob->>Box: Kind 3 — Follow Alice (réciproque)
    App->>Alice: "N1 = 3/5 — encore 2 liens"
    Note over Box: À N1=5 → DU base activé
    end

    %% ÉTAPE 3 : CERTIFICATION DE COMPÉTENCE (WoTx2)
    rect rgb(25, 20, 40)
    Note over Alice, Oracle: 3. WoTx2 — Certification de savoir-faire
    Alice->>Box: Kind 30501 — Demande maraîchage X1 + compétence réclamée
    Bob->>Box: Kind 30502 — Attestation + compétences révélées
    Oracle->>Box: Kind 30503 — Verifiable Credential (maraîchage X1)
    Oracle->>Box: Crée automatiquement PERMIT_MARAICHAGE_X2
    App->>Alice: "✓ Certification maraîchage X1 — DU multiplié"
    end

    %% ÉTAPE 4 : CALCUL DU v5
    rect rgb(15, 30, 25)
    Note over App: 4. Calcul DU_i(t+1) avec multiplicateur
    App->>Box: REQ Kind 3 (N1/N2) + Kind 30503 (credentials actifs)
    App->>App: DU_base = C² × (M_n1 + M_n2/√N2) / (N1 + √N2)
    App->>App: S_i = Σ(Xn × poids_marché) / nb_compétences
    App->>App: DU_final = DU_base × (1 + α × S_i)
    App->>Alice: "+X ẐEN · Y.YY DU · (dont Z% compétence)"
    end

    %% ÉTAPE 5 : ÉMISSION ET CIRCULATION
    rect rgb(20, 25, 40)
    Note over Alice, Box: 5. Bons ẐEN — émission et circulation
    App->>App: Découpe DU en coupures · SSSS · HMAC path[]
    App->>Box: Kind 30303 (P3 + preuve WoT + skill_level optionnel)
    Alice->>Bob: Double scan hors-ligne · hop_count++ · TTL inchangé
    end

    %% ÉTAPE 6 : BOUCLE
    rect rgb(15, 30, 25)
    Note over Alice, Box: 6. Cycle de vie — circuit révélé
    alt Retour organique
        App->>Alice: "🎉 Boucle · X ẐEN · Y hops · Z jours"
        App->>Box: Kind 30304 (BonCircuit)
    else Rachat volontaire (TTL < 3j)
        App->>Alice: DM Kind 4 → rachat négocié
    else Expiration
        App->>App: Archivage silencieux — diagnostic réseau
    end
    end
```

---

## Architecture Multi-Marchés avec WoTx2

Les credentials WoTx2 sont **portables entre marchés**, mais leur **poids varie** selon la pertinence définie par chaque seedMarket.

```
Alice[maraîchage X3]
│
├── Marché Producteurs (poids maraîchage = 0.8) → DU × 1.42
├── Marché Voisinage  (poids maraîchage = 0.2) → DU × 1.10
└── Collectif Artisans (poids maraîchage = 0.0) → DU × 1.00
    (compétence non pertinente — aucun bonus)
```

**Un credential, des effets différents selon le marché.** C'est la communauté qui décide de ce qui compte chez elle.

### Portefeuille v5

```
Alice — Marchés actifs
┌──────────────────────────────────────────────────────────────────┐
│ 🌿 Marché Producteurs  DU: 15 ẐEN/j (×1.42)  N1: 8  α=0.3      │
│    Certs actifs : maraîchage X3 · transformation X1              │
├──────────────────────────────────────────────────────────────────┤
│ 🏘️  Voisinage Jolimont  DU: 11 ẐEN/j (×1.10)  N1: 5  α=0.3     │
│    Certs actifs : maraîchage X3 (poids réduit)                   │
├──────────────────────────────────────────────────────────────────┤
│ 🔧 Collectif Artisans   DU: 12 ẐEN/j (×1.00)  N1: 6  α=0.3     │
│    Certs actifs : aucun pertinent dans ce marché                 │
└──────────────────────────────────────────────────────────────────┘
  Total quotidien : ~38 ẐEN (si fongibilité partielle activée)
  Boucles ce mois : 14 · Ratio santé : 1.6×
  Certification en cours : maraîchage X4 (1/4 attestations)
```

---

## Annotation de Compétence sur les Bons ẐEN (optionnel)

Un Bon ẐEN peut porter une **annotation de compétence** optionnelle, lisible à la destruction du bon :

```json
{
  "kind": 30303,
  "content": {
    "value_zen": 10,
    "ttl_seconds": 2419200,
    "issued_for": {
      "act": "2h de conseil en maraîchage",
      "skill_cert": "PERMIT_MARAICHAGE_X3",
      "credential_id": "cred_abc123"
    }
  }
}
```

Quand ce bon revient à l'émetteur, son parcours révèle non seulement *qui* a tenu le bon mais *quel acte certifié* il représentait. La mémoire économique devient une **mémoire du travail réel**.

Cette annotation est optionnelle et ne change pas la mécanique du bon — elle enrichit l'information disponible à la destruction.

---

## Règles Protocolaires v5 — Référence Développeur

| # | Règle | Implémentation |
|---|---|---|
| **R0** | seedMarket dérive l'espace Nostr | `HKDF(seed, "troczen-market")` |
| **R1** | TTL min 7j, max 365j | `assert 604800 ≤ ttl_seconds ≤ 31536000` |
| **R2** | `expires_at` immuable | Champ `readonly` dès la création |
| **R3** | Hop → `hop_count++` uniquement | `expires_at` jamais touché en transit |
| **R4** | TTL résiduel calculé à la volée | `expires_at − now()`, jamais stocké |
| **R5** | Alerte TTL < 3j (configurable) | `ALERT_THRESHOLD_SECONDS = 259200` |
| **R6** | Retour émetteur = destruction | `issued_by == ma_pubkey` à chaque réception |
| **R7** | Expiration = archivage silencieux | Job horaire, `expires_at < now()` |
| **R8** | Valeur DU recalculée chaque matin | Cache max 24h |
| **R9** | Bon atomique — pas de split | Découpe à la création uniquement |
| **R10** | `path[]` = HMAC uniquement | `HMAC-SHA256(pubkey_i, bon_id)` |
| **R11** | Bon Zéro non fongible | `kind: zero_bond` traité séparément |
| **R12** | Multi-marchés segmentés | Bons tagués `market_id` |
| **R13** | DU(0) = 10 ẐEN/jour | `DU_INITIAL = 10` dans la seedMarket |
| **R14** | Fongibilité = opt-in local | `fongible: false` par défaut |
| **R15** | `skills_declared` (Kind 0) ≠ `S_i` | Seuls les Kind 30503 entrent dans le calcul DU |
| **R16** | α ∈ [0, 1] décidé par le marché | `alpha: 0.3` par défaut dans la seedMarket |
| **R17** | Poids compétence par marché | `skill_weights: {}` dans la seedMarket, voté en assemblée |
| **R18** | Un seul Oracle par Astroport | Tag `ipfs_node` sur tous les events WoTx2 |

---

## Correspondance Nostr Kinds — Vue Complète

| Kind | Standard | Usage TrocZen |
|---|---|---|
| 0 | Profil utilisateur | + `troczen{}` : markets[], skills_declared[], bon_zero_active |
| 3 | Contact List | Graphe social → N1/N2 → DU base |
| 4 | DM chiffré | Demande de rachat volontaire (TTL critique) |
| 30303 | Parameterized Replaceable | Bon ẐEN (valeur + TTL + path HMAC + annotation optionnelle) |
| 30304 | Parameterized Replaceable | BonCircuit (boucle fermée — preuve sans identités) |
| 30500 | Parameterized Replaceable | WoTx2 — Définition de permit/maîtrise |
| 30501 | Parameterized Replaceable | WoTx2 — Demande d'apprentissage |
| 30502 | Parameterized Replaceable | WoTx2 — Attestation par un pair certifié |
| 30503 | Parameterized Replaceable | WoTx2 — Verifiable Credential W3C (signé Oracle) |
| 22242 | NIP-42 Auth | Authentification Oracle pour progression automatique |

---

## Rôles Sociaux Émergents — Version Enrichie

| Rôle | Signal WoT sociale | Signal WoTx2 | Ce que ça révèle |
|---|---|---|---|
| **Tisseurs** | N2/N1 élevé | — | Architectes de la confiance inter-groupes |
| **Animateurs** | Fort N1 local | — | Moteurs de la liquidité locale |
| **Gardiens** | Liens durables | — | Garants de la qualité du réseau |
| **Passeurs** | Présents dans N marchés | — | Connecteurs inter-espaces |
| **Maîtres** | — | WoTx2 Xn élevé | Détenteurs et transmetteurs de savoir-faire |
| **Révélateurs** | — | Attesteurs qui enrichissent les compétences | Ceux qui nomment ce que les autres savent sans le savoir |
| **Fondateurs** | Bon Zéro à fort N2 final | Créateurs de maîtrises X1 | Semeurs de communautés et de savoirs |

---

## Métriques de Santé v5

| Métrique | Formule | Seuil sain | Signification |
|---|---|---|---|
| **Ratio de santé** | Boucles / ẐEN expirés (mensuel) | > 1.0× | Confiance qui se régénère |
| **Vélocité** | Transferts / masse / jour | > 0.05 | Monnaie qui circule |
| **Profondeur** | Hops moyens / boucle | 3–7 | Équilibre local/étendu |
| **Taux de rachat** | Rachats / expirations imminentes | > 20% | Soin collectif des bons |
| **Taux DU actifs** | Membres N1≥5 / total | > 60% | Bootstrap réussi |
| **Couverture WoTx2** | Membres avec ≥1 cert / total | > 30% | Compétences reconnues |
| **Profondeur certif.** | Niveau Xn moyen dans le marché | croissant | Maturité du savoir collectif |
| **Ratio révélation** | Nouvelles compétences / attestations | > 0.2 | Créativité du savoir-faire local |

---

## Phrases Clés

> **"Ce n'est pas la richesse qui crée la confiance — c'est la confiance qui crée la richesse."**

> **"Le Bon Zéro vaut tout car il ne vaut rien — il permet à tous les autres d'exister."**

> **"La seedMarket n'est pas un mot de passe. C'est une déclaration d'appartenance."**

> **"La compétence n'est pas ce que tu te déclares — c'est ce que tes pairs reconnaissent."**

> **"La coopérative n'est pas fondée. Elle est révélée."**

---

*Protocole TrocZen · Bons ẐEN v5 · Nostr Kind 0/3/30303/30304/30500–30503 · Fév. 2026*  
*WoTx2 & Oracle : Astroport.ONE / papiche — AGPL-3.0*
