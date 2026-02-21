# Protocole TrocZen — Architecture v6 · Hyperrelativiste

> La monnaie est un observatoire.  
> Chaque utilisateur voit l'économie depuis sa position unique dans l'espace-temps du réseau.  
> Les paramètres ne sont pas des réglages — ce sont des instruments de lecture.

---

## 0. Rupture conceptuelle v6

Les versions précédentes fixaient C², α, DU(0), TTL conseillé comme des constantes locales. La v6 les rend **entièrement dynamiques** — calculés en continu depuis l'état réel du réseau. Il n'y a plus de paramètre à configurer : il y a un **état observé** qui produit tous les indicateurs à la volée.

Cette approche est cohérente avec la Théorie de la Relativité Monétaire (TRM) poussée à son extrême : dans un système où chaque membre calcule son propre DU depuis sa propre position dans le graphe, il n'existe pas de "valeur absolue". Il n'y a que des **rapports de confiance** entre agents, des **flux observés** dans le temps, et un **tableau de bord** qui traduit ces rapports en DU, en multiplicateurs, en signaux de navigation.

---

## 1. Hiérarchie des Marchés — La Seed comme Entropie

### Le marché HACKATHON — seed `000...0`

La seed `000...0` (32 octets nuls) est la **seed publique universelle**. Elle ne protège rien — elle ouvre tout.

```
HACKATHON = seedMarket(000...0)
  → P3 lisible par tous (clé de chiffrement = zéro = pas de chiffrement effectif)
  → Traçabilité complète du parcours des bons
  → Connaissance totale : tout le monde voit tout
  → DU[0] = 10 ẐEN/jour (paramètre initial universel)
  → C'est LE marché d'apprentissage, de bootstrap, de confiance maximale
```

HACKATHON est le marché où bootstrapper l'écosystème. Trouver 5 amis ici = activer DU[0] universel. Les bons HACKATHON portent leur parcours en clair — c'est voulu. C'est l'espace de la **confiance totale et de la transparence absolue**.

### La hiérarchie des marchés par entropie de seed

```
HACKATHON    seed=000...0    entropie=0    transparence totale
     ↓
Marché public  seed=1mot     entropie faible  semi-transparent
     ↓
Marché privé   seed=phrase   entropie moyenne  confidentiel
     ↓
Marché fermé   seed=aléatoire entropie max      opaque aux tiers
```

**Plus la seed a d'entropie, plus le marché est privé.** Ce n'est pas une règle technique — c'est une conséquence naturelle du chiffrement de P3. Dans HACKATHON, P3 est en clair. Dans un marché fermé, P3 ne peut être déchiffré que par les membres connaissant la seed.

### La perméabilité inter-marchés est une émergence P2P

Il n'y a **pas de règle de conversion fixée**. La fongibilité entre marchés se définit par les échanges réels :

```
Alice[Prod] paie Bob[Artisans] avec un bon ẐEN[Prod]
  → Bob accepte → conversion implicite Prod→Artisans existe
  → L'historique de ces échanges P2P *constitue* le taux de change observable
  → Pas de registre central — juste des boucles inter-marchés dans Kind 30304
```

Le relais observe les boucles fermées inter-marchés et calcule un **taux de conversion émergent** : `rate(A→B) = somme(bons A acceptés par membres B) / somme(bons B acceptés par membres A)` sur une fenêtre glissante de 30 jours.

---

## 2. Le Rôle du Capitaine

Le Capitaine est un rôle **humain et infrastructurel**, pas un rôle monétaire. Il est le gardien de l'infrastructure locale du marché.

### Responsabilités

```
Capitaine
├── Reçoit la nsec d'un utilisateur (acte de confiance totale)
├── Coupe la nsec en 3 parts SSSS (Shamir Secret Sharing)
│   ├── P1 → reste chez l'utilisateur (dans l'app, local)
│   ├── P2 → stocké sur la TrocZen Box du Capitaine (IPFS pin)
│   └── P3 → publié sur le relais Nostr (Kind 30303, chiffré avec seed)
├── Active le nœud IPFS permanent (stockage des circuits, credentials, BonZero maps)
├── Active le modèle économique Astroport.ONE (abonnement, services, factures)
└── Garantit la disponibilité hors-ligne du marché local
```

### Le passage nsec → Capitaine est optionnel

Un utilisateur peut utiliser TrocZen en mode **entièrement local** : P1 seul suffit pour émettre et recevoir des bons hors-ligne. Le Capitaine enrichit l'expérience avec :
- Persistance des bons sur IPFS (récupération après perte de téléphone)
- Accès aux métriques du marché (tableau de navigation)
- Passerelle vers les services Astroport.ONE
- Archivage certifié des circuits (WoTx2 + BonCircuit)

### Sécurité du partage nsec

```
nsec (256 bits)
    ↓ SSSS(k=2, n=3)   — seuil : 2 parts sur 3 suffisent pour reconstruire
P1 (utilisateur) + P2 (capitaine) + P3 (relais Nostr)

Reconstruction possible avec : P1+P2, P1+P3, ou P2+P3
→ Aucune part seule ne révèle la clé
→ Le Capitaine seul ne peut pas agir à la place de l'utilisateur
→ L'utilisateur seul (P1) peut récupérer avec P2 ou P3
```

---

## 3. Hyperrelativisme — Paramètres Dynamiques

### Principe

Dans la TRM standard, C² est une constante universelle (~4.88%/an dans Ğ1). Dans TrocZen v6, **C² est une observation locale** calculée depuis l'état réel du réseau à l'instant t.

