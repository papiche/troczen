#!/usr/bin/env python3
"""
TrocZen Circuit Indexer

Indexation des circuits de bons Zen (Kind 30303 et 30304).

Fonctionnalités:
- Indexation des bons actifs
- Traitement des circuits fermés
- Calcul des métriques de circulation
- Taux inter-marchés

Architecture Stateless: Interroge le relai Nostr à la volée.
"""

import json
import time
import re
from typing import Dict, List, Optional, Tuple
from datetime import datetime
from collections import defaultdict
import sys
from pathlib import Path

# Ajouter le répertoire parent au path pour les imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import du module de logging centralisé
from logger import get_logger

# Logger spécifique pour le module Circuit
logger = get_logger('circuit_indexer')


class CircuitIndexer:
    """
    Indexeur de circuits pour le module DRAGON.
    
    Gère l'indexation des bons (Kind 30303) et des circuits fermés (Kind 30304).
    """
    
    def __init__(self, nostr_client):
        """
        Initialise l'indexeur de circuits.
        
        Args:
            nostr_client: Client Nostr pour les requêtes
        """
        self.client = nostr_client
    
    async def get_active_bonds(
        self, 
        market_id: str,
        owner_pubkey: str = None
    ) -> List[Dict]:
        """
        Récupère les bons actifs (non expirés) d'un marché.
        
        Args:
            market_id: ID du marché
            owner_pubkey: Pubkey du propriétaire (optionnel, pour filtrer)
            
        Returns:
            Liste des bons actifs
        """
        now = int(time.time())
        market_tag = self._normalize_market_tag(market_id)
        
        filters = {
            "kinds": [30303],
            "#market": [market_tag]
        }
        
        if owner_pubkey:
            filters["authors"] = [owner_pubkey]
        
        events = await self.client.query_events([filters])
        
        active_bonds = []
        for event in events:
            bond = self._parse_bond_event(event)
            
            # Vérifier que le bon n'est pas expiré
            if bond.get('expires_at', 0) > now:
                active_bonds.append(bond)
        
        return active_bonds
    
    async def get_bond_by_id(self, bon_id: str) -> Optional[Dict]:
        """Récupère un bon par son ID."""
        events = await self.client.query_events([{
            "kinds": [30303],
            "#d": [bon_id],
            "limit": 1
        }])
        
        if events:
            return self._parse_bond_event(events[0])
        return None
    
    async def get_circuits(
        self, 
        market_id: str,
        issuer_pubkey: str = None,
        since: int = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Récupère les circuits fermés d'un marché.
        
        Args:
            market_id: ID du marché
            issuer_pubkey: Pubkey de l'émetteur original (optionnel)
            since: Timestamp minimum (optionnel)
            limit: Nombre maximum de résultats
            
        Returns:
            Liste des circuits fermés
        """
        market_tag = self._normalize_market_tag(market_id)
        
        filters = {
            "kinds": [30304],
            "#market": [market_tag],
            "limit": limit
        }
        
        if issuer_pubkey:
            filters["#issued_by"] = [issuer_pubkey]
        
        if since:
            filters["since"] = since
        
        events = await self.client.query_events([filters])
        
        return [self._parse_circuit_event(e) for e in events]
    
    async def get_circuit_by_bon_id(self, bon_id: str) -> Optional[Dict]:
        """Récupère le circuit d'un bon spécifique."""
        events = await self.client.query_events([{
            "kinds": [30304],
            "#bon_id": [bon_id],
            "limit": 1
        }])
        
        if events:
            return self._parse_circuit_event(events[0])
        return None
    
    async def calculate_market_stats(self, market_id: str) -> Dict:
        """
        Calcule les statistiques d'un marché.
        
        Args:
            market_id: ID du marché
            
        Returns:
            Statistiques du marché
        """
        now = int(time.time())
        month_ago = now - (30 * 86400)
        
        # Bons actifs
        active_bonds = await self.get_active_bonds(market_id)
        
        # Circuits du mois
        circuits = await self.get_circuits(market_id, since=month_ago)
        
        # Calculs
        total_active_value = sum(b.get('value_zen', 0) for b in active_bonds)
        total_loops = len(circuits)
        
        # Âge moyen des circuits
        ages = [c.get('age_days', 0) for c in circuits if c.get('age_days')]
        avg_age = sum(ages) / len(ages) if ages else 0
        
        # Distribution par niveau de compétence
        skill_distribution = defaultdict(int)
        for circuit in circuits:
            cert = circuit.get('skill_cert', 'none')
            skill_distribution[cert] += 1
        
        # Santé du marché (ratio boucles/expirations)
        # Note: Approximatif, nécessiterait de compter les expirés
        health_ratio = 1.0  # TODO: calculer correctement
        
        return {
            'market_id': market_id,
            'active_bonds_count': len(active_bonds),
            'active_bonds_value': round(total_active_value, 2),
            'loops_30d': total_loops,
            'avg_circuit_age_days': round(avg_age, 1),
            'skill_distribution': dict(skill_distribution),
            'health_ratio': health_ratio,
            'computed_at': now
        }
    
    async def calculate_intermarket_rates(self) -> Dict[str, Dict]:
        """
        Calcule les taux de change inter-marchés émergents.
        
        Le taux est calculé depuis les circuits qui traversent deux marchés.
        
        Returns:
            Dictionnaire des taux: {market_A: {market_B: rate}}
        """
        now = int(time.time())
        month_ago = now - (30 * 86400)
        
        # Récupérer tous les circuits inter-marchés du mois
        events = await self.client.query_events([{
            "kinds": [30304],
            "since": month_ago,
            "limit": 1000
        }])
        
        # Compter les flux par paire de marchés
        flows = defaultdict(lambda: {'a_to_b': 0, 'b_to_a': 0})
        
        for event in events:
            content = json.loads(event.get('content', '{}'))
            market_id = content.get('market_id', '')
            dest_market = content.get('dest_market_id', '')
            value = content.get('value_zen', 0)
            
            if dest_market and dest_market != market_id:
                # Flux de market_id vers dest_market
                key = tuple(sorted([market_id, dest_market]))
                if market_id < dest_market:
                    flows[key]['a_to_b'] += value
                else:
                    flows[key]['b_to_a'] += value
        
        # Calculer les taux
        rates = {}
        for (m1, m2), flow in flows.items():
            total = flow['a_to_b'] + flow['b_to_a']
            if total > 0:
                # Taux = flux A->B / flux total
                rate = flow['a_to_b'] / total if m1 < m2 else flow['b_to_a'] / total
                
                if m1 not in rates:
                    rates[m1] = {}
                if m2 not in rates:
                    rates[m2] = {}
                
                # Taux dans les deux sens
                rates[m1][m2] = round(rate, 3)
                rates[m2][m1] = round(1 - rate, 3)
        
        return rates
    
    async def get_user_circulation_stats(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> Dict:
        """
        Récupère les statistiques de circulation d'un utilisateur.
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché
            
        Returns:
            Statistiques de circulation
        """
        now = int(time.time())
        month_ago = now - (30 * 86400)
        
        # Circuits où l'utilisateur est l'émetteur
        issuer_circuits = await self.get_circuits(
            market_id, 
            issuer_pubkey=user_pubkey,
            since=month_ago
        )
        
        # Bons actifs de l'utilisateur
        active_bonds = await self.get_active_bonds(market_id, user_pubkey)
        
        # Calculs
        loops_count = len(issuer_circuits)
        total_looped_value = sum(c.get('value_zen', 0) for c in issuer_circuits)
        
        ages = [c.get('age_days', 0) for c in issuer_circuits if c.get('age_days')]
        median_age = self._median(ages) if ages else 0
        
        hops = [c.get('hop_count', 0) for c in issuer_circuits]
        avg_hops = sum(hops) / len(hops) if hops else 0
        
        # Bons en transit
        in_transit = [b for b in active_bonds if b.get('hop_count', 0) > 0]
        transit_value = sum(b.get('value_zen', 0) for b in in_transit)
        
        # TTL résiduel moyen
        now = int(time.time())
        residual_ttls = []
        for bond in active_bonds:
            expires = bond.get('expires_at', 0)
            if expires > now:
                residual_ttls.append((expires - now) / 86400)
        
        avg_residual_ttl = sum(residual_ttls) / len(residual_ttls) if residual_ttls else 0
        
        return {
            'user_pubkey': user_pubkey,
            'market_id': market_id,
            'loops_30d': loops_count,
            'total_looped_value': round(total_looped_value, 2),
            'median_circuit_age_days': round(median_age, 1),
            'avg_hop_count': round(avg_hops, 1),
            'active_bonds_count': len(active_bonds),
            'in_transit_count': len(in_transit),
            'in_transit_value': round(transit_value, 2),
            'avg_residual_ttl_days': round(avg_residual_ttl, 1),
            'computed_at': now
        }
    
    # ==================== Parsing ====================
    
    def _parse_bond_event(self, event: Dict) -> Dict:
        """Parse un événement de bon (Kind 30303)."""
        tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
        content = json.loads(event.get('content', '{}'))
        
        return {
            'bon_id': tags.get('d', ''),
            'issued_by': event.get('pubkey', ''),
            'issued_at': event.get('created_at', 0),
            'expires_at': int(tags.get('expires', 0)),
            'value_zen': float(tags.get('value', 0)),
            'hop_count': content.get('hop_count', 0),
            'path': content.get('path', []),
            'market_id': tags.get('market', ''),
            'skill_cert': tags.get('skill_cert'),
            'p3_encrypted': content.get('p3_encrypted'),
            'current_holder': event.get('pubkey', '')  # Le dernier émetteur
        }
    
    def _parse_circuit_event(self, event: Dict) -> Dict:
        """Parse un événement de circuit (Kind 30304)."""
        tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
        content = json.loads(event.get('content', '{}'))
        
        return {
            'circuit_id': tags.get('d', ''),
            'bon_id': tags.get('bon_id', ''),
            'issued_by': content.get('issued_by', ''),
            'market_id': tags.get('market', content.get('market_id', '')),
            'dest_market_id': content.get('dest_market_id'),
            'value_zen': content.get('value_zen', 0),
            'age_days': content.get('age_days', 0),
            'hop_count': content.get('hop_count', 0),
            'ttl_consumed': content.get('ttl_consumed', 0),
            'skill_cert': content.get('skill_cert'),
            'closed_at': event.get('created_at', 0),
            'closed_by': event.get('pubkey', '')
        }
    
    # ==================== Versions synchrones pour DragonServiceSync ====================
    
    def get_active_bonds_sync(
        self,
        market_id: str,
        owner_pubkey: str = None
    ) -> List[Dict]:
        """
        Version synchrone de get_active_bonds.
        
        Récupère les bons actifs (non expirés) d'un marché.
        Utilisé par DragonServiceSync.
        """
        now = int(time.time())
        market_tag = self._normalize_market_tag(market_id)
        
        filters = {
            "kinds": [30303],
            "#market": [market_tag]
        }
        
        if owner_pubkey:
            filters["authors"] = [owner_pubkey]
        
        # Appel synchrone - le client doit être NostrClientSync
        events = self.client.query_events([filters])
        
        active_bonds = []
        for event in events:
            bond = self._parse_bond_event(event)
            
            # Vérifier que le bon n'est pas expiré
            if bond.get('expires_at', 0) > now:
                active_bonds.append(bond)
        
        return active_bonds
    
    def get_circuits_sync(
        self,
        market_id: str,
        issuer_pubkey: str = None,
        since: int = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Version synchrone de get_circuits.
        
        Récupère les circuits fermés d'un marché.
        Utilisé par DragonServiceSync.
        """
        market_tag = self._normalize_market_tag(market_id)
        
        filters = {
            "kinds": [30304],
            "#market": [market_tag],
            "limit": limit
        }
        
        if issuer_pubkey:
            filters["#issued_by"] = [issuer_pubkey]
        
        if since:
            filters["since"] = since
        
        # Appel synchrone - le client doit être NostrClientSync
        events = self.client.query_events([filters])
        
        return [self._parse_circuit_event(e) for e in events]
    
    # ==================== Utilitaires ====================
    
    def _normalize_market_tag(self, market_id: str) -> str:
        """Normalise un ID de marché en tag Nostr."""
        import unicodedata
        
        nfkd = unicodedata.normalize('NFKD', market_id)
        without_diacritics = ''.join(c for c in nfkd if not unicodedata.combining(c))
        lower = without_diacritics.lower()
        sanitized = re.sub(r'[^a-z0-9]', '_', lower)
        cleaned = re.sub(r'_+', '_', sanitized).strip('_')
        
        return f"market_{cleaned}"
    
    def _median(self, values: List[float]) -> float:
        """Calcule la médiane d'une liste."""
        if not values:
            return 0
        sorted_vals = sorted(values)
        n = len(sorted_vals)
        mid = n // 2
        if n % 2 == 0:
            return (sorted_vals[mid - 1] + sorted_vals[mid]) / 2
        return sorted_vals[mid]


# ==================== Fonctions utilitaires ====================

def format_circuit_summary(circuit: Dict) -> str:
    """Formate un résumé de circuit lisible."""
    return (
        f"Circuit {circuit.get('bon_id', 'unknown')[:8]}: "
        f"{circuit.get('value_zen', 0)} Zen, "
        f"{circuit.get('age_days', 0)}j, "
        f"{circuit.get('hop_count', 0)} hops"
    )


def calculate_circuit_efficiency(circuit: Dict) -> float:
    """
    Calcule l'efficacité d'un circuit.
    
    Efficacité = valeur / (âge × hops)
    Plus élevé = circuit plus efficace (valeur rapide avec peu d'intermédiaires).
    """
    value = circuit.get('value_zen', 0)
    age = max(circuit.get('age_days', 1), 1)
    hops = max(circuit.get('hop_count', 1), 1)
    
    return value / (age * hops)