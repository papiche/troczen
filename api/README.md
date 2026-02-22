# API Backend TrocZen

Backend Flask pour l'écosystème TrocZen : gestion des marchés, distribution d'APK, intégration Nostr Strfry, stockage IPFS, et modules ORACLE/DRAGON.

## Résumé

L'API backend TrocZen est connectée au relai Nostr Strfry local (`ws://127.0.0.1:7777`) pour récupérer dynamiquement les données des marchands et des bons, et construire l'interface web en temps réel. Elle gère également:

- **Module ORACLE**: Système de certification par pairs (WoTx2) avec Verifiable Credentials
- **Module DRAGON**: Calcul dynamique des paramètres économiques (C², alpha, DU)

## Fonctionnalités

### Récupération depuis Nostr Strfry
- **kind 0** : Profils marchands (name, about, picture, banner, website, lud16, nip05)
- **kind 30303** : Bons Zen (tags market, status, value, expiry, category, rarity)
- **kind 30304** : Circuits fermés (métriques de circulation)
- **kind 30501-30503** : WoTx2 - Demande, attestation, credentials

### Module ORACLE (WoTx2)
- Écoute des attestations (Kind 30502) en temps réel
- Génération automatique de Verifiable Credentials (Kind 30503)
- Progression automatique X1 → X2 → X3...
- Badges NIP-58 pour gamification

### Module DRAGON (Capitaine)
- Calcul dynamique de C² (vitesse de création monétaire)
- Calcul de alpha (multiplicateur compétence)
- Calcul du DU (Dividende Universel) avec formule TRM étendue
- Tableau de navigation utilisateur
- Taux de change inter-marchés émergents

### Distribution APK
- Détection automatique de la dernière version
- Téléchargement direct
- Génération de QR code
- Checksum SHA256

### Stockage décentralisé IPFS
- Upload automatique des images vers IPFS
- URLs permanentes via CID
- Fallback local si IPFS désactivé

## Structure du projet

```
api/
├── api_backend.py              # Application Flask principale
├── nostr_client.py             # Client Nostr WebSocket
├── nostr_daemon.py             # Daemon ORACLE (écoute 30502)
├── requirements.txt            # Dépendances Python
├── .env.example                # Variables d'environnement
│
├── oracle/                     # Module ORACLE (WoTx2)
│   ├── __init__.py
│   ├── oracle_service.py       # Service principal stateless
│   ├── permit_manager.py       # Gestion permits et progression
│   └── credential_generator.py # Génération VC format W3C
│
├── dragon/                     # Module DRAGON (Capitaine)
│   ├── __init__.py
│   ├── dragon_service.py       # Service principal
│   ├── params_engine.py        # Calcul C² et alpha
│   ├── du_engine.py            # Calcul DU (TRM étendue)
│   ├── circuit_indexer.py      # Indexation circuits
│   └── dashboard_builder.py    # Tableau de navigation
│
├── templates/
│   ├── index.html              # Page d'accueil API
│   └── market.html             # Page marché dynamique
│
├── uploads/                    # Fichiers uploadés (fallback)
├── apks/                       # Fichiers APK
└── README.md                   # Ce fichier
```

## Installation rapide

### 1. Prérequis
- Python 3.10+
- pip
- Strfry (relai Nostr) - optionnel pour le mode fallback

### 2. Installer les dépendances
```bash
cd api
pip install -r requirements.txt
```

### 3. Configurer l'environnement
```bash
# Copier le fichier d'exemple
cp .env.example .env

# Éditer les variables
nano .env
```

Variables importantes:
```bash
# Nostr
NOSTR_RELAY_URL=ws://127.0.0.1:7777

# Oracle (générer une clé sécurisée!)
ORACLE_NSEC_HEX=<64_chars_hex_private_key>
ORACLE_PUBKEY=<64_chars_hex_public_key>

# IPFS
IPFS_ENABLED=true
IPFS_API_URL=http://127.0.0.1:5001
```

### 4. Démarrer l'API
```bash
# API Flask
python api_backend.py

# Daemon ORACLE (dans un autre terminal)
python nostr_daemon.py
```

L'API sera accessible sur `http://localhost:5000`

## Endpoints API

### Health Check
```bash
GET /health
```

### Module ORACLE

#### Liste des permits
```bash
GET /api/permit/definitions?market=<market_id>
```

#### Credentials d'un utilisateur
```bash
GET /api/permit/credentials/<npub>
```

#### Statistiques Oracle
```bash
GET /api/permit/stats
```