De même pour α (multiplicateur compétence) et le "TTL optimal". Ce ne sont pas des réglages — ce sont des **instruments de mesure** qui lisent le réseau et produisent un signal.

### Calcul dynamique de C²_i(t)

```
C²_i(t) = vitesse_retour_médiane_i(t) / TTL_médian_i(t)
         × facteur_santé_i(t)
         × (1 + taux_croissance_N1_i(t))
```

Où :
- `vitesse_retour_médiane_i(t)` = âge médian des boucles fermées par i sur 30j glissants
- `TTL_médian_i(t)` = TTL médian des bons émis par i
- `facteur_santé_i(t)` = `loops_closed / zen_expired` sur 30j (ratio de santé)
- `taux_croissance_N1_i(t)` = `(N1_today - N1_30j_ago) / N1_30j_ago`

**Interprétation** : C²_i augmente quand les boucles se ferment vite ET que la masse reste saine ET que le réseau grandit. Il diminue quand les bons expirent sans retour ou quand le réseau stagne. C'est un **indicateur de vitalité** du sous-réseau de i.

### Calcul dynamique de α_i(t)

```
α_i(t) = corrélation(score_compétence_N1, vitesse_retour_bons_annotés)
         sur 30j glissants, dans le marché considéré
```

**Interprétation** : α mesure si la compétence *prédit* la vitesse de retour des bons dans ce marché. Si les bons annotés "maraîchage X3" reviennent plus vite que les bons non annotés, α monte. Si la compétence ne prédit rien dans ce marché, α → 0. C'est le marché lui-même qui vote pour la valeur du savoir-faire — pas les administrateurs.

### Calcul dynamique du TTL optimal_i(t)

```
TTL_optimal_i(t) = age_retour_médian_i(30j) × 1.5
                   borné entre 7j et 365j
```

C'est simplement la valeur suggérée à l'utilisateur lors de la création d'un bon. Pas une contrainte.

### Le Tableau de Navigation

Chaque utilisateur dispose d'un tableau personnel mis à jour quotidiennement :

```
Alice — Tableau de Navigation · J+365
┌─────────────────────────────────────────────────────────────────────┐
│ POSITION RÉSEAU                                                     │
│   N1=8 · N2=67 · N2/N1=8.4 (Tisseur)                              │
│   Marchés actifs : 2                                               │
├─────────────────────────────────────────────────────────────────────┤
│ PARAMÈTRES DYNAMIQUES (calculés depuis ton réseau)                  │
│   C²  = 0.094   ↑ (+12% vs mois dernier) — réseau en accélération  │
│   α   = 0.41    ↑ (+8%)  — maraîchage X3 bien valorisé ici        │
│   TTL = 21j     ↓ (-7j)  — tes bons reviennent plus vite          │
├─────────────────────────────────────────────────────────────────────┤
│ PRODUCTION                                                          │
│   DU base   = 14.2 ẐEN/j                                           │
│   DU comp.  = +4.1 ẐEN/j (maraîchage X3 × α=0.41)                 │
│   DU total  = 18.3 ẐEN/j · ~549 ẐEN/mois                          │
├─────────────────────────────────────────────────────────────────────┤
│ CIRCULATION                                                         │
│   Boucles ce mois : 14 · Ratio santé : 1.7×  🟢                   │
│   Bons en transit : 8 · Valeur : 127 ẐEN                          │
│   Taux expiration 30j : 11%  🟢 (< 20%)                           │
│   TTL résiduel moyen : 16.4j                                       │
├─────────────────────────────────────────────────────────────────────┤
│ POSITION RELATIVE (anonymisée)                                      │
│   DU : top 23% du marché Producteurs                               │
│   Boucles : top 15%                                                │
│   Compétence reconnue : top 8% (maraîchage X3)                    │
│                                                                     │
│   ⟶ Signal : "Réseau en croissance · Envisage TTL 21j"            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Architecture Technique Complète

### 4.1 Vue d'ensemble des composants

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         INFRASTRUCTURE                                  │
│                                                                         │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────────┐  │
│  │ TrocZen App  │    │  TrocZen Box     │    │  Astroport.ONE       │  │
│  │ (Client)     │◄──►│  (Relais Nostr   │◄──►│  (IPFS + Oracle      │  │
│  │              │    │   + calculs)     │    │   + WoTx2 + Capitaine│  │
│  └──────────────┘    └──────────────────┘    └──────────────────────┘  │
│         │                    │                         │                │
│         └────────────────────┴─────────────────────────┘               │
│                          Nostr Protocol                                 │
│                    (Kinds 0,3,4,30303,30304,30500–30503)                │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 4.2 TrocZen Box — Relais Nostr étendu

La TrocZen Box est un relais Nostr standard (ex: `strfry`, `nostr-rs-relay`) augmenté de **hooks de calcul** qui s'exécutent à la réception de certains événements.

#### Structure de fichiers

```
troczen-box/
├── relay/                    # Relais Nostr standard (strfry ou équivalent)
│   └── strfry.conf
├── hooks/                    # Hooks exécutés à la réception d'événements
│   ├── on_kind3.js           # Mise à jour du graphe social (N1/N2)
│   ├── on_kind30303.js       # Réception bon ẐEN → mise à jour masse
│   ├── on_kind30304.js       # Boucle fermée → mise à jour métriques
│   └── on_kind30503.js       # Credential WoTx2 → mise à jour scores
├── compute/                  # Moteur de calcul dynamique
│   ├── graph.js              # Calcul N1/N2 depuis Kind 3
│   ├── du_engine.js          # Calcul DU (base + multiplicateur)
│   ├── params_engine.js      # Calcul dynamique C², α, TTL optimal
│   ├── market_engine.js      # Taux inter-marchés émergents
│   └── navigation.js         # Tableau de navigation par utilisateur
├── store/                    # Cache local (LevelDB ou SQLite)
│   ├── graph.db              # État du graphe social
│   ├── bonds.db              # Bons actifs par marché
│   ├── metrics.db            # Métriques par utilisateur et marché
│   └── params.db             # Paramètres dynamiques calculés
└── api/                      # API REST pour l'app cliente
    ├── routes/
    │   ├── dashboard.js      # GET /api/dashboard/:npub
    │   ├── du.js             # GET /api/du/:npub/:market
    │   ├── params.js         # GET /api/params/:npub/:market
    │   └── bonds.js          # GET/POST /api/bonds/:market
    └── server.js
