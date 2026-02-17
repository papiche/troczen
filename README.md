# TrocZen - Application de Bons ẐEN

Application Flutter pour la création, le transfert et l'encaissement de bons de valeur locaux (ẐEN) en mode 100% offline.

## 🎯 Caractéristiques

- **Offline-first**: Fonctionne sans connexion Internet après synchronisation
- **Sécurité cryptographique**: Découpage SSSS (Shamir Secret Sharing 2-sur-3)
- **Handshake atomique**: Double scan pour empêcher la double dépense
- **QR codes binaires**: Format compact (113 octets) pour une lecture fiable
- **Interface Panini**: Cartes à collectionner ludiques et intuitives
- **Synchronisation Nostr**: Publication et récupération via kind 30303

## 📋 Prérequis

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio ou Xcode
- Appareil Android 5.0+ ou iOS 12+

## 🚀 Installation

### 1. Cloner le projet

```bash
git clone https://github.com/papiche/troczen.git
cd troczen
```

### 2. Installer les dépendances

```bash
flutter pub get
```

### 3. Vérifier la configuration

```bash
flutter doctor
```

### 4. Lancer l'application

```bash
# En mode développement
flutter run

# Pour Android
flutter run -d android

# Pour iOS
flutter run -d ios
```

## 📦 Compilation pour production

### Android (APK)

```bash
# APK classique
flutter build apk --release

# APK splitté (recommandé, plus petit)
flutter build apk --split-per-abi --release
```

Les fichiers se trouvent dans `build/app/outputs/flutter-apk/`

### iOS (IPA)

```bash
flutter build ios --release
```

Puis utilisez Xcode pour archiver et distribuer.

## 🏗️ Architecture

```
lib/
├── main.dart                 # Point d'entrée
├── models/
│   ├── user.dart            # Modèle utilisateur
│   ├── bon.dart             # Modèle bon ẐEN
│   ├── market.dart          # Modèle marché
│   └── nostr_profile.dart   # Modèle pour les profils Nostr
├── services/
│   ├── crypto_service.dart  # Cryptographie (SSSS, chiffrement)
│   ├── qr_service.dart      # Génération/décodage QR binaire
│   ├── storage_service.dart # Stockage sécurisé
│   ├── api_service.dart      # Service pour les appels API
│   ├── audit_trail_service.dart # Service pour l'audit des transactions
│   ├── burn_service.dart     # Service pour brûler les bons
│   ├── feedback_service.dart # Service pour gérer les retours utilisateurs
│   ├── nfc_service.dart      # Service pour la gestion NFC
│   ├── nostr_service.dart    # Service pour les interactions Nostr
│   └── crypto_service_old.dart # Ancienne version du service de cryptographie
├── screens/
│   ├── wallet_screen.dart   # Liste des bons
│   ├── create_bon_screen.dart  # Création de bon
│   ├── offer_screen.dart    # Affichage QR d'offre
│   ├── scan_screen.dart     # Scan QR
│   ├── market_screen.dart   # Configuration marché
│   ├── ack_scanner_screen.dart # Écran pour scanner les QR codes ACK
│   ├── ack_screen.dart      # Écran pour afficher les QR codes ACK
│   ├── atomic_swap_screen.dart # Écran pour les échanges atomiques
│   ├── bon_profile_screen.dart # Écran pour afficher le profil d'un bon
│   ├── feedback_screen.dart # Écran pour les retours utilisateurs
│   ├── gallery_screen.dart  # Écran pour la galerie
│   ├── help_screen.dart     # Écran d'aide
│   └── merchant_dashboard_screen.dart # Tableau de bord pour les commerçants
└── widgets/
    └── panini_card.dart     # Carte Panini
```

## 🔐 Sécurité

### Découpage SSSS

Chaque bon est une identité Nostr dont la clé privée est divisée en 3 parts :

- **P1 (Ancre)**: Reste chez l'émetteur, permet la révocation
- **P2 (Voyageur)**: Circule de main en main, représente la valeur
- **P3 (Témoin)**: Publiée sur Nostr, permet la validation

### Chiffrement

- **P2**: Chiffré avec `K_P2 = SHA256(P3)` lors des transferts
- **P3**: Chiffré avec `K_market` (clé AES-256 du marché) avant publication Nostr

### Stockage

- Clés utilisateur: `FlutterSecureStorage` (keystore Android/iOS)
- Bons et P3: Stockage sécurisé avec chiffrement matériel

## 📱 Utilisation

### Premier lancement

