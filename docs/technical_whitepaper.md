# Livre Blanc Technique de TrocZen
## Comprendre la monnaie ẐEN par le jeu, la cryptographie et l'analogie institutionnelle

**Version 1.1 – Février 2026**

---

### Introduction : Pourquoi ce document est différent

Ce livre blanc a deux objectifs :
1.  **Expliquer simplement** le fonctionnement technique de TrocZen à travers un **jeu de post‑it** que vous pouvez reproduire chez vous.
2.  **Définir précisément** l’architecture technique, le rôle de la monnaie libre Ğ1 comme régulateur, et l’analogie avec notre système monétaire traditionnel.

Que vous soyez commerçant, développeur ou simple curieux, vous trouverez ici les clés pour comprendre pourquoi TrocZen est une petite révolution.

---

## Partie 1 : Le Jeu des Post‑It
### (Comprendre la confiance sans banque)

Pour comprendre TrocZen, oublions d’abord les ordinateurs. Prenez une feuille de papier, des post‑it de trois couleurs différentes, et jouons.

#### Le contexte
Imaginez un **marché de producteurs** dans un village. Il n’y a pas de banque, pas d’Internet, et tout le monde se méfie un peu des faux billets. Pourtant, on veut pouvoir échanger des “droits à acheter” (des bons) de manière sûre.

#### Les rôles (les trois parts d’un bon)
Chaque bon de valeur (nous l’appellerons **ẐEN**) est représenté par un **secret** écrit sur un bout de papier. Pour le sécuriser, nous allons le découper en trois parts, comme on déchire une carte en trois morceaux. La magie du “secret sharing” (découpage de Shamir) veut que pour reconstituer le secret, il faut **2 morceaux sur les 3**. Un seul morceau ne sert à rien.

Donnons une couleur à chaque part et un rôle :

*   **🟦 Post‑it Bleu (P1 – l’Ancre)** : Il reste toujours chez **l’émetteur** du bon (le marchand qui a créé la réduction). Il est la preuve d’origine.
*   **🟩 Post‑it Vert (P2 – le Voyageur)** : C’est la part qui **circule** de main en main. Elle représente la valeur momentanée.
*   **🟥 Post‑it Rouge (P3 – le Témoin)** : Cette part est **affichée publiquement** sur la place du marché (sur un tableau de liège). Tout le monde peut la voir, mais elle est écrite dans un code secret que seuls les membres du marché comprennent.

#### Scénario 1 : La Création du Bon (Émission)
1.  **La Marchande Alice** veut offrir un bon d’achat de 10 Œufs. Elle écrit le secret “10 Œufs” sur un papier.
2.  Elle utilise une machine magique (qui représente la mathématique du secret sharing) pour découper ce secret en trois morceaux inintelligibles seuls : un Bleu, un Vert, un Rouge.
3.  **Action** :
    *   Elle garde le **🟦 Post‑it Bleu (P1)** dans son tiroir.
    *   Elle code le **🟥 Post‑it Rouge (P3)** avec un code secret partagé par tous les marchands du village (la clé du marché) et l’épingler sur le tableau public.
    *   Elle garde le **🟩 Post‑it Vert (P2)** dans sa poche, prêt à être donné.

#### Scénario 2 : Le Transfert du Bon (Donner et Recevoir)
Maintenant, Alice veut donner son bon à **Bob le Bûcheron**.

1.  **L’Offre (Donneur → Receveur)** :
    *   Alice sort son **🟩 Post‑it Vert (P2)**. Mais elle ne peut pas le donner comme ça, car si quelqu’un l’interceptait, il pourrait l’utiliser. Elle doit le protéger.
    *   Elle va au tableau public, regarde le **🟥 Post‑it Rouge (P3)** du bon. Elle en dérive un code de protection (un cadenas temporaire).
    *   Elle enferme son **🟩 Post‑it Vert** dans une enveloppe avec ce cadenas et le tend à Bob. (En vrai, c’est le QR code à durée de vie très courte.)
