# 🚀 API Backend TrocZen

Backend Flask pour l'écosystème TrocZen : gestion des marchés, distribution d'APK, intégration Nostr Strfry et stockage IPFS.

## 📋 Résumé

L'API backend TrocZen est connectée au relai Nostr Strfry local (`ws://127.0.0.1:7777`) pour récupérer dynamiquement les données des marchands et des bons, et construire l'interface web en temps réel. Elle gère également l'upload d'images vers IPFS et la distribution de l'application mobile Android.

## 🎯 Fonctionnalités

### ✅ Récupération depuis Nostr Strfry
- **kind 0** : Profils marchands (name, about, picture, banner, website, lud16, nip05)
- **kind 30303** : Bons (tags market, status, value, expiry, category, rarity)
- **Association automatique** : Marchands ↔ Bons
- **Fallback** : Fichiers JSON locaux si Nostr indisponible

### ✅ Distribution APK
- Détection automatique de la dernière version
- Téléchargement direct
- Génération de QR code
- Checksum SHA256

### ✅ Stockage décentralisé IPFS
- Upload automatique des images vers IPFS
- URLs permanentes via CID
- Fallback local si IPFS désactivé

### ✅ Interface Web
- Pages marché dynamiques avec statistiques
- Liste des marchands avec photos et descriptions
- Affichage des bons associés

## 📁 Structure du projet

```
api/
├── api_backend.py          # Application Flask principale
├── nostr_client.py         # Client Nostr WebSocket
├── requirements.txt        # Dépendances Python
├── test_nostr_api.py       # Tests automatisés
├── templates/
│   ├── index.html         # Page d'accueil API
│   └── market.html        # Page marché dynamique
├── uploads/               # Fichiers uploadés (fallback)
├── apks/                  # Fichiers APK
├── IPFS_CONFIG.md         # Configuration IPFS
└── README.md              # Ce fichier
```

## 🚀 Installation rapide

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
# Activer Nostr (optionnel)
export NOSTR_ENABLED=true
export NOSTR_RELAY=ws://127.0.0.1:7777

# Activer IPFS (optionnel)
export IPFS_ENABLED=true
export IPFS_API_URL=http://127.0.0.1:5001
export IPFS_GATEWAY=https://ipfs.copylaradio.com
```

### 4. Démarrer l'API
```bash
python api_backend.py
```

L'API sera accessible sur `http://localhost:5000`

## 📡 Endpoints API

### Health Check
```bash
GET /health
```

### Upload d'image
```bash
POST /api/upload/image
Content-Type: multipart/form-data

file: <image_file>
npub: <nostr_public_key>
type: logo|banner|avatar  # optionnel, défaut: logo
```

**Exemple :**
```bash
curl -X POST http://localhost:5000/api/upload/image \
  -F "file=@logo.png" \
  -F "npub=npub1abc123..."
```

### APK Latest Info
```bash
GET /api/apk/latest
```

**Réponse :**
```json
{
  "filename": "troczen-1.0.0.apk",
  "version": "1.0.0",
  "size": 15728640,
  "checksum": "sha256...",
  "download_url": "/api/apk/download/troczen-1.0.0.apk",
  "updated_at": "2026-02-16T12:00:00"
}
```

### Télécharger APK
```bash
GET /api/apk/download/<filename>
```

### QR Code APK
```bash
GET /api/apk/qr
```
Retourne une image PNG du QR code pour télécharger l'APK.

### Récupérer les données d'un marché
```bash
GET /api/nostr/marche/<market_name>
```

**Paramètres :**
- `market_name` : ID du marché (ex: `marche-toulouse`)

**Réponse :**
```json
{
  "success": true,
  "data": {
    "market_name": "marche-toulouse",
    "merchants": [
      {
        "pubkey": "npub1abc123...",
        "name": "La Miellerie",
        "about": "Miel local bio",
        "picture": "https://ipfs.copylaradio.com/ipfs/Qm...",
        "banner": "https://ipfs.copylaradio.com/ipfs/Qm...",
        "website": "https://miellerie.example.com",
        "lud16": "lnurl1...",
        "nip05": "miellerie@troczen.local",
        "bons": [
          {
            "id": "bon_123",
            "pubkey": "npub1abc123...",
            "value": 10,
            "status": "active",
            "category": "miel",
            "rarity": "rare"
          }
        ],
        "bons_count": 5
      }
    ],
    "total_bons": 10,
    "total_merchants": 3
  },
  "source": "nostr_strfry"
}
```

