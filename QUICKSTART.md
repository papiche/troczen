# Guide de Démarrage Rapide - TrocZen

**Retour à la [Documentation Principale](README.md)** | [Index des Fichiers](FILE_INDEX.md) | [Architecture Technique](ARCHITECTURE.md)

## 🚀 Installation en 5 minutes

> 📄 Ce guide suppose que vous avez déjà lu le [README principal](README.md).
> 🛠️ Pour une installation complète avec toutes les options, consultez le [Résumé du Projet](PROJECT_SUMMARY.md).

### 1. Vérifier Flutter

```bash
flutter doctor
```

Si Flutter n'est pas installé : https://docs.flutter.dev/get-started/install

### 2. Cloner et installer

```bash
cd troczen
flutter pub get
```

> ⚠️ Note : Le fichier `build.sh` mentionné dans certaines documentations n'existe pas. Utilisez directement les commandes Flutter ci-dessus.

### 3. Lancer sur Android

```bash
flutter run
```

### 4. Construire l'APK

```bash
flutter build apk --release
```

L'APK se trouve dans : `build/app/outputs/flutter-apk/app-release.apk`

## 📱 Test rapide sur émulateur

### Android Studio

1. Ouvrir Android Studio
2. AVD Manager → Create Virtual Device
3. Choisir Pixel 4 (ou similaire)
4. API Level 30 (Android 11)
5. Start

```bash
flutter run
```

### VS Code

1. Installer l'extension Flutter
2. F5 ou Run → Start Debugging

## 🔧 Configuration minimale pour tester

### 1. Première connexion

- Login : `demo`
- Password : `password123`
- Nom : `Testeur`

### 2. Configuration marché

Dans Paramètres (⚙️) :

- Nom du marché : `marche-test`
- K_market : `0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef`
- URL relais : (laisser vide pour l'instant)

### 3. Créer un bon

- Valeur : `5`
- Émetteur : `Rucher de Jean`

## 🧪 Scénario de test complet

### Avec 2 téléphones (ou 2 émulateurs)

**Téléphone A (émetteur)**
1. Créer compte : alice / password123
2. Configurer marché avec la même K_market
3. Créer bon de 5 ẐEN

**Téléphone B (receveur)**
1. Créer compte : bob / password123  
2. Configurer marché (même K_market)

**Transfert**
1. A : Sélectionner le bon → "Donner"
2. B : Scanner le QR
3. Vérifier que le bon apparaît chez B

## 🐛 Problèmes courants

### "Camera permission denied"

```bash
# Android
adb shell pm grant com.example.troczen android.permission.CAMERA
```

### "Gradle build failed"

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

### "No devices found"

```bash
# Vérifier les appareils connectés
flutter devices

# Démarrer un émulateur
flutter emulators
flutter emulators --launch <emulator_id>
```

### Problèmes de certificat (iOS)

1. Ouvrir `ios/Runner.xcworkspace` dans Xcode
2. Signing & Capabilities
3. Choisir votre équipe de développement

## 📊 État du MVP

### ✅ Fonctionnel
- [x] Génération identité Nostr
- [x] Création de bons
- [x] Découpage SSSS (P1/P2/P3)
- [x] Chiffrement P2 et P3
- [x] Format QR binaire compact
- [x] Interface wallet (cartes Panini)
- [x] Configuration marché (K_market)
- [x] Stockage sécurisé

### 🚧 En cours / À compléter
- [ ] Scan et validation complète
- [ ] Handshake ACK (double scan)
- [ ] Publication Nostr kind 30303
- [ ] Synchronisation P3 depuis relais
- [ ] Reconstruction temporaire nsec_bon
- [ ] Gestion des bons expirés
- [ ] Tests unitaires

### 🔮 Prochaines étapes
1. Implémenter le service Nostr
2. Compléter le handshake atomique
3. Ajouter la synchronisation automatique
4. Tests terrain sur un vrai marché

## 📞 Support

Si vous rencontrez des problèmes :

1. Consulter le README.md principal
2. Vérifier les issues GitHub
3. Créer une nouvelle issue avec :
   - Version Flutter (`flutter --version`)
   - Système d'exploitation
   - Message d'erreur complet
   - Étapes pour reproduire

## 🎯 Objectif MVP

Permettre à 2 personnes de :
1. Créer un compte
2. Configurer le même marché
3. Créer un bon
4. Le transférer de main à main (scan QR)
5. Vérifier que la double dépense est impossible

---

**Bon développement ! 🚀**
