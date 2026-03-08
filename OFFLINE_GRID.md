# **"Offline-First"** (Priorité au hors-ligne)

Voici concrètement comment cela fonctionne sans aucun réseau et à quoi ressemble l'expérience utilisateur.

---

### 1. Le Prérequis : La "Synchronisation du Matin"
Pour que le mode hors-ligne fonctionne, il y a une seule condition : l'utilisateur doit avoir ouvert l'application au moins une fois avec du réseau (chez lui en Wi-Fi, ou en arrivant sur le marché via la TrocZen Box) pour faire sa **Synchronisation**.

*   **Que se passe-t-il pendant cette synchro ?** L'application télécharge silencieusement toutes les **parts P3** (les Témoins) des bons existants sur le marché et les stocke dans la base de données locale (SQLite) du téléphone.
*   L'application télécharge également les images/avatars des commerçants via le `ImageCacheService` pour les stocker physiquement sur le téléphone.

---

### 2. À quoi ressemble l'App sans réseau ? (L'Expérience Utilisateur)

L'interface reste **fluide et riche**. Contrairement à une application bancaire classique qui affiche un "Spinner" infini ou un message d'erreur "Pas de connexion", TrocZen affiche tout normalement :

*   **Le Wallet (Mon Portefeuille) fonctionne à 100%** : Vous voyez vos bons ẐEN, leurs valeurs, les couleurs, la rareté (cartes Panini), et même les logos des commerçants (grâce au cache local).
*   **Le Mode "Miroir" (Échange) fonctionne à 100%** : L'écran divisé en deux (QR en haut, caméra en bas) s'ouvre instantanément.
*   **La vibration et le son de succès** : Le "Bol tibétain" (son de succès) retentit bien lors de la transaction.

#### 🔄 Ce qui est mis en pause (Le vrai côté "dégradé") :
1.  **Création de nouveaux bons** : Un commerçant *ne peut pas* émettre un tout nouveau bon s'il n'a pas de réseau. Pourquoi ? Parce qu'il faut publier la part P3 sur le relai Nostr pour que les autres puissent valider le bon.
2.  **Le Dashboard Économique (Observatoire)** : Les statistiques du marché (vitesse de circulation, volume total) ne se mettront pas à jour en temps réel. Elles affichent le dernier état connu.
3.  **L'historique public ("Carnet de voyage")** : Si vous transférez un bon, le fait qu'il soit passé entre vos mains (hop +1) ne sera publié sur le réseau que plus tard.

*(Note sur le NFC : Bien que mentionné dans le code, le service NFC est actuellement expérimental/mocké. Le transfert atomique hors-ligne repose donc aujourd'hui sur le **double scan QR**).*

---

### 3. Comment l'Atomic Swap fonctionne-t-il sans internet ?

C'est la magie cryptographique de TrocZen. Tout se passe entre les deux téléphones (Alice et Bob) par communication visuelle (QR Codes) :

1.  **L'Offre (Alice génère le QR 1)** :
    *   L'app d'Alice prend la part **P2** du bon et la chiffre (AES-GCM) avec une clé dérivée de **P3** (qu'elle a en cache).
    *   Alice génère un *Challenge aléatoire* (16 octets) et signe le tout.
    *   Son téléphone affiche le QR Code v2 (240 octets max).
2.  **L'Acceptation (Bob scanne le QR 1)** :
    *   Le téléphone de Bob lit le QR.
    *   Bob va chercher la part **P3** de ce bon dans *son propre cache hors-ligne*.
    *   Grâce à P3, il déchiffre P2.
    *   **En RAM** (sans rien sauvegarder), le téléphone de Bob assemble P2 + P3 = Il reconstitue la **Clé Privée du Bon** !
    *   Il utilise cette clé pour signer le *Challenge* d'Alice et affiche un QR Code 2 (ACK / Accusé de réception - 97 octets).
3.  **La Finalisation (Alice scanne le QR 2)** :
    *   Le téléphone d'Alice vérifie la signature de Bob. Si c'est bon, cela prouve mathématiquement que Bob a bien reçu le bon.
    *   Le téléphone d'Alice **supprime définitivement la part P2** de sa mémoire locale. Le bon est dépensé.

**Résultat :** L'échange est cryptographiquement prouvé, anti-double dépense, et atomique, le tout dans un champ de patates sans aucune barre de réseau 4G.

---

### 4. Le retour à la civilisation (Reconnexion)

Lorsque les téléphones retrouvent une connexion internet (ou se reconnectent à la borne Wi-Fi locale du marché) :
*   Le `NostrService` détecte le réseau.
*   En arrière-plan, les applications publient les événements **Kind 1** (Les historiques de transfert des bons échangés hors-ligne) pour mettre à jour la comptabilité globale et le Dashboard du marché.
*   L'application télécharge les nouvelles parts P3 créées par d'autres pendant la coupure.

### 5. L'Architecture "Pollinisateur" (Gossip)

Pour les utilisateurs en mode **Alchimiste / Capitaine**, l'application va plus loin et agit comme un pont entre les marchés isolés :
*   **Aspiration (Light Node)** : Lors de la synchronisation, l'application aspire l'intégralité des événements du marché (profils, transferts, attestations) et les stocke dans une table `outbox_gossip`.
*   **Dissémination (Push)** : Lorsque le Capitaine se déplace et se connecte à une **nouvelle ZenBOX** (nouveau marché), son téléphone détecte le changement de réseau et "vomit" silencieusement tout l'historique collecté vers le nouveau relais.
*   **Résultat** : Les graphes sociaux et économiques des différents marchés s'unifient organiquement, portés par le mouvement physique des humains, sans nécessiter de connexion Internet globale.

**En résumé :** Le mode hors-ligne de TrocZen s'apparente exactement à l'usage d'un billet de banque physique. Tant que vous avez le billet (P2) et que l'autre sait le reconnaître (P3 en cache), l'échange est immédiat et définitif. Le réseau ne sert qu'à l'audit a posteriori, et la résilience globale est assurée par le protocole Gossip des Capitaines.