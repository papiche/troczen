# Système WoTxN (Web of Trust eXtended on Nostr)

Le système WoTxN permet de gérer les savoir-faire (skills) et les certifications croisées entre les participants du marché local TrocZen.

## Événements Nostr utilisés

### 1. Définition de Savoir-Faire (Kind 30500)
Cet événement définit l'existence d'un savoir-faire sur le marché.
- **Kind** : 30500
- **Tags** : `d` (nom du savoir-faire)
- **Contenu** : Chiffré avec la Seed du Marché.
- **Usage** : Ensemencement initial du relais avec les savoir-faire par défaut, ou ajout d'un nouveau savoir-faire personnalisé par un utilisateur.

### 2. Demande d'Attestation (Kind 30501)
Cet événement est émis par un utilisateur pour déclarer qu'il possède un savoir-faire et demander à être certifié par ses pairs.
- **Kind** : 30501
- **Tags** : `d` (nom du savoir-faire)
- **Contenu** : Motivation (chiffrée avec la Seed du Marché).
- **Usage** : Émis lors de la finalisation de l'onboarding pour chaque savoir-faire sélectionné par l'utilisateur, ou lors de l'ajout d'un nouveau savoir-faire à son profil.

### 3. Attestation de Savoir-Faire (Kind 30502)
Cet événement est émis par un pair pour certifier qu'un utilisateur possède bien le savoir-faire revendiqué.
- **Kind** : 30502
- **Tags** : `e` (ID de la demande 30501), `p` (npub du demandeur), `a` (référence au savoir-faire 30500)
- **Contenu** : Motivation/Avis (chiffré avec la Seed du Marché).
- **Usage** : Émis lorsqu'un utilisateur valide les compétences d'un autre utilisateur suite à une transaction ou une interaction.

## Processus de Bootstrap (Onboarding)

1. **Création du compte** : L'utilisateur génère ses clés cryptographiques (Nostr et Ğ1).
2. **Ensemencement (Kind 30500)** : Si le relais est vierge, l'application publie les définitions des savoir-faire par défaut (Kind 30500) en utilisant les clés de l'utilisateur.
3. **Sélection des savoir-faire** : L'utilisateur sélectionne ses savoir-faire parmi ceux disponibles ou en crée de nouveaux (ce qui publie immédiatement un Kind 30500).
4. **Demande d'attestation (Kind 30501)** : À la fin de l'onboarding, l'application publie une demande d'attestation (Kind 30501) pour chaque savoir-faire sélectionné par l'utilisateur. Cela permet d'initier la certification croisée.

## Évolution de la certification croisée

Grâce aux événements 30501, les autres participants du marché peuvent voir les revendications de savoir-faire et y répondre en émettant des événements 30502 (Attestations). Cela crée un réseau de confiance (Web of Trust) décentralisé et spécifique au marché local.