2.  **L’Acceptation (Receveur → Donneur)** :
    *   Bob reçoit l’enveloppe. Il ne peut pas l’ouvrir sans la clé. Il va aussi consulter le tableau public et trouve le **🟥 Post‑it Rouge (P3)** correspondant au bon.
    *   Grâce à ce P3, il peut déchiffrer le cadenas et ouvrir l’enveloppe. Il a maintenant en main le **🟩 Post‑it Vert**.
3.  **La Vérification et l’ACK (Accusé de Réception)** :
    *   Bob a maintenant deux morceaux : le **🟩 Vert (P2)** et le **🟥 Rouge (P3)** qu’il a pris sur le tableau. Il les assemble mentalement : il reconstitue le secret “10 Œufs”. Il vérifie que c’est bien le bon, que le compte est bon.
    *   Pour dire à Alice que tout est OK et que le transfert est FINI, Bob écrit un petit mot **“ACK, j’ai le bon !”** sur un papier (son propre QR code) et le tend à Alice.
4.  **La Finalisation** :
    *   Alice reçoit l’ACK. Elle peut maintenant **déchirer son 🟩 Post‑it Vert** original. Elle n’en a plus besoin, le bon n’est plus à elle. Le transfert est atomique et irréversible.

#### Pourquoi ce jeu est‑il génial ?
*   **Pas de banque centrale** : La confiance repose sur le fait que personne n’a les 3 morceaux. Le vendeur a P1, l’acheteur a P2, le tableau public a P3.
*   **Anti‑double dépense** : Si Alice essayait de donner son P2 à Charlie en même temps, elle ne pourrait pas car elle a dû le donner à Bob, et l’ACK de Bob l’oblige à le détruire. Et Charlie ne pourrait pas le déchiffrer sans le P3 correspondant.
*   **Offline** : Tout le monde a une copie locale du tableau public (les P3 sont téléchargés une fois par jour). Donc Bob peut déchiffrer sans être connecté au tableau à ce moment‑là.

---

## Partie 2 : L’Analogie avec les Institutions et la Régulation

Maintenant que le jeu est clair, superposons‑lui notre réalité économique.

#### Le système traditionnel (Euro €)
*   **L’Institution** : La Banque Centrale Européenne (BCE) est l’autorité centrale. Elle décide combien d’euros sont créés et à quelles conditions (taux d’intérêt, etc.). C’est une pyramide de confiance centralisée.
*   **L’Utilisateur** : Vous et moi, nous utilisons ces euros. Nous n’avons aucun droit de regard sur leur création. La confiance est un acte de foi en l’institution.

#### Le système TrocZen (Ğ1 et ẐEN)
Ici, nous remplaçons la pyramide par un réseau distribué.

*   **L’Institution de Premier Niveau : La Monnaie Libre Ğ1 (le “Socle de Confiance”)**
    *   La Ğ1 n’est pas créée par une banque, mais par un **Dividende Universel (DU)** distribué également à chaque membre humain (une fois identifié dans une “Toile de Confiance”).
    *   **Son rôle** : Elle est la **réserve de valeur fondamentale et le régulateur d’identité**. Posséder des Ğ1, c’est être reconnu comme un membre actif et fiable de la communauté élargie. L’institution, ici, c’est le **protocole mathématique** et la **communauté** qui le fait vivre.
    *   **Analogique** : La Ğ1, c’est comme l’or ou la confiance absolue dans un village. C’est ce qui est rare et distribué équitablement.

*   **L’Institution de Second Niveau : La Monnaie Locale ẐEN (les “Bons d’Échange”)**
    *   Les ẐEN sont créés par les commerçants et les membres de la communauté locale. Ce sont des **promesses d’achat**, des bons de réduction ou de service.
    *   **Problème** : Si tout le monde peut créer des ẐEN sans limite, on risque l’inflation locale ou la création de “fausses promesses”. Il faut une **régulation**.
    *   **La Solution : Le Jumelage Ğ1 ↔ ẐEN**
        *   Pour avoir le **droit d’émettre** des ẐEN, un commerçant doit **provisionner** son “compte d’émission” avec des Ğ1.
        *   **La règle est simple et transparente : 1 Ğ1 = 10 Ẑ**. (Ce taux est fixé pour l’exemple, il pourrait être variable selon les marchés.)
        *   Si un commerçant veut émettre pour 100 Ẑ de bons, il doit bloquer 10 Ğ1 dans un mécanisme de provisionnement (smart‑contract ou suivi local avec preuve cryptographique).

