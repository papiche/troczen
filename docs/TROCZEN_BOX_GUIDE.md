# Guide d'Installation : La TrocZen Box (Solaire & Autonome)

Ce guide explique comment transformer un Raspberry Pi en **"TrocZen Box"** : une borne Wi-Fi autonome, un relais Nostr local, une API et un serveur de distribution de l'APK TrocZen.

Cette configuration est optimisée pour fonctionner sur batterie et panneau solaire avec un **Raspberry Pi Zero 2 W**.

---

## ☀️ PARTIE 1 : Faisabilité Énergétique (Solaire 24/24)

Pour fonctionner sur batterie/solaire, le choix du matériel est critique. Un Raspberry Pi 4 consomme trop pour un petit panneau. Il faut utiliser un **Raspberry Pi Zero 2 W** (ou un Raspberry Pi 3A+).

### Bilan Électrique (Raspberry Pi Zero 2 W)
*   **Consommation moyenne** : ~1.2 Watts (avec Wi-Fi actif et petits pics CPU).
*   **Consommation journalière** : 1.2W × 24h = **~29 Wh/jour**.

### Dimensionnement de la Batterie (Pour 3 jours sans soleil)
Pour que la borne survive à 3 jours de mauvais temps (hiver) :
*   Besoin : 29 Wh × 3 jours = **87 Wh**.
*   **Batterie recommandée** : Une batterie externe (Powerbank) de **30 000 mAh** (à 3.7V, cela représente environ 111 Wh). Attention à choisir un modèle qui supporte la *charge "pass-through"* (qui peut se charger via le panneau solaire tout en alimentant le Pi).
*   *Alternative pro* : Petite batterie Plomb/Gel ou LiFePO4 de 12V 12Ah (~144 Wh) + convertisseur 12V vers USB 5V.

### Dimensionnement du Panneau Solaire
En hiver, vous n'aurez que 2 à 3 heures d'équivalent "plein soleil" par jour. Le panneau doit pouvoir générer les 29 Wh quotidiens en 2 heures.
*   **Panneau recommandé** : Un panneau solaire de **20W à 30W** (USB ou 12V).
*   Avec 30W, en 2 heures de soleil moyen, vous générez environ 40 à 50 Wh, ce qui recharge la batterie pour le jour actuel et le lendemain.

✅ **Conclusion Faisabilité** : **C'est 100% faisable, très fiable, et peu coûteux.**
*Budget matériel total (Pi Zero + SD + Powerbank 30k + Panneau USB 20W) : ~100€.*

---

## 🛠️ PARTIE 2 : Installation Pas-à-Pas (La TrocZen Box)

