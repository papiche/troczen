# TrocZen : De la Monnaie Libre Quantitative à l'Économie Circulaire Qualitative

*Cet article est destiné à être publié sur le forum de la Monnaie Libre (forum.monnaie-libre.fr) et le forum technique Duniter (forum.duniter.org).*

---

Bonjour à tous,

Après plusieurs mois de recherche et développement, je suis très heureux de vous présenter **TrocZen (le ẐEN)**, une application mobile open-source conçue pour résoudre certains des défis les plus tenaces que nous rencontrons sur le terrain avec la Ğ1, notamment sur les Gmarchés.

TrocZen n'est pas une nouvelle blockchain, ni un concurrent de Duniter. C'est une **couche locale, hors-ligne et qualitative** qui s'inspire de la TRM pour créer des boucles d'économie circulaire résilientes.

## 1. Le Constat : Les limites de la fongibilité absolue

Notre expérience collective avec la Ğ1 a mis en évidence un phénomène économique connu : **le déséquilibre entre les biens et les services**. 
Dans la Ğ1, la monnaie est parfaitement fongible et anonyme. Un DU créé par un masseur est mathématiquement identique à un DU créé par un maraîcher. Or, produire des légumes coûte des euros (intrants, matériel, carburant), tandis qu'offrir un massage coûte principalement du temps. 

Résultat : les producteurs de biens physiques peinent à écouler leurs Ğ1 car ils ne peuvent pas payer leurs fournisseurs avec. Le marché a tendance à se remplir de services et à se vider de biens de première nécessité. Certains ont proposé de séparer artificiellement les marchés, mais cela va à l'encontre de la fluidité des échanges.

**Comment TrocZen aborde ce problème ? En rendant la monnaie "Qualitative".**

Dans TrocZen, un ẐEN n'est pas juste un chiffre dans un solde de compte. C'est un objet cryptographique unique (une sorte de "carte à collectionner") qui porte son propre ADN :
- **Son émetteur** (Qui a créé ce bon ?)
- **Sa catégorie** (Est-ce un bien agricole, un service, de l'artisanat ?)
- **Son Vœu** (Une intention économique, ex: *"Je recherche du Houblon"*)

Le marché s'auto-régule naturellement : un utilisateur verra visuellement s'il accepte un bon "Alimentation" ou un bon "Service", et pourra appliquer ses propres taux de change implicites.

## 2. L'Expérience Utilisateur : Le "Mode Miroir" 100% Hors-Ligne

Sur un marché local, la 4G passe souvent mal. TrocZen est conçu **Offline-First**.
L'échange d'un bon se fait par un transfert atomique de smartphone à smartphone, sans aucun serveur central au moment de la transaction.

Pour rendre cela magique, nous avons développé le **Mode Miroir** :
1. Alice clique sur "Donner", Bob sur "Recevoir".
2. L'écran de chaque téléphone se divise en deux : la moitié haute affiche un QR Code, la moitié basse active la caméra frontale.
3. Alice et Bob mettent leurs téléphones face à face (écran contre écran).
4. Les téléphones se scannent mutuellement en une fraction de seconde, vibrent, et l'écran devient vert. Le transfert est cryptographiquement validé ! Zéro clic, zéro friction.

## 3. La TRM de Présence et la Monnaie Fondante

C'est ici que TrocZen innove radicalement en adaptant la Théorie Relative de la Monnaie à un réseau local P2P.

### Le DU basé sur la Toile de Confiance Locale
Il n'y a pas de blockchain globale. Le DU est calculé localement sur votre téléphone en fonction de **votre propre graphe social**. 
À chaque fois que vous faites un échange avec un commerçant, l'application vous propose de "Tisser un lien" (un *Follow* réciproque). 
Dès que vous atteignez **5 liens réciproques**, vous débloquez la création monétaire. La formule de la TRM est appliquée en temps réel sur la masse monétaire de votre réseau étendu (N1 + N2).

### Pas de rente d'inactivité
Si vous ne venez pas au marché (pas de synchronisation locale), vous ne générez pas de DU. Il n'y a pas de "rattrapage" des jours manqués. Cela évite la prédation monétaire où des utilisateurs inactifs débarquent soudainement avec des milliers de ẐEN, provoquant de l'inflation. C'est une **Preuve de Présence**.

### La Monnaie Fondante (Demurrage)
Pour forcer la circulation de la monnaie et éviter la thésaurisation, les bons issus du DU ont une **durée de vie stricte de 28 jours**. 
Sur l'interface, la carte affiche un compte à rebours rouge anxiogène. Si vous ne dépensez pas ce DU dans le mois, il s'évapore. 
Cependant, **dès que le bon est dépensé chez un commerçant, il perd sa date d'expiration** ! La pression de la monnaie fondante (type Silvio Gesell) pèse uniquement sur le créateur initial pour le forcer à injecter la valeur dans l'économie réelle. Le commerçant, lui, reçoit une monnaie pérenne.

## 4. Le Carnet de Voyage et l'Effet "Petit Monde" (Petites Annonces)

Puisque chaque transfert est tracé publiquement (de manière pseudonyme), chaque bon possède un **Carnet de Voyage**.
Mais ce n'est pas tout : lors de la création d'un bon, l'émetteur peut y attacher un **Vœu** (une demande). Par exemple, un brasseur crée un bon de réduction et y attache le vœu : *"Je recherche du Houblon local"*.

Le bon va voyager de main en main :
📍 *Brasseur* ➔ 👤 *Client* ➔ 🥖 *Boulangerie* ➔ 🌾 *Agriculteur (qui cultive du houblon !)*

Grâce à l'effet "Petit Monde" (les 6 degrés de séparation), le bon agit comme une **petite annonce décentralisée** qui se propage physiquement sur le marché. Si le bon atteint la personne capable de répondre à la demande, la boucle de valeur est identifiée et fermée !

Quand le bon revient à son émetteur initial, la boucle est bouclée. L'émetteur peut alors "Brûler" (détruire) le bon pour nettoyer sa comptabilité, ce qui débloque des **Succès publics** sur son profil (ex: *Trophée de l'Économie Circulaire*).

