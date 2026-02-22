"""
TrocZen DRAGON Module - Capitaine

Système de calcul dynamique pour l'économie Zen.
Architecture Stateless - Interroge le relai Nostr à la volée.

Kinds gérés:
- 30303: Bons  Zen (indexation)
- 30304: Circuits fermés (métriques)
- 3: Contact List (graphe social N1/N2)

Calculs:
- C²: Vitesse de retour / santé du réseau
- alpha: Multiplicateur compétence
- DU: Dividende Universel
"""

from .dragon_service import DragonService
from .params_engine import ParamsEngine
from .du_engine import DUEngine
from .circuit_indexer import CircuitIndexer
from .dashboard_builder import DashboardBuilder

__all__ = [
    'DragonService', 
    'ParamsEngine', 
    'DUEngine', 
    'CircuitIndexer',
    'DashboardBuilder'
]