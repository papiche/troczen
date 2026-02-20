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
# Copier l'APK dans les assets pour le partage P2P
# ============================================
ASSETS_DIR="assets/apk"

# Créer le dossier assets/apk s'il n'existe pas
mkdir -p "$ASSETS_DIR"

# Copier l'APK pour le partage P2P (nom fixe pour le service de partage)
cp "$APK_SRC" "$ASSETS_DIR/troczen.apk"

echo "✅ APK copié dans $ASSETS_DIR/troczen.apk pour le partage P2P"
echo ""
echo "📱 Pour activer le partage P2P:"
echo "   1. Reconstruisez l'APK avec ce script"
echo "   2. L'APK sera inclus dans les assets de l'application"
echo "   3. Utilisez 'Partager l\'application' dans les paramètres"
