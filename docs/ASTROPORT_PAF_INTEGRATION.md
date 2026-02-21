# Intégration de la PAF (Participation Aux Frais) sur Astroport / TrocZen Box

Ce document décrit l'architecture technique pour intégrer le modèle économique du G1FabLab (Armateur / Capitaine) directement dans la TrocZen Box (Relais Nostr / API / IPFS).

L'objectif est de permettre aux opérateurs de l'infrastructure de fixer une PAF en ẐEN, qui servira d'unité de compte interne pour justifier des paiements en euros (remboursements de frais ou factures) via Open Collective, tout en respectant strictement la licence AGPL.

---

## 1. Le Modèle Économique (Rappel)

- **Le ẐEN n'est pas une monnaie spéculative**, c'est une unité de compte interne (comptabilité analytique).
- **Armateur** : Celui qui héberge la machine (fournit l'électricité, la connexion internet, le matériel).
- **Capitaine** : Celui qui configure, maintient et met à jour le système (travail humain).
- **PAF (Participation Aux Frais)** : Un montant fixe en ẐEN demandé aux utilisateurs pour accéder aux services du relais.

---

## 2. Configuration de la Box (Côté Serveur)

Sur le Raspberry Pi (TrocZen Box), nous ajoutons un fichier de configuration `astroport.json` à la racine de l'API Flask.

```json
{
  "relay_name": "TrocZen Box - Marché de Toulouse",
  "paf_zen": 5.0,
  "paf_period": "monthly",
  "operators": {
    "armateur": {
      "npub": "npub1_romain_...",
      "share": 0.33
    },
    "capitaine": {
      "npub": "npub1_fred_...",
      "share": 0.67
    }
  }
}
```

L'API Flask (`api_backend.py`) expose une nouvelle route publique :
`GET /api/paf` -> Renvoie le contenu de ce fichier JSON.

---

## 3. L'Expérience Utilisateur (Côté App Flutter)

Le flux dans l'application TrocZen est conçu pour être transparent et pédagogique :

1. **Détection** : Quand l'utilisateur se connecte au Wi-Fi du marché, l'application interroge `/api/paf`.
2. **Vérification locale** : L'application vérifie dans son historique (SQLite) si l'utilisateur a déjà payé la PAF pour la période en cours (ex: ce mois-ci).
3. **La Modale de Contribution** : Si la PAF n'est pas payée, une modale s'affiche :
   > *"Bienvenue sur le relais Astroport ! Pour soutenir l'infrastructure locale (hébergement et maintenance), une PAF de 5 ẐEN est demandée."*
   > Boutons : `[Contribuer (5 ẐEN)]` / `[Plus tard]`
4. **Le Paiement (Transfert P2P)** : 
   - Si l'utilisateur accepte, l'application sélectionne automatiquement des bons dans son wallet pour un total de 5 ẐEN.
   - Elle génère un événement de transfert Nostr (`Kind 1`) vers les `npub` de l'Armateur et du Capitaine, en répartissant la valeur selon les pourcentages définis (ex: 1.65 ẐEN pour l'Armateur, 3.35 ẐEN pour le Capitaine).
   - L'événement est publié sur le relais local.

---

## 4. Le "Proof of PAF" (Script Python)

Sur la TrocZen Box, un script Python tourne en tâche de fond pour écouter les événements Nostr et tenir la comptabilité.

### Algorithme du script (`paf_listener.py`) :
1. Se connecte au relais local `strfry` via WebSocket.
2. S'abonne aux événements `Kind 1` (Transferts) où le destinataire (`#p`) est l'Armateur ou le Capitaine.
3. Lorsqu'un transfert est détecté :
   - Vérifie la signature cryptographique du bon (pour éviter les faux paiements).
   - Enregistre la transaction dans une base de données SQLite locale (`paf_ledger.db`).
   - Met à jour le statut de l'utilisateur (son `npub`) comme "À jour de sa PAF" pour le mois en cours.

### Export Comptable :
L'API Flask expose une route sécurisée (protégée par mot de passe ou accessible uniquement en local) :
`GET /api/admin/export_paf` -> Génère un fichier CSV.
Ce fichier CSV sert de **pièce comptable justificative** pour l'Armateur et le Capitaine lorsqu'ils soumettent leurs notes de frais ou factures sur la plateforme Open Collective.

---

## 5. Le Paywall Nostr (Optionnel / Mode Strict)

Si le collectif décide que la PAF est obligatoire pour utiliser le relais (et non plus basée sur le don volontaire), il est possible de configurer un "Paywall" au niveau du relais Nostr.

### Implémentation avec `strfry` :
Le relais `strfry` supporte des plugins d'authentification et de filtrage (via des scripts externes).
1. On active l'authentification NIP-42 (Authentication of clients to relays).
2. Quand un client essaie de publier un événement (ex: un nouveau bon `Kind 30303`), `strfry` appelle un script de validation.
3. Le script vérifie dans `paf_ledger.db` si le `npub` du client est à jour de sa PAF.
4. Si oui -> L'événement est accepté.
5. Si non -> L'événement est rejeté avec un message `NOTICE: PAF requise. Veuillez contribuer via l'application TrocZen.`

*Note : Pour préserver l'esprit de la Monnaie Libre, il est souvent préférable de commencer par le mode "Don volontaire" (sans Paywall strict) et de n'activer le Paywall que si l'infrastructure peine à se financer.*

---

## 6. Résumé des tâches de développement

Pour implémenter cette architecture, voici les tâches à réaliser :

**Côté TrocZen Box (Python) :**
- [ ] Créer `astroport.json` et la route `/api/paf` dans Flask.
- [ ] Créer le script `paf_listener.py` (écoute WebSocket Nostr + SQLite).
- [ ] Créer la route d'export CSV `/api/admin/export_paf`.

**Côté Application (Flutter) :**
- [ ] Ajouter un appel API vers `/api/paf` au démarrage ou lors de la connexion à un marché.
- [ ] Créer la modale UI de demande de PAF.
- [ ] Implémenter la logique de sélection automatique des bons pour atteindre le montant de la PAF.
- [ ] Générer et publier les événements `Kind 1` vers les opérateurs.
