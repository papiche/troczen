# Changelog Sécurité - Chiffrement WoTx

## 2026-02-22 - Correction du "Syndrome du Panopticon"

### 🛡️ Problème de sécurité identifié

**Le problème :** Si on publie les attestations (qui connaît qui, qui valide qui) en clair sur le relai local, n'importe qui s'y connectant peut aspirer l'intégralité du graphe social et économique du village.

### ✅ Solution implémentée

Tout comme pour les bons (Kind 30303), le champ `content` des événements WoTx est désormais chiffré en AES-GCM avec la Seed du Marché.

Les tags publics (`p`, `e`, `t`) servent au routage par Strfry, mais la "chair" du message (motivation, commentaires) n'est lisible que par ceux qui ont été invités sur le marché (ceux qui ont la Seed).

### 📋 Événements concernés

| Kind | Nom | Description | Contenu chiffré |
|------|-----|-------------|-----------------|
| 30500 | Skill Permit | Déclaration de compétence/permis | Niveau, type, timestamp |
| 30501 | Skill Request | Demande d'attestation | Motivation, timestamp |
| 30502 | Skill Attest | Attestation par un pair | Motivation, commentaires |
| 30304 | Bon Circuit | Révélation de circuit | Stats du parcours, annotations |

### 🔧 Modifications techniques

#### 1. `crypto_service.dart` - Nouvelles méthodes

```dart
/// Chiffre le contenu d'un événement avec la Seed du Marché
Map<String, String> encryptWoTxContent(String content, String seedHex)

/// Déchiffre le contenu d'un événement avec la Seed du Marché
String decryptWoTxContent(String ciphertextHex, String nonceHex, String seedHex)

/// Crée un événement WoTx avec contenu chiffré
Map<String, dynamic> createEncryptedWoTxEvent({...})

/// Déchiffre le contenu d'un événement reçu
String decryptWoTxEvent(Map<String, dynamic> event, String seedHex)
```

#### 2. `nostr_service.dart` - Méthodes modifiées

- `publishSkillPermit()` - Ajout paramètre `seedMarket`
- `publishSkillRequest()` - Ajout paramètre `seedMarket`
- `publishSkillAttestation()` - Ajout paramètre `seedMarket`
- `publishBonCircuit()` - Ajout paramètre `seedMarket`

#### 3. Format des événements chiffrés

```json
{
  "kind": 30501,
  "pubkey": "...",
  "tags": [
    ["permit_id", "PERMIT_BOULANGER_X1"],
    ["t", "boulanger"],
    ["encryption", "aes-gcm", "nonce_hex_24_chars"]
  ],
  "content": "ciphertext_hex_chiffré"
}
```

### 🔐 Comportement selon le mode

| Mode | Seed | Comportement |
|------|------|--------------|
| HACKATHON | `000...0` | Contenu en clair (transparence totale) |
| Marché privé | Seed aléatoire | Contenu chiffré AES-GCM |

### 📁 Fichiers modifiés

1. `troczen/lib/services/crypto_service.dart` - Ajout méthodes chiffrement WoTx
2. `troczen/lib/services/nostr_service.dart` - Modification méthodes publication
3. `troczen/lib/services/burn_service.dart` - Ajout seedMarket à publishBonCircuit
4. `troczen/lib/screens/onboarding/onboarding_profile_screen.dart` - Ajout seedMarket
5. `troczen/lib/screens/onboarding/onboarding_complete_screen.dart` - Ajout seedMarket
6. `troczen/lib/screens/views/explore_view.dart` - Ajout seedMarket

### 🧪 Tests recommandés

1. Vérifier que les événements sont publiés avec le tag `encryption` en marché privé
2. Vérifier que le contenu est lisible après déchiffrement
3. Vérifier le mode HACKATHON (contenu en clair)
4. Vérifier que les tags publics restent lisibles pour le routage Strfry

### 📖 Références

- [Protocole TrocZen v6](docs/troczen_protocol_v6.md)
- [NIP-33 - Parameterized Replaceable Events](https://github.com/nostr-protocol/nips/blob/master/33.md)
- [AES-GCM Specification](https://csrc.nist.gov/publications/detail/sp/800-38d/final)
