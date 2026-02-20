#!/bin/bash
set -e

# Build APK and deploy to API folder
# Exécute depuis la racine du projet Flutter

# Nettoyage
cd troczen && flutter clean

# Build release APK
flutter build apk --release

# Chemin du APK généré
APK_SRC="build/app/outputs/flutter-apk/app-release.apk"

# Dossier de destination dans l'API
DEST_DIR="../api/apks"

# Créer le dossier s'il n'existe pas
mkdir -p "$DEST_DIR"

# Extraire la version depuis pubspec.yaml
VERSION=$(grep "^version:" pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)

# Nom de l'APK avec le préfixe troczen et la version
APK_NAME="troczen-$VERSION.apk"

# Copier l'APK avec le bon nom
cp "$APK_SRC" "$DEST_DIR/$APK_NAME"

echo "✅ APK built: $APK_NAME"
echo "✅ Placed in $DEST_DIR/$APK_NAME"
echo "✅ Téléchargeable via /api/apk/download/$APK_NAME"

# ============================================
# Note sur le partage P2P
# ============================================
# L'application utilise désormais une méthode optimisée pour le partage P2P.
# Elle extrait directement son propre APK installé via ApplicationInfo.sourceDir.
# Cela évite de doubler la taille de l'APK en l'incluant dans les assets.
echo "✅ Partage P2P optimisé (extraction native de l'APK installé)"
