**ẐEN**

**Protocole Bons v2 — Spécification révisée**

*Amorce sociale · TTL décroissant · Anonymisation HMAC · Rachat volontaire*

# **1\. T1 — Le Bon à 0 ẐEN : amorce sociale**

## **1.1 Principe**

Au bootstrap l’application génère un **Bon à 0 ẐEN** — un objet cryptographique valide mais sans valeur monétaire, dont la seule fonction est de **propager le graphe social (WoT Nostr)** nécessaire au déclenchement du DU.

C'est le bien le plus précieux du système au démarrage : il ne crée pas de richesse artificielle, il crée la **topologie** qui rendra toute richesse future possible.

| 🌱 | Philosophie du Bon Zéro Un bon sans valeur qui permet à une communauté d'exister est plus précieux qu'un bon avec valeur dans un réseau inexistant. La valeur vient après la confiance, jamais avant. |
| :---- | :---- |

## **1.2 Mécanique de propagation**

**A émet le Bon Zéro** lors de sa première utilisation de l'app. Ce bon a : valeur \= 0 ẐEN, TTL \= 28 jours, structure cryptographique complète (SSSS, HMAC path), marqué **kind: "zero\_bond"**.

| Étape | Acteur | Action |
| :---- | :---- | :---- |
| 1 | A | Finalise l'onboarding. App génère le Bon Zéro. A le présente en QR sur le marché. |
| 2 | X | Scanne le QR de A. App de X affiche : "Recevoir le bon de A (0 ẐEN, 28j) — Accepter ?" |
| 3 | App | Lors de l'acceptation par X : propose à X de suivre A (Kind 3 Nostr). Propose à A de suivre X si pas encore fait. |
| 4 | X→Y | X transfère le Bon Zéro à Y. Même proposition : "Suivre X ? Suivre A ?" |
| 5 | Réseau | Après N transferts, le graphe social se construit. Dès que A atteint N1 ≥ 5 liens réciproques, le DU s'active automatiquement. |
| 6 | Bon Zéro | Quand il revient à A (boucle), ou à expiration (28j) : détruit. Parcours révélé \= carte des premiers liens. |

## **1.3 Proposition de follow — formulation UX**

L'app doit proposer le follow de manière informelle, jamais obligatoire. Formulations recommandées :

| Moment | Message suggéré |
| :---- | :---- |
| Réception d'un Bon Zéro | "\[Nom\] t'invite dans son réseau de confiance. Veux-tu le suivre ? (Tu pourras recevoir son DU quand votre lien sera réciproque)" |
| Re-transfert X→Y | "\[X\] t'a transmis ce bon. Veux-tu suivre \[X\] ? Et suivre \[A\], l'émetteur original ?" |
| Seuil N1=4 (presque) | "Il te manque 1 lien réciproque pour commencer à créer du ẐEN. Qui veux-tu inviter ?" |
| Seuil N1=5 atteint | "🎉 Ton réseau est actif \! Tu reçois ton premier DU demain matin." |

| ⚠️ | Règle UX critique La proposition de follow ne doit jamais bloquer le transfert du bon. Le follow est une invitation, pas un péage. Un utilisateur peut recevoir et transmettre le Bon Zéro sans jamais suivre personne — il perd juste l'opportunité d'activer son DU. |
| :---- | :---- |

# **2\. T2 — Conseil TTL & valeur à la création**

## **2.1 Principe**

L'utilisateur reste **entièrement libre** de choisir le TTL et la valeur de ses bons. L'app l'assiste en analysant son historique personnel pour suggérer des paramètres **cohérents avec sa communauté réelle**.

## **2.2 Données utilisées pour le conseil**

| Signal mesuré | Ce qu'il révèle | Impact sur le conseil |
| :---- | :---- | :---- |
| Âge moyen de retour des bons précédents | Vitesse réelle de circulation dans son réseau | Suggérer TTL ≈ âge\_retour\_moyen × 1.5 |
| Taux d'expiration personnel (%) | Part de bons qui meurent sans retour | Si \> 30% : suggérer TTL plus long ou réseau plus dense |
| Valeur moyenne des bons reçus en retour | Calibrage de valeur dans la communauté | Suggérer valeur ≈ médiane des bons circulants locaux |
| Saison / période | Marchés saisonniers, cycles coopératifs | Suggestions contextuelles (ex: 90j en automne \= récolte) |
| N1 et N2 actuels | Densité du réseau local | Si N2/N1 \> 8 : réseau dense → TTL court possible |

## **2.3 Format du conseil dans l'UI**

**À la création d'un bon**, après que l'utilisateur a saisi une valeur brute, l'app affiche un encart non-bloquant :

