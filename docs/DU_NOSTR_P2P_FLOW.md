# Flux du Dividende Universel (DU) — Boucles, Distribution, Valeur

> **Note architecturale :** TrocZen peut fonctionner en deux modes.
> **Mode Hybride** : Boucle ④ via UPlanet/Ğ1 Love Ledger (Kind 30305 émis par ZEN.ECONOMY.sh).
> **Mode Autonome** : Boucle ④ auto-générée par l'activité du marché lui-même (aucune dépendance Ğ1).
> Les Boucles ①②③ sont **identiques dans les deux modes** — elles n'utilisent que NOSTR.

> « Ğ1 apporte la Liberté · Ẑen apporte l'Égalité · ❤️ apporte la Fraternité »  
> *car 1 ❤️ = 1 DU — le don bénévole est la valeur co-créée par la communauté*

Ce document décrit **comment la valeur naît, circule et revient** dans TrocZen. La monnaie est portée par des **Bons ẐEN à durée de vie choisie**, détruits à leur retour à l'émetteur et révélant leur parcours. Elle n'est pas enregistrée sur une blockchain globale mais naît **du graphe social Nostr** (follows réciproques).

---

## 🏛️ Architecture : Indépendance de Ğ1

```
CE QUI EST DÉJÀ 100% INDÉPENDANT DE Ğ1 :
  ✅ Boucle ① (Sociale)    = Kind 3 NOSTR réciproques → N1 → DU → Bons
  ✅ Boucle ② (Monétaire)  = Bons P2P cryptographiques (SSSS, Kind 30303/30304)
  ✅ Boucle ③ (Information)= HMAC anonymisation, Gossip strfry
  ✅ Formule DU            = graphe social NOSTR pur, pas de blockchain
  ✅ WoT seuil N1 ≥ 5      = follows réciproques NOSTR, pas Ğ1 WoT
  ✅ "Ẑen" dans TrocZen    = unité locale arbitraire, pas (Ğ1-1)×10

CE QUI PEUT ÊTRE DÉCOUPLÉ (Boucle ④) :
  Mode Hybride : ZEN.ECONOMY.sh → LOVE_DONATION → Kind 30305 (via UPlanet)
  Mode Autonome: Activité marché → auto-génération Kind 30305 (locale, aucun Ğ1)
```

### Mode Autonome — Règles d'Auto-Génération (sans Ğ1)

En mode autonome, la Box TrocZen génère elle-même les Kind 30305 basés sur l'activité du marché :

| Déclencheur | Formule amount | Signification |
|-------------|---------------|---------------|
| Boucle fermée confirmée | `amount = valeur_bon × 0.1` | Le circuit récompense l'opérateur |
| Transferts / jour | `amount = transferts_j × C²` | Vélocité récompensée |
| Membres actifs (N1≥5) | `amount = membres_actifs × DU_base` | Communauté récompensée |
| Bootstrap (premier boot) | `amount = DU(0) initial` | Amorce de la monnaie locale |

```bash
# Exemple auto-génération Kind 30305 par la TrocZen Box
# (sans ZEN.ECONOMY.sh, sans Ğ1)

BOUCLES_FERMEES=$(strfry scan '{"kinds":[30304]}' | wc -l)
DU_INCREMENT=$(echo "scale=2; $BOUCLES_FERMEES * 0.5" | bc)
DU_DATE=$(date +%Y-%m-%d)
TAGS="[[\"d\",\"du-$DU_DATE\"],[\"amount\",\"$DU_INCREMENT\"]]"

nostr_send_note.py \
    --keyfile "$BOX_OPERATOR_KEYFILE" \
    --kind 30305 \
    --content "" \
    --tags "$TAGS" \
    --relays "ws://127.0.0.1:7777"
```

**Invariant clé :** peu importe la source du Kind 30305 (UPlanet Ğ1 ou Box autonome), TrocZen app lit le **tag `amount` identiquement** — la logique DU est la même.

---

## Vue d'Ensemble : 4 Boucles Fondamentales

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LES 4 BOUCLES TROCZEN                            │
│                                                                     │
│  ① SOCIAL          ② MONÉTAIRE         ③ INFORMATION    ④ LOVE    │
│  ────────          ─────────────        ─────────────    ──────────│
│  Alice ↔ Bob       Bon ẐEN émis         Bon: anonyme     Capitaine │
│  follows récip.    transferts P2P        circuit: public  bénévole  │
│  → N1++           → hops++             émetteur:        Kind 30305 │
│  → N1≥5 → DU      → retour → détruit   partiel révélé   → DU      │
│  → DU → Bon       → boucle fermée      → santé réseau   → Bons    │
│                                                          → marché   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Boucle ① — Sociale : La Confiance crée la Monnaie

