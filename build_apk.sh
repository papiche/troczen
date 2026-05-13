#!/bin/bash
set -e

# Build APK and deploy to IPFS
# Exécute depuis la racine du projet Flutter
#
# Usage: ./build_apk.sh [OPTIONS]
# Options:
#   -p, --push    Commit et push vers Git après le build
#   -d, --debug   Compile l'APK en mode debug
#   -h, --help    Affiche cette aide

# ============================================
# Parse arguments
# ============================================
PUSH_TO_GIT=false
DEBUG_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--push)
            PUSH_TO_GIT=true
            shift
            ;;
        -d|--debug)
            DEBUG_MODE=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./build_apk.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -p, --push    Commit et push vers Git après le build"
            echo "  -d, --debug   Compile l'APK en mode debug"
            echo "  -h, --help    Affiche cette aide"
            echo ""
            echo "Exemples:"
            echo "  ./build_apk.sh           # Build release uniquement"
            echo "  ./build_apk.sh --debug   # Build debug uniquement"
            echo "  ./build_apk.sh --push    # Build release + commit + push Git"
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
IPFS_FALLBACK_GATEWAYS="ipfs.paratge.copylaradio.com ipfs.guenoel.fr"

# ============================================
# Constellation UPLANET — lecture de ~/.ipfs/swarm.key
# ============================================
SWARM_KEY_FILE="$HOME/.ipfs/swarm.key"
DART_DEFINES=""

# Nom d'affichage (override via env: APP_DISPLAY_NAME=MonApp ./build_apk.sh)
_APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-}"

