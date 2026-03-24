# Guide TrocZen Box — Architecture, Boucles et Installation

> « Ğ1 apporte la Liberté · Ẑen apporte l'Égalité · ❤️ apporte la Fraternité »  
> *La TrocZen Box est le nœud physique qui rend ces trois vertus vivantes sur un marché local.*

---

## 🧭 Vue d'Ensemble : Ce qu'est une TrocZen Box

Une **TrocZen Box** (Raspberry Pi Zero 2 W + panneau solaire) est un **nœud d'économie locale autonome** qui remplit simultanément quatre rôles :

| Rôle | Technologie | Boucle activée |
|------|-------------|----------------|
| **Borne Wi-Fi** | Hotspot NetworkManager | Connexion physique au marché |
| **Relais Nostr local** | strfry (C++, léger) | Synchronisation des graphes sociaux et des bons ẐEN |
| **API de marché** | Flask/Gunicorn | Création/vérification des bons, profils marchands |
| **Distributeur APK** | Nginx + portail captif | Embarquement de nouveaux participants |

```
┌─────────────────────────────────────────────────────────────────┐
│                     TrocZen Box (Raspberry Pi Zero 2 W)        │
├────────────────┬───────────────┬────────────────┬──────────────┤
│  📡 Wi-Fi AP   │ 📝 strfry     │ 🐍 Flask API   │ 📱 Nginx APK │
│  TrocZen-Mché  │ ws://:7777    │ :5000          │ :80          │
│                │               │                │              │
│  QR → Wifi     │ Kind 3 WoT    │ Bon Ẑen CRUD   │ troczen.apk  │
│  auto-connect  │ Kind 30303/5  │ DU calc cache  │  download    │
│  portail captif│ Kind 30305 DU │ marché info    │  QR code     │
└────────────────┴───────────────┴────────────────┴──────────────┘
         ↑                   ↑                ↑
    Connexion             Gossip          Installation
    physique          P2P marchés        nouveaux membres
```

---

## 🔄 Les 4 Boucles du Système

### Boucle 1 — Connexion Physique (Wi-Fi → APK → Marché)

```
Visiteur arrive au marché
        ↓
Scanne QR Wi-Fi sur la Box
        ↓
Téléphone se connecte à "TrocZen-Marche"
        ↓
Portail captif → page de téléchargement
        ↓
Installe TrocZen.apk depuis la Box
        ↓
Scanne QR TrocZen (market_seed)
        ↓
Synchronisé avec le marché local ←────── Boucle fermée
```

**Effet sur la distribution :** chaque nouvelle personne rejoint le réseau local *sans internet*, *sans compte*, *sans intermédiaire*. La Box est la porte d'entrée souveraine.

---

### Boucle 2 — Graphe Social (WoT → DU → Confiance)

```
Alice suit Bob (Kind 3 Nostr)
        ↓
Bob suit Alice (Kind 3 Nostr)
        ↓
Lien réciproque établi (N1++)
        ↓
Quand N1 ≥ 5 → DU journalier activé
        ↓
Alice émet des Bons ẐEN (Kind 30303)
        ↓
Bons circulent au marché → créent du N2
        ↓
N2 plus dense → DU plus élevé ←──────── Boucle vertueuse
```

**Effet sur la distribution :** la monnaie naît *de* la confiance tissée. Plus le réseau est dense, plus chacun peut créer. Résistance Sybil naturelle : créer des faux comptes dilue sa propre création.

---

### Boucle 3 — Circulation des Bons (Valeur → Hops → Retour)

```
Bon émis par Alice (montant Z ẐEN, TTL choisi)
        ↓
Transféré à Bob (double scan hors-ligne)
        ↓        hop++, path[HMAC(Bob, bon_id)]
Transféré à Charlie
        ↓        hop++, path[HMAC(Charlie, bon_id)]
...
        ↓
Retour à Alice → BOUCLE FERMÉE
        ↓
Destruction du bon + révélation du circuit
        ↓
Publication Kind 30304 (BonCircuit)
        ↓
Alice reçoit: X ẐEN · Y hops · Z jours ←─ Diagnostic de confiance
```

**Effet sur la distribution :** chaque bon raconte son voyage. Le réseau apprend où la confiance coule naturellement. Les bons qui expirent (TTL=0) marquent les zones à renforcer.

---

### Boucle 4 — Love Ledger UPlanet (❤️ → DU Kind 30305 → Bons TrocZen)

Cette boucle **connecte TrocZen à l'écosystème UPlanet** :