#### Comparaison Directe : L’Acte de Création Monétaire

| Concept | Système Euro (€) | Système TrocZen (Ğ1 ↔ ẐEN) |
| :--- | :--- | :--- |
| **Droit de créer** | Accordé par une banque centrale après analyse de crédit. | Accordé par la possession de Ğ1 (monnaie libre). |
| **Régulation** | Centralisée, opaque (taux directeurs). | Décentralisée, transparente (taux de change fixe et provisionnement). |
| **Garantie** | Garantie par l’État et la banque centrale. | Garantie par la cryptographie (le jeu de post‑it) et la confiance du réseau Ğ1. |
| **Identité** | Identité légale (papiers, KYC). | Identité vivante (Toile de Confiance Ğ1) + Identité numérique (Nostr). |
| **But** | Fluidifier l’économie nationale. | Fluidifier l’économie locale en reliant l’identité vivante à la capacité d’échange. |

**En clair :** Dans le système Euro, l’institution bancaire dit “*Tu as le droit de créer de la valeur (via un prêt) parce que nous analysons ton dossier*”. Dans TrocZen, le protocole dit “*Tu as le droit de créer des ẐEN parce que tu es un membre actif de la communauté Ğ1, et tu en apportes la preuve en provisionnant une partie de ta confiance (tes Ğ1).*”

C’est un passage d’une **confiance hiérarchique** à une **confiance distribuée et mathématiquement prouvée**.

---

## Partie 3 : L’Architecture Technique en Détail

*(Pour les développeurs et les curieux techniques)*

### 3.1. Les Composants Clés

*   **Identité Nostr** : Chaque utilisateur et chaque bon ẐEN est une paire de clés (`nsec`/`npub`) sur le protocole Nostr. Le `npub_bon` est son identifiant public.
*   **SSSS (Shamir’s Secret Sharing Scheme)** : Algorithme utilisé pour diviser la `nsec_bon` (la clé privée du bon) en 3 parts (P1, P2, P3). Seuil requis pour reconstituer la clé : 2 parts.
*   **Chiffrement AES‑GCM** : Utilisé pour :
    *   Chiffrer P3 avec une clé dérivée quotidiennement (voir §3.4) avant publication sur Nostr.
    *   Chiffrer P2 avec `K_P2 = SHA256(P3)` lors du transfert.
*   **QR Code Binaire** : Format compact de 113 octets transportant `{bon_id, p2_cipher, nonce, challenge, timestamp, ttl}`.
*   **Stockage Local** : `FlutterSecureStorage` pour les clés utilisateur et la graine du marché. Base de données locale chiffrée pour les bons et les P3.
*   **Nostr (kind 30303)** : Utilisé comme registre public et décentralisé pour les `P3_chiffrés` des bons.

### 3.2. Workflow Technique (Cycle de Vie d’un Bon)

#### 3.2.1. Émission (Avec Provisionnement Ğ1)
1.  **Vérification** : L’application vérifie que le portefeuille Ğ1 de l’utilisateur a un solde suffisant pour provisionner l’émission (ex: pour créer 100 Ẑ, il faut 10 Ğ1 bloqués). Ce mécanisme est géré par un oracle ou un contrat sur la blockchain Ğ1 (ou un simple suivi local avec preuve cryptographique).
2.  **Création du Bon** :
    *   Génération d’une nouvelle paire de clés Nostr (`nsec_bon`, `npub_bon`).
    *   Application de SSSS sur `nsec_bon` → obtention de `P1`, `P2`, `P3`.
