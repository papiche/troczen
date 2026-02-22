#!/usr/bin/env python3
"""
TrocZen Dashboard Builder

Construction du tableau de navigation utilisateur.

Le dashboard agrège toutes les informations:
- Position réseau (N1, N2)
- Paramètres dynamiques (C², alpha, TTL)
- DU calculé
- Circulation (boucles, transit)
- Position relative (percentiles)
- Signaux automatiques

Architecture Stateless: Calcule tout à la volée depuis le relai Nostr.
"""

import json
import time
import math
from typing import Dict, List, Optional
from datetime import datetime


def log(level: str, message: str):
    """Log avec timestamp et niveau."""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [DASHBOARD] [{level}] {message}")


class DashboardBuilder:
    """
    Constructeur de tableaux de navigation.
    
    Génère le dashboard complet pour un utilisateur en agrégeant
    toutes les données depuis le relai Nostr.
    """
    
    def __init__(
        self, 
        nostr_client, 
        params_engine, 
        du_engine, 
        circuit_indexer,
        oracle_pubkey: str = None
    ):
        """
        Initialise le constructeur de dashboard.
        
        Args:
            nostr_client: Client Nostr
            params_engine: Moteur de paramètres (C², alpha)
            du_engine: Moteur de calcul DU
            circuit_indexer: Indexeur de circuits
            oracle_pubkey: Pubkey de l'Oracle pour les credentials
        """
        self.client = nostr_client
        self.params_engine = params_engine
        self.du_engine = du_engine
        self.circuit_indexer = circuit_indexer
        self.oracle_pubkey = oracle_pubkey
    
    async def build_dashboard(
        self, 
        user_pubkey: str, 
        market_id: str = None
    ) -> Dict:
        """
        Construit le tableau de navigation complet.
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché (optionnel, sinon tous les marchés actifs)
            
        Returns:
            Dashboard complet
        """
        log("INFO", f"Construction dashboard pour {user_pubkey[:16]}...")
        
        now = int(time.time())
        
        # 1. Déterminer les marchés actifs
        markets = await self._get_user_markets(user_pubkey)
        if market_id:
            markets = [m for m in markets if m == market_id]
        
        # 2. Position réseau global
        network = await self._get_network_position(user_pubkey)
        
        # 3. Construire les données par marché
        market_data = []
        for mkt in markets:
            mkt_data = await self._build_market_data(user_pubkey, mkt)
            market_data.append(mkt_data)
        
        # 4. Construire le dashboard
        dashboard = {
            'npub': user_pubkey,
            'computed_at': datetime.utcfromtimestamp(now).isoformat() + 'Z',
            'network': network,
            'markets': market_data,
            'summary': self._build_summary(network, market_data)
        }
        
        log("INFO", f"Dashboard construit: {len(markets)} marchés")
        
        return dashboard
    
    async def _build_market_data(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> Dict:
        """Construit les données pour un marché spécifique."""
        
        # DU
        du_result = await self.du_engine.calculate_du(user_pubkey, market_id)
        
        # Paramètres
        params = await self.params_engine.get_all_params(user_pubkey, market_id)
        
        # Circulation
        circulation = await self.circuit_indexer.get_user_circulation_stats(
            user_pubkey, market_id
        )
        
        # Credentials
        credentials = await self._get_user_credentials(user_pubkey)
        
        # Position relative (percentiles)
        position = await self._calculate_position(user_pubkey, market_id, du_result)
        
        # Signaux
        signals = self._build_signals(params, du_result, circulation)
        
        return {
            'market_id': market_id,
            'du': {
                'daily': du_result.get('du', 0),
                'monthly': du_result.get('du_monthly', 0),
                'base': du_result.get('du_base', 0),
                'skill_bonus': du_result.get('du_skill', 0),
                'multiplier': du_result.get('multiplier', 1.0),
                'active': du_result.get('active', False)
            },
            'params': {
                'c2': params.get('c2', 0.07),
                'alpha': params.get('alpha', 0.3),
                'ttl_optimal_days': params.get('ttl_optimal', 28),
                'health_ratio': params.get('c2_details', {}).get('health_ratio', 1.0)
            },
            'circulation': {
                'loops_this_month': circulation.get('loops_30d', 0),
                'median_return_age_days': circulation.get('median_circuit_age_days', 0),
                'in_transit_count': circulation.get('in_transit_count', 0),
                'in_transit_value': circulation.get('in_transit_value', 0),
                'avg_residual_ttl_days': circulation.get('avg_residual_ttl_days', 0)
            },
            'credentials': {
                'count': len(credentials),
                'list': credentials[:5]  # Limiter à 5 pour le dashboard
            },
            'position': position,
            'signals': signals
        }
    
    async def _get_network_position(self, user_pubkey: str) -> Dict:
        """Récupère la position dans le réseau social."""
        n1 = await self.du_engine._get_n1_list(user_pubkey)
        n2 = await self.du_engine._get_n2_list(user_pubkey)
        
        n1_count = len(n1)
        n2_count = len(n2)
        
        # Catégorie de tisseur
        if n1_count >= 10 and n2_count >= 50:
            category = "Tisseur"
        elif n1_count >= 5:
            category = "Actif"
        elif n1_count >= 2:
            category = "Emergent"
        else:
            category = "Starter"
        
        return {
            'n1': n1_count,
            'n2': n2_count,
            'n2_per_n1': round(n2_count / n1_count, 1) if n1_count > 0 else 0,
            'category': category
        }
    
    async def _get_user_markets(self, user_pubkey: str) -> List[str]:
        """Récupère les marchés actifs de l'utilisateur."""
        # Récupérer les bons de l'utilisateur pour identifier les marchés
        events = await self.client.query_events([{
            "kinds": [30303],
            "authors": [user_pubkey],
            "limit": 100
        }])
        
        markets = set()
        for event in events:
            tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
            market = tags.get('market', '')
            if market:
                markets.add(market)
        
        # Si aucun marché, ajouter HACKATHON par défaut
        if not markets:
            markets.add('market_hackathon')
        
        return list(markets)
    
    async def _get_user_credentials(self, user_pubkey: str) -> List[Dict]:
        """Récupère les credentials de l'utilisateur."""
        if not self.oracle_pubkey:
            return []
        
        events = await self.client.query_events([{
            "kinds": [30503],
            "authors": [self.oracle_pubkey],
            "#p": [user_pubkey]
        }])
        
        credentials = []
        for event in events:
            tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
            credentials.append({
                'permit_id': tags.get('permit_id', ''),
                'level': int(tags.get('level', 1)),
                'expires_at': int(tags.get('expires', 0))
            })
        
        return credentials
    
    async def _calculate_position(
        self, 
        user_pubkey: str, 
        market_id: str, 
        du_result: Dict
    ) -> Dict:
        """
        Calcule la position relative de l'utilisateur dans le marché.
        
        Note: Approximatif en mode stateless. Une vraie implémentation
        nécessiterait de calculer les percentiles sur tous les utilisateurs.
        """
        # Pour l'instant, on retourne des valeurs par défaut
        # TODO: Implémenter le calcul de percentiles
        
        du_percentile = 50  # Par défaut: médian
        loops_percentile = 50
        
        # Ajuster selon le DU
        if du_result.get('active'):
            du = du_result.get('du', 0)
            if du > 20:
                du_percentile = 25  # Top 25%
            elif du > 15:
                du_percentile = 40
            elif du < 10:
                du_percentile = 60
        
        return {
            'du_percentile': du_percentile,
            'loops_percentile': loops_percentile,
            'note': 'Approximatif - calcul complet à implémenter'
        }
    
    def _build_signals(
        self, 
        params: Dict, 
        du_result: Dict, 
        circulation: Dict
    ) -> List[str]:
        """
        Génère des signaux textuels automatiques.
        
        Les signaux aident l'utilisateur à comprendre son état
        et suggèrent des actions.
        """
        signals = []
        
        c2 = params.get('c2', 0.07)
        alpha = params.get('alpha', 0.3)
        health = params.get('c2_details', {}).get('health_ratio', 1.0)
        ttl_optimal = params.get('ttl_optimal', 28)
        
        # Santé du réseau
        if health < 1.0:
            signals.append(" Taux d'expiration élevé - réseau à revitaliser")
        elif health > 1.5:
            signals.append(" Réseau en bonne santé")
        
        # C²
        if c2 > 0.12:
            signals.append(" Réseau en forte accélération")
        elif c2 < 0.05:
            signals.append(" Réseau lent - envisagez d'élargir N1")
        
        # TTL
        if ttl_optimal < 14:
            signals.append(f" Réseau rapide - envisage TTL ~{ttl_optimal}j")
        elif ttl_optimal > 60:
            signals.append(f" Réseau patient - TTL suggéré: {ttl_optimal}j")
        
        # Alpha (compétences)
        if alpha > 0.5:
            signals.append(" Compétences très valorisées dans ce marché")
        elif alpha < 0.1:
            signals.append(" Compétences peu différenciantes ici - pur TRM")
        
        # DU
        if not du_result.get('active'):
            signals.append(f" DU inactif - besoin de {self.du_engine.MIN_N1_FOR_DU} N1")
        else:
            du = du_result.get('du', 0)
            if du > 20:
                signals.append(" DU élevé - réseau très actif")
        
        # Circulation
        loops = circulation.get('loops_30d', 0)
        if loops > 10:
            signals.append(f" {loops} boucles ce mois - excellente circulation")
        elif loops == 0:
            signals.append(" Aucune boucle ce mois - émettez des bons")
        
        # Signal par défaut
        if not signals:
            signals.append(" Réseau stable - continuer")
        
        return signals
    
    def _build_summary(self, network: Dict, market_data: List[Dict]) -> Dict:
        """Construit un résumé du dashboard."""
        total_du = sum(m.get('du', {}).get('daily', 0) for m in market_data)
        total_loops = sum(m.get('circulation', {}).get('loops_this_month', 0) for m in market_data)
        active_markets = len([m for m in market_data if m.get('du', {}).get('active')])
        
        return {
            'total_du_daily': round(total_du, 2),
            'total_du_monthly': round(total_du * 30, 2),
            'total_loops_30d': total_loops,
            'active_markets': active_markets,
            'network_category': network.get('category', 'Unknown')
        }


# ==================== Formatage ====================

def format_dashboard_text(dashboard: Dict) -> str:
    """
    Formate le dashboard en texte lisible pour terminal ou SMS.
    """
    lines = []
    
    # En-tête
    lines.append("=" * 60)
    lines.append(f"TABLEAU DE NAVIGATION - {dashboard['npub'][:16]}...")
    lines.append(f"Calculé le: {dashboard['computed_at']}")
    lines.append("=" * 60)
    
    # Réseau
    network = dashboard.get('network', {})
    lines.append("")
    lines.append("POSITION RÉSEAU")
    lines.append(f"  N1={network.get('n1', 0)} · N2={network.get('n2', 0)} · N2/N1={network.get('n2_per_n1', 0)}")
    lines.append(f"  Catégorie: {network.get('category', 'Unknown')}")
    
    # Marchés
    for market in dashboard.get('markets', []):
        lines.append("")
        lines.append("-" * 60)
        lines.append(f"MARCHÉ: {market.get('market_id', 'unknown')}")
        lines.append("-" * 60)
        
        # DU
        du = market.get('du', {})
        if du.get('active'):
            lines.append(f"DU: {du.get('daily', 0)} Zen/jour ({du.get('monthly', 0)}/mois)")
            lines.append(f"  Base: {du.get('base', 0)} + Bonus: {du.get('skill_bonus', 0)} (x{du.get('multiplier', 1)})")
        else:
            lines.append("DU: Inactif")
        
        # Paramètres
        params = market.get('params', {})
        lines.append(f"C²: {params.get('c2', 0):.4f} · alpha: {params.get('alpha', 0):.2f}")
        lines.append(f"TTL optimal: {params.get('ttl_optimal_days', 28)}j")
        
        # Circulation
        circ = market.get('circulation', {})
        lines.append(f"Boucles 30j: {circ.get('loops_this_month', 0)} · Âge médian: {circ.get('median_return_age_days', 0)}j")
        lines.append(f"En transit: {circ.get('in_transit_count', 0)} bons ({circ.get('in_transit_value', 0)} Zen)")
        
        # Signaux
        signals = market.get('signals', [])
        if signals:
            lines.append("")
            lines.append("SIGNAUX:")
            for signal in signals:
                lines.append(f"  {signal}")
    
    # Résumé
    summary = dashboard.get('summary', {})
    lines.append("")
    lines.append("=" * 60)
    lines.append("RÉSUMÉ")
    lines.append(f"DU total: {summary.get('total_du_daily', 0)} Zen/jour")
    lines.append(f"Boucles 30j: {summary.get('total_loops_30d', 0)}")
    lines.append(f"Marchés actifs: {summary.get('active_markets', 0)}")
    lines.append("=" * 60)
    
    return "\n".join(lines)


def format_dashboard_json(dashboard: Dict) -> str:
    """Formate le dashboard en JSON compact."""
    return json.dumps(dashboard, separators=(',', ':'))