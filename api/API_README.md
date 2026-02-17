# TrocZen API Backend

Backend Flask pour gérer les logos commerçants, la distribution d'APK et les profils Nostr.

## 🚀 Installation

### Prérequis
- Python 3.10+
- pip

### Setup

```bash
# Installer les dépendances
pip install -r requirements.txt

# Créer les dossiers
mkdir -p uploads apks profiles templates

# Copier les templates HTML
cp templates/*.html templates/
```

## 📁 Structure

```
.
├── api_backend.py          # Application Flask principale
├── requirements.txt        # Dépendances Python
├── templates/
│   ├── index.html         # Page d'accueil API
│   └── market.html        # Page présentation marché
├── uploads/               # Logos commerçants uploadés
├── apks/                  # Fichiers APK
└── profiles/              # Profils JSON commerçants
```

## 🔧 Configuration

### Variables d'environnement (optionnel)

```bash
export UPLOAD_FOLDER=./uploads
export APK_FOLDER=./apks
export MAX_FILE_SIZE=5242880  # 5MB
```

## 🏃 Lancer l'API

### Mode développement

```bash
python api_backend.py
```

L'API sera accessible sur `http://localhost:5000`

### Mode production (avec Gunicorn)

```bash
gunicorn -w 4 -b 0.0.0.0:5000 api_backend:app
```

### Avec systemd (démarrage automatique)

```bash
# Créer /etc/systemd/system/troczen-api.service
[Unit]
Description=TrocZen API Backend
After=network.target

[Service]
User=www-data
WorkingDirectory=/var/www/troczen-api
Environment="PATH=/var/www/troczen-api/venv/bin"
ExecStart=/var/www/troczen-api/venv/bin/gunicorn -w 4 -b 0.0.0.0:5000 api_backend:app

[Install]
WantedBy=multi-user.target

# Activer
sudo systemctl enable troczen-api
sudo systemctl start troczen-api
```

## 📡 Endpoints

### Health Check
```bash
GET /health
```

### Upload Logo
```bash
POST /api/upload/logo
Content-Type: multipart/form-data

file: <image_file>
npub: <nostr_public_key>
```

**Exemple :**
```bash
curl -X POST http://localhost:5000/api/upload/logo \
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

**Exemple :**
```bash
curl -O http://localhost:5000/api/apk/download/troczen-1.0.0.apk
```

### QR Code APK
```bash
GET /api/apk/qr
```

Retourne une image PNG du QR code pour télécharger l'APK.

### Profil Commerçant

**Créer/Mettre à jour :**
```bash
POST /api/profile/<npub>
Content-Type: application/json

{
  "name": "La Miellerie",
  "description": "Miel local bio",
  "location": "Marché de Toulouse",
  "hours": "Sam 9h-13h",
  "phone": "+33 6 12 34 56 78",
  "website": "https://miellerie.example.com",
  "logo_url": "/uploads/npub1abc_logo.png"
}
```

**Récupérer :**
```bash
GET /api/profile/<npub>
```

**Lister tous :**
```bash
GET /api/profiles
```

### Page Marché
```bash
GET /market/<market_name>
```

Affiche la page HTML avec :
- QR code téléchargement APK
- Liste des commerçants participants
- Informations du marché

## 📊 Statistiques

```bash
GET /api/stats
```

**Réponse :**
```json
{
  "apks": 3,
  "logos": 42,
  "profiles": 15,
  "timestamp": "2026-02-16T12:00:00"
}
```

## 🔐 Sécurité

### Validation fichiers
- Extensions autorisées : `.png`, `.jpg`, `.jpeg`, `.webp`
- Taille max : 5 MB
- Nom sécurisé avec `secure_filename()`

### Checksums
Tous les fichiers uploadés ont un checksum SHA256 calculé.

### Headers CORS
CORS activé pour permettre l'accès depuis l'app mobile.

## 🚢 Déploiement

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

### Docker

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:5000", "api_backend:app"]
```

```bash
# Build
docker build -t troczen-api .

# Run
docker run -d -p 5000:5000 \
  -v $(pwd)/uploads:/app/uploads \
  -v $(pwd)/apks:/app/apks \
  -v $(pwd)/profiles:/app/profiles \
  troczen-api
```

## 📝 Workflow d'utilisation

### 1. Déployer l'API sur un serveur

```bash
# Sur le serveur
git clone https://github.com/troczen/troczen-api
cd troczen-api
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
gunicorn -w 4 -b 0.0.0.0:5000 api_backend:app
```

### 2. Upload APK initial

```bash
# Copier l'APK compilé
cp ~/troczen/build/app/outputs/flutter-apk/app-release.apk apks/troczen-1.0.0.apk
```

### 3. Créer profils commerçants

```bash
curl -X POST http://api.troczen.local/api/profile/npub1apiculteur \
  -H "Content-Type: application/json" \
  -d '{
    "name": "L'\''Apiculteur",
    "description": "Miel de lavande et produits de la ruche",
    "location": "Stand 12, Marché de Toulouse",
    "hours": "Samedi 8h-13h"
  }'
```

### 4. Partager la page marché

Envoyer aux participants :
```
https://api.troczen.local/market/marche-toulouse
```

Ils peuvent :
- Scanner le QR code pour télécharger l'APK
- Voir tous les commerçants participants
- Accéder aux infos de contact

## 🔄 Mise à jour APK

```bash
# Compiler nouvelle version
cd ~/troczen
flutter build apk --release

# Copier sur le serveur
scp build/app/outputs/flutter-apk/app-release.apk \
  user@server:/var/www/troczen-api/apks/troczen-1.1.0.apk

# L'endpoint /api/apk/latest retourne automatiquement la plus récente
```

## 🧪 Tests

```bash
# Health check
curl http://localhost:5000/health

# Upload test
curl -X POST http://localhost:5000/api/upload/logo \
  -F "file=@test-logo.png" \
  -F "npub=npub1test123"

# Get APK info
curl http://localhost:5000/api/apk/latest

# Create profile
curl -X POST http://localhost:5000/api/profile/npub1test \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","description":"Test merchant"}'

# List profiles
curl http://localhost:5000/api/profiles
```

## 📖 Documentation API complète

Accessible sur `http://localhost:5000/` après démarrage.

## 🐛 Troubleshooting

### Erreur "ModuleNotFoundError: No module named 'flask'"
```bash
pip install -r requirements.txt
```

### Erreur "Permission denied" sur uploads/
```bash
chmod 755 uploads apks profiles
```

### APK non trouvé
Vérifier que le fichier .apk est bien dans le dossier `apks/`

## 📄 License

MIT

## 👥 Contributeurs

Projet TrocZen - 2026