### Étape 1 : Préparation du système
1. Utilisez *Raspberry Pi Imager* pour flasher **Raspberry Pi OS Lite (64-bit)** (sans interface graphique pour économiser la RAM et l'énergie) sur une carte MicroSD.
2. Activez SSH dans les options avancées de l'imager.
3. Insérez la carte, branchez le Pi, et connectez-vous en SSH (`ssh pi@<IP_DU_PI>`).

### Étape 2 : Créer le réseau Wi-Fi (Point d'Accès)
Avec les versions récentes de Raspberry Pi OS, `NetworkManager` gère cela très facilement.

1. Créez un Hotspot nommé "TrocZen-Marche" :
```bash
sudo nmcli device wifi hotspot ifname wlan0 ssid TrocZen-Marche password "0penS0urce!"
```
*On collera un QR code sur la BOX pour se connecter facilement au WiFi de la BOX*

2. Le Pi aura l'IP fixe par défaut de son hotspot, généralement `10.42.0.1`.

### Étape 3 : Installer le Portail Captif & Serveur Web (Nginx + Dnsmasq)
L'objectif est que quiconque se connecte soit redirigé vers la page de téléchargement de l'APK.

1. Installez les paquets :
```bash
sudo apt update
sudo apt install nginx dnsmasq git python3-pip python3-venv -y
```

2. Configurez `dnsmasq` pour rediriger toutes les requêtes DNS vers le Pi :
```bash
sudo nano /etc/dnsmasq.conf
```
Ajoutez ces lignes à la fin :
```text
address=/#/10.42.0.1
interface=wlan0
```
Relancez dnsmasq : `sudo systemctl restart dnsmasq`

3. Configurez Nginx pour le portail captif :
```bash
sudo nano /etc/nginx/sites-available/default
```
Remplacez le contenu par :
```nginx
server {
    listen 80 default_server;
    server_name _;

    # Redirection portail captif (Android/iOS)
    error_page 404 =200 /index.html;
    location /generate_204 { return 302 http://10.42.0.1/; }
    location /hotspot-detect.html { return 302 http://10.42.0.1/; }

    root /var/www/html;
    index index.html;

    # Servir l'APK
    location /apks/ {
        alias /var/www/html/apks/;
        autoindex on;
    }

    # Proxy pour l'API Flask
    location /api/ {
        proxy_pass http://127.0.0.1:5000;
    }

    # Proxy pour Nostr Strfry
    location /nostr/ {
        proxy_pass http://127.0.0.1:7777;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
    }
}
```
Relancez Nginx : `sudo systemctl restart nginx`

4. Déposez l'APK et créez la page d'accueil :
```bash
sudo mkdir -p /var/www/html/apks
# Copiez votre troczen.apk dans /var/www/html/apks/ via SCP ou SFTP
```
Créez un fichier `/var/www/html/index.html` avec un gros bouton HTML qui pointe vers `<a href="/apks/troczen.apk">Télécharger TrocZen</a>`.

### Étape 4 : Installer le Relais Nostr (`strfry`)
`strfry` est écrit en C++ et est incroyablement léger, parfait pour un Pi Zero.

1. Téléchargez le binaire pré-compilé pour ARM64 :
```bash
wget https://github.com/hoytech/strfry/releases/latest/download/strfry-aarch64
chmod +x strfry-aarch64
sudo mv strfry-aarch64 /usr/local/bin/strfry
```

2. Créez la configuration et lancez-le en tâche de fond :
```bash
mkdir ~/strfry-data
cd ~/strfry-data
strfry init
```

3. **Configuration du Rate Limiting (Architecture Pollinisateur)** :
Pour permettre aux "Capitaines" (Alchimistes) de synchroniser massivement l'historique d'autres marchés (Gossip Push) sans être bannis pour spam, il faut désactiver ou augmenter les limites de `strfry` pour les IP locales.
Éditez le fichier `strfry.conf` généré dans `~/strfry-data/` :
```bash
nano ~/strfry-data/strfry.conf
```
Trouvez la section `rate_limiting` et ajustez les valeurs pour le réseau local (ex: `10.42.0.0/24`) :
```ini
rate_limiting {
    # Désactiver le rate limiting pour les IP du portail captif
    whitelist = ["10.42.0.0/24", "127.0.0.1"]
    
    # Ou augmenter considérablement les limites globales
    max_events_per_second = 5000
}
```

4. Créez un service Systemd pour qu'il démarre tout seul :
```bash
sudo nano /etc/systemd/system/strfry.service
```
```ini
[Unit]
Description=Strfry Nostr Relay
After=network.target

[Service]
ExecStart=/usr/local/bin/strfry relay
WorkingDirectory=/home/pi/strfry-data
User=pi
Restart=always

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl enable strfry --now
```

### Étape 5 : L'API Python (Optionnelle mais utile)
Si vous voulez gérer les logos en local sans IPFS (je recommande d'**éviter IPFS sur un Pi Zero** car c'est trop gourmand en RAM).

1. Clonez votre repo TrocZen :
```bash
cd ~
git clone https://github.com/papiche/troczen.git
cd troczen/api
```

2. Créez l'environnement et installez les dépendances :
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt gunicorn
```

3. Créez le service Systemd pour Flask :
```bash
sudo nano /etc/systemd/system/troczen-api.service
```
```ini
[Unit]
Description=TrocZen API
After=network.target

[Service]
User=pi
WorkingDirectory=/home/pi/troczen/api
Environment="PATH=/home/pi/troczen/api/venv/bin"
Environment="IPFS_ENABLED=false"
Environment="NOSTR_RELAY=ws://127.0.0.1:7777"
ExecStart=/home/pi/troczen/api/venv/bin/gunicorn -w 2 -b 127.0.0.1:5000 api_backend:app
Restart=always

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl enable troczen-api --now
```

---

## 🔋 Astuces d'Optimisation (Spécial "Solaire")

Si vous utilisez le Pi Zero 2 W avec cette configuration, voici comment gratter les derniers milliwatts :

1. **Désactiver le Bluetooth** et le HDMI (inutiles ici) :
   Dans `/boot/firmware/config.txt` (ou `/boot/config.txt`), ajoutez à la fin :
   ```text
   dtoverlay=disable-bt
   ```
   Pour désactiver le HDMI, éditez `/etc/rc.local` et ajoutez `tvservice -o` avant `exit 0`.

2. **Éviter IPFS** : Comme paramétré dans l'étape 5 (`IPFS_ENABLED=false`), ne faites pas tourner le daemon IPFS. Flask sauvegardera les images en local dans le dossier `uploads`, et Nginx les servira. C'est amplement suffisant pour un marché local et ça sauve 100 Mo de RAM.

3. **Paramétrage Flutter** : Côté code Dart `app_config.dart`, assurez-vous que `localRelayUrl` pointe bien vers `ws://10.42.0.1/nostr/` et l'API vers `http://10.42.0.1/api/`.

## 📱 L'UX Magique sur le terrain (Le scénario de Paolo)

L'application TrocZen intègre une fonctionnalité permettant de dériver le mot de passe Wi-Fi directement depuis la `market_seed`.

1. **L'Accroche (Appareil photo natif)** : Fred montre un QR Code généré par son application TrocZen (Onglet : "Partager le réseau Wi-Fi"). Paolo scanne ce QR avec l'appareil photo normal de son téléphone.
2. **La Connexion** : Le téléphone de Paolo se connecte instantanément au réseau `TrocZen-Marche`.
3. **Le Portail Captif** : Une page s'ouvre toute seule sur le téléphone de Paolo : *"Bienvenue sur le marché ! Téléchargez l'application TrocZen pour commencer."* Paolo installe l'APK.
4. **L'Embarquement** : Paolo ouvre TrocZen. L'application lui demande de scanner un marché. Fred lui montre alors le QR Code du Marché (qui contient la `market_seed`).
5. **C'est fini** : Paolo est synchronisé et prêt à émettre son premier bon !

### Paramétrage de la TrocZen Box (Raspberry Pi)
1. Le Pi est pré-configuré avec une `market_seed` fixe générée à l'avance.
2. Le mot de passe Wi-Fi du Pi est généré via la même logique (`SHA256(seed + "wifi_password")`).
3. Sur le boîtier physique en plastique du Raspberry Pi, on colle **deux autocollants QR Codes** :
   * 📡 **ÉTAPE 1** : Un QR Wi-Fi standard (pour se connecter et télécharger l'App via le portail captif).
   * 🤝 **ÉTAPE 2** : Un QR TrocZen (format `troczen://market?...`) contenant la seed, que Fred et Paolo scanneront depuis l'application pour synchroniser leurs données.