3.  **Publication** :
    *   Calcul de la clé du jour `K_day` à partir de la graine du marché (voir §3.4).
    *   Chiffrement de `P3` avec `K_day` → `P3_cipher`.
    *   Création et publication d’un événement Nostr de kind **30303** contenant `npub_bon`, `P3_cipher` et le timestamp du jour.
4.  **Stockage Local** :
    *   `P1` est stocké localement (c’est l’ancre).
    *   `P2` est stocké comme “disponible” dans le portefeuille.
    *   Le `npub_bon` et les métadonnées (valeur, émetteur) sont enregistrés.

#### 3.2.2. Synchronisation et Cache des P3
1.  L’application interroge périodiquement le ou les relais Nostr configurés.
2.  Elle filtre les événements kind **30303** du marché.
3.  Pour chaque `P3_cipher` reçu, elle utilise le timestamp pour calculer la `K_day` correspondante (via la graine) et tente de déchiffrer.
4.  En cas de succès, elle stocke le triplet `{npub_bon, P3, métadonnées}` dans un cache local sécurisé.

#### 3.2.3. Transfert
1.  **Donneur** :
    *   Sélectionne un bon (qui contient `P2` en clair dans son portefeuille).
    *   Récupère `P3` du cache local (associé au `npub_bon`).
    *   Calcule `K_P2 = SHA256(P3)`.
    *   Chiffre `P2` avec AES‑GCM en utilisant `K_P2` et un nonce aléatoire → `P2_cipher`.
    *   Construit le payload binaire du QR : `{npub_bon, P2_cipher, nonce, challenge, timestamp, ttl}`.
    *   Affiche le QR code.
2.  **Receveur** :
    *   Scanne le QR code, extrait `npub_bon` et `P2_cipher`.
    *   Cherche dans son cache local le `P3` associé à `npub_bon`.
    *   Calcule `K_P2 = SHA256(P3)` et déchiffre `P2_cipher` → obtient `P2`.
    *   **Reconstitution temporaire** : Assemble `P2` et `P3` pour reformer `nsec_bon`.
    *   Vérifie la signature d’un message de défi avec `nsec_bon` pour authentifier le bon.
    *   Si tout est correct, stocke `P2` dans son propre portefeuille (le bon lui appartient maintenant) et génère un QR code **ACK** contenant la confirmation signée.
3.  **Finalisation (Donneur)** :
    *   Scanne le QR code **ACK** du receveur.
    *   Vérifie la signature pour confirmer que le receveur a bien pris possession du bon.
    *   **Supprime définitivement** `P2` de son portefeuille local.

### 3.3. Sécurité et Régulation par la Ğ1

*   **Limitation de l’Émission** : Le provisionnement en Ğ1 est une preuve cryptographique de “poids” dans la communauté. Il empêche la création massive et non souveraine de ẐEN. C’est une forme de **preuve de réserve**.
*   **Révocation** : Si un bon est émis frauduleusement, l’émetteur peut utiliser sa `P1` pour le révoquer, mais cela pourrait entraîner la perte de sa provision en Ğ1 (mécanisme de “slashing” à définir).
*   **Confidentialité** : Les transferts sont visibles localement mais pas sur Nostr. Seule la création (`P3`) est publique (mais chiffrée). La vie privée des transactions est préservée.

### 3.4. Gestion Simplifiée de la Clé de Marché : La Graine Quotidienne

Dans la version initiale, la clé du marché (`K_market`) changeait chaque jour, ce qui obligeait les smartphones à se synchroniser quotidiennement pour obtenir la nouvelle clé, complexifiant la gestion du cache et la disponibilité hors ligne. Pour simplifier tout en conservant une sécurité forte, nous introduisons une **graine de marché** (`seed_market`).