| 💡 | Exemple de conseil — Alice (28j historique, 15% expiration)   Tes bons reviennent en moyenne en 18 jours. Un TTL de 21j maximiserait les retours.  Ta communauté échange surtout des bons entre 5 et 20 ẐEN. Valeur suggérée : 10 ẐEN.  \[Appliquer\] \[Personnaliser\] |
| :---- | :---- |

**Règle d'or du conseil :** Ne jamais afficher de conseil si l'utilisateur a moins de 10 bons dans son historique. Sous ce seuil, les données sont insuffisantes — mieux vaut ne rien dire que suggérer quelque chose de non pertinent.

| Profil utilisateur | Conseil TTL suggéré | Conseil valeur suggéré |
| :---- | :---- | :---- |
| \< 10 bons (historique vide) | Aucun conseil — afficher "7j à 365j, à toi de choisir" | Aucun conseil |
| Réseau rapide (retour \< 10j) | TTL entre 7 et 21j | Coupures moyennes (5–15 ẐEN) |
| Réseau lent (retour \> 45j) | TTL entre 60 et 120j | Moins de bons, valeurs plus élevées |
| Fort taux expiration (\> 40%) | Augmenter TTL ou diversifier les hops | Réduire valeur unitaire (plus de petits bons) |
| Passeur/Tisseur (N2/N1 \> 8\) | TTL court OK (réseau dense) | Valeur standard — les bons circulent bien |

# **3\. T3 — Rachat volontaire avant expiration**

## **3.1 Principe**

Quand un bon approche de son TTL critique (résiduel \< seuil configurable, défaut 3j), plutôt que de laisser la valeur disparaître, l'app propose au porteur de **contacter l'émetteur original** pour initier un **rachat volontaire**.

L'émetteur **reçoit son bon en avance** (boucle fermée, parcours révélé), et en échange émet un **nouveau bon frais** vers l'utilisateur. C'est un acte bilatéral, jamais automatique.

| 🔄 | Logique du rachat — tout le monde y gagne L'émetteur : récupère son circuit d'information (âge, hops, parcours) avant que le bon n'expire sans retour. C'est de la data sur son réseau.Le porteur : récupère un bon frais (TTL plein) au lieu de regarder la valeur s'évaporer.Le réseau : une boucle est fermée proprement plutôt qu'interrompue par l'expiration. |
| :---- | :---- |

## **3.2 Flux technique du rachat**

| \# | Acteur | Action |
| :---- | :---- | :---- |
| 1 | App | Détecte TTL résiduel \< seuil. Affiche : "Ce bon expire dans Xj. Proposer un rachat à \[Émetteur\] ?" |
| 2 | Porteur | Accepte. App envoie une notification Nostr chiffrée (Kind 4 DM) à l'émetteur : "Ton bon \[ID partiel\] expire dans Xj — veux-tu le racheter ?" |
| 3 | Émetteur | Reçoit la notification. Voit la valeur et le TTL résiduel. Peut accepter, refuser, ou ne pas répondre. |
| 4a | Émetteur accepte | Double scan classique : le porteur présente le bon expirant → l'émetteur le scanne (boucle fermée) → émet immédiatement un nouveau bon frais au porteur. |
| 4b | Émetteur refuse/silence | Aucune action forcée. Le bon continue son TTL et expire normalement. App informe le porteur : "Pas de réponse — le bon expire le \[date\]." |
| 5 | App | Si rachat accepté : log "Rachat volontaire" distinct du log "Boucle organique" pour les stats. |

## **3.3 Règles du rachat**

* **Toujours volontaire :** l'émetteur n'est jamais obligé d'accepter. Aucune pénalité en cas de refus.

* **Valeur du nouveau bon \= valeur du bon racheté :** pas de décote imposée par le protocole. La négociation de valeur est libre entre les parties.

* **Un seul rachat par bon :** empêcher les cycles de rachat artificiel (A rachète → réémet → A rachète...).

* **Délai de réponse :** si l'émetteur ne répond pas dans 24h après la demande, l'app cesse de relancer. Un seul rappel automatique.

* **Hors-ligne compatible :** si l'émetteur est hors-ligne, la demande est mise en file dans la Box locale. Elle sera livrée à la prochaine connexion.

| ⚠️ | Ce que le rachat n'est pas Ce n'est pas un marché secondaire automatique. Ce n'est pas une garantie de valeur. L'émetteur peut refuser sans explication. Le système ne doit jamais créer l'illusion que tous les bons seront rachetés — cela réintroduirait la thésaurisation. |
| :---- | :---- |

# **4\. T4 — Anonymisation du parcours (HMAC)**

## **4.1 Problème**

Si **path\[\]** contient les pubkeys brutes des porteurs successifs, quiconque intercepte le bon peut reconstruire un réseau d'échange potentiellement sensible. Deux personnes qui ne veulent pas que leur relation soit publique seraient exposées.