```

#### Hook `on_kind3.js` — Mise à jour du graphe social

```javascript
// hooks/on_kind3.js
// Exécuté à chaque réception d'un événement Kind 3 (Contact List)

const { getDB } = require('../store/graph');
const { recalcN1N2 } = require('../compute/graph');

module.exports = async function onKind3(event) {
  const db = getDB();
  const pubkey = event.pubkey;

  // Extraire la liste des follows de ce pubkey
  const follows = event.tags
    .filter(t => t[0] === 'p')
    .map(t => t[1]);

  // Mettre à jour le graphe orienté
  await db.put(`follows:${pubkey}`, JSON.stringify(follows));
  await db.put(`follows_at:${pubkey}`, event.created_at);

  // Recalculer N1 (liens réciproques) pour ce pubkey
  const n1 = [];
  for (const follow of follows) {
    const theirFollows = JSON.parse(await db.get(`follows:${follow}`).catch(() => '[]'));
    if (theirFollows.includes(pubkey)) {
      n1.push(follow);
    }
  }
  await db.put(`n1:${pubkey}`, JSON.stringify(n1));

  // Recalculer N2 (amis des amis réciproques, sans doublons)
  const n2Set = new Set();
  for (const friend of n1) {
    const friendN1 = JSON.parse(await db.get(`n1:${friend}`).catch(() => '[]'));
    for (const f of friendN1) {
      if (f !== pubkey && !n1.includes(f)) n2Set.add(f);
    }
  }
  await db.put(`n2:${pubkey}`, JSON.stringify([...n2Set]));

  // Invalider le cache DU pour ce pubkey (sera recalculé au prochain appel)
  await db.del(`du_cache:${pubkey}`).catch(() => {});

  // Déclencher recalcul des paramètres dynamiques (async, non bloquant)
  setImmediate(() => require('../compute/params_engine').recalc(pubkey));
};
```

#### Hook `on_kind30304.js` — Boucle fermée → métriques

```javascript
// hooks/on_kind30304.js
// Exécuté quand un BonCircuit est publié (boucle fermée)

const { getDB } = require('../store/metrics');
const { updateParams } = require('../compute/params_engine');
const { updateInterMarketRate } = require('../compute/market_engine');

module.exports = async function onKind30304(event) {
  const db = getDB();
  const content = JSON.parse(event.content);

  const {
    issued_by,       // émetteur original
    market_id,       // marché du bon
    value_zen,       // valeur
    age_days,        // âge du circuit (jours)
    hop_count,       // nombre de hops
    ttl_consumed,    // TTL consommé (%)
    dest_market_id,  // marché de destination si inter-marchés
    skill_cert       // annotation de compétence optionnelle
  } = content;

  const now = Date.now();
  const monthKey = new Date().toISOString().slice(0, 7); // "2026-02"

  // 1. Incrémenter boucles fermées pour l'émetteur
  const key = `loops:${issued_by}:${market_id}:${monthKey}`;
  const current = JSON.parse(await db.get(key).catch(() => '{"count":0,"ages":[],"hops":[]}'));
  current.count++;
  current.ages.push(age_days);
  current.hops.push(hop_count);
  if (skill_cert) current.skill_ages = current.skill_ages || [];
  if (skill_cert) current.skill_ages.push({ cert: skill_cert, age: age_days });
  await db.put(key, JSON.stringify(current));

  // 2. Mettre à jour taux inter-marchés si boucle traverse deux marchés
  if (dest_market_id && dest_market_id !== market_id) {
    await updateInterMarketRate(market_id, dest_market_id, value_zen, now);
  }

  // 3. Recalculer paramètres dynamiques de l'émetteur
  await updateParams(issued_by, market_id);

  // 4. Mettre à jour ratio de santé du marché
  const healthKey = `health:${market_id}:${monthKey}`;
  const health = JSON.parse(await db.get(healthKey).catch(() => '{"loops":0,"expired":0}'));
  health.loops++;
  await db.put(healthKey, JSON.stringify(health));
};
```

#### Moteur de calcul `params_engine.js` — C², α, TTL dynamiques

```javascript
// compute/params_engine.js
// Calcule dynamiquement C², α et TTL optimal pour un utilisateur dans un marché

const { getDB: getMetricsDB } = require('../store/metrics');
const { getDB: getBondsDB } = require('../store/bonds');