*   **Distribution initiale** : La `seed_market` est une chaîne aléatoire de 256 bits (ou plus) distribuée **une seule fois** aux membres du marché, hors ligne, via un QR code imprimé, une page web locale ou une transmission NFC. Cette graine est stockée de manière sécurisée sur chaque appareil (par exemple dans `FlutterSecureStorage`).
*   **Dérivation quotidienne** : À partir de cette graine, chaque appareil peut calculer de manière déterministe la clé de chiffrement pour un jour donné en utilisant une fonction de dérivation robuste (par exemple HMAC‑SHA256) :
    `K_day = HMAC-SHA256(seed_market, "daily-key-" || YYYY-MM-DD)`
    où `YYYY-MM-DD` est la date du jour au format ISO.
*   **Publication des P3** : Lors de la création d’un bon, l’émetteur chiffre `P3` avec la `K_day` du jour courant (ou du jour de validité du bon) et publie l’événement Nostr avec un timestamp. Le timestamp permet au receveur de savoir quelle `K_day` utiliser pour déchiffrer.
*   **Synchronisation** : Les smartphones n’ont plus besoin de recevoir une nouvelle clé chaque jour. Ils téléchargent simplement les nouveaux événements Nostr et déchiffrent les `P3` en utilisant la `K_day` correspondante, calculée localement à partir de la graine. Le cache des `P3` déchiffrés est conservé localement.
*   **Sécurité** : La sécurité repose sur la confidentialité de la `seed_market`. Si elle est compromise, il faut la changer, ce qui nécessite une redistribution. Pour limiter l’impact, on peut prévoir une rotation de la graine à intervalle long (par exemple annuel) ou utiliser un mécanisme de révocation basé sur une liste noire publiée sur Nostr.

Cette approche combine la robustesse du chiffrement quotidien (limitant l’impact d’une compromission de clé journalière) avec la simplicité d’une distribution unique. Elle permet également un fonctionnement hors ligne prolongé, car une fois la graine installée, l’appareil peut déchiffrer tous les P3 des jours passés et futurs sans connexion supplémentaire.

---

#### Partie 4 : Le ẐEN comme Pont vers la Société des Communs

Au-delà de la technique, cette architecture ouvre des perspectives philosophiques et politiques majeures, en phase avec le projet **UPlanet**.

### 4.1. Le ẐEN : Capturer la Valeur de l'Ancien Monde pour les Communs

Le ẐEN devient un **outil de comptabilité coopérative**. Il permet de gérer l'inévitable interaction avec le "monde de la dette" (l'économie en Euros) sans contaminer la pureté du Dividende Universel (DU) de la Ğ1.