## **4.2 Solution : empreintes HMAC**

Chaque entrée dans **path\[\]** est remplacée par :

**empreinte \= HMAC-SHA256(pubkey\_porteur, bon\_id)**

| Qui sait quoi ? | Peut voir | Ne peut pas voir |
| :---- | :---- | :---- |
| N'importe qui | Nombre de hops, TTL consommé, valeur, bon\_id | Qui a porté le bon (pubkeys) |
| Un porteur quelconque | Son propre hop (il connaît sa pubkey) | Les autres porteurs dans le path\[\] |
| L'émetteur uniquement | Tout le parcours : il connaît bon\_id et peut dériver HMAC(pubkey\_i, bon\_id) pour chaque membre connu de son réseau | Les porteurs hors de son N1+N2 |

## **4.3 Implémentation**

* **À chaque hop,** le porteur calcule **HMAC-SHA256(sa\_pubkey, bon\_id)** et l'ajoute à **path\[\]**. Il ne modifie pas les entrées précédentes.

* **bon\_id** est fixé à l'émission et ne change jamais (il fait partie de la signature du bon). C'est la clé HMAC implicite.

* **À la destruction (retour émetteur),** l'app de l'émetteur itère sur son annuaire N1+N2 et tente **HMAC(pubkey\_connue, bon\_id)** pour chaque contact. Les correspondances révèlent les porteurs identifiables.

* **Les porteurs hors réseau de l'émetteur** restent anonymes même pour l'émetteur — c'est normal et souhaitable.

| ✅ | Propriété de privacy préservée La transparence sur le circuit (il a circulé, X hops, Y jours) est préservée pour la santé du réseau. La vie privée des porteurs est préservée par défaut. Seul l'émetteur peut partiellement désanonymiser, et seulement pour ses contacts connus. |
| :---- | :---- |

# **5\. T5 — Le bon est atomique (pas de split)**

Par décision de conception, **un bon ne peut pas être fractionné** en transit. Un bon de 20 ẐEN ne peut pas devenir un bon de 7 ẐEN \+ un bon de 13 ẐEN.

## **5.1 Justification**

* **Complexité cryptographique :** le split implique de recréer deux bons avec de nouvelles clés SSSS, deux nouveaux parcours HMAC, deux nouvelles signatures Nostr. Hors-ligne, sans connexion au relais, c'est irréalisable de façon sûre.

* **Intégrité du parcours :** le bon fractionné rompt la traçabilité. Le path\[\] originel ne s'applique qu'au bon entier.

* **Simplicité d'usage :** au marché, la contrainte force à bien choisir ses coupures à la création. C'est un coût cognitif ponctuel qui évite une complexité permanente.

## **5.2 Compensation UX**

Pour réduire le problème du "rendu de monnaie", l'app aide à bien découper les bons à la création :

* **Suggestion de coupures :** lors de la création, l'app propose automatiquement une répartition en coupures standards (ex: 20 ẐEN de DU → 1×10 \+ 2×5) adaptées aux échanges habituels de la communauté.

* **Historique des valeurs reçues :** l'app connaît les montants fréquents dans le réseau local et peut suggérer des coupures qui matchent.

* **Principe de précaution :** mieux vaut 4 bons de 5 ẐEN qu'un seul bon de 20 ẐEN si le réseau échange typiquement des petites valeurs.

# **6\. Métriques de santé — tableau de bord communautaire**

Ces métriques sont calculées localement par la TrocZen Box à partir des événements Nostr. Elles sont affichées à la communauté de façon agrégée et anonymisée.

| Métrique | Formule | Seuil sain | Interprétation |
| :---- | :---- | :---- | :---- |
| Ratio de santé | Boucles fermées / ẐEN expirés (par mois) | \> 1.0× | Au-dessus de 1 : la confiance se régénère plus vite qu'elle ne s'érode |
| Vélocité moyenne | Bons transférés / masse totale / jour | \> 0.05 | La monnaie circule — elle ne dort pas |
| Âge moyen des circuits | Moyenne(age\_retour) sur 30j glissants | Stable ou décroissant | Si ça monte : le réseau ralentit ou s'éparpille |
| Taux de rachat | Rachats volontaires / expirations imminentes | \> 20% | Indique une communauté qui prend soin de ses bons |
| Profondeur des circuits | Hops moyens par boucle fermée | 3–7 hops | \< 3 : réseau trop local. \> 10 : possible fragilité |
| Acteurs N1≥5 / total | % de membres avec DU actif | \> 60% | Indique si le bootstrap a bien fonctionné |

*"Le Bon Zéro est le vrai premier ẐEN — celui qui vaut tout car il ne vaut rien en lui-même, mais permet à tous les autres d'exister."*

*Document TrocZen · Protocole Bons ẐEN v2 · Spécification révisée · Fév. 2026*