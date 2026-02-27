#!/bin/bash
# Script d'installation du service systemd pour TrocZen API

set -e

##################################################################  SUDO
##  Lancement "root" interdit...
########################################################################
[ $(id -u) -eq 0 ] && echo "LANCEMENT root INTERDIT. " && exit 1
[[ ! $(groups | grep -w sudo) ]] \
    && echo "AUCUN GROUPE \"sudo\" : su -; usermod -aG sudo $USER" \
    && su - && apt-get install sudo -y \
    && echo "Run Install Again..." && exit 0

# Couleurs pour la sortie
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonctions de couleur
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Vérifier si on est root
if [ "$EUID" -ne 0 ]; then
    print_error "Ce script doit être exécuté en tant que root (sudo)"
    exit 1
fi

# Variables
SERVICE_NAME="troczen-api"
CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="$SCRIPT_DIR"
SYSTEMD_DIR="/etc/systemd/system"
LOG_DIR="/var/log/troczen"

print_info "Installation du service TrocZen API"
echo "=========================================="

# Étape 1: Créer les répertoires
print_info "Étape 1: Création des répertoires"
mkdir -p "$API_DIR"
mkdir -p "$LOG_DIR"
print_success "Répertoires créés"

# Étape 2: Configurer les permissions
print_info "Étape 2: Configuration des permissions"
chown -R "$CURRENT_USER:$CURRENT_USER" "$API_DIR"
chmod -R 755 "$API_DIR"
chmod 755 "$API_DIR/start_api.sh"
chmod 644 "$API_DIR/troczen-api.service"
chmod 644 "$LOG_DIR" 2>/dev/null || true
print_success "Permissions configurées"

# Étape 3: Créer le fichier .env si nécessaire
print_info "Étape 3: Configuration de l'environnement"
if [ ! -f "$API_DIR/.env" ]; then
    print_warning "Fichier .env non trouvé, copie de .env.example"
    cp "$API_DIR/.env.example" "$API_DIR/.env"
    chown "$CURRENT_USER:$CURRENT_USER" "$API_DIR/.env"
    chmod 600 "$API_DIR/.env"
    print_success "Fichier .env créé (à personnaliser)"
else
    print_info "Fichier .env déjà présent"
fi

# Étape 4: Installer le service systemd
print_info "Étape 4: Installation du service systemd"
sudo cp "$API_DIR/troczen-api.service" "$SYSTEMD_DIR/"
sudo sed -i "s~_APIDIR_~$API_DIR~g" "$SYSTEMD_DIR/troczen-api.service"
sudo sed -i "s~%i~$CURRENT_USER~g" "$SYSTEMD_DIR/troczen-api.service"
sudo sed -i "s~%h_~$HOME~g" "$SYSTEMD_DIR/troczen-api.service"

sudo systemctl daemon-reload
print_success "Service systemd installé"

# Étape 5: Activer le service au démarrage
print_info "Étape 5: Activation du service au démarrage"
sudo systemctl enable "$SERVICE_NAME"
print_success "Service activé au démarrage"

# Étape 6: Afficher les informations de configuration
echo ""
echo "=========================================="
print_success "Installation terminée avec succès!"
echo ""
print_info "Informations de configuration:"
echo "  - Service: $SERVICE_NAME"
echo "  - Utilisateur: $CURRENT_USER"
echo "  - Répertoire: $API_DIR"
echo "  - Log: $LOG_DIR/$SERVICE_NAME.log"
echo ""
print_info "Note: Le service utilisera le chemin dynamique:"
echo "  - WorkingDirectory: $API_DIR"
echo "  - EnvironmentFile: $API_DIR/.env"
echo "  - ExecStart: $API_DIR/start_api.sh production"
echo ""
print_info "Commandes utiles:"
echo "  - Démarrer: systemctl start $SERVICE_NAME"
echo "  - Arrêter: systemctl stop $SERVICE_NAME"
echo "  - Redémarrer: systemctl restart $SERVICE_NAME"
echo "  - Statut: systemctl status $SERVICE_NAME"
echo "  - Logs: journalctl -u $SERVICE_NAME -f"
echo "  - Logs fichier: tail -f $LOG_DIR/$SERVICE_NAME.log"
echo ""
print_warning "IMPORTANT: Personnalisez le fichier $API_DIR/.env avant de démarrer le service"
echo ""
print_info "Pour démarrer le service:"
echo "  sudo systemctl start $SERVICE_NAME"
echo ""