1. **Créer un compte**
   - Saisir un login unique et un mot de passe fort (min 8 caractères)
   - Un nom d'affichage optionnel
   - Le système dérive votre identité Nostr depuis ces identifiants

2. **Configurer le marché** (icône ⚙️)
   - Nom du marché (ex: marche-toulouse)
   - K_market (64 caractères hex, obtenue via QR de la borne ou Wi-Fi local)
   - URL du relais Nostr (optionnel)

### Créer un bon

1. Cliquer sur le bouton `+`
2. Saisir la valeur et le nom de l'émetteur
3. Le bon apparaît dans votre wallet

### Donner un bon

1. Sélectionner un bon dans le wallet
2. Choisir "Donner ce bon"
3. Montrer le QR code au receveur (TTL 30s)
4. Attendre la confirmation

### Recevoir un bon

1. Cliquer sur le bouton scan 📷
2. Scanner le QR code de l'offre
3. Vérification automatique avec P3
4. Afficher la confirmation au donneur

## 🛠️ Configuration avancée

### Clé du marché (K_market)

La clé du marché est distribuée hors ligne par la borne Raspberry Pi :

- QR code imprimé
- Page web locale (http://zen.local/key)
- Bluetooth / NFC

Rotation recommandée: quotidienne

### Relais Nostr

L'application peut se connecter à un relais Nostr pour :

- Publier les P3 des bons créés (kind 30303)
- Synchroniser les P3 des autres commerçants
- Enregistrer les transferts (kind 1)

Configuration dans Paramètres > URL du relais

## 🧪 Tests

```bash
# Tests unitaires
flutter test

# Tests d'intégration
flutter drive --target=test_driver/app.dart
```

## 🐛 Debugging

### Activer les logs

Dans `main.dart`, décommenter :

```dart
debugPrint('Log message');
```

### Inspecter le stockage

```bash
# Android
adb shell
run-as com.example.troczen
cd app_flutter
ls

# iOS
Utiliser Xcode > Window > Devices and Simulators
```

## 📊 Format du QR code

### Structure binaire (113 octets)

| Champ | Taille | Description |
|-------|--------|-------------|
| bon_id | 32 octets | Clé publique du bon |
| p2_cipher | 48 octets | P2 chiffré (AES-GCM) |
| nonce | 12 octets | Nonce AES |
| challenge | 16 octets | Challenge anti-rejeu |
| timestamp | 4 octets | Unix timestamp |
| ttl | 1 octet | Durée de validité (secondes) |

## 🔄 Workflow complet

1. **Émetteur crée le bon**
   - Génère `nsec_bon`, `npub_bon`
   - Découpe en P1, P2, P3
   - Chiffre P3 avec K_market
   - Publie P3 sur Nostr (kind 30303)
   - Stocke P1 et P2 localement

2. **Synchronisation** (quotidienne)
   - Récupère tous les kind 30303 du marché
   - Déchiffre P3 avec K_market
   - Stocke P3 en cache local

3. **Transfert**
   - Donneur chiffre P2 avec `hash(P3)`
   - Génère QR binaire (113 octets)
   - Receveur scanne et déchiffre P2
   - Reconstruit temporairement `nsec_bon` (P2+P3)
   - Vérifie la signature
   - Génère QR ACK
   - Donneur scanne ACK et supprime P2

## 🤝 Contribution

1. Fork le projet
2. Créer une branche (`git checkout -b feature/amelioration`)
3. Commit (`git commit -am 'Ajout fonctionnalité'`)
4. Push (`git push origin feature/amelioration`)
5. Créer une Pull Request

## 📝 Licence

MIT License - Voir le fichier LICENSE

## 🆘 Support

- Issues GitHub: https://github.com/votre-repo/troczen/issues
- Documentation: https://docs.troczen.org
- Email: support@troczen.org

## 🔮 Roadmap

- [ ] Implémentation complète du handshake ACK
- [ ] Intégration Nostr (publication/sync kind 30303)
- [ ] Service de synchronisation automatique
- [ ] Gestion des bons expirés
- [ ] Statistiques et graphiques
- [ ] Export PDF des transactions
- [ ] Support multi-marchés
- [ ] PWA (Progressive Web App)

## 💡 Crédits

- Protocole Nostr: https://github.com/nostr-protocol/nostr
- Spécification TrocZen/ẐEN: [Lien vers le document de spécification]
- Design inspiré par les vignettes Panini

---

**TrocZen** - Le troc local, simple et zen 🌻