**Principe :** La monnaie ne naît pas d'une banco centrale ou d'un algorithme. Elle naît de la confiance mutuelle entre humains.

```
Alice suit Bob (Kind 3 NOSTR)
        ↓
Bob suit Alice (Kind 3 NOSTR)
        ↓
Lien RÉCIPROQUE établi ← seul ce lien compte
        ↓
N1 d'Alice increment de 1
        ↓
Quand N1 ≥ 5 : DU quotidien activé
        ↓
DU disponible s'accumule chaque jour
        ↓
Alice émet des Bons ẐEN librement
        ↓
Bons circulent → nouveaux membres → N2 plus dense
        ↓
N2 plus dense → DU plus élevé ─────────────────────┐
                                                     │
← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
```

**Résistance Sybil naturelle :** créer de faux comptes *dilue* sa propre création monétaire (ils augmentent le dénominateur `N1 + √N2` plus vite que le numérateur). Il est économiquement non rentable de tricher.

**Formule TRM locale :**
```
DU_i(t+1) = DU_i(t) + C² × (M_n1 + M_n2/√N2) / (N1 + √N2)

C²    = Constante de croissance calibrée localement
M_n1  = Masse ẐEN active des amis directs
M_n2  = Masse ẐEN active des amis d'amis
N1    = Liens réciproques directs (≥5 pour activer)
√N2   = Amortissement réseau étendu (anti-explosion)
```

---

## Boucle ② — Monétaire : Le Bon Voyage et Revient

**Principe :** chaque bon a une durée de vie. À son retour à l'émetteur, le circuit est révélé et le bon est détruit. La monnaie est *vivante*.

```
1. ÉMISSION (manuelle, par choix)
   ─────────────────────────────
   DU disponible ≥ Z ẐEN ?
         ↓ oui
   Alice choisit : montant Z, TTL (7j–365j)
   App génère : bon_id, SSSS(P1,P2,P3), path[HMAC(Alice, bon_id)]
   Publie Kind 30303 (P3 chiffré sur strfry)
   DU disponible -= Z

2. TRANSFERT P2P (hors-ligne, double scan)
   ──────────────────────────────────────
   Alice → Bob :
     Scan 1 : Bob voit valeur + TTL résiduel (peut refuser)
     Scan 2 : ACK signé de Bob
     Résultat : hop++, path[].append(HMAC(Bob, bon_id))
              expires_at INCHANGÉ (TTL continue de s'écouler)
   
   Bob → Charlie → ... (mêmes étapes)

3. TROIS DESTINS POSSIBLES
   ────────────────────────
   A. BOUCLE FERMÉE (retour à Alice)
      Alice reçoit le bon → détection issued_by == ma_pubkey
      → Destruction immédiate
      → Révélation partielle du parcours (contacts connus)
      → Publication Kind 30304 (BonCircuit)
      → Notification : "🎉 X ẐEN · Y hops · Z jours"
   
   B. RACHAT (TTL résiduel < 3 jours)
      App alerte le porteur actuel
      → DM Nostr (Kind 4) à Alice : "Veux-tu racheter ?"
      → Double scan → Alice reçoit son bon, émet un frais
   
   C. EXPIRATION (TTL = 0)
      Archivage silencieux
      Log : "Bon expiré — diagnostic de confiance insuffisante"
```

**Effet :** la vélocité de retour des bons mesure la *santé* du réseau. Les bons qui expirent indiquent les zones à renforcer.

---

## Boucle ③ — Information : Transparence Collective, Vie Privée Individuelle

**Principe :** le réseau sait *qu'un bon a circulé*, mais pas *qui l'a porté*.

### Qui peut voir quoi ?

```
Information                    Public  Porteurs  Émetteur  Personne
─────────────────────────────  ──────  ────────  ────────  ────────
bon_id, valeur, nb hops, TTL   ✅       ✅         ✅
Qu'Alice a émis un bon         ✅       ✅         ✅
Masse monétaire agrégée M_n1   ✅*                ✅
Qui a porté le bon             ❌       ❌         Partiel*  ——
Parcours complet               ❌       ❌         ❌        ✅
Porteurs hors W N1+N2          ❌       ❌         ❌        ✅

* = Émetteur peut tenter HMAC(pubkey_connue, bon_id) pour ses contacts
```

### Anatomie de l'anonymisation (HMAC)