if [ -f "$SWARM_KEY_FILE" ]; then
    # Format swarm.key : ligne 1 = /key/swarm/psk/1.0.0/
    #                    ligne 2 = /base16/
    #                    ligne 3 = <hex64>
    UPLANET_KEY=$(sed -n '3p' "$SWARM_KEY_FILE" | tr -d '[:space:]')
    if [ ${#UPLANET_KEY} -eq 64 ]; then
        DART_DEFINES="--dart-define=UPLANET_KEY=$UPLANET_KEY"
        echo "🔑 Constellation: swarm.key détectée (${UPLANET_KEY:0:8}...${UPLANET_KEY:56:8})"
    else
        echo "⚠️  swarm.key malformée, clé ORIGIN par défaut"
    fi
else
    echo "ℹ️  ~/.ipfs/swarm.key absente — clé ORIGIN (0xFFFF...) par défaut"
fi

if [ -n "$_APP_DISPLAY_NAME" ]; then
    DART_DEFINES="$DART_DEFINES --dart-define=APP_DISPLAY_NAME=$_APP_DISPLAY_NAME"
    echo "🏷️  App name: $_APP_DISPLAY_NAME"
fi

# ============================================
# Nettoyage et Build
# ============================================
echo "🔧 Nettoyage du projet Flutter..."
cd troczen && flutter clean

# Extraire la version depuis pubspec.yaml
VERSION=$(grep "^version:" pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)

# Préfixe APK (utilise APP_DISPLAY_NAME en minuscules si défini)
APK_PREFIX=$(echo "${_APP_DISPLAY_NAME:-troczen}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

if [ "$DEBUG_MODE" = true ]; then
    echo "📦 Build de l'APK debug..."
    # shellcheck disable=SC2086
    flutter build apk --debug $DART_DEFINES

    # Chemin du APK généré
    APK_SRC="build/app/outputs/flutter-apk/app-debug.apk"

    # Nom de l'APK avec le préfixe et la version
    APK_NAME="$APK_PREFIX-$VERSION-debug.apk"
else
    echo "📦 Build de l'APK release..."
    # shellcheck disable=SC2086
    flutter build apk --release $DART_DEFINES

    # Chemin du APK généré
    APK_SRC="build/app/outputs/flutter-apk/app-release.apk"

    # Nom de l'APK avec le préfixe et la version
    APK_NAME="$APK_PREFIX-$VERSION.apk"
fi

# Dossier de destination dans l'API
DEST_DIR="../api/apks"

# Créer le dossier s'il n'existe pas
mkdir -p "$DEST_DIR"

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
    echo "   Installez Astroport: https://docs.ipfs.tech/install/"
    exit 0
fi

# Ajouter l'APK à IPFS avec wrapping (-w)
IPFS_OUTPUT=$(ipfs add -w "$DEST_DIR/$APK_NAME" -Q)
IPFS_CID=$(echo "$IPFS_OUTPUT" | tail -1)

echo "✅ APK ajouté à IPFS"
echo "   CID: $IPFS_CID"
echo "   Lien: https://$IPFS_GATEWAY/ipfs/$IPFS_CID/$APK_NAME"

# ============================================
# Nettoyage des anciens CIDs TrocZen
# ============================================
# Lire l'ancien CID depuis ipfs_meta.json s'il existe
META_FILE="$DEST_DIR/ipfs_meta.json"
if [ -f "$META_FILE" ]; then
    # Extraire tous les anciens CIDs du fichier JSON
    OLD_CIDS=$(grep -o '"cid": "[^"]*"' "$META_FILE" | cut -d'"' -f4)
    
    if [ -n "$OLD_CIDS" ]; then
        echo ""
        echo "🧹 Nettoyage des anciens CIDs TrocZen..."
        
        for old_cid in $OLD_CIDS; do
            # Ne pas unpin le nouveau CID (cas de rebuild même version)
            if [ "$old_cid" != "$IPFS_CID" ]; then
                echo "   Unpin: $old_cid"
                ipfs pin rm "$old_cid" 2>/dev/null || true
            fi
        done
        
        # Exécuter le garbage collector pour libérer l'espace
        echo "   Garbage collection..."
        echo " Lancez .... ipfs repo gc"
        echo "✅ Anciens CIDs supprimés et espace libéré"
    fi
fi

# ============================================
# Mise à jour des templates
# ============================================
echo ""
echo "📝 Mise à jour des templates..."

# Retour à la racine du projet
cd ..

# Chemin absolu depuis la racine du projet
DEST_DIR="api/apks"

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

# Mise à jour du fichier ipfs_meta.json pour l'API
APK_SIZE=$(stat -c%s "$DEST_DIR/$APK_NAME" 2>/dev/null || stat -f%z "$DEST_DIR/$APK_NAME" 2>/dev/null)
APK_CHECKSUM=$(sha256sum "$DEST_DIR/$APK_NAME" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$DEST_DIR/$APK_NAME" 2>/dev/null | cut -d' ' -f1)
UPLOAD_DATE=$(date -Iseconds)

# Créer ou mettre à jour le fichier ipfs_meta.json
META_FILE="$DEST_DIR/ipfs_meta.json"
if [ -f "$META_FILE" ]; then
    # Charger les métadonnées existantes
    EXISTING_META=$(cat "$META_FILE")
else
    EXISTING_META='{"apks":{}}'
fi

# Utiliser jq pour mettre à jour le JSON (ou Python si jq non disponible)
if command -v jq &> /dev/null; then
    echo "$EXISTING_META" | jq --arg name "$APK_NAME" \
        --arg cid "$IPFS_CID" \
        --arg size "$APK_SIZE" \
        --arg checksum "$APK_CHECKSUM" \
        --arg date "$UPLOAD_DATE" \
        --arg version "$VERSION" \
        '.apks[$name] = {"cid": $cid, "size": ($size | tonumber), "checksum": $checksum, "uploaded_at": $date, "version": $version}' > "$META_FILE"
elif command -v python3 &> /dev/null; then
    python3 << PYEOF
import json
import sys

existing = json.loads('''$EXISTING_META''')
existing.setdefault('apks', {})
existing['apks']['$APK_NAME'] = {
    'cid': '$IPFS_CID',
    'size': $APK_SIZE,
    'checksum': '$APK_CHECKSUM',
    'uploaded_at': '$UPLOAD_DATE',
    'version': '$VERSION'
}
with open('$META_FILE', 'w') as f:
    json.dump(existing, f, indent=2)
PYEOF
else
    # Fallback: créer un fichier simple sans dépendances
    cat > "$META_FILE" << METAEOF
{
  "apks": {
    "$APK_NAME": {
      "cid": "$IPFS_CID",
      "size": $APK_SIZE,
      "checksum": "$APK_CHECKSUM",
      "uploaded_at": "$UPLOAD_DATE",
      "version": "$VERSION"
    }
  }
}
METAEOF
fi

echo "✅ Templates mis à jour"
echo "   - $DEST_DIR/README.md"
echo "   - $DEST_DIR/index.html"
echo "   - $DEST_DIR/ipfs_meta.json"

# ============================================
# Commit et push Git (optionnel)
# ============================================
if [ "$PUSH_TO_GIT" = true ]; then
    echo ""
    echo "📤 Mise à jour du dépôt Git..."

    # Ajouter les fichiers modifiés (pas les APK, ils sont dans .gitignore)
    git add "$DEST_DIR/README.md" "$DEST_DIR/index.html" "$DEST_DIR/ipfs_meta.json"

    # Vérifier s'il y a des changements à committer
    if git diff --cached --quiet; then
        echo "ℹ️  Aucun changement à committer"
    else
        git commit -m "Mise à jour APK (https://$IPFS_GATEWAY/ipfs/$IPFS_CID/$APK_NAME)"
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
