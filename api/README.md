# API Backend TrocZen

Backend Flask pour l'écosystème TrocZen : infrastructure de service, distribution d'APK, gestion de la whitelist Nostr Strfry, et stockage IPFS.

## Résumé

L'API backend TrocZen a été simplifiée pour devenir une pure infrastructure de service. Toute l'intelligence économique (calcul du DU, paramètres C² et alpha, gestion des circuits) et la certification (WoTx2) ont été migrées dans le code Dart de l'application mobile (App Flutter V6 "Hyper-Relativiste").

Le backend se concentre désormais sur ce que le téléphone ne peut pas faire seul :
- L'hébergement de fichiers (IPFS)
- La distribution de l'application (APK)
- La passerelle de sécurité (GitHub, Whitelist Strfry)
- La configuration de la TrocZen Box

## Fonctionnalités

### Stockage décentralisé IPFS
- Upload automatique des images (logos, bannières) vers IPFS
- URLs permanentes via CID
- Fallback local si IPFS désactivé
- Polling asynchrone du statut d'upload

### Distribution APK (Viralité)
- Détection automatique de la dernière version
- Téléchargement direct
- Génération de QR code
- Checksum SHA256

### Sécurité & Configuration (TrocZen Box)
- Enregistrement des clés publiques (pubkey) dans la whitelist `amisOfAmis.txt` du relai Strfry
- Génération de QR codes pour la connexion WiFi et la configuration du marché sur la Box
- Découverte dynamique de la configuration (URL du relai, IPFS) lors de l'onboarding

### Support
- Transformation des retours utilisateurs (logs/feedback) en issues GitHub de manière sécurisée (sans exposer le token client)
- Monitoring de base (Health check)

## Structure du projet

```
api/
├── api_backend.py              # Application Flask principale
├── requirements.txt            # Dépendances Python
├── .env.example                # Variables d'environnement
│
├── uploads/                    # Fichiers uploadés (fallback local)
├── apks/                       # Fichiers APK
└── README.md                   # Ce fichier
```

## Installation rapide

### 1. Prérequis
- Python 3.10+
- pip

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
# IPFS
IPFS_ENABLED=true
IPFS_API_URL=http://127.0.0.1:5001
IPFS_GATEWAY=https://ipfs.copylaradio.com

# GitHub (pour le feedback)
GITHUB_TOKEN=votre_token
GITHUB_REPO=papiche/troczen

# TrocZen Box
MARKET_SEED=0000000000000000000000000000000000000000000000000000000000000000
MARKET_NAME=marche-libre
WIFI_SSID=ZenBox
WIFI_PASSWORD=0penS0urce!
BOX_IP=10.42.0.1
```

### 4. Démarrer l'API
```bash
python api_backend.py
```

L'API sera accessible sur `http://localhost:5000`

## Endpoints API

### Health Check & Config
```bash
GET /health
GET /api/health/services
GET /api/config
```

### Upload d'image
```bash
POST /api/upload/image
Content-Type: multipart/form-data

file: <image_file>
npub: <nostr_public_key>
type: logo|banner|avatar
```

```bash
GET /api/upload/status/<filename>
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

### Sécurité & Box

#### Enregistrement Whitelist Strfry
```bash
POST /api/nostr/register
Content-Type: application/json

{
  "pubkey": "<nostr_public_key_hex>"
}
```

#### QR Codes Box
```bash
GET /api/box/qr
```

### Support

#### Feedback GitHub
```bash
POST /api/feedback
Content-Type: application/json

{
  "title": "Titre du bug",
  "description": "Description détaillée",
  "type": "bug",
  "email": "user@example.com",
  "app_version": "1.0.0",
  "platform": "android"
}
```

## Architecture

L'API est conçue pour être une infrastructure légère et **stateless**. Elle ne possède pas de base de données propre (hormis le stockage de fichiers) et délègue toute la logique métier et le stockage des données structurées au relai Nostr et à l'application mobile.

## Sécurité

- Validation des extensions de fichiers (png, jpg, jpeg, webp)
- Taille maximale : 5 MB
- Noms sécurisés avec `secure_filename()`
- Checksum SHA256 pour tous les fichiers
- CORS activé pour l'app mobile
- Magic bytes validation pour les uploads
- Token GitHub conservé côté serveur

## Déploiement

### Mode production avec Gunicorn
```bash
gunicorn -w 4 -b 0.0.0.0:5000 api_backend:app
```

### Docker Compose
```yaml
version: '3.8'

services:
  api:
    build: .
    ports:
      - "5000:5000"
    environment:
      - IPFS_ENABLED=true
```

---

**TrocZen API Backend** - Version 2.0.0 - 2026
**Rôle**: Infrastructure de service et stockage IPFS