---

# 🛠️ Section Technique (Pour les Devs / forum.duniter.org)

Pour les curieux de l'architecture, voici comment TrocZen réalise ces prouesses sans serveur central.

### 1. Shamir's Secret Sharing (SSSS) et Secp256k1
Un bon ẐEN n'est pas une ligne dans une base de données, c'est une **paire de clés cryptographiques (BIP-340 Schnorr)**.
Pour empêcher la double dépense hors-ligne, la clé privée du bon (`sk_B`) est découpée en 3 parts (seuil 2-sur-3) :
- **P1 (L'Ancre)** : Reste chez l'émetteur.
- **P2 (Le Voyageur)** : Circule de téléphone en téléphone via les QR codes.
- **P3 (Le Témoin)** : Est chiffrée (AES-GCM) et publiée sur un relais Nostr local.

Lors d'un échange hors-ligne, le receveur combine le P2 scanné avec le P3 de son cache local pour reconstituer `sk_B` en RAM de manière éphémère, signer un challenge (ACK), et prouver qu'il a bien reçu le bon.

### 2. Nostr comme Registre d'État (State Machine)
TrocZen utilise le protocole Nostr de manière non-conventionnelle :
- **Kind 0** : Profils des commerçants et métadonnées des bons.
- **Kind 1** : Historique public des transferts (pour le Carnet de Voyage).
- **Kind 3** : Le graphe social (Follows) utilisé pour calculer le DU local.
- **Kind 5** : Destruction (Burn) des bons quand la boucle est bouclée.
- **Kind 30303** : Publication des parts P3 chiffrées.

### 3. La TrocZen Box (Raspberry Pi Solaire)
L'infrastructure physique du marché repose sur un simple **Raspberry Pi Zero 2 W** alimenté par un petit panneau solaire (consommation ~1.2W). 
Il fait tourner :
- Un point d'accès Wi-Fi (Portail Captif).
- Un relais Nostr ultra-léger (`strfry` écrit en C++).
- Un serveur Nginx pour distribuer l'APK de l'application.

Le mot de passe du réseau Wi-Fi est dérivé cryptographiquement de la `market_seed` (la graine du marché). Ainsi, seuls les participants légitimes peuvent se connecter à l'antenne et déchiffrer l'économie locale.

### 4. La Formule du DU Relativiste P2P
Pour conserver l'invariance d'échelle de la TRM tout en évitant l'explosion exponentielle due au réseau étendu (les amis des amis), l'algorithme local de TrocZen utilise cette formule pondérée :

`DU_new = DU_current + C² * (M_n1 + M_n2 / sqrt(N2)) / (N1 + sqrt(N2))`

*(Où N1 sont les liens réciproques directs, et N2 les liens de niveau 2).*

---

Le code est intégralement open-source (AGPL v3) et disponible sur GitHub. Nous cherchons des testeurs, des développeurs Flutter/Python, et des passionnés de crypto-économie pour affiner ces concepts !

👉 **Découvrir le code et la documentation complète : [GitHub TrocZen](https://github.com/papiche/troczen)**

Qu'en pensez-vous ? Avez-vous des retours sur cette approche de "Monnaie Fondante" couplée à la TRM ?
