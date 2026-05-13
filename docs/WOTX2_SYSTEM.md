# Système WoTxN (Web of Trust eXtended on Nostr)

Le système WoTxN permet de gérer les savoir-faire (skills) et les certifications croisées entre les participants du marché local TrocZen. **Depuis la v3.6, le système est entièrement P2P : aucun oracle centralisé n'intervient dans la progression des maîtrises auto-proclamées.**

## Événements Nostr utilisés

### 1. Définition de Savoir-Faire (Kind 30500)
Cet événement déclare l'existence d'un savoir-faire sur le marché.
- **Kind** : 30500
- **Tags** : `d` (ID du permit, ex: `PERMIT_BOULANGER_X1`), `t` (tag normalisé, ex: `boulanger`)
- **Contenu** : Chiffré avec la Seed du Marché (AES-GCM).
- **Signataire** : L'utilisateur lui-même (auto-déclaration folksonomique).
- **Usage** : Émis lors de l'onboarding ou de l'ajout d'un savoir-faire. Le tag `d` est calculé automatiquement depuis le tag normalisé.

### 2. Demande d'Attestation (Kind 30501)
Cet événement est émis par un utilisateur pour déclarer qu'il possède un savoir-faire et demander à être certifié par ses pairs.
- **Kind** : 30501
- **Tags** : `permit_id` (ex: `PERMIT_BOULANGER_X1`), `t` (tag normalisé)
- **Contenu** : Motivation (chiffrée avec la Seed du Marché).
- **Usage** : Émis lors de la finalisation de l'onboarding ou lors de l'ajout d'un nouveau savoir-faire.

### 3. Attestation de Savoir-Faire (Kind 30502)
Cet événement est émis par un pair pour certifier qu'un utilisateur possède le savoir-faire revendiqué.
- **Kind** : 30502
- **Tags** : `e` (ID de la demande 30501), `p` (npub du demandeur), `permit_id`, `t` (tag normalisé)
- **Contenu** : Motivation/Avis (chiffré avec la Seed du Marché).
- **Usage** : Émis lorsqu'un pair de niveau supérieur (Règle B — Adoubement) valide la compétence d'un utilisateur.