```
path[i] = HMAC-SHA256(pubkey_porteur_i, bon_id)

→ Vérifiable par l'émetteur si il connaît le porteur
→ Opaque pour tout autre observateur
→ Le bon_id est nécessaire pour dériver → jamais transmis sans consentement
```

### Distribution de l'Information sur le réseau

```
TrocZen Box locale (strfry)
├── Kind 3 : graphe social de confiance (public, réciproque)
├── Kind 30303 : P3 chiffré des bons (pseudo-anonyme)
├── Kind 30304 : circuits fermés (anonymisés, santé réseau)
├── Kind 30305 : DU Love Ledger (depuis UPlanet, public)
└── Kind 30503 : Credentials Oracle UPlanet (permis validés)

Gossip Push (Capitaine/Alchimiste entre marchés)
└── Synchronise les graphes de confiance entre TrocZen Box voisines
    → Un Passeur de marché en marché unifie les N2
    → DU plus élevé pour tous les membres interconnectés
```

---

## Boucle ④ — Love Ledger : Le Bénévolat devient Monnaie Locale

**Principe :** le Capitaine UPlanet qui héberge la TrocZen Box bénévolement est récompensé en DU TrocZen via le protocole Love Ledger.

```
Capitaine héberge TrocZen Box gratuitement
         ↓
ZEN.ECONOMY.sh constate : CASH insuffisant pour payer NODE
         ↓
Comptabilise dans love_ledger.json :
  total_donated_zen += LOVE_DONATION_THIS_WEEK
  weeks_on_volunteer++
         ↓
Émet Kind 1 NOSTR (gratitude publique) :
  "❤️ L'Astroport héberge grâce au bénévolat ! 1❤️=1DU"
         ↓
Émet Kind 30305 (DU TrocZen, format exact) :
  tags: [["d","du-2026-03-24"],["amount","28.00"]]
  content: "" (toujours vide — TrocZen lit le tag amount)
         ↓
TrocZen app du Capitaine :
  computeAvailableDu(captain_npub)
  = Σ amount(Kind 30305) - Σ value(Kind 30303 émis)
         ↓
Capitaine peut émettre Bons ẐEN fondants (28j TTL)
         ↓
Bons échangés sur le marché local → services/biens
         ↓
Nouveaux membres → loyers MULTIPASS → CASH UPlanet rechargé
         ↓ ─────────────────────────────────────────────────┐
                                                             │
Boucle fermée :                                             │
sacrifice bénévole → monnaie locale → économie → CASH ←────┘
```

**Équivalence :**
```
1 ❤️ offert (sacrifice Ẑen bénévole)
= 1 DU TrocZen (Kind 30305, "amount" = sacrifice en Ẑen)
= 1 Bon TrocZen de 1 Ẑen (28j fondant)
= 1 acte de confiance locale
= 1 acte de fraternité concrète
```

---

## Séquence Complète (Mermaid)

```mermaid
sequenceDiagram
    autonumber

    actor Alice
    actor Bob
    actor Charlie
    actor Capitaine as Capitaine (UPlanet + TrocZen)
    participant Box as TrocZen Box (strfry)
    participant UPlanet as ZEN.ECONOMY.sh

    %% BOUCLE ④ : Love Ledger → DU
    rect rgb(40, 20, 60)
    Note over Capitaine, UPlanet: ④ Love Ledger (Fraternité)
    UPlanet->>UPlanet: CASH insuffisant → bénévolat
    UPlanet->>Box: Kind 30305 [["d","du-DATE"],["amount","28.00"]]
    Note over Box: DU Capitaine += 28 Ẑen
    Capitaine->>Box: Émet Bon Z ẐEN (Kind 30303)
    end

    %% BOUCLE ① : Social → DU
    rect rgb(20, 35, 30)
    Note over Alice, Box: ① Social (Confiance → Monnaie)
    Alice->>Box: Kind 3 : Follow Bob
    Bob->>Box: Kind 3 : Follow Alice
    Note over Box: Lien réciproque → N1++
    alt N1 < 5
        Box-->>Alice: "N1 = 4/5 — encore 1 lien"
    else N1 ≥ 5
        Box-->>Alice: "✅ DU activé → +X ẐEN/jour disponible"
    end
    end

    %% BOUCLE ② : Bon → Transferts → Retour
    rect rgb(30, 25, 45)
    Note over Alice, Charlie: ② Monétaire (Bon circule)
    Alice->>Box: Émet Bon Z ẐEN TTL=28j (Kind 30303)
    Alice->>Bob: Scan 1 (offre) + Scan 2 (ACK)
    Note over Alice: hop++, path[HMAC(Bob, bon_id)]
    Bob->>Charlie: Scanner offre + ACK
    Note over Bob: hop++, path[HMAC(Charlie, bon_id)]

    alt Retour à Alice (boucle fermée)
        Charlie->>Alice: Double scan rachat
        Note over Alice: 🎉 Détruit bon · révèle circuit
        Alice->>Box: Kind 30304 (BonCircuit, anonymisé)
    else TTL critique (< 3j)
        Box-->>Charlie: "⚠️ Bon expire — contacter Alice ?"
        Charlie->>Alice: DM Kind 4 → négociation rachat
    else Expiration TTL = 0
        Box->>Box: Archivage silencieux — diagnostic
    end
    end

    %% BOUCLE ③ : Information
    rect rgb(45, 20, 20)
    Note over Box: ③ Information (Gossip)
    Capitaine->>Box: Push outbox_gossip (nouveau marché)
    Note over Box: Graphes sociaux fusionnés
    Note over Box: N2 de tous les membres ++
    Note over Box: DU de tous ++ (réseau plus dense)
    end
```

