# Configuration IPFS - TrocZen API

## 📦 Intégration IPFS

L'API TrocZen supporte maintenant le stockage décentralisé des images via IPFS (InterPlanetary File System).

### Avantages IPFS

✅ **Décentralisé** : Pas de serveur unique  
✅ **Permanent** : Contenu adressé par hash (CID)  
✅ **Résilient** : Réplication automatique  
✅ **Cache** : Distribution mondiale via passerelles  
✅ **Vérifable** : CID = hash du contenu  

---

## 🔧 Configuration

### Variables d'environnement

```bash
# API IPFS locale (node IPFS)
export IPFS_API_URL="http://127.0.0.1:5001"

# Passerelle publique pour accès HTTP
export IPFS_GATEWAY="https://ipfs.copylaradio.com"

# Activer/désactiver IPFS
export IPFS_ENABLED="true"
```

### Par défaut

- **API** : `http://127.0.0.1:5001` (node IPFS local)
- **Passerelle** : `https://ipfs.copylaradio.com`
- **Statut** : Activé

---

## 🚀 Installation IPFS

### Option 1 : Kubo (go-ipfs)

```bash
# Télécharger
wget https://dist.ipfs.tech/kubo/v0.26.0/kubo_v0.26.0_linux-amd64.tar.gz

# Extraire
tar -xvzf kubo_v0.26.0_linux-amd64.tar.gz

# Installer
cd kubo
sudo bash install.sh

# Initialiser
ipfs init

# Démarrer daemon
ipfs daemon
```

### Option 2 : Docker

```bash
docker run -d --name ipfs_host \
  -v /path/to/ipfs:/data/ipfs \
  -p 4001:4001 \
  -p 5001:5001 \
  -p 8080:8080 \
  ipfs/kubo:latest
```

### Option 3 : Service systemd

```bash
# Créer /etc/systemd/system/ipfs.service
[Unit]
Description=IPFS Daemon
After=network.target

[Service]
Type=simple
User=ipfs
ExecStart=/usr/local/bin/ipfs daemon
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable ipfs
sudo systemctl start ipfs
```

---

## 📡 Passerelle IPFS

### Configuration Nginx (ipfs.copylaradio.com)

```nginx
server {
    listen 443 ssl http2;
    server_name ipfs.copylaradio.com;

    ssl_certificate /etc/letsencrypt/live/ipfs.copylaradio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ipfs.copylaradio.com/privkey.pem;

    # Redirection IPFS
    location /ipfs/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        
        # Cache agressif
        proxy_cache_valid 200 365d;
        proxy_cache_valid 404 1h;
    }

    location /ipns/ {
        proxy_pass http://127.0.0.1:8080;
    }
}
```

---

## 🔄 Workflow Upload

### 1. Application Flutter

```dart
// Upload logo
final result = await apiService.uploadLogo(
  npub: user.npub,
  imageFile: File('/path/to/logo.png'),
);

// Récupérer URLs
final ipfsUrl = result['ipfs_url'];   // https://ipfs.copylaradio.com/ipfs/Qm...
final localUrl = result['local_url']; // /uploads/abc123.png
final cid = result['ipfs_cid'];       // QmXXXXXXXXXXX...
```

### 2. API Backend

```
1. Sauvegarde locale (/uploads/...)
2. Upload vers IPFS node (POST /api/v0/add)
3. Récupération CID
4. Construction URL passerelle
5. Retour JSON avec URLs multiples
```

### 3. Stockage Profil

```json
{
  "picture": "https://ipfs.copylaradio.com/ipfs/QmXXX/logo.png",
  "picture_cid": "QmXXXXXXXXXXXXXXXX",
  "picture_local": "/uploads/logo_abc.png"
}
```

---

## 📊 Format Réponse API

```json
{
  "success": true,
  "url": "https://ipfs.copylaradio.com/ipfs/QmYjtig7VJQ6/logo.png",
  "local_url": "/uploads/merchant_123.png",
  "ipfs_url": "https://ipfs.copylaradio.com/ipfs/QmYjtig7VJQ6/logo.png",
  "ipfs_cid": "QmYjtig7VJQ6XNW8PSUw8gXCCWGqgV5HEZ2yiBWVb8CZke",
  "filename": "merchant_123.png",
  "checksum": "a3f5...",
  "size": 45678,
  "storage": "ipfs",
  "uploaded_at": "2026-02-16T21:00:00"
}
```

---

## 🧪 Test

### Vérifier IPFS actif

```bash
curl http://127.0.0.1:5001/api/v0/version
```

### Upload test

```bash
curl -F "file=@test.png" -F "npub=abc123" \
  http://localhost:5000/api/upload/logo
```

### Récupérer via IPFS

```bash
curl https://ipfs.copylaradio.com/ipfs/QmXXXXX...
```

---

## ⚠️ Fallback Automatique

Si IPFS non disponible :
- ✅ Upload local fonctionne quand même
- ✅ `url` pointe vers `/uploads/...`
- ✅ `storage` = "local"
- ❌ `ipfs_cid` = null

**L'API reste fonctionnelle même sans IPFS !**

---

## 🎯 Passerelles Publiques Alternatives

Si `ipfs.copylaradio.com` indisponible :

1. **ipfs.io** : `https://ipfs.io/ipfs/<CID>`
2. **dweb.link** : `https://dweb.link/ipfs/<CID>`
3. **cloudflare** : `https://cloudflare-ipfs.com/ipfs/<CID>`
4. **pinata** : `https://gateway.pinata.cloud/ipfs/<CID>`

Configuration:
```python
IPFS_GATEWAY = "https://ipfs.io"
```

---

## 📈 Avantages pour TrocZen

1. **Résilience** : Images accessibles même si serveur tombe
2. **Distribution** : Cache mondial automatique
3. **Vérifiabilité** : CID = preuve d'intégrité
4. **Permanence** : Contenu ne disparaît pas (si pinned)
5. **Décentralisation** : Cohérent avec philosophie Nostr

---

## 🔐 Pinning (Optionnel)

Pour garantir disponibilité permanente:

```bash
# Pin localement
ipfs pin add QmXXXXX...

# Ou via service (Pinata, Web3.Storage)
curl -X POST "https://api.pinata.cloud/pinning/pinByHash" \
  -H "Authorization: Bearer YOUR_JWT" \
  -d '{"hashToPin":"QmXXXXX..."}'
```

---

**Date** : 16 février 2026  
**Version** : 1.2.0-ipfs  
**Statut** : ✅ Production-ready avec IPFS