// Médiane d'un tableau
function median(arr) {
  if (!arr.length) return 0;
  const s = [...arr].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

// Corrélation de Pearson entre deux séries
function pearson(x, y) {
  const n = Math.min(x.length, y.length);
  if (n < 3) return 0;
  const mx = x.slice(0, n).reduce((a, b) => a + b) / n;
  const my = y.slice(0, n).reduce((a, b) => a + b) / n;
  const num = x.slice(0, n).reduce((s, xi, i) => s + (xi - mx) * (y[i] - my), 0);
  const den = Math.sqrt(
    x.slice(0, n).reduce((s, xi) => s + (xi - mx) ** 2, 0) *
    y.slice(0, n).reduce((s, yi) => s + (yi - my) ** 2, 0)
  );
  return den === 0 ? 0 : num / den;
}

async function recalc(npub, marketId) {
  const mdb = getMetricsDB();
  const bdb = getBondsDB();
  const monthKey = new Date().toISOString().slice(0, 7);
  const prevMonthKey = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 7);

  // ── 1. Lire les données de circulation des 30 derniers jours ──
  const loopsCurrent = JSON.parse(
    await mdb.get(`loops:${npub}:${marketId}:${monthKey}`).catch(() => '{"count":0,"ages":[],"hops":[]}')
  );
  const loopsPrev = JSON.parse(
    await mdb.get(`loops:${npub}:${marketId}:${prevMonthKey}`).catch(() => '{"count":0,"ages":[],"hops":[]}')
  );

  const expiredKey = `expired:${npub}:${marketId}:${monthKey}`;
  const expired = JSON.parse(await mdb.get(expiredKey).catch(() => '{"count":0,"values":[]}'));

  // TTL médian des bons émis par npub ce mois
  const emittedTTLs = JSON.parse(
    await bdb.get(`emitted_ttls:${npub}:${marketId}:${monthKey}`).catch(() => '[]')
  );

  // ── 2. Calcul C²_dynamique ──
  const medianReturnAge = median(loopsCurrent.ages);
  const medianTTL = median(emittedTTLs) || 28; // défaut 28j si pas d'historique
  const healthRatio = loopsCurrent.count / Math.max(expired.count, 0.1);
  const n1Growth = Math.max(0,
    (loopsCurrent.count - loopsPrev.count) / Math.max(loopsPrev.count, 1)
  );

  let c2 = 0.07; // valeur par défaut
  if (medianReturnAge > 0 && medianTTL > 0) {
    c2 = (medianReturnAge / medianTTL)
       * Math.min(healthRatio, 2.0)  // plafonné à 2
       * (1 + Math.min(n1Growth, 0.5));
    c2 = Math.max(0.02, Math.min(c2, 0.25)); // borné [0.02, 0.25]
  }

  // ── 3. Calcul α_dynamique ──
  // Corrélation entre niveau de compétence des N1 et vitesse de retour de leurs bons
  let alpha = 0.3; // valeur par défaut
  if (loopsCurrent.skill_ages && loopsCurrent.skill_ages.length >= 5) {
    const skillLevels = loopsCurrent.skill_ages.map(s => {
      const match = s.cert.match(/_X(\d+)$/);
      return match ? parseInt(match[1]) : 1;
    });
    const skillAges = loopsCurrent.skill_ages.map(s => s.age);
    const corr = pearson(skillLevels, skillAges.map(a => -a)); // corrélation inverse (haut niveau → retour rapide)
    alpha = Math.max(0, Math.min(corr * 0.8, 1.0)); // borné [0, 1]
  }

  // ── 4. TTL optimal ──
  const ttlOptimal = medianReturnAge > 0
    ? Math.round(Math.max(7, Math.min(365, medianReturnAge * 1.5)))
    : 28;

  // ── 5. Stocker les paramètres calculés ──
  const params = { c2, alpha, ttlOptimal, computedAt: Date.now(), medianReturnAge, healthRatio };
  await mdb.put(`params:${npub}:${marketId}`, JSON.stringify(params));

  return params;
}

// Lire les paramètres (depuis cache ou recalculer si > 24h)
async function getParams(npub, marketId) {
  const mdb = getMetricsDB();
  try {
    const cached = JSON.parse(await mdb.get(`params:${npub}:${marketId}`));
    if (Date.now() - cached.computedAt < 86400000) return cached; // cache 24h
  } catch {}
  return recalc(npub, marketId);
}

module.exports = { recalc, getParams, updateParams: recalc };
```

#### Moteur DU `du_engine.js` — Calcul complet avec multiplicateur

```javascript
// compute/du_engine.js
// Calcule DU_i(t+1) avec paramètres dynamiques

const { getDB: getGraphDB } = require('../store/graph');
const { getDB: getMetricsDB } = require('../store/metrics');
const { getDB: getBondsDB } = require('../store/bonds');
const { getParams } = require('./params_engine');

const DU_INITIAL = 10; // ẐEN/jour — constante fondamentale