### Module DRAGON

#### Tableau de navigation
```bash
GET /api/dashboard/<npub>?market=<market_id>
```

**Réponse:**
```json
{
  "npub": "user_pubkey_hex",
  "computed_at": "2026-02-22T00:00:00Z",
  "network": {
    "n1": 8,
    "n2": 67,
    "category": "Tisseur"
  },
  "markets": [{
    "market_id": "market_hackathon",
    "du": {
      "daily": 18.3,
      "monthly": 549,
      "base": 14.2,
      "skill_bonus": 4.1
    },
    "params": {
      "c2": 0.094,
      "alpha": 0.41,
      "ttl_optimal_days": 21
    },
    "circulation": {
      "loops_this_month": 14,
      "median_return_age_days": 12.5
    },
    "signals": ["Réseau en forte accélération"]
  }]
}
```

#### Calcul DU
```bash
GET /api/du/<npub>/<market>
```

#### Paramètres dynamiques
```bash
GET /api/params/<npub>/<market>
```

#### Santé du marché
```bash
GET /api/health/<market>
```

#### Participation aux Frais (PAF)
```bash
GET /api/paf/<market>
```

### Upload d'image
```bash
POST /api/upload/image
Content-Type: multipart/form-data

file: <image_file>
npub: <nostr_public_key>
type: logo|banner|avatar
```

### APK

#### Info dernière version
```bash
GET /api/apk/latest
```

#### Téléchargement
```bash
GET /api/apk/download/<filename>
```

#### QR Code
```bash
GET /api/apk/qr
```

### Nostr

#### Données d'un marché
```bash
GET /api/nostr/marche/<market_name>
```

#### Synchroniser
```bash
POST /api/nostr/sync?market=<market_name>
```

## Architecture Stateless

Les modules ORACLE et DRAGON utilisent une architecture **stateless**:

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  App Flutter     │     │  Relai Strfry    │     │  Daemon ORACLE   │
│                  │◄───►│  (Nostr Relay)   │◄───►│  (écoute 30502)  │
└──────────────────┘     └──────────────────┘     └──────────────────┘
         │                        │                         │
         │                        │                         │
         ▼                        ▼                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      API Flask (stateless)                           │
│  - Interroge Strfry à la volée                                       │
│  - Pas de base de données locale                                     │
│  - Calculs en mémoire                                                │
└─────────────────────────────────────────────────────────────────────┘
```

**Avantages:**
- Zéro migration de base de données
- Pas de problème de concurrence
- Code ultra-léger et purement fonctionnel
- Totalement aligné avec l'écosystème Nostr

## Formules de calcul

### C² (vitesse de création monétaire)
```
C²_i(t) = vitesse_retour_médiane / TTL_médian
         × facteur_santé
         × (1 + taux_croissance_N1)
```
Borné entre 0.02 (2%) et 0.25 (25%)

### alpha (multiplicateur compétence)
```
alpha = corrélation_pearson(niveau_compétence, vitesse_retour)
```
Mesure si la compétence prédit la vitesse de retour des bons.

### DU (Dividende Universel)
```
DU_base = DU_prev + C² × (M_N1 + M_N2/√N2) / (N1 + √N2)
DU_final = DU_base × (1 + alpha × S_i)
```
Où S_i est le score de compétence moyen (niveaux X1, X2, X3...)

## Tests

### Tests automatisés
```bash
python test_nostr_api.py
```

### Tests manuels rapides
```bash
# Health check
curl http://localhost:5000/health

# Dashboard utilisateur
curl http://localhost:5000/api/dashboard/npub1abc123...

# Santé du marché
curl http://localhost:5000/api/health/market_hackathon