```
Capitaine UPlanet héberge la Box bénévolement
        ↓
ZEN.ECONOMY.sh comptabilise le sacrifice (Love Ledger)
        ↓
Émet Kind 30305 NOSTR (DU TrocZen, amount=LOVE_ZEN)
        ↓
TrocZen voit le Kind 30305 du Capitaine
        ↓
Crédite le Capitaine de DU disponible
        ↓
Capitaine émet des Bons ẐEN fondants (28j TTL)
        ↓
Échange sur le marché local → services/biens
        ↓
Nouveaux membres → revenus UPlanet CASH ←── Boucle autonome
```

**Effet :** le bénévolat technique (héberger la Box, maintenir l'infra) est **récompensé en monnaie locale** via le DU TrocZen. Le sacrifice du Capitaine circule dans l'économie locale sous forme de confiance et de biens.

```
1 ❤️ = 1 DU = 1 Bon TrocZen = 1 service/bien local
```

---

## 📊 Distribution d'Information : Qui Sait Quoi ?

| Information | Visible par | Protégée de |
|-------------|-------------|-------------|
| Qu'un bon a circulé (X hops, Y jours) | Tous | — |
| Valeur nominale d'un bon | Tous | — |
| Qui a porté le bon | Personne | Tous |
| Émetteur du bon | Émetteur seulement | Autres porteurs |
| Porteurs dans N1+N2 de l'émetteur | Émetteur (HMAC dérivé) | Porteurs hors réseau |
| Masse monétaire totale (M_n1, M_n2) | App (calcul) | Individus spécifiques |
| DU disponible d'Alice | Alice seulement | Bob, Charlie, etc. |

**Principe :** la *santé collective* est transparente (métriques agrégées). La *vie privée individuelle* est protégée par défaut (HMAC).

---

## ⚡ Distribution de Valeur : Qui Crée Quoi ?

| Acteur | Création de valeur | Mécanisme |
|--------|--------------------|-----------|
| **Membre ordinaire** | DU local (N1 ≥ 5) | Formule TRM, graphe social |
| **Tisseur** | DU amplifié (dense N2) | Ponts entre communautés |
| **Capitaine Box** | DU TrocZen (Kind 30305) | Love Ledger UPlanet |
| **Marchand actif** | Vélocité de la monnaie | Bons qui circulent vite |
| **Gardien** | Stabilité (faibles expirations) | Boucles fermées régulières |

---

## ☀️ PARTIE 1 : Faisabilité Énergétique (Solaire 24/24)

### Bilan Électrique (Raspberry Pi Zero 2 W)

- **Consommation moyenne** : ~1.2 Watts (Wi-Fi actif, petits pics CPU)
- **Consommation journalière** : 1.2W × 24h = **~29 Wh/jour**

### Dimensionnement pour 3 jours sans soleil

- Besoin : 29 Wh × 3 jours = **87 Wh**
- **Batterie recommandée** : Powerbank 30 000 mAh (~111 Wh) avec charge pass-through
- *Alternative pro* : Batterie LiFePO4 12V/12Ah + convertisseur 12V→USB 5V

### Panneau Solaire

En hiver : 2–3 heures d'équivalent plein soleil par jour.
- **Panneau recommandé** : 20W à 30W (USB ou 12V)
- 30W × 2h = 40–50 Wh → recharge la journée + réserve pour demain

✅ **Budget total estimé (Pi Zero + SD + Powerbank 30k + Panneau 20W) : ~100€**

---

## 🛠️ PARTIE 2 : Installation Pas-à-Pas

### Étape 1 : Système de base

1. Flashez **Raspberry Pi OS Lite 64-bit** avec Raspberry Pi Imager
2. Activez SSH dans les options avancées
3. Connectez-vous : `ssh pi@<IP_DU_PI>`

### Étape 2 : Point d'Accès Wi-Fi

```bash
# Création du hotspot "TrocZen-Marche"
sudo nmcli device wifi hotspot ifname wlan0 ssid TrocZen-Marche password "0penS0urce!"
# Le Pi obtient l'IP 10.42.0.1
```

Collez un QR code du Wi-Fi sur le boîtier physique de la Box.

### Étape 3 : Portail Captif (Nginx + Dnsmasq)

```bash
sudo apt update && sudo apt install nginx dnsmasq git python3-pip python3-venv -y
```

Configuration dnsmasq (`/etc/dnsmasq.conf`) — redirige tout vers le Pi :
```text
address=/#/10.42.0.1
interface=wlan0
```

Configuration Nginx (`/etc/nginx/sites-available/default`) :
```nginx
server {
    listen 80 default_server;
    server_name _;

    # Portail captif Android/iOS
    location /generate_204 { return 302 http://10.42.0.1/; }
    location /hotspot-detect.html { return 302 http://10.42.0.1/; }

    root /var/www/html;
    index index.html;

    # APK TrocZen
    location /apks/ {
        alias /var/www/html/apks/;
        autoindex on;
    }

    # API Flask (Bons, DU, marchands)
    location /api/ {
        proxy_pass http://127.0.0.1:5000;
    }

    # Relais Nostr strfry (WebSocket)
    location /nostr/ {
        proxy_pass http://127.0.0.1:7777;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
    }
}
```

```bash
sudo mkdir -p /var/www/html/apks
# → Copiez troczen.apk ici via SCP
# → Créez index.html avec <a href="/apks/troczen.apk">Télécharger TrocZen</a>
sudo systemctl restart nginx dnsmasq
```

### Étape 4 : Relais Nostr (strfry)

strfry est écrit en C++, extrêmement léger — idéal pour Pi Zero.

```bash
wget https://github.com/hoytech/strfry/releases/latest/download/strfry-aarch64
chmod +x strfry-aarch64
sudo mv strfry-aarch64 /usr/local/bin/strfry
mkdir ~/strfry-data && cd ~/strfry-data
strfry init
```

Configuration rate limiting pour le réseau local (`~/strfry-data/strfry.conf`) — essentiel pour le Gossip Push des Capitaines :
```ini
rate_limiting {
    whitelist = ["10.42.0.0/24", "127.0.0.1"]
    max_events_per_second = 5000
}
```

Service Systemd :
```bash
sudo nano /etc/systemd/system/strfry.service
```
```ini
[Unit]
Description=Strfry Nostr Relay (TrocZen Box)
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

> **Kinds synchronisés** : 0, 1, 3, 4, 5, 6, 7, 30303, 30304, 30305 (DU Love Ledger), 30503 (credentials Oracle UPlanet)

### Étape 5 : API Python (DU, Bons, Marchands)

```bash
cd ~ && git clone https://github.com/papiche/troczen.git
cd troczen/api
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt gunicorn
```

Service Systemd (sans IPFS sur Pi Zero — trop gourmand en RAM) :
```bash
sudo nano /etc/systemd/system/troczen-api.service
```
```ini
[Unit]
Description=TrocZen API (Bons, DU, Marchands)
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

## 🔋 Optimisation Énergétique

```bash
# Dans /boot/firmware/config.txt
dtoverlay=disable-bt    # Désactive Bluetooth

# Dans /etc/rc.local (avant exit 0)
tvservice -o            # Désactive HDMI
```

**Ne pas installer IPFS** sur Pi Zero (`IPFS_ENABLED=false`) — consomme 100 Mo RAM inutilement. Nginx sert les images localement.

---

## 📱 Scénario d'Embarquement (Paolo arrive au marché)

```
1. 📡 Paolo voit la Box avec 2 QR codes collés dessus
   
2. 📷 Scan QR Wi-Fi (appareil photo natif)
   → Connexion automatique à "TrocZen-Marche"
   
3. 📲 Portail captif s'ouvre : "Bienvenue ! Téléchargez TrocZen"
   → Installe troczen.apk depuis la Box
   
4. 🤝 Fred montre le QR TrocZen (market_seed)
   → Paolo scanne → synchronisé avec le marché
   
5. 🌱 Paolo reçoit son Bon Zéro (0 ẐEN, 28j)
   → Suit Fred → N1 de Fred++
   → Fred se rapproche de son premier DU
   
6. 💫 Quand Fred atteint N1 = 5
   → ZEN.ECONOMY.sh détecte (si Capitaine UPlanet)
   → Kind 30305 : DU TrocZen émis = Love Ledger
   → Fred peut émettre de vrais Bons ẐEN
```

---

## 🔗 Connexion avec l'Écosystème UPlanet

```
TrocZen Box (marché local)          UPlanet Astroport (infra coopérative)
────────────────────────────        ────────────────────────────────────────
Kind 30303 (Bon ẐEN)                ZEN.ECONOMY.sh (paiement PAF)
Kind 30304 (BonCircuit)     ↔       love_ledger.json (sacrifice bénévolat)
Kind 30305 (DU Love Ledger) ←──────  Kind 30305 émis si LOVE_DONATION > 0
Kind 3 (WoT locale)                 Kind 30850 (santé économique constellation)

Ğ1 → Ẑen (paiements infra)         ❤️ → DU (bónévolat → monnaie locale)
LIBERTÉ                              FRATERNITÉ
        ───────── ÉGALITÉ ──────────
                 Ẑen = 1 unité de compte
```

---

## 📦 Résumé des QR Codes sur le Boîtier Physique

```
┌─────────────────────────────────────┐
│  📡 ÉTAPE 1         🤝 ÉTAPE 2      │
│  [QR Wi-Fi]        [QR TrocZen]    │
│  Se connecter       Rejoindre       │
│  au réseau         le marché       │
│  télécharger       synchroniser    │
│  TrocZen.apk       ses bons        │
└─────────────────────────────────────┘
```

> *TrocZen Box · Économie locale souveraine · NIP-30303/30304/30305 · AGPL-3.0*