async function calcDU(npub, marketId) {
  const gdb = getGraphDB();
  const mdb = getMetricsDB();
  const bdb = getBondsDB();

  // ── 1. Lecture du graphe social ──
  const n1 = JSON.parse(await gdb.get(`n1:${npub}`).catch(() => '[]'));
  const n2 = JSON.parse(await gdb.get(`n2:${npub}`).catch(() => '[]'));

  if (n1.length < 5) {
    return { du: 0, du_base: 0, du_skill: 0, reason: 'N1 < 5', n1: n1.length };
  }

  // ── 2. Lecture des masses monétaires actives ──
  const now = Date.now() / 1000;

  // M_n1 : somme des ẐEN actifs (TTL > now) des N1
  let m_n1 = 0;
  for (const friend of n1) {
    const bonds = JSON.parse(await bdb.get(`active_bonds:${friend}:${marketId}`).catch(() => '[]'));
    m_n1 += bonds.filter(b => b.expires_at > now).reduce((s, b) => s + b.value_zen, 0);
  }

  // M_n2 : somme des ẐEN actifs des N2
  let m_n2 = 0;
  for (const friend of n2) {
    const bonds = JSON.parse(await bdb.get(`active_bonds:${friend}:${marketId}`).catch(() => '[]'));
    m_n2 += bonds.filter(b => b.expires_at > now).reduce((s, b) => s + b.value_zen, 0);
  }

  // ── 3. DU précédent ──
  const prevDU = parseFloat(
    await mdb.get(`du_prev:${npub}:${marketId}`).catch(() => String(DU_INITIAL))
  );

  // ── 4. Paramètres dynamiques ──
  const { c2, alpha } = await getParams(npub, marketId);
  const sqN2 = Math.sqrt(Math.max(n2.length, 1));

  // ── 5. Formule TRM étendue ──
  const du_base_increment = c2 * (m_n1 + m_n2 / sqN2) / (n1.length + sqN2);
  const du_base = prevDU + du_base_increment;

  // ── 6. Score de compétence S_i ──
  const credentials = JSON.parse(
    await mdb.get(`credentials:${npub}:${marketId}`).catch(() => '[]')
  );
  // Lire les poids de compétences du marché (définis dans la seedMarket ou votes)
  const skillWeights = JSON.parse(
    await mdb.get(`skill_weights:${marketId}`).catch(() => '{}')
  );

  let s_i = 0;
  let certCount = 0;
  for (const cred of credentials) {
    const match = cred.permit_id.match(/_X(\d+)$/);
    const level = match ? parseInt(match[1]) : 1;
    const skillTag = cred.skill_tag; // ex: "maraîchage"
    const weight = skillWeights[skillTag] ?? 0;
    s_i += level * weight;
    certCount++;
  }
  if (certCount > 0) s_i /= certCount;

  // ── 7. DU final avec multiplicateur compétence ──
  const multiplier = 1 + alpha * s_i;
  const du_final = du_base * multiplier;
  const du_skill_bonus = du_base * (multiplier - 1);

  // Stocker pour le prochain calcul
  await mdb.put(`du_prev:${npub}:${marketId}`, String(du_final));
  await mdb.put(`du_last:${npub}:${marketId}`, JSON.stringify({
    du: du_final, du_base, du_skill: du_skill_bonus,
    c2, alpha, s_i, multiplier,
    n1: n1.length, n2: n2.length,
    m_n1, m_n2, computedAt: Date.now()
  }));

  return { du: du_final, du_base, du_skill: du_skill_bonus, c2, alpha, n1: n1.length, n2: n2.length };
}

module.exports = { calcDU, DU_INITIAL };
```

#### API `dashboard.js` — Tableau de navigation

```javascript
// api/routes/dashboard.js
const express = require('express');
const router = express.Router();
const { calcDU } = require('../../compute/du_engine');
const { getParams } = require('../../compute/params_engine');
const { getDB: getMetricsDB } = require('../../store/metrics');
const { getDB: getGraphDB } = require('../../store/graph');

