#!/usr/bin/env python3
"""
Module de logging centralisé pour TrocZen API

Ce module fournit une configuration de logging unifiée avec :
- Niveaux de log : DEBUG, INFO, WARNING, ERROR, CRITICAL
- Configuration pour le développement et la production
- Support de fichiers de log en production
- Formatage cohérent des messages
- Intégration avec traceback.format_exc() pour les exceptions

Usage:
    from logger import setup_logging, get_logger
    
    # Configuration initiale (à appeler au démarrage de l'application)
    setup_logging()
    
    # Utilisation dans le code
    logger = get_logger(__name__)
    logger.info("Message d'information")
    logger.error("Message d'erreur", exc_info=True)
"""

import logging
import logging.handlers
import sys
from pathlib import Path
from datetime import datetime
import os


# Niveaux de log personnalisés
class LogLevel:
    DEBUG = logging.DEBUG
    INFO = logging.INFO
    WARNING = logging.WARNING
    ERROR = logging.ERROR
    CRITICAL = logging.CRITICAL


# Configuration par défaut
DEFAULT_LOG_LEVEL = logging.INFO
DEFAULT_LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
DEFAULT_LOG_FORMAT_DETAILED = '%(asctime)s - %(name)s - %(levelname)s - %(message)s\n%(pathname)s:%(lineno)d\n%(exc_info)s'


def setup_logging(
    log_level: str = None,
    log_file: str = None,
    max_file_size: int = 10 * 1024 * 1024,  # 10MB
    backup_count: int = 5,
    console_output: bool = True,
    production_mode: bool = False
) -> logging.Logger:
    """
    Configure le système de logging pour l'application.
    
    Args:
        log_level: Niveau de log (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        log_file: Chemin du fichier de log (si None, pas de fichier de log)
        max_file_size: Taille maximale du fichier de log avant rotation (en octets)
        backup_count: Nombre de fichiers de log à conserver
        console_output: Si True, affiche les logs dans la console
        production_mode: Si True, utilise un format plus compact pour la production
    
    Returns:
        Logger configuré pour l'application
    """
    # Déterminer le niveau de log
    if log_level is None:
        log_level = os.getenv('LOG_LEVEL', 'INFO').upper()
    
    level_map = {
        'DEBUG': logging.DEBUG,
        'INFO': logging.INFO,
        'WARNING': logging.WARNING,
        'ERROR': logging.ERROR,
        'CRITICAL': logging.CRITICAL
    }
    
    level = level_map.get(log_level, logging.INFO)
    
    # Créer le logger racine
    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    
    # Supprimer les handlers existants
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)
    
    # Formateur
    if production_mode:
        formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
    else:
        formatter = logging.Formatter(
            DEFAULT_LOG_FORMAT,
            datefmt='%Y-%m-%d %H:%M:%S'
        )
    
    # Handler console
    if console_output:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(level)
        console_handler.setFormatter(formatter)
        root_logger.addHandler(console_handler)
    
    # Handler fichier (si spécifié)
    if log_file:
        log_path = Path(log_file)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Utiliser RotatingFileHandler pour la rotation des logs
        file_handler = logging.handlers.RotatingFileHandler(
            log_file,
            maxBytes=max_file_size,
            backupCount=backup_count,
            encoding='utf-8'
        )
        file_handler.setLevel(level)
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)
        
        # Log de confirmation
        root_logger.info(f"Logging configuré vers le fichier: {log_file}")
    
    # Log de confirmation
    root_logger.info(f"Logging configuré avec niveau: {log_level}")
    
    return root_logger


def get_logger(name: str) -> logging.Logger:
    """
    Récupère un logger avec le nom spécifié.
    
    Args:
        name: Nom du logger (généralement __name__)
    
    Returns:
        Logger configuré
    """
    return logging.getLogger(name)


def log_exception(logger: logging.Logger, message: str, exc_info: bool = True):
    """
    Log une exception avec le traceback complet.
    
    Args:
        logger: Logger à utiliser
        message: Message à loguer
        exc_info: Si True, inclut le traceback (par défaut: True)
    """
    if exc_info:
        logger.error(message, exc_info=True)
    else:
        logger.error(message)


def create_api_error_response(
    error_message: str,
    error_code: int = 500,
    success: bool = False,
    include_details: bool = False,
    details: dict = None
) -> dict:
    """
    Crée une réponse d'erreur structurée pour les endpoints API.
    
    Args:
        error_message: Message d'erreur à retourner au client
        error_code: Code HTTP d'erreur (par défaut: 500)
        success: Toujours False pour les erreurs
        include_details: Si True, inclut des détails supplémentaires (pour le debug)
        details: Dictionnaire de détails supplémentaires
    
    Returns:
        Dictionnaire structuré pour la réponse JSON
    """
    response = {
        'success': success,
        'error': error_message,
        'code': error_code
    }
    
    # Ajouter des détails supplémentaires si demandé (uniquement en mode debug)
    if include_details and details:
        response['details'] = details
    
    return response


def format_error_for_log(error: Exception) -> str:
    """
    Formate une exception pour le logging avec traceback complet.
    
    Args:
        error: Exception à formater
    
    Returns:
        String formatée avec traceback
    """
    import traceback
    return f"{str(error)}\n{traceback.format_exc()}"


# Logger par défaut pour le module
logger = get_logger(__name__)


# Exemple d'utilisation
if __name__ == '__main__':
    # Configuration de test
    setup_logging(log_level='DEBUG', console_output=True)
    
    # Récupérer un logger
    test_logger = get_logger('test')
    
    # Tester les différents niveaux
    test_logger.debug("Message de debug")
    test_logger.info("Message d'information")
    test_logger.warning("Message d'avertissement")
    test_logger.error("Message d'erreur")
    test_logger.critical("Message critique")
    
    # Tester avec exception
    try:
        1 / 0
    except Exception as e:
        log_exception(test_logger, "Erreur lors du calcul", exc_info=True)
    
    # Tester la création de réponse d'erreur API
    error_response = create_api_error_response(
        error_message="Erreur interne du serveur",
        error_code=500,
        include_details=True,
        details={'trace': 'Trace complète'}
    )
    print(f"\nRéponse d'erreur API: {error_response}")
