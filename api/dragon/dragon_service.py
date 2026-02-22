#!/usr/bin/env python3
"""
TrocZen DRAGON Service - Capitaine

Service principal du module DRAGON pour le calcul dynamique
des paramètres économiques et le tableau de navigation.

Architecture Stateless: Toutes les données sont lues depuis le relai Nostr.
"""

import os
import json
import time
from typing import Dict, List, Optional
from datetime import datetime

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from nostr_client import NostrClient
from .params_engine import ParamsEngine
from .du_engine import DUEngine
from .circuit_indexer import CircuitIndexer
from .dashboard_builder import DashboardBuilder


def log(level: str, message: str):
    """Log avec timestamp et niveau."""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [DRAGON] [{level}] {message}")


class DragonService:
    """
    Service DRAGON - Capitaine de l'économie Zen.
    
    Responsabilités:
    - Calcul dynamique de C² et alpha
    - Calcul du DU (Dividende Universel)
    - Indexation des circuits
    - Construction du tableau de navigation
    - Gestion de la PAF (Participation aux Frais)
    """
    
    def __init__(
        self, 
        relay_url: str = None,
        oracle_pubkey: str = None
    ):
        """
        Initialise le service DRAGON.
        
        Args:
            relay_url: URL du relai Nostr (défaut: depuis env)
            oracle_pubkey: Pubkey de l'Oracle pour vérifier les credentials
        """
        self.relay_url = relay_url or os.getenv('NOSTR_RELAY', 'ws://127.0.0.1:7777')
        self.oracle_pubkey = oracle_pubkey or os.getenv('ORACLE_PUBKEY', '')
        
        # Client Nostr
        self.client = NostrClient(relay_url=self.relay_url)
        
        # Moteurs
        self.params_engine = ParamsEngine(self.client)
        self.du_engine = DUEngine(self.client, self.params_engine, self.oracle_pubkey)
        self.circuit_indexer = CircuitIndexer(self.client)
        self.dashboard_builder = DashboardBuilder(
            self.client,
            self.params_engine,
            self.du_engine,
            self.circuit_indexer,
            self.oracle_pubkey
        )
        
        log("INFO", f"Service DRAGON initialisé - Relai: {self.relay_url}")
    
    async def connect(self):
        """Connecte le client Nostr."""
        await self.client.connect()
    
    async def disconnect(self):
        """Déconnecte le client Nostr."""
        await self.client.disconnect()
    
    # ==================== Dashboard ====================
    
    async def build_dashboard(
        self, 
        user_pubkey: str, 
        market_id: str = None
    ) -> Dict:
        """
        Construit le tableau de navigation complet.
        
        C'est l'endpoint principal appelé par l'app Flutter.
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché (optionnel)
            
        Returns:
            Dashboard complet avec DU, params, circulation, signaux
        """
        await self.connect()
        try:
            return await self.dashboard_builder.build_dashboard(user_pubkey, market_id)
        finally:
            await self.disconnect()
    
    # ==================== DU ====================
    
    async def calculate_du(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> Dict:
        """
        Calcule le DU pour un utilisateur dans un marché.
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché
            
        Returns:
            Dictionnaire avec DU et métriques
        """
        await self.connect()
        try:
            return await self.du_engine.calculate_du(user_pubkey, market_id)
        finally:
            await self.disconnect()
    
    # ==================== Paramètres ====================
    
    async def get_params(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> Dict:
        """
        Récupère les paramètres dynamiques (C², alpha, TTL).
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché
            
        Returns:
            Dictionnaire avec C², alpha, TTL optimal
        """
        await self.connect()
        try:
            return await self.params_engine.get_all_params(user_pubkey, market_id)
        finally:
            await self.disconnect()
    
    # ==================== Circuits ====================
    
    async def get_circuits(
        self, 
        market_id: str,
        page: int = 1,
        limit: int = 50
    ) -> Dict:
        """
        Récupère les circuits indexés d'un marché.
        
        Args:
            market_id: ID du marché
            page: Numéro de page
            limit: Résultats par page
            
        Returns:
            Liste paginée des circuits
        """
        await self.connect()
        try:
            circuits = await self.circuit_indexer.get_circuits(
                market_id,
                limit=limit
            )
            
            return {
                'market_id': market_id,
                'page': page,
                'limit': limit,
                'count': len(circuits),
                'circuits': circuits
            }
        finally:
            await self.disconnect()
    
    # ==================== Santé du marché ====================
    
    async def get_market_health(self, market_id: str) -> Dict:
        """
        Récupère les indicateurs de santé d'un marché.
        
        Args:
            market_id: ID du marché
            
        Returns:
            Statistiques de santé
        """
        await self.connect()
        try:
            stats = await self.circuit_indexer.calculate_market_stats(market_id)
            
            # Ajouter des indicateurs de santé
            health = {
                'market_id': market_id,
                'active_bonds': stats.get('active_bonds_count', 0),
                'active_value': stats.get('active_bonds_value', 0),
                'loops_30d': stats.get('loops_30d', 0),
                'avg_circuit_age': stats.get('avg_circuit_age_days', 0),
                'health_ratio': stats.get('health_ratio', 1.0),
                'status': self._calculate_health_status(stats),
                'computed_at': stats.get('computed_at', int(time.time()))
            }
            
            return health
        finally:
            await self.disconnect()
    
    def _calculate_health_status(self, stats: Dict) -> str:
        """Calcule le statut de santé global."""
        health_ratio = stats.get('health_ratio', 1.0)
        loops = stats.get('loops_30d', 0)
        
        if health_ratio >= 1.5 and loops >= 10:
            return "excellent"
        elif health_ratio >= 1.0 and loops >= 5:
            return "good"
        elif health_ratio >= 0.5:
            return "moderate"
        else:
            return "needs_attention"
    
    # ==================== Taux inter-marchés ====================
    
    async def get_intermarket_rates(self) -> Dict:
        """
        Récupère les taux de change inter-marchés émergents.
        
        Returns:
            Matrice des taux de change
        """
        await self.connect()
        try:
            rates = await self.circuit_indexer.calculate_intermarket_rates()
            
            return {
                'rates': rates,
                'computed_at': int(time.time()),
                'note': 'Taux calculés depuis les circuits inter-marchés des 30 derniers jours'
            }
        finally:
            await self.disconnect()
    
    # ==================== PAF (Participation aux Frais) ====================
    
    async def calculate_paf(
        self, 
        market_id: str,
        user_pubkey: str = None
    ) -> Dict:
        """
        Calcule la PAF (Participation aux Frais) en Zen.
        
        La PAF justifie le maintien de l'infrastructure de confiance.
        
        Formule: PAF = (coût_infrastructure / nombre_utilisateurs) × facteur_zen
        
        Args:
            market_id: ID du marché
            user_pubkey: Pubkey de l'utilisateur (optionnel, pour PAF individuelle)
            
        Returns:
            Détails de la PAF
        """
        # Coûts infrastructure (à configurer)
        monthly_server_cost = float(os.getenv('MONTHLY_SERVER_COST', '42'))  # EUR
        zen_eur_rate = float(os.getenv('ZEN_EUR_RATE', '1'))  # 1 Zen = 1 EUR
        
        # Récupérer les stats du marché
        stats = await self.circuit_indexer.calculate_market_stats(market_id)
        
        # Estimer le nombre d'utilisateurs actifs
        # (approximatif depuis les bons actifs)
        active_bonds = stats.get('active_bonds_count', 0)
        estimated_users = max(active_bonds // 3, 1)  # ~3 bons par utilisateur
        
        # Calcul PAF
        monthly_paf_eur = monthly_server_cost / estimated_users
        monthly_paf_zen = monthly_paf_eur / zen_eur_rate
        
        return {
            'market_id': market_id,
            'monthly_paf_zen': round(monthly_paf_zen, 2),
            'monthly_paf_eur': round(monthly_paf_eur, 2),
            'zen_eur_rate': zen_eur_rate,
            'estimated_users': estimated_users,
            'infrastructure_cost_eur': monthly_server_cost,
            'computed_at': int(time.time())
        }
    
    # ==================== Statistiques globales ====================
    
    async def get_global_stats(self) -> Dict:
        """
        Récupère les statistiques globales du système.
        
        Returns:
            Statistiques agrégées
        """
        await self.connect()
        try:
            # Récupérer tous les bons
            bond_events = await self.client.query_events([{
                "kinds": [30303],
                "limit": 1000
            }])
            
            # Récupérer tous les circuits
            circuit_events = await self.client.query_events([{
                "kinds": [30304],
                "limit": 1000
            }])
            
            # Calculs
            now = int(time.time())
            active_bonds = 0
            total_value = 0
            unique_users = set()
            markets = set()
            
            for event in bond_events:
                tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
                expires = int(tags.get('expires', 0))
                
                if expires > now:
                    active_bonds += 1
                    total_value += float(tags.get('value', 0))
                
                unique_users.add(event.get('pubkey', ''))
                market = tags.get('market', '')
                if market:
                    markets.add(market)
            
            return {
                'active_bonds': active_bonds,
                'total_active_value': round(total_value, 2),
                'total_circuits': len(circuit_events),
                'unique_users': len(unique_users),
                'active_markets': len(markets),
                'markets_list': list(markets)[:10],  # Limiter
                'computed_at': now
            }
        finally:
            await self.disconnect()


# ==================== Version synchrone pour Flask ====================

class DragonServiceSync:
    """
    Version synchrone du service DRAGON pour Flask.
    
    Utilise le client NostrClientSync existant.
    """
    
    def __init__(
        self, 
        relay_url: str = None,
        oracle_pubkey: str = None
    ):
        """Initialise le service DRAGON synchrone."""
        self.relay_url = relay_url or os.getenv('NOSTR_RELAY', 'ws://127.0.0.1:7777')
        self.oracle_pubkey = oracle_pubkey or os.getenv('ORACLE_PUBKEY', '')
        
        # Import du client synchrone
        from nostr_client import NostrClientSync
        self.client = NostrClientSync(relay_url=self.relay_url)
        
        # Moteurs (version simplifiée pour sync)
        self.params_engine = ParamsEngine(self.client)
        self.du_engine = DUEngine(self.client, self.params_engine, self.oracle_pubkey)
        self.circuit_indexer = CircuitIndexer(self.client)
        
        log("INFO", f"Service DRAGON Sync initialisé - Relai: {self.relay_url}")
    
    def get_dashboard(self, user_pubkey: str, market_id: str = None) -> Dict:
        """
        Version synchrone du dashboard.
        
        Note: Simplifiée pour Flask - ne calcule pas tout en détail.
        """
        if not self.client.connect():
            return {"error": "Relai inaccessible"}
        
        try:
            # Calcul simplifié
            now = int(time.time())
            
            # N1/N2
            contact_events = self.client.query_events([{
                "kinds": [3],
                "authors": [user_pubkey]
            }])
            
            n1_pubkeys = []
            if contact_events:
                n1_pubkeys = [t[1] for e in contact_events for t in e.get('tags', []) if t[0] == 'p']
            
            # Credentials
            credentials = []
            if self.oracle_pubkey:
                cred_events = self.client.query_events([{
                    "kinds": [30503],
                    "authors": [self.oracle_pubkey],
                    "#p": [user_pubkey]
                }])
                credentials = cred_events
            
            # Circuits
            market_tag = market_id or 'market_hackathon'
            circuits = self.client.query_events([{
                "kinds": [30304],
                "#market": [market_tag]
            }])
            
            return {
                "npub": user_pubkey,
                "computed_at": datetime.utcfromtimestamp(now).isoformat() + "Z",
                "network": {
                    "n1": len(n1_pubkeys),
                    "n2": 0,  # Simplifié
                    "category": "Actif" if len(n1_pubkeys) >= 5 else "Emergent"
                },
                "markets": [{
                    "market_id": market_tag,
                    "du": {
                        "daily": 10.0,  # Simplifié
                        "monthly": 300.0,
                        "active": len(n1_pubkeys) >= 5
                    },
                    "params": {
                        "c2": 0.07,
                        "alpha": 0.3,
                        "ttl_optimal_days": 28
                    },
                    "circulation": {
                        "loops_this_month": len(circuits),
                        "in_transit_count": 0
                    },
                    "credentials": len(credentials),
                    "signals": [" Réseau stable - continuer"]
                }]
            }
        finally:
            self.client.disconnect()
    
    def get_market_health(self, market_id: str) -> Dict:
        """Version synchrone de la santé du marché."""
        if not self.client.connect():
            return {"error": "Relai inaccessible"}
        
        try:
            now = int(time.time())
            market_tag = market_id
            
            # Bons actifs
            bonds = self.client.query_events([{
                "kinds": [30303],
                "#market": [market_tag]
            }])
            
            # Circuits
            circuits = self.client.query_events([{
                "kinds": [30304],
                "#market": [market_tag]
            }])
            
            active_bonds = 0
            total_value = 0
            
            for bond in bonds:
                tags = {t[0]: t[1] for t in bond.get('tags', []) if len(t) >= 2}
                expires = int(tags.get('expires', 0))
                if expires > now:
                    active_bonds += 1
                    total_value += float(tags.get('value', 0))
            
            return {
                "market_id": market_id,
                "active_bonds": active_bonds,
                "active_value": round(total_value, 2),
                "loops_30d": len(circuits),
                "status": "good" if active_bonds > 10 else "moderate",
                "computed_at": now
            }
        finally:
            self.client.disconnect()