### 4. Accomplissement de Compétence (Kind 30503)
Cet événement matérialise la montée de niveau validée. Il est **auto-émis par le client Flutter** (non signé par l'Oracle).
- **Kind** : 30503
- **Tags** : `d` (ID du permit obtenu, ex: `PERMIT_BOULANGER_X2`), `t` (tag normalisé), `level` (numéro de niveau), `e` (IDs des événements justificatifs — Kind 7 ou Kind 30502)
- **Contenu** : JSON public non chiffré (`type`, `skill`, `level`, `timestamp`, `justifications`).
- **Signataire** : L'utilisateur lui-même. Les tags `e` constituent la preuve cryptographique intégrée.
- **Usage** : Publié automatiquement par le client après que `checkLevelUpgrade()` confirme que les conditions (Règle A ou B) sont satisfaites.

### 5. Réaction / Avis Client (Kind 7)
Cet événement exprime un avis positif ou négatif sur une compétence d'un pair.
- **Kind** : 7
- **Tags** : `e` (ID de l'événement de compétence cible), `p` (npub du pair évalué), `t` (`wotx-review`), `t` (tag normalisé de la compétence), `k` (`30500`)
- **Contenu** : `+` (pouce levé) ou `-` (pouce baissé)
- **Usage** : Contribue à la Règle A (3 avis `+` distincts → montée de niveau). Les avis `-` sont collectés mais leur traitement algorithmique (bifurcation de toile) est planifié (voir Roadmap §3.4).

---

## Processus de Bootstrap (Onboarding)

1. **Création du compte** : L'utilisateur génère ses clés cryptographiques (Nostr et Ğ1).
2. **Sélection des savoir-faire** : L'utilisateur choisit parmi les tags existants sur le relay, ou saisit un nouveau tag libre (folksonomie).
3. **Déclaration (Kind 30500)** : L'application publie une définition du savoir-faire (auto-signée), ce qui crée le permit `PERMIT_[TAG]_X1`.
4. **Demande d'attestation (Kind 30501)** : L'application publie une demande d'attestation pour initier la certification croisée.

---

## Normalisation des Savoir-Faire

Pour éviter la fragmentation de la Toile de Confiance (ex: "Maraîcher" vs "maraicher"), le protocole applique une normalisation stricte via `NostrUtils.normalizeSkillTag()` avant toute publication ou filtrage :
1. Suppression de tous les accents et diacritiques.
2. Passage en minuscules.
3. Remplacement des espaces et caractères spéciaux par des tirets (`-`).

Ainsi, "Maître Pâtissier !" sera toujours indexé sous le tag unifié `maitre-patissier`.

---

## Mécanismes de Progression P2P (Sans Oracle)

Contrairement aux Permits Officiels d'Astroport (gérés par `ORACLE.refresh.sh`), le WoTx2 ne requiert aucune autorité centrale. La montée de niveau est calculée **localement par le client Flutter** via `CacheDatabaseService.checkLevelUpgrade()` et déclenche une auto-émission cryptographiquement prouvée.

### 3.1 Règle A — Consensus des Pairs (Kind 7)
Si un utilisateur reçoit **3 réactions positives** (Kind 7, contenu `+`) de **3 pairs distincts** sur un même tag de compétence, le client l'autorise à publier un Skill Achievement (Kind 30503) le propulsant au niveau supérieur. Les 3 IDs d'événements Kind 7 sont inclus comme justifications (`e` tags).

### 3.2 Règle B — Adoubement (Kind 30502)
Une seule attestation formelle (Kind 30502) d'un utilisateur possédant déjà un niveau supérieur suffit pour déclencher la montée de niveau. Le Kind 30502 valide se substitue aux 3 Kind 7.

> **Note d'implémentation** : dans le code actuel ([cache_database_service.dart:1322](../troczen/lib/services/cache_database_service.dart#L1322)), le niveau de l'attestateur n'est pas encore vérifié dynamiquement (TODO). L'interface de scan ([skill_swap_screen.dart:114](../troczen/lib/screens/skill_swap_screen.dart#L114)) affiche le bouton "Badge Expert" (Kind 30502) uniquement si `myLevel > 1`, mais `myLevel` est en dur à `1` pour l'instant.

### 3.3 Flux de Vérification

```
Utilisateur appuie sur "Vérifier mes montées de niveau"
  │
  ▼
checkLevelUpgrade(npub, skill, currentLevel)
  │
  ├─ Règle B : Y a-t-il un Kind 30502 reçu pour ce skill ?
  │    └─ OUI → canUpgrade = true, rule = 'B', justifications = [event_id]
  │
  └─ Règle A : Y a-t-il ≥ 3 Kind 7 positifs distincts pour ce skill ?
       └─ OUI → canUpgrade = true, rule = 'A', justifications = [3 event_ids]

Si canUpgrade = true :
  → publishSkillAchievement(npub, nsec, skill, newLevel, justificationEventIds)
  → Publie Kind 30503 auto-signé avec les justifications intégrées
  → Animation de célébration
```

---

## Folksonomie et Nuage de Mots-Clefs

Les compétences ne sont pas pré-définies dans une liste centrale. Elles **émergent organiquement** du réseau par l'usage libre des tags.

- Exemples : `boulanger`, `sans-gluten`, `boulangerie-artisanale`, `pain-au-levain`
- Chaque client recalcule son nuage de compétences en scannant les profils du relay (Kind 0) via `fetchActivityTagsFromProfiles()`, qui extrait :
  - Les tags explicites (`t` dans les metadata)
  - Le champ `activity` et `profession`
  - Les hashtags dans le champ `about`
- Les tags combinés (ex: `boulanger` + `sans-gluten`) permettent de créer des sous-marchés thématiques sans coordination centrale.

---

## Roadmap : Dislikes et Bifurcations de Toile

### État actuel
Les avis négatifs (Kind 7 avec contenu `-`) sont **collectés et stockés** dans le cache local (`_skillReactionsTable`, colonne `is_positive = 0`). Ils n'influencent pas encore la logique de progression.

### Implémentation prévue
Un algorithme permettra la **bifurcation des toiles de confiance** : si un fort consensus négatif émerge sur un tag de compétence pour un utilisateur, le graphe social diverge localement — créant des sous-marchés aux évaluations subjectives différentes de cette compétence. Cela produira de nouvelles toiles relatives sans invalider les toiles existantes.

Exemple concret : `boulanger` avec consensus positif → toile A. `boulanger` avec 5 dislikes → toile B séparée. Les deux coexistent sur le relay, chaque client calculant la sienne depuis son point de vue N1/N2.

---

## Comparaison avec les Permits Officiels (Oracle)

| Aspect | WoTx2 (Folksonomie P2P) | Permits Officiels (Oracle) |
|--------|-------------------------|---------------------------|
| **Création** | Auto-déclaration par l'utilisateur (Kind 30500) | Par administrateur (`UPLANETNAME_G1`) |
| **Tags** | Libres (folksonomie) | Définis à la création |
| **Validation** | Calcul local par le client Flutter | Script centralisé `ORACLE.refresh.sh` |
| **Émission Kind 30503** | Auto-signé par l'utilisateur (avec preuves) | Signé par la clé Oracle |
| **Progression** | Dynamique via Règle A (3 pairs) ou Règle B (Adoubement) | Statique (1 niveau) |
| **Philosophie** | Bottom-Up (Pairs) | Top-Down (Autorité) |
| **Oracle requis** | Non | Oui |
