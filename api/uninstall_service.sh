#!/bin/bash
# Script de désinstallation du service systemd pour TrocZen API

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

# Variables
SERVICE_NAME="troczen-api"
CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="$SCRIPT_DIR"   # identique à install_service.sh
SYSTEMD_DIR="/etc/systemd/system"
LOG_DIR="/var/log/troczen"

print_info "Désinstallation du service TrocZen API"
echo "=========================================="

# Étape 1: Arrêter le service
print_info "Étape 1: Arrêt du service"
if systemctl is-active --quiet "$SERVICE_NAME"; then
    sudo systemctl stop "$SERVICE_NAME"
    print_success "Service arrêté"
else
    print_info "Service déjà arrêté"
fi

# Étape 2: Désactiver le service au démarrage
print_info "Étape 2: Désactivation du service au démarrage"
if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    sudo systemctl disable "$SERVICE_NAME"
    print_success "Service désactivé"
else
    print_info "Service déjà désactivé"
fi

# Étape 3: Supprimer le fichier de service systemd
print_info "Étape 3: Suppression du fichier de service systemd"
if [ -f "$SYSTEMD_DIR/$SERVICE_NAME.service" ]; then
    sudo rm -f "$SYSTEMD_DIR/$SERVICE_NAME.service"
    sudo systemctl daemon-reload
    print_success "Fichier de service supprimé"
else
    print_info "Fichier de service déjà supprimé"
fi

# Étape 4: Supprimer les fichiers de log
print_info "Étape 4: Suppression des fichiers de log"
if [ -f "$LOG_DIR/$SERVICE_NAME.log" ]; then
    sudo rm -f "$LOG_DIR/$SERVICE_NAME.log"
    print_success "Fichier de log supprimé"
else
    print_info "Fichier de log déjà supprimé"
fi

echo ""
echo "=========================================="
print_success "Désinstallation terminée avec succès!"
echo ""
print_info "Informations:"
echo "  - Service: $SERVICE_NAME"
echo "  - Répertoire API: $API_DIR"
echo "  - Log: $LOG_DIR/$SERVICE_NAME.log"
echo ""
print_info "Pour réinstaller:"
echo "  ./install_service.sh"
echo ""