// GET /api/dashboard/:npub
// Retourne le tableau de navigation complet pour un utilisateur
router.get('/:npub', async (req, res) => {
  const { npub } = req.params;
  const { market } = req.query; // optionnel, sinon tous les marchés actifs
  const mdb = getMetricsDB();
  const gdb = getGraphDB();
  const monthKey = new Date().toISOString().slice(0, 7);

  try {
    // Marchés actifs de l'utilisateur
    const markets = market
      ? [market]
      : JSON.parse(await gdb.get(`markets:${npub}`).catch(() => '[]'));

    const dashboard = {
      npub,
      computed_at: new Date().toISOString(),
      network: {
        n1: JSON.parse(await gdb.get(`n1:${npub}`).catch(() => '[]')).length,
        n2: JSON.parse(await gdb.get(`n2:${npub}`).catch(() => '[]')).length,
      },
      markets: []
    };

    for (const marketId of markets) {
      const du = await calcDU(npub, marketId);
      const params = await getParams(npub, marketId);
      const loops = JSON.parse(
        await mdb.get(`loops:${npub}:${marketId}:${monthKey}`)
          .catch(() => '{"count":0,"ages":[],"hops":[]}')
      );
      const expired = JSON.parse(
        await mdb.get(`expired:${npub}:${marketId}:${monthKey}`)
          .catch(() => '{"count":0}')
      );
      const marketRank = JSON.parse(
        await mdb.get(`rank:${npub}:${marketId}:${monthKey}`)
          .catch(() => '{"du_percentile":50,"loops_percentile":50}')
      );

      dashboard.markets.push({
        market_id: marketId,
        du: {
          daily: Math.round(du.du * 100) / 100,
          monthly: Math.round(du.du * 30 * 100) / 100,
          base: Math.round(du.du_base * 100) / 100,
          skill_bonus: Math.round(du.du_skill * 100) / 100,
          multiplier: Math.round((1 + du.alpha * (du.s_i || 0)) * 100) / 100
        },
        params: {
          c2: Math.round(params.c2 * 1000) / 1000,
          alpha: Math.round(params.alpha * 100) / 100,
          ttl_optimal_days: params.ttlOptimal,
          health_ratio: Math.round(params.healthRatio * 100) / 100
        },
        circulation: {
          loops_this_month: loops.count,
          median_return_age_days: Math.round(params.medianReturnAge * 10) / 10,
          expired_this_month: expired.count,
          expiration_rate: loops.count + expired.count > 0
            ? Math.round(expired.count / (loops.count + expired.count) * 100) + '%'
            : 'N/A'
        },
        position: {
          du_percentile: marketRank.du_percentile,
          loops_percentile: marketRank.loops_percentile
        },
        signal: buildSignal(params, du, loops, expired)
      });
    }

    res.json(dashboard);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Génère un signal textuel simple depuis les indicateurs
function buildSignal(params, du, loops, expired) {
  const signals = [];
  if (params.healthRatio < 1.0) signals.push('⚠️ Taux d\'expiration élevé — réseau à revitaliser');
  if (params.c2 > 0.12) signals.push('🚀 Réseau en forte accélération');
  if (params.ttlOptimal < 14) signals.push(`⚡ Réseau rapide — envisage TTL ~${params.ttlOptimal}j`);
  if (params.alpha > 0.5) signals.push('⭐ Compétences très valorisées dans ce marché');
  if (params.alpha < 0.1) signals.push('ℹ️ Compétences peu différenciantes ici — pur TRM');
  if (signals.length === 0) signals.push('🟢 Réseau stable — continuer');
  return signals;
}

module.exports = router;
```

---

### 4.3 Application Cliente — Architecture

#### Structure

```
troczen-app/
├── src/
│   ├── identity/
│   │   ├── KeyManager.js          # Génération et stockage nsec local (P1)
│   │   ├── ProfileSync.js         # Sync Kind 0 vers relais
│   │   └── CaptainHandoff.js      # Transmission nsec au Capitaine (SSSS)
│   ├── market/
│   │   ├── SeedMarket.js          # Gestion des seeds, dérivation espace
│   │   ├── BonZero.js             # Création et propagation Bon Zéro
│   │   └── MarketSelector.js      # Multi-marchés, portefeuille segmenté
│   ├── bonds/
│   │   ├── BondFactory.js         # Création bons ẐEN (SSSS + HMAC path)
│   │   ├── BondTransfer.js        # Double scan P2P hors-ligne
│   │   ├── BondWallet.js          # Portefeuille, TTL tracker, alertes
│   │   └── BondBuyback.js         # Rachat volontaire (DM Kind 4)
│   ├── wotx2/
│   │   ├── CredentialViewer.js    # Affichage des 30503 de l'utilisateur
│   │   ├── SkillRequest.js        # Émettre un Kind 30501 (demande)
│   │   └── SkillAttest.js         # Émettre un Kind 30502 (attestation)
│   ├── dashboard/
│   │   ├── NavigationDash.js      # Tableau de navigation (appel /api/dashboard)
│   │   ├── ParamsChart.js         # Graphe C², α, TTL dans le temps
│   │   └── MarketMap.js           # Carte des marchés et perméabilité
│   └── nostr/
│       ├── NostrClient.js         # Client Nostr (publish, subscribe)
│       ├── EventBuilder.js        # Construction d'événements signés
│       └── HMACPath.js            # Calcul HMAC(pubkey, bon_id) pour path[]
```

#### `SeedMarket.js` — Gestion des seeds et HACKATHON

```javascript
// src/market/SeedMarket.js
import { sha256 } from '@noble/hashes/sha256';
import { hkdf } from '@noble/hashes/hkdf';
import { bytesToHex, hexToBytes } from '@noble/hashes/utils';

// La seed universelle publique
const HACKATHON_SEED = new Uint8Array(32).fill(0); // 000...0

export class SeedMarket {
  constructor(seedInput) {
    // Accepte string passphrase, bytes, ou null pour HACKATHON
    if (seedInput === null || seedInput === 'HACKATHON') {
      this.seed = HACKATHON_SEED;
      this.name = 'HACKATHON';
      this.isPublic = true;
    } else if (typeof seedInput === 'string') {
      this.seed = sha256(new TextEncoder().encode(seedInput));
      this.name = seedInput.slice(0, 20);
      this.isPublic = false;
    } else {
      this.seed = seedInput;
      this.name = bytesToHex(seedInput).slice(0, 16);
      this.isPublic = false;
    }
    this.marketId = bytesToHex(this.seed).slice(0, 16);
  }

  // Dériver la clé de chiffrement P3 depuis la seed
  deriveP3Key() {
    if (this.isPublic) return null; // HACKATHON : P3 non chiffré
    return hkdf(sha256, this.seed, 'p3-encryption-key', '', 32);
  }

  // Dériver le namespace Nostr (pour filtrer les events du marché)
  deriveNamespace() {
    return bytesToHex(hkdf(sha256, this.seed, 'nostr-namespace', '', 16));
  }

  // Chiffrer P3 (NIP-44 ou null pour HACKATHON)
  encryptP3(p3Bytes) {
    if (this.isPublic) return bytesToHex(p3Bytes); // En clair pour HACKATHON
    const key = this.deriveP3Key();
    // Chiffrement NIP-44 (ChaCha20-Poly1305)
    return nip44Encrypt(p3Bytes, key);
  }

  // Déchiffrer P3
  decryptP3(p3Encrypted) {
    if (this.isPublic) return hexToBytes(p3Encrypted); // Déchiffrement trivial
    const key = this.deriveP3Key();
    return nip44Decrypt(p3Encrypted, key);
  }

  // Sérialisation pour stockage local
  toJSON() {
    return {
      marketId: this.marketId,
      name: this.name,
      isPublic: this.isPublic,
      seedHash: bytesToHex(sha256(this.seed)) // jamais la seed elle-même
    };
  }
}
```

#### `BondFactory.js` — Création des Bons ẐEN

```javascript
// src/bonds/BondFactory.js
import { sha256, hmac } from '@noble/hashes/sha256';
import { bytesToHex, randomBytes } from '@noble/hashes/utils';
import { shamir } from './shamir'; // SSSS k=2, n=3
import { SeedMarket } from '../market/SeedMarket';

export class BondFactory {
  constructor(nsec, market) {
    this.nsec = nsec;           // Uint8Array — clé privée de l'émetteur
    this.npub = deriveNpub(nsec); // clé publique
    this.market = market;       // instance SeedMarket
  }

  // Créer un bon ẐEN
  create({ valueZen, ttlDays, actAnnotation = null }) {
    const bonId = bytesToHex(randomBytes(16));
    const issuedAt = Math.floor(Date.now() / 1000);
    const expiresAt = issuedAt + ttlDays * 86400;

    // Génération de la clé secrète du bon
    const nsecBon = randomBytes(32);

    // SSSS(nsec_bon) → P1, P2, P3
    const [p1, p2, p3] = shamir.split(nsecBon, { threshold: 2, shares: 3 });

    // Chiffrement de P3 selon la seed du marché
    const p3Encrypted = this.market.encryptP3(p3);

    // Initialisation du path avec le premier HMAC
    const path = [this.hmacHop(this.npub, bonId)];

    const bond = {
      bon_id: bonId,
      issued_by: this.npub,
      issued_at: issuedAt,
      expires_at: expiresAt,                // IMMUABLE
      ttl_seconds: ttlDays * 86400,
      value_zen: valueZen,
      hop_count: 0,
      path,
      market_id: this.market.marketId,
      p1,                                   // Stocké localement, jamais publié
      p3_encrypted: p3Encrypted,            // Publié sur Nostr (Kind 30303)
      act: actAnnotation                    // Annotation compétence optionnelle
    };

    return { bond, p1, p2, p3 };
  }

  // Calculer HMAC(pubkey, bon_id) pour path[]
  hmacHop(pubkey, bonId) {
    const key = typeof bonId === 'string' ? Buffer.from(bonId, 'hex') : bonId;
    const msg = typeof pubkey === 'string' ? Buffer.from(pubkey, 'hex') : pubkey;
    return bytesToHex(hmac(sha256, key, msg));
  }

  // Construire l'événement Nostr Kind 30303
  buildNostrEvent(bond) {
    return {
      kind: 30303,
      pubkey: this.npub,
      created_at: bond.issued_at,
      tags: [
        ['d', bond.bon_id],
        ['market', bond.market_id],
        ['expires', String(bond.expires_at)],
        ['value', String(bond.value_zen)],
        ...(bond.act ? [['skill_cert', bond.act.skill_cert]] : [])
      ],
      content: JSON.stringify({
        bon_id: bond.bon_id,
        issued_by: bond.issued_by,
        issued_at: bond.issued_at,
        expires_at: bond.expires_at,
        value_zen: bond.value_zen,
        hop_count: bond.hop_count,
        path: bond.path,
        market_id: bond.market_id,
        p3_encrypted: bond.p3_encrypted,
        act: bond.act
      })
    };
  }
}
```

#### `BondTransfer.js` — Double scan P2P hors-ligne

```javascript
// src/bonds/BondTransfer.js
// Protocole de transfert hors-ligne : Offre → ACK → Confirmation

import { hmac } from '@noble/hashes/sha256';
import { bytesToHex } from '@noble/hashes/utils';
import { signEvent, verifyEvent } from 'nostr-tools';

export class BondTransfer {

  // CÔTÉ ÉMETTEUR — Étape 1 : préparer l'offre (QR)
  static prepareOffer(bond, senderNsec) {
    const offer = {
      type: 'bond_offer',
      bon_id: bond.bon_id,
      value_zen: bond.value_zen,
      ttl_residual_seconds: bond.expires_at - Math.floor(Date.now() / 1000),
      hop_count: bond.hop_count,
      market_id: bond.market_id,
      offered_at: Math.floor(Date.now() / 1000),
      // NE PAS inclure P1 ni path complet dans l'offre
    };
    // Signer l'offre avec la clé de l'émetteur courant
    offer.signature = signOffer(offer, senderNsec);
    return offer; // Encodé en QR
  }

  // CÔTÉ RECEVEUR — Étape 2 : valider l'offre et générer ACK
  static receiveOffer(offer, receiverNpub) {
    // Vérifications avant acceptation
    if (offer.ttl_residual_seconds < 86400) {
      return { ok: false, reason: `TTL résiduel : ${Math.round(offer.ttl_residual_seconds / 3600)}h — trop faible` };
    }
    if (offer.ttl_residual_seconds < 259200) { // < 3j
      return { ok: false, reason: 'alert', ttlDays: Math.round(offer.ttl_residual_seconds / 86400) };
    }

    const ack = {
      type: 'bond_ack',
      bon_id: offer.bon_id,
      receiver: receiverNpub,
      acked_at: Math.floor(Date.now() / 1000),
    };
    ack.signature = signACK(ack, receiverNpub); // Signé avec la clé du receveur
    return { ok: true, ack };
  }

  // CÔTÉ ÉMETTEUR — Étape 3 : confirmer le transfert
  static confirmTransfer(bond, ack, receiverHmac) {
    if (!verifyACK(ack)) throw new Error('ACK invalide');

    // Mettre à jour le bon
    const updatedBond = {
      ...bond,
      hop_count: bond.hop_count + 1,
      path: [...bond.path, receiverHmac],  // HMAC(receiver.pubkey, bon_id)
      // expires_at INCHANGÉ — règle R2 absolue
    };

    return updatedBond;
  }

  // Calcul HMAC pour le nouveau hop
  static computeHopHMAC(receiverPubkey, bonId) {
    const key = Buffer.from(bonId, 'hex');
    const msg = Buffer.from(receiverPubkey, 'hex');
    return bytesToHex(hmac(sha256, key, msg));
  }
}
```

---

### 4.4 Table de correspondance complète — Kinds Nostr v6

| Kind | Standard Nostr | Usage TrocZen v6 | Émis par | Hook Box |
|---|---|---|---|---|
| `0` | Profil | + `troczen{}` : markets[], skills_declared[] | Utilisateur | `on_kind0` → mise à jour index découvrabilité |
| `3` | Contact List | WoT sociale → N1/N2 → DU | Utilisateur | `on_kind3` → recalc N1/N2/DU |
| `4` | DM chiffré | Demande de rachat volontaire (TTL < 3j) | Utilisateur | passthrough |
| `30303` | Parameterized Replaceable | Bon ẐEN (P3 chiffré selon seed) | Utilisateur | `on_kind30303` → update bonds.db |
| `30304` | Parameterized Replaceable | BonCircuit (boucle fermée) | Utilisateur | `on_kind30304` → update métriques, taux inter-marchés |
| `30500` | Parameterized Replaceable | WoTx2 — Définition permit | Oracle (UPLANETNAME_G1) | `on_kind30500` → index permits |
| `30501` | Parameterized Replaceable | WoTx2 — Demande d'apprentissage | Utilisateur | `on_kind30501` → queue Oracle |
| `30502` | Parameterized Replaceable | WoTx2 — Attestation par pair | Utilisateur certifié | `on_kind30502` → update attestation count |
| `30503` | Parameterized Replaceable | WoTx2 — Verifiable Credential W3C | Oracle | `on_kind30503` → update credentials, recalc DU |
| `22242` | NIP-42 Auth | Auth Oracle pour progression automatique | Oracle | relay standard |

---

### 4.5 Le Capitaine — Interface et code

```javascript
// src/identity/CaptainHandoff.js
// Transmission de la nsec à un Capitaine de marché

import { shamir } from './shamir';
import { encryptNIP44 } from 'nostr-tools/nip44';

export class CaptainHandoff {

  // Préparer le handoff : couper nsec en 3 parts SSSS
  static prepare(nsec, captainNpub) {
    const [p1, p2, p3] = shamir.split(nsec, { threshold: 2, shares: 3 });
    // P1 → reste sur le téléphone de l'utilisateur (stockage local chiffré)
    // P2 → envoyé au Capitaine via DM NIP-44
    // P3 → publié sur le relais Nostr (chiffré avec la clé du marché ou npub)

    // Chiffrer P2 pour le Capitaine (seul lui peut le lire)
    const p2Encrypted = encryptNIP44(p2, captainNpub);

    return { p1, p2Encrypted, p3 };
  }

  // Construire l'événement DM Kind 4 vers le Capitaine
  static buildDMToCapitain(p2Encrypted, captainNpub, marketId) {
    return {
      kind: 4,
      tags: [['p', captainNpub]],
      content: JSON.stringify({
        type: 'captain_handoff',
        market_id: marketId,
        p2: p2Encrypted,
        request: 'activate_ipfs_and_economy'
      })
    };
  }

  // Reconstruire la nsec depuis P1 (local) + P2 (Capitaine) ou P3 (Nostr)
  static reconstruct(p1, p2OrP3) {
    return shamir.combine([p1, p2OrP3]);
  }
}
```

---

## 5. Règles Protocolaires v6

| # | Règle | Implémentation |
|---|---|---|
| **R0** | HACKATHON = seed `000...0` | `HACKATHON_SEED = new Uint8Array(32).fill(0)` |
| **R0b** | P3 HACKATHON = non chiffré | `encryptP3 → identity si isPublic` |
| **R1** | TTL min 7j, max 365j | `assert 604800 ≤ ttl ≤ 31536000` |
| **R2** | `expires_at` immuable | Champ `readonly`, jamais modifié en transit |
| **R3** | Hop → `hop_count++` + HMAC path | `expires_at` inchangé |
| **R4** | C² calculé dynamiquement | `params_engine.recalc()` quotidien |
| **R5** | α calculé par corrélation Pearson | Entre skill level et vitesse retour |
| **R6** | Perméabilité inter-marchés = émergence | Taux calculé depuis Kind 30304 inter-marchés |
| **R7** | Retour émetteur = destruction | `issued_by == ma_pubkey` |
| **R8** | Expiration = archivage silencieux | |
| **R9** | Tableau de navigation mis à jour quotidiennement | Cache 24h, recalc sur event majeur |
| **R10** | `path[]` = HMAC uniquement | `HMAC-SHA256(pubkey_i, bon_id)` |
| **R11** | SSSS k=2/n=3 pour nsec Capitaine | P1 local, P2 Capitaine, P3 Nostr |
| **R12** | DU(0) = 10 ẐEN/jour | Constante fondamentale, seule valeur fixe |
| **R13** | skills_declared (Kind 0) ≠ S_i | Seuls Kind 30503 entrent dans S_i |
| **R14** | Pas de split de bon | Atomicité stricte |
| **R15** | N1 ≥ 5 pour DU actif | Inchangé |

---

## 6. Phrases Clés v6

> **"HACKATHON est le seul marché sans secret — c'est pourquoi c'est le plus grand acte de confiance."**

> **"Les paramètres ne se règlent pas. Ils se lisent."**

> **"La perméabilité entre marchés n'est pas une règle. C'est une conséquence."**

> **"Le Capitaine ne détient pas ton argent. Il détient la moitié de la clé qui te permet de le retrouver."**

> **"Ce n'est pas la richesse qui crée la confiance — c'est la confiance qui crée la richesse."**

---

*Protocole TrocZen · Bons ẐEN v6 · Hyperrelativiste · Fév. 2026*  
*WoTx2 & Oracle : Astroport.ONE / papiche — AGPL-3.0*  
*TrocZen Box : strfry + hooks Node.js*  
*App : Vanilla JS / React Native — Nostr-tools*
