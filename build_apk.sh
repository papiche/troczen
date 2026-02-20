#!/bin/bash
set -e

# Build APK and deploy to IPFS
# Exécute depuis la racine du projet Flutter
#
# Usage: ./build_apk.sh [OPTIONS]
# Options:
#   -p, --push    Commit et push vers Git après le build
#   -h, --help    Affiche cette aide

# ============================================
# Parse arguments
# ============================================
PUSH_TO_GIT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--push)
            PUSH_TO_GIT=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./build_apk.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -p, --push    Commit et push vers Git après le build"
            echo "  -h, --help    Affiche cette aide"
            echo ""
            echo "Exemples:"
            echo "  ./build_apk.sh           # Build uniquement"
            echo "  ./build_apk.sh --push    # Build + commit + push Git"
            exit 0
            ;;
        *)
            echo "Option inconnue: $1"
            echo "Utilisez -h ou --help pour voir les options disponibles"
            exit 1
            ;;
    esac
done

# ============================================
# Configuration
# ============================================
IPFS_GATEWAY="ipfs.copylaradio.com"
IPFS_FALLBACK_GATEWAYS="ipfs.io dweb.link cloudflare-ipfs.com"

# ============================================
# Nettoyage et Build
# ============================================
echo "🔧 Nettoyage du projet Flutter..."
cd troczen && flutter clean

echo "📦 Build de l'APK release..."
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

# ============================================
# Upload vers IPFS
# ============================================
echo ""
echo "🚀 Upload vers IPFS..."

# Vérifier qu'IPFS est disponible
if ! command -v ipfs &> /dev/null; then
    echo "⚠️  IPFS non installé. L'APK reste disponible localement."
    echo "   Installez IPFS: https://docs.ipfs.tech/install/"
    exit 0
fi

# Ajouter l'APK à IPFS avec wrapping (-w)
IPFS_OUTPUT=$(ipfs add -w "$DEST_DIR/$APK_NAME" -Q)
IPFS_CID=$(echo "$IPFS_OUTPUT" | tail -1)

echo "✅ APK ajouté à IPFS"
echo "   CID: $IPFS_CID"
echo "   Lien: https://$IPFS_GATEWAY/ipfs/$IPFS_CID/$APK_NAME"

# ============================================
# Mise à jour des templates
# ============================================
echo ""
echo "📝 Mise à jour des templates..."

# Retour à la racine du projet
cd ..

# Mise à jour du README.md
cat > "$DEST_DIR/README.md" << EOF
# Téléchargement des APK TrocZen

Les APK sont hébergés sur IPFS pour un accès décentralisé et résilient.

## Versions disponibles

| Version | Lien IPFS |
|---------|-----------|
| TrocZen $VERSION | [Télécharger](https://$IPFS_GATEWAY/ipfs/$IPFS_CID/$APK_NAME) |

## Comment télécharger

### Via une passerelle IPFS publique
Cliquez simplement sur le lien ci-dessus. La passerelle \`$IPFS_GATEWAY\` servira le fichier.

### Via IPFS en local
Si vous avez un nœud IPFS local :
\`\`\`bash
ipfs get $IPFS_CID/$APK_NAME
\`\`\`

### Via d'autres passerelles
Vous pouvez remplacer \`$IPFS_GATEWAY\` par d'autres passerelles :
- \`ipfs.io\`
- \`dweb.link\`
- \`cloudflare-ipfs.com\`

Exemple : \`https://ipfs.io/ipfs/$IPFS_CID/$APK_NAME\`

## Vérification

Les APK sont signés avec la clé de signature TrocZen. Vérifiez toujours la signature avant installation.

---
*Dernière mise à jour : $(date '+%Y-%m-%d %H:%M:%S')*
EOF

# Mise à jour du index.html
cat > "$DEST_DIR/index.html" << EOF
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Téléchargement TrocZen $VERSION</title>
    <meta http-equiv="refresh" content="0; url=https://$IPFS_GATEWAY/ipfs/$IPFS_CID/$APK_NAME" />
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 2rem;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 16px;
            backdrop-filter: blur(10px);
        }
        h1 { margin-bottom: 1rem; }
        .loader {
            border: 4px solid rgba(255, 255, 255, 0.3);
            border-top: 4px solid white;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 1rem auto;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        a { color: white; text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 TrocZen $VERSION</h1>
        <div class="loader"></div>
        <p>Redirection vers le téléchargement...</p>
        <p><small>Si la redirection ne fonctionne pas, <a href="https://$IPFS_GATEWAY/ipfs/$IPFS_CID/$APK_NAME">cliquez ici</a></small></p>
    </div>
</body>
</html>
EOF

echo "✅ Templates mis à jour"
echo "   - $DEST_DIR/README.md"
echo "   - $DEST_DIR/index.html"

# ============================================
# Commit et push Git (optionnel)
# ============================================
if [ "$PUSH_TO_GIT" = true ]; then
    echo ""
    echo "📤 Mise à jour du dépôt Git..."

    # Ajouter les fichiers modifiés (pas les APK, ils sont dans .gitignore)
    git add "$DEST_DIR/README.md" "$DEST_DIR/index.html"

    # Vérifier s'il y a des changements à committer
    if git diff --cached --quiet; then
        echo "ℹ️  Aucun changement à committer"
    else
        git commit -m "Mise à jour APK $VERSION sur IPFS (CID: $IPFS_CID)"
        echo "✅ Changements commités"
        
        # Push vers origin
        if git remote | grep -q "origin"; then
            git push origin main
            echo "✅ Changements poussés vers origin/main"
        else
            echo "⚠️  Pas de remote 'origin' configuré"
        fi
    fi
fi

# ============================================
# Résumé
# ============================================
echo ""
echo "============================================"
echo "🎉 Build terminé avec succès !"
echo "============================================"
echo "📦 APK: $APK_NAME"
echo "🌐 IPFS CID: $IPFS_CID"
echo "🔗 Téléchargement: https://$IPFS_GATEWAY/ipfs/$IPFS_CID/$APK_NAME"
if [ "$PUSH_TO_GIT" = true ]; then
    echo "📤 Git: commit et push effectués"
fi
echo ""
echo "✅ Partage P2P optimisé (extraction native de l'APK installé)"