### Synchroniser les données Nostr
```bash
POST /api/nostr/sync?market=<market_name>
```

### Statistiques globales
```bash
GET /api/stats
```

### Page marché (HTML)
```bash
GET /market/<market_name>
```
Affiche la page HTML avec :
- QR code téléchargement APK
- Statistiques du marché
- Liste des marchands participants
- Bons associés

### Servir fichiers uploadés
```bash
GET /uploads/<filename>
```

## 🧪 Tests

### Tests automatisés
```bash
python test_nostr_api.py
```

### Tests manuels rapides
```bash
# Health check
curl http://localhost:5000/health

# Récupérer données marché
curl http://localhost:5000/api/nostr/marche/marche-toulouse

# Voir page marché
curl http://localhost:5000/market/marche-toulouse
```

## 🔧 Configuration avancée

### Variables d'environnement

| Variable | Défaut | Description |
|----------|--------|-------------|
| `NOSTR_ENABLED` | `true` | Activer/désactiver la récupération Nostr |
| `NOSTR_RELAY` | `ws://127.0.0.1:7777` | URL du relai Strfry |
| `IPFS_ENABLED` | `true` | Activer/désactiver IPFS |
| `IPFS_API_URL` | `http://127.0.0.1:5001` | API du nœud IPFS local |
| `IPFS_GATEWAY` | `https://ipfs.copylaradio.com` | Passerelle IPFS publique |

### Fallback local
Si Nostr est indisponible, l'API utilise automatiquement les fichiers JSON locaux dans `api/uploads/`. Structure attendue :

```json
{
  "npub": "npub1...",
  "name": "Nom du marchand",
  "description": "Description",
  "logo_url": "/uploads/logo.png",
  "market": "marche-toulouse",
  "category": "alimentation"
}
```

## 🐳 Docker Compose

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
      - NOSTR_ENABLED=true
      - NOSTR_RELAY=ws://strfry:7777
      - IPFS_ENABLED=false
    depends_on:
      - strfry
```

## 🚢 Déploiement

### Mode production avec Gunicorn
```bash
gunicorn -w 4 -b 0.0.0.0:5000 api_backend:app
```

### Nginx reverse proxy
```nginx
server {
    listen 80;
    server_name api.troczen.local;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /uploads {
        alias /var/www/troczen-api/uploads;
    }

    client_max_body_size 10M;
}
```

## 📚 Documentation complémentaire

- [IPFS_CONFIG.md](IPFS_CONFIG.md) - Configuration détaillée IPFS
- [DASHBOARD_MARCHAND_DOC.md](../DASHBOARD_MARCHAND_DOC.md) - Dashboard marchand
- [ARCHITECTURE.md](../ARCHITECTURE.md) - Architecture technique du système
- [FILE_INDEX.md](../FILE_INDEX.md) - Index complet de la documentation

## 🐛 Dépannage

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

### APK non trouvé
Vérifier que le fichier `.apk` est bien dans le dossier `apks/`

### Upload échoue
Vérifier les permissions :
```bash
chmod 755 uploads apks
```

## 🔒 Sécurité

- Validation des extensions de fichiers (png, jpg, jpeg, webp)
- Taille maximale : 5 MB
- Noms sécurisés avec `secure_filename()`
- Checksum SHA256 pour tous les fichiers uploadés
- CORS activé pour l'app mobile

## 📞 Support

Pour toute question :
1. Vérifier les logs de l'API
2. Consulter la documentation
3. Ouvrir une issue sur [GitHub](https://github.com/papiche/troczen)

## ✅ Checklist de déploiement

- [ ] Dépendances Python installées
- [ ] Variables d'environnement configurées
- [ ] API démarrée (port 5000)
- [ ] Strfry démarré (port 7777) - optionnel
- [ ] Tests passés
- [ ] Page web accessible
- [ ] Fallback testé

---

**TrocZen API Backend** - Version 1.0.0 - 2026