# Credentials
curl http://localhost:5000/api/permit/credentials/npub1abc123...
```

## Configuration avancée

### Variables d'environnement ORACLE

| Variable | Défaut | Description |
|----------|--------|-------------|
| `ORACLE_NSEC_HEX` | - | Clé privée Oracle (64 chars hex) |
| `ORACLE_PUBKEY` | - | Pubkey Oracle (64 chars hex) |
| `ORACLE_OFFICIAL_THRESHOLD` | 2 | Seuil attestations permits officiels |
| `ORACLE_WOTX2_THRESHOLD` | 1 | Seuil attestations WoTx2 |
| `CREDENTIAL_VALIDITY_SKILL` | 365 | Validité credentials compétence (jours) |

### Variables d'environnement DRAGON

| Variable | Défaut | Description |
|----------|--------|-------------|
| `C2_MIN` | 0.02 | C² minimum |
| `C2_MAX` | 0.25 | C² maximum |
| `C2_DEFAULT` | 0.07 | C² par défaut |
| `ALPHA_DEFAULT` | 0.3 | alpha par défaut |
| `DU_INITIAL` | 10.0 | DU initial (Zen/jour) |
| `MIN_N1_FOR_DU` | 5 | N1 minimum pour DU actif |
| `ANALYSIS_WINDOW` | 30 | Fenêtre d'analyse (jours) |

### Variables d'environnement générales

| Variable | Défaut | Description |
|----------|--------|-------------|
| `NOSTR_RELAY_URL` | ws://127.0.0.1:7777 | URL du relai Strfry |
| `IPFS_ENABLED` | true | Activer IPFS |
| `IPFS_API_URL` | http://127.0.0.1:5001 | API du nœud IPFS |
| `IPFS_GATEWAY` | https://ipfs.copylaradio.com | Passerelle IPFS |

## Déploiement

### Mode production avec Gunicorn
```bash
# API Flask
gunicorn -w 4 -b 0.0.0.0:5000 api_backend:app

# Daemon ORACLE (avec systemd)
sudo systemctl enable troczen-oracle
sudo systemctl start troczen-oracle
```

### Systemd service pour le daemon
```ini
# /etc/systemd/system/troczen-oracle.service
[Unit]
Description=TrocZen ORACLE Daemon
After=network.target

[Service]
Type=simple
User=troczen
WorkingDirectory=/opt/troczen/api
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 nostr_daemon.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Docker Compose
```yaml
version: '3.8'

services:
  strfry:
    image: ghcr.io/hoytech/strfry:latest
    ports:
      - "7777:7777"
    volumes:
      - ./strfry.conf:/app/strfry.conf
      - ./strfry-db:/app/strfry-db
    command: relay

  api:
    build: .
    ports:
      - "5000:5000"
    environment:
      - NOSTR_RELAY_URL=ws://strfry:7777
      - ORACLE_NSEC_HEX=${ORACLE_NSEC_HEX}
    depends_on:
      - strfry

  oracle-daemon:
    build: .
    environment:
      - NOSTR_RELAY_URL=ws://strfry:7777
      - ORACLE_NSEC_HEX=${ORACLE_NSEC_HEX}
    command: python nostr_daemon.py
    depends_on:
      - strfry
```

## Documentation complémentaire

- [BACKLOG_SERVEUR_PYTHON.md](../docs/BACKLOG_SERVEUR_PYTHON.md) - Backlog détaillé ORACLE/DRAGON
- [IPFS_CONFIG.md](IPFS_CONFIG.md) - Configuration détaillée IPFS
- [troczen_protocol_v6.md](../docs/troczen_protocol_v6.md) - Protocole complet v6
- [ARCHITECTURE.md](../ARCHITECTURE.md) - Architecture technique

## Sécurité

- Validation des extensions de fichiers (png, jpg, jpeg, webp)
- Taille maximale : 5 MB
- Noms sécurisés avec `secure_filename()`
- Checksum SHA256 pour tous les fichiers
- CORS activé pour l'app mobile
- Magic bytes validation pour les uploads

## Dépannage

### Erreur "ModuleNotFoundError"
```bash
pip install -r requirements.txt
```

### Strfry non accessible
```bash
# Vérifier que Strfry tourne
curl http://127.0.0.1:7777

# Vérifier les logs
docker logs strfry
```

### ORACLE ne génère pas de credentials
```bash
# Vérifier la clé Oracle
echo $ORACLE_NSEC_HEX | wc -c  # Doit être 65 (64 chars + newline)

# Vérifier les logs du daemon
journalctl -u troczen-oracle -f
```

### DU toujours à 0
- Vérifier que N1 >= 5 (seuil minimum)
- Vérifier les contacts Kind 3
- Vérifier que les bons ont des circuits fermés (Kind 30304)

## Checklist de déploiement

- [ ] Dépendances Python installées
- [ ] Variables d'environnement configurées
- [ ] Clé Oracle générée et configurée
- [ ] API démarrée (port 5000)
- [ ] Strfry démarré (port 7777)
- [ ] Daemon ORACLE démarré
- [ ] Tests passés
- [ ] Page web accessible

---

**TrocZen API Backend** - Version 1.1.0 - 2026
**Modules**: ORACLE (WoTx2) + DRAGON (Capitaine)