---

## Métriques de Santé du Réseau

| Métrique | Formule | Seuil sain | Signal |
|----------|---------|------------|--------|
| **Vélocité** | Transferts / masse totale / jour | > 0.05 | La monnaie circule |
| **Ratio santé** | Boucles fermées / expirations | > 1.0× | Confiance se régénère |
| **Profondeur** | Hops moyens / boucle | 3–7 | < 3 = trop local, > 10 = fragile |
| **Taux rachat** | Rachats / avis TTL critique | > 20% | Communauté prend soin |
| **Activation DU** | Membres N1≥5 / total | > 60% | Bootstrap réussi |
| **DU Love Ledger** | Kind 30305 émis / semaine | ≥ 1 | Capitaine bénévole actif |

---

## Rôles Émergents (Sans Hiérarchie)

| Rôle | Ce que le réseau mesure | Récompense naturelle |
|------|-------------------------|----------------------|
| **Tisseurs** | Ponts entre communautés (N2/N1 élevé) | DU amplifié |
| **Animateurs** | Fort N1 local dense | DU stable et régulier |
| **Gardiens** | Peu d'expirations, boucles longues | Ratio santé élevé |
| **Passeurs** | Gossip entre marchés | N2 de tous augmente |
| **Capitaines** | Love Ledger (Kind 30305, bénévolat) | DU TrocZen + Bons fondants |

> *Ces rôles ne sont pas nommés — ils sont **révélés** par les flux de confiance réels.*

---

## Règles Protocolaires (Référence)

| # | Règle | Implémentation |
|---|-------|----------------|
| **R1** | TTL min 7j, max 365j | `assert 604800 ≤ ttl ≤ 31536000` |
| **R2** | `expires_at` immuable | Pas de setter exposé, jamais modifié en transit |
| **R3** | Hop → `hop_count++` uniquement | `expires_at` inchangé à chaque transfert |
| **R4** | TTL résiduel calculé à la volée | Jamais stocké, jamais mis en cache |
| **R5** | Alerte TTL < 3j (configurable) | `ALERT_THRESHOLD_SECONDS = 259200` |
| **R6** | Retour émetteur = destruction | `issued_by == ma_pubkey` vérifié à réception |
| **R7** | Expiration = archivage silencieux | Job horaire : archiver `expires_at < now()` |
| **R8** | Ratio DU recalculé chaque matin | Cache < 24h obligatoire |
| **R9** | Pas de fractionnement | Bon est atomique — découpe à la création |
| **R10** | path[] = HMAC, jamais pubkeys brutes | `path[i] = HMAC-SHA256(pubkey_i, bon_id)` |
| **R11** | Kind 30305 content toujours vide | TrocZen lit `["amount","XX.XX"]` seulement |
| **R12** | DU TrocZen = sacrifice Love Ledger | `amount = LOVE_DONATION_ZEN` en Ẑen ≈ € |

---

## Phrases Fondatrices

> **"Ce n'est pas la richesse qui crée la confiance — c'est la confiance qui crée la richesse."**

> **"Le Bon Zéro vaut tout car il ne vaut rien — il permet à tous les autres d'exister."**

> **"La coopérative n'est pas fondée. Elle est révélée."**

> **"1 ❤️ = 1 DU — le don bénévole est la valeur co-créée par la communauté."**

---

> *Protocole TrocZen · Bons ẐEN v2 · NOSTR Kinds 30303/30304/30305 · UPlanet Love Ledger · AGPL-3.0*
