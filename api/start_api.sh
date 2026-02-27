#!/bin/bash
# Script de démarrage pour l'API TrocZen
# Ce script configure l'environnement et lance le service

set -e

# Déterminer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Définir le répertoire de l'API (parent du script)
API_DIR="$(dirname "$SCRIPT_DIR")"

# Charger les variables d'environnement depuis .env si le fichier existe
if [ -f ".env" ]; then
    echo "Chargement des variables d'environnement depuis .env..."
    export $(grep -v '^#' .env | xargs)
else
    echo "⚠️  Fichier .env non trouvé. Utilisation des variables d'environnement système."
fi

# Vérifier si Python est disponible
if ! command -v python3 &> /dev/null; then
    echo "❌ Erreur: python3 n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

# Vérifier si pip est disponible
if ! command -v pip3 &> /dev/null; then
    echo "❌ Erreur: pip3 n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

# Vérifier si l'environnement virtuel existe
VENV_DIR="$API_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "Création de l'environnement virtuel..."
    python3 -m venv "$VENV_DIR"
    
    # Activer l'environnement virtuel
    source "$VENV_DIR/bin/activate"
    
    # Installer les dépendances
    echo "Installation des dépendances Python..."
    pip3 install -r requirements.txt
    
    echo "✅ Environnement virtuel créé et dépendances installées"
else
    echo "Environnement virtuel détecté..."
    source "$VENV_DIR/bin/activate"
fi

# Vérifier si les dossiers nécessaires existent
echo "Vérification des dossiers nécessaires..."
mkdir -p "$API_DIR/uploads" "$API_DIR/apks" "$API_DIR/profiles" "$API_DIR/static" "$API_DIR/templates"

# Définir le mode de fonctionnement
MODE="${1:-production}"
echo "Mode de fonctionnement: $MODE"

# Définir le port
PORT="${PORT:-5000}"
HOST="${HOST:-0.0.0.0}"

# Définir le nombre de workers pour gunicorn
WORKERS="${WORKERS:-4}"
THREADS="${THREADS:-2}"

# Définir le timeout
TIMEOUT="${TIMEOUT:-120}"

# Définir le niveau de log
LOG_LEVEL="${LOG_LEVEL:-info}"

# Définir le fichier de log
LOG_FILE="${LOG_FILE:-/var/log/troczen/api.log}"

# Créer le dossier de log si nécessaire
if [ ! -z "$LOG_FILE" ]; then
    LOG_DIR=$(dirname "$LOG_FILE")
    # Essayer de créer le dossier, mais ne pas échouer si on n'a pas les permissions
    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        touch "$LOG_FILE" 2>/dev/null && chmod 644 "$LOG_FILE" 2>/dev/null || true
    else
        # Fallback vers un dossier local
        LOG_DIR="$API_DIR/logs"
        mkdir -p "$LOG_DIR"
        LOG_FILE="$LOG_DIR/api.log"
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
        echo "⚠️  Impossible de créer $LOG_DIR, utilisation de $LOG_DIR"
    fi
fi

# Fonction pour lancer l'API en mode développement
start_development() {
    echo "🚀 Démarrage de l'API en mode développement..."
    echo "   URL: http://$HOST:$PORT"
    echo "   Debug: $FLASK_DEBUG"
    echo ""
    
    # Lancer Flask en mode développement
    python3 "$API_DIR/api_backend.py"
}

# Fonction pour lancer l'API en mode production avec gunicorn
start_production() {
    echo "🚀 Démarrage de l'API en mode production..."
    echo "   URL: http://$HOST:$PORT"
    echo "   Workers: $WORKERS"
    echo "   Threads: $THREADS"
    echo "   Timeout: $TIMEOUT"
    echo "   Log: $LOG_FILE"
    echo ""
    
    # Lancer gunicorn
    gunicorn \
        --bind "$HOST:$PORT" \
        --workers "$WORKERS" \
        --threads "$THREADS" \
        --timeout "$TIMEOUT" \
        --log-level "$LOG_LEVEL" \
        --access-logfile "$LOG_FILE" \
        --error-logfile "$LOG_FILE" \
        --capture-output \
        --enable-stdio-inheritance \
        "$API_DIR/api_backend:app"
}

# Fonction pour vérifier si le service est déjà en cours d'exécution
check_running() {
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        echo "⚠️  Un service est déjà en cours d'exécution sur le port $PORT"
        echo "   PID: $(lsof -Pi :$PORT -sTCP:LISTEN -t)"
        return 1
    fi
    return 0
}

# Fonction pour arrêter le service
stop_service() {
    echo "Arrêt du service sur le port $PORT..."
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        PID=$(lsof -Pi :$PORT -sTCP:LISTEN -t)
        kill $PID
        echo "✅ Service arrêté (PID: $PID)"
    else
        echo "ℹ️  Aucun service en cours d'exécution sur le port $PORT"
    fi
}

# Fonction pour afficher l'aide
show_help() {
    echo "Usage: $0 [MODE] [OPTIONS]"
    echo ""
    echo "Modes:"
    echo "  production    Lancer avec gunicorn (mode production, défaut)"
    echo "  development   Lancer avec Flask (mode développement)"
    echo "  stop          Arrêter le service"
    echo "  restart       Redémarrer le service"
    echo "  status        Vérifier le statut du service"
    echo "  help          Afficher cette aide"
    echo ""
    echo "Variables d'environnement:"
    echo "  PORT          Port d'écoute (défaut: 5000)"
    echo "  HOST          Interface d'écoute (défaut: 0.0.0.0)"
    echo "  WORKERS       Nombre de workers gunicorn (défaut: 4)"
    echo "  THREADS       Nombre de threads par worker (défaut: 2)"
    echo "  TIMEOUT       Timeout en secondes (défaut: 120)"
    echo "  LOG_LEVEL     Niveau de log (debug, info, warning, error)"
    echo "  LOG_FILE      Chemin du fichier de log"
    echo ""
    echo "Exemples:"
    echo "  $0 development"
    echo "  $0 production"
    echo "  PORT=8080 $0 production"
    echo "  $0 stop"
}

# Gestion des commandes
case "$MODE" in
    development|dev)
        start_development
        ;;
    production|prod)
        if check_running; then
            start_production
        else
            echo "❌ Impossible de démarrer, un service est déjà en cours d'exécution"
            exit 1
        fi
        ;;
    stop)
        stop_service
        ;;
    restart)
        stop_service
        sleep 2
        if check_running; then
            start_production
        else
            echo "❌ Impossible de redémarrer, un service est toujours en cours d'exécution"
            exit 1
        fi
        ;;
    status)
        if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1 ; then
            PID=$(lsof -Pi :$PORT -sTCP:LISTEN -t)
            echo "✅ Service en cours d'exécution sur le port $PORT (PID: $PID)"
            exit 0
        else
            echo "❌ Service arrêté sur le port $PORT"
            exit 1
        fi
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "❌ Mode inconnu: $MODE"
        echo ""
        show_help
        exit 1
        ;;
esac
