#!/bin/bash
# Script de désinstallation du service systemd pour TrocZen API

set -e

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
API_DIR="$(dirname "$SCRIPT_DIR")"
SYSTEMD_DIR="/etc/systemd/system"
LOG_DIR="/var/log/troczen"

print_info "Désinstallation du service TrocZen API"
echo "=========================================="

# Étape 1: Arrêter le service
print_info "Étape 1: Arrêt du service"
if systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl stop "$SERVICE_NAME"
    print_success "Service arrêté"
else
    print_info "Service déjà arrêté"
fi

# Étape 2: Désactiver le service au démarrage
print_info "Étape 2: Désactivation du service au démarrage"
if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    systemctl disable "$SERVICE_NAME"
    print_success "Service désactivé"
else
    print_info "Service déjà désactivé"
fi

# Étape 3: Supprimer le fichier de service systemd
print_info "Étape 3: Suppression du fichier de service systemd"
if [ -f "$SYSTEMD_DIR/$SERVICE_NAME.service" ]; then
    rm -f "$SYSTEMD_DIR/$SERVICE_NAME.service"
    systemctl daemon-reload
    print_success "Fichier de service supprimé"
else
    print_info "Fichier de service déjà supprimé"
fi

# Étape 4: Supprimer les fichiers de log
print_info "Étape 4: Suppression des fichiers de log"
if [ -f "$LOG_DIR/$SERVICE_NAME.log" ]; then
    rm -f "$LOG_DIR/$SERVICE_NAME.log"
    print_success "Fichier de log supprimé"
else
    print_info "Fichier de log déjà supprimé"
fi

# Étape 5: Supprimer les fichiers de l'API (optionnel)
print_info "Étape 5: Suppression des fichiers de l'API"
if [ -d "$API_DIR" ]; then
    echo ""
    read -p "Voulez-vous supprimer les fichiers de l'API ? (o/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Oo]$ ]]; then
        rm -rf "$API_DIR"
        print_success "Fichiers de l'API supprimés"
    else
        print_info "Fichiers de l'API conservés"
    fi
else
    print_info "Fichiers de l'API déjà supprimés"
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
echo "  sudo ./install_service.sh"
echo ""