*   **Le constat** : Pour construire des communs (serveurs, ateliers, fermes), nous devons encore acheter du matériel dans le système Euro. Comment financer ces achats sans tomber dans la spéculation ou la dépendance ?
*   **La solution ẐEN** : Un contributeur qui apporte un bien ou un service payé en Euros (ex: achat d'un serveur, heures de travail facturées) peut être **crédité en ẐEN** par la communauté, selon un taux de conversion défini collectivement. Il a alors le choix :
    *   **Convertir** ses ẐEN en Euros (via une caisse commune) pour se rembourser.
    *   **Conserver** ses ẐEN. Dans ce cas, il fait don de sa créance à la communauté. Les ẐEN non convertis deviennent la **valeur capturée à l'ancien monde**, qui vient abonder le trésor de guerre des communs.

**C'est ainsi que le travail bénévole, ou l'apport en nature, se transforme en capital collectif, mesuré et traçable via le ẐEN, sans passer par un mécanisme de dette.**

### 4.2. Comprendre la Nécessité de la Ğ1 : Le DU comme Droit de Vote

Le mécanisme de provisionnement (1 Ğ1 = 10 Ẑ) n'est pas qu'une règle technique. C'est une **leçon d'économie politique** pour l'utilisateur.

*   Pour créer des ẐEN (et donc participer à l'économie locale), il faut **d'abord posséder des Ğ1**.
*   Et pour posséder des Ğ1, il faut **être membre de la Toile de Confiance** et recevoir le **Dividende Universel (DU)**.
*   Le DU n'est pas un simple revenu. Dans cette vision élargie, il devient un **point de vote**, une preuve de participation à la communauté. Plus on reçoit de DU (car on est membre depuis longtemps), plus on a de poids pour :
    *   Proposer de nouveaux projets.
    *   Valider l'émission de ẐEN pour des projets collectifs.
    *   Participer aux décisions sur la répartition des ressources (les 3×1/3 : Trésorerie, R&D, Actifs).

Ainsi, le circuit Ğ1 → ẐEN crée une **démocratie des contributeurs**, où le pouvoir de vote est proportionnel à l'ancienneté et à la participation, et non à la richesse accumulée.

### 4.3. Le Triptyque Ğ1 / ẐEN / Euro : Un Système à Trois Étages

Nous arrivons à une vision claire d'un système monétaire et social à trois niveaux, en parfaite cohérence avec les piliers d'UPlanet.

| Niveau | Monnaie / Outil | Rôle | Origine | Gouvernance |
| :--- | :--- | :--- | :--- | :--- |
| **1. Socle de Confiance** | **Ğ1 (June)** | Mesure de la valeur relative, Dividende Universel, droit de vote. | Création monétaire égalitaire par le DU. | Toile de Confiance (1 humaine = 1 voix). |
| **2. Outil d'Échange Local** | **ẐEN** | Monnaie d'usage quotidien, bons de réduction, comptabilité des communs. | Création par provisionnement de Ğ1 (1Ğ1 = 10Ẑ). | Communauté locale (via les portefeuilles Ğ1/ẐEN). |
| **3. Interface avec l'Ancien Monde**| **Euro (€)** | Achats externes, paiement des factures du monde "dette". | Apports des contributeurs, conversion de ẐEN. | Caisse commune, gérée par la communauté. |

### 4.4. Une Invitation à l'Action : Rejoindre le Mouvement

Ce modèle technique n'est pas une utopie. Il est en cours de construction. Rejoindre TrocZen et UPlanet, c'est choisir de :

1.  **Devenir acteur** de son économie locale en utilisant et en émettant des ẐEN.
2.  **Comprendre** la monnaie libre en recevant son DU Ğ1 et en voyant comment il permet de créer de la valeur locale.
3.  **Contribuer** aux projets de la communauté (logiciels, matériels low-tech, communs) et être rétribué en ẐEN pour ses apports.
4.  **Voter** avec son DU pour orienter les ressources collectives vers les projets qui construisent la résilience commune (énergie, information, inclusion).

Comme l'explique la page UPlanet, il s'agit de passer d'un monde de "services publics" verticaux à un monde de **"biens communs" horizontaux**, où chaque utilisateur est un **bâtisseur souverain**. Le ẐEN est l'outil comptable qui rend cette transition possible et transparente.

---

## Conclusion : Une Nouvelle Souveraineté Monétaire

TrocZen, adossé à la Ğ1 et intégré à la vision d'UPlanet, n'est pas juste une application de bons de réduction. C'est un **protocole d'émission monétaire décentralisé** et un **outil de gouvernance des communs**. Il démontre qu'il est possible de créer de la valeur locale (les ẐEN) en s'ancrant sur une monnaie libre et équitable (la Ğ1), et d'utiliser cette dynamique pour financer collectivement les infrastructures de notre autonomie.

C'est un pas vers une société où l'acte de créer de la monnaie n'est plus un privilège institutionnel, mais une **capacité répartie**, liée à notre existence et à notre contribution au sein de la communauté. Le marché devient alors un espace de handshakes atomiques où la confiance n'est plus un postulat, mais une propriété émergente du système, au service de la construction d'un monde résilient et désirable.


---

**Pour contribuer, poser des questions ou signaler un bug :** [Lien vers les Issues GitHub](https://github.com/papiche/troczen/issues)

**Pour aller plus loin :**
- [Dépôt GitHub de Astroport.ONE](https://github.com/papiche/Astroport.ONE)
- [Site de la Monnaie Libre Ğ1](https://monnaie-libre.fr)
- [La vision UPlanet](https://ipfs.copylaradio.com/ipns/copylaradio.com/Unation.html)