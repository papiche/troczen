#!/usr/bin/env python3
"""
TrocZen ORACLE Daemon - Écouteur Stateless

Daemon qui écoute les événements Nostr en temps réel et déclenche
les actions automatiques (émission de credentials 30503).

Architecture stateless: Aucune base de données locale.
Le relai Strfry est la source de vérité.

Kinds écoutés:
- 30502: Attestations de permit (déclenche vérification seuil)

Kinds publiés:
- 30503: Verifiable Credentials (si seuil atteint)
"""

import asyncio
import json
import os
import sys
from pathlib import Path
from datetime import datetime

# Ajouter le répertoire parent au path pour les imports
sys.path.insert(0, str(Path(__file__).parent))

import websockets
from oracle.oracle_service import OracleService

# Import du module de logging centralisé
from logger import setup_logging, get_logger

# Configuration
RELAY_URL = os.getenv('NOSTR_RELAY', 'ws://127.0.0.1:7777')
ORACLE_NSEC_HEX = os.getenv('ORACLE_NSEC_HEX', '')

# Configuration du logging
LOG_FILE = os.getenv('LOG_FILE', None)
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
is_production = os.getenv('PRODUCTION', 'false').lower() == 'true'

# Initialiser le logging
setup_logging(
    log_level=LOG_LEVEL,
    log_file=LOG_FILE,
    console_output=True,
    production_mode=is_production
)

# Logger spécifique pour le daemon
logger = get_logger('nostr_daemon')

async def listen_to_nostr():
    """
    Boucle principale d'écoute du daemon ORACLE.
    
    Écoute uniquement les événements qui déclenchent des actions automatiques:
    - Kind 30502: Attestations → vérifier seuil → émettre 30503 si éligible
    """
    if not ORACLE_NSEC_HEX:
        logger.error("ORACLE_NSEC_HEX non défini dans l'environnement")
        return
    
    oracle = OracleService(RELAY_URL, ORACLE_NSEC_HEX)
    
    retry_count = 0
    max_retries = 10
    retry_delay = 5  # secondes
    
    while retry_count < max_retries:
        try:
            logger.info(f"Connexion au relai Nostr: {RELAY_URL}")
            
            async with websockets.connect(RELAY_URL) as websocket:
                retry_count = 0  # Reset counter on successful connection
                
                # Abonnement aux attestations (Kind 30502)
                # C'est le seul événement qui déclenche une action automatique
                req_msg = ["REQ", "troczen_oracle_daemon", {
                    "kinds": [30502],
                    "limit": 0  # Seulement les nouveaux événements
                }]
                await websocket.send(json.dumps(req_msg))
                logger.info(f"📡 Daemon ORACLE connecté et en écoute sur {RELAY_URL}")
                logger.info("Écoute des attestations (Kind 30502)...")
                
                async for message in websocket:
                    try:
                        data = json.loads(message)
                        
                        if data[0] == "EVENT":
                            event = data[2]
                            subscription_id = data[1]
                            
                            if event.get('kind') == 30502:
                                logger.info(f"📨 Attestation reçue de {event['pubkey'][:16]}...")
                                await oracle.process_attestation(event, websocket)
                                
                        elif data[0] == "EOSE":
                            logger.debug(f"End of stored events for subscription: {data[1]}")
                            
                        elif data[0] == "OK":
                            logger.debug(f"Event published successfully: {data[1]}")
                            
                        elif data[0] == "NOTICE":
                            logger.warning(f"Relay notice: {data[1]}")
                            
                        elif data[0] == "AUTH":
                            logger.debug(f"Auth challenge received: {data[1]}")
                            # TODO: Implémenter NIP-42 si requis
                            
                    except json.JSONDecodeError as e:
                        logger.error(f"Erreur décodage JSON: {e}")
                    except Exception as e:
                        logger.error(f"Erreur traitement message: {e}")
                        
        except websockets.exceptions.ConnectionClosed as e:
            retry_count += 1
            logger.warning(f"Connexion fermée: {e}. Tentative {retry_count}/{max_retries}")
            await asyncio.sleep(retry_delay * retry_count)
            
        except ConnectionRefusedError:
            retry_count += 1
            logger.error(f"Relai inaccessible: {RELAY_URL}. Tentative {retry_count}/{max_retries}")
            await asyncio.sleep(retry_delay * retry_count)
            
        except Exception as e:
            retry_count += 1
            logger.error(f"Erreur inattendue: {e}. Tentative {retry_count}/{max_retries}")
            await asyncio.sleep(retry_delay * retry_count)
    
    logger.error(f"Échec après {max_retries} tentatives. Arrêt du daemon.")


async def main():
    """Point d'entrée principal."""
    logger.info("=" * 60)
    logger.info("TrocZen ORACLE Daemon v1.0")
    logger.info("Architecture Stateless - No Database Required")
    logger.info("=" * 60)
    
    await listen_to_nostr()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Arrêt du daemon demandé par l'utilisateur")
        sys.exit(0)
