#!/usr/bin/env python3
"""
TrocZen Params Engine - Calcul Dynamique C² et alpha

Moteur de calcul des paramètres dynamiques du protocole TrocZen v6.

Formules:
- C² = vitesse_retour_médiane / TTL_médian × facteur_santé × (1 + croissance_N1)
- alpha = corrélation_pearson(niveau_compétence, vitesse_retour)

Architecture Stateless: Toutes les données sont lues depuis le relai Nostr.
"""

import json
import math
import time
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
from collections import defaultdict
import re
import sys
from pathlib import Path

# Ajouter le répertoire parent au path pour les imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import du module de logging centralisé
from logger import get_logger

# Logger spécifique pour le module Params
logger = get_logger('params_engine')


class ParamsEngine:
    """
    Moteur de calcul des paramètres dynamiques C² et alpha.
    
    Architecture stateless: interroge le relai Nostr pour chaque calcul.
    """
    
    # Constantes du protocole
    C2_MIN = 0.02      # C² minimum (2%)
    C2_MAX = 0.25      # C² maximum (25%)
    C2_DEFAULT = 0.07  # C² par défaut (7%)
    
    ALPHA_MIN = 0.0    # alpha minimum
    ALPHA_MAX = 1.0    # alpha maximum
    ALPHA_DEFAULT = 0.3  # alpha par défaut
    
    TTL_MIN = 7        # TTL minimum (jours)
    TTL_MAX = 365      # TTL maximum (jours)
    TTL_DEFAULT = 28   # TTL par défaut (jours)
    
    # Fenêtre d'analyse (jours)
    ANALYSIS_WINDOW = 30
    
    def __init__(self, nostr_client):
        """
        Initialise le moteur de paramètres.
        
        Args:
            nostr_client: Client Nostr pour les requêtes
        """
        self.client = nostr_client
    
    async def calculate_c2(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> Dict:
        """
        Calcule C² dynamique pour un utilisateur dans un marché.
        
        Formule:
        C²_i(t) = vitesse_retour_médiane_i(t) / TTL_médian_i(t)
                 × facteur_santé_i(t)
                 × (1 + taux_croissance_N1_i(t))
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché
            
        Returns:
            Dictionnaire avec C² et les métriques associées
        """
        logger.info(f"Calcul C² pour {user_pubkey[:16]}... dans {market_id}")
        
        # 1. Récupérer les boucles fermées des 30 derniers jours
        loops = await self._get_loops_30d(user_pubkey, market_id)
        
        # 2. Calculer l'âge médian de retour
        ages = [loop.get('age_days', 0) for loop in loops if loop.get('age_days')]
        median_return = self._median(ages) if ages else 0
        
        # 3. Récupérer les TTL des bons émis
        emitted_ttls = await self._get_emitted_ttls_30d(user_pubkey, market_id)
        median_ttl = self._median(emitted_ttls) if emitted_ttls else self.TTL_DEFAULT
        
        # 4. Calculer le ratio de santé (boucles / expirés)
        expired_count = await self._get_expired_count_30d(user_pubkey, market_id)
        health_ratio = len(loops) / max(expired_count, 0.1)
        health_ratio = min(health_ratio, 2.0)  # Plafonné à 2
        
        # 5. Calculer la croissance N1
        prev_loops = await self._get_loops_prev_month(user_pubkey, market_id)
        n1_growth = max(0, (len(loops) - len(prev_loops)) / max(len(prev_loops), 1))
        n1_growth = min(n1_growth, 0.5)  # Plafonné à 50%
        
        # 6. Calcul C²
        if median_return > 0 and median_ttl > 0:
            c2 = (median_return / median_ttl) * health_ratio * (1 + n1_growth)
            c2 = max(self.C2_MIN, min(c2, self.C2_MAX))
        else:
            c2 = self.C2_DEFAULT
        
        logger.info(f"C² calculé: {c2:.4f} (retour: {median_return}j, santé: {health_ratio:.2f})")
        
        return {
            'c2': round(c2, 4),
            'median_return_age': round(median_return, 1),
            'median_ttl': round(median_ttl, 1),
            'health_ratio': round(health_ratio, 2),
            'n1_growth': round(n1_growth, 3),
            'loops_count': len(loops),
            'expired_count': expired_count,
            'computed_at': int(time.time())
        }
    
    async def calculate_alpha(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> Dict:
        """
        Calcule alpha (multiplicateur compétence) par corrélation Pearson.
        
        alpha mesure si la compétence prédit la vitesse de retour des bons.
        Si les bons annotés "maraîchage X3" reviennent plus vite que les 
        bons non annotés, alpha monte.
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché
            
        Returns:
            Dictionnaire avec alpha et les métriques associées
        """
        logger.info(f"Calcul alpha pour {user_pubkey[:16]}... dans {market_id}")
        
        # Récupérer les boucles avec certification de compétence
        skill_loops = await self._get_skill_loops_30d(user_pubkey, market_id)
        
        if len(skill_loops) < 5:
            logger.info(f"Pas assez de données ({len(skill_loops)} < 5), alpha par défaut")
            return {
                'alpha': self.ALPHA_DEFAULT,
                'skill_loops_count': len(skill_loops),
                'correlation': 0,
                'computed_at': int(time.time())
            }
        
        # Extraire niveaux et âges
        skill_levels = []
        return_ages = []
        
        for loop in skill_loops:
            cert = loop.get('skill_cert', '')
            level = self._extract_skill_level(cert)
            skill_levels.append(level)
            # Négatif: retour rapide = bon
            return_ages.append(-loop.get('age_days', 0))
        
        # Calculer la corrélation de Pearson
        if len(skill_levels) >= 3:
            corr = self._pearson_correlation(skill_levels, return_ages)
            alpha = max(self.ALPHA_MIN, min(corr * 0.8, self.ALPHA_MAX))
        else:
            alpha = self.ALPHA_DEFAULT
            corr = 0
        
        logger.info(f"Alpha calculé: {alpha:.3f} (corrélation: {corr:.3f})")
        
        return {
            'alpha': round(alpha, 3),
            'skill_loops_count': len(skill_loops),
            'correlation': round(corr, 3),
            'avg_skill_level': round(sum(skill_levels) / len(skill_levels), 1) if skill_levels else 0,
            'computed_at': int(time.time())
        }
    
    async def calculate_ttl_optimal(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> int:
        """
        Calcule le TTL optimal suggéré pour l'utilisateur.
        
        Formule: TTL_optimal = age_retour_médian × 1.5
        Borné entre 7 et 365 jours.
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché
            
        Returns:
            TTL optimal en jours
        """
        loops = await self._get_loops_30d(user_pubkey, market_id)
        ages = [loop.get('age_days', 0) for loop in loops if loop.get('age_days')]
        
        median_return = self._median(ages) if ages else 0
        
        if median_return > 0:
            ttl = round(median_return * 1.5)
            ttl = max(self.TTL_MIN, min(ttl, self.TTL_MAX))
        else:
            ttl = self.TTL_DEFAULT
        
        return ttl
    
    async def get_all_params(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> Dict:
        """
        Calcule tous les paramètres dynamiques en une seule fois.
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché
            
        Returns:
            Dictionnaire avec C², alpha, TTL optimal
        """
        c2_result = await self.calculate_c2(user_pubkey, market_id)
        alpha_result = await self.calculate_alpha(user_pubkey, market_id)
        ttl_optimal = await self.calculate_ttl_optimal(user_pubkey, market_id)
        
        return {
            'c2': c2_result['c2'],
            'alpha': alpha_result['alpha'],
            'ttl_optimal': ttl_optimal,
            'c2_details': c2_result,
            'alpha_details': alpha_result,
            'computed_at': int(time.time())
        }
    
    # ==================== Méthodes de récupération des données ====================
    
    async def _get_loops_30d(self, user_pubkey: str, market_id: str) -> List[Dict]:
        """Récupère les boucles fermées des 30 derniers jours."""
        now = int(time.time())
        since = now - (self.ANALYSIS_WINDOW * 86400)
        
        # Normaliser le tag market
        market_tag = self._normalize_market_tag(market_id)
        
        events = await self.client.query_events([{
            "kinds": [30304],
            "#issued_by": [user_pubkey],  # L'émetteur original
            "#market": [market_tag],
            "since": since
        }])
        
        loops = []
        for event in events:
            content = json.loads(event.get('content', '{}'))
            loops.append({
                'age_days': content.get('age_days', 0),
                'hop_count': content.get('hop_count', 0),
                'value_zen': content.get('value_zen', 0),
                'skill_cert': content.get('skill_cert'),
                'closed_at': event.get('created_at', 0)
            })
        
        return loops
    
    async def _get_loops_prev_month(self, user_pubkey: str, market_id: str) -> List[Dict]:
        """Récupère les boucles fermées du mois précédent."""
        now = int(time.time())
        since = now - (2 * self.ANALYSIS_WINDOW * 86400)
        until = now - (self.ANALYSIS_WINDOW * 86400)
        
        market_tag = self._normalize_market_tag(market_id)
        
        events = await self.client.query_events([{
            "kinds": [30304],
            "#issued_by": [user_pubkey],
            "#market": [market_tag],
            "since": since,
            "until": until
        }])
        
        return [{'closed_at': e.get('created_at', 0)} for e in events]
    
    async def _get_emitted_ttls_30d(self, user_pubkey: str, market_id: str) -> List[int]:
        """Récupère les TTL des bons émis dans les 30 derniers jours."""
        now = int(time.time())
        since = now - (self.ANALYSIS_WINDOW * 86400)
        
        market_tag = self._normalize_market_tag(market_id)
        
        events = await self.client.query_events([{
            "kinds": [30303],
            "authors": [user_pubkey],
            "#market": [market_tag],
            "since": since
        }])
        
        ttls = []
        for event in events:
            content = json.loads(event.get('content', '{}'))
            issued_at = content.get('issued_at', event.get('created_at', now))
            expires_at = content.get('expires_at', 0)
            if expires_at > issued_at:
                ttl_days = (expires_at - issued_at) // 86400
                ttls.append(ttl_days)
        
        return ttls
    
    async def _get_expired_count_30d(self, user_pubkey: str, market_id: str) -> int:
        """
        Compte les bons expirés sans retour.
        
        Note: Les bons expirés sont détectés par l'absence de circuit
        et une date d'expiration passée.
        """
        now = int(time.time())
        since = now - (self.ANALYSIS_WINDOW * 86400)
        
        market_tag = self._normalize_market_tag(market_id)
        
        # Récupérer les bons émis avec expiration dans la fenêtre
        events = await self.client.query_events([{
            "kinds": [30303],
            "authors": [user_pubkey],
            "#market": [market_tag],
            "since": since
        }])
        
        expired_count = 0
        for event in events:
            tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
            expires_at = int(tags.get('expires', 0))
            bon_id = tags.get('d', '')
            
            # Si le bon a expiré
            if expires_at > 0 and expires_at < now:
                # Vérifier s'il y a un circuit (Kind 30304)
                circuits = await self.client.query_events([{
                    "kinds": [30304],
                    "#bon_id": [bon_id]
                }])
                
                if not circuits:
                    expired_count += 1
        
        return expired_count
    
    async def _get_skill_loops_30d(self, user_pubkey: str, market_id: str) -> List[Dict]:
        """Récupère les boucles avec certification de compétence."""
        loops = await self._get_loops_30d(user_pubkey, market_id)
        return [l for l in loops if l.get('skill_cert')]
    
    # ==================== Fonctions mathématiques ====================
    
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
    
    def _pearson_correlation(self, x: List[float], y: List[float]) -> float:
        """
        Calcule le coefficient de corrélation de Pearson.
        
        r = sum((xi - mx)(yi - my)) / sqrt(sum((xi - mx)²) × sum((yi - my)²))
        """
        n = min(len(x), len(y))
        if n < 3:
            return 0
        
        x = x[:n]
        y = y[:n]
        
        mean_x = sum(x) / n
        mean_y = sum(y) / n
        
        numerator = sum((x[i] - mean_x) * (y[i] - mean_y) for i in range(n))
        
        sum_sq_x = sum((xi - mean_x) ** 2 for xi in x)
        sum_sq_y = sum((yi - mean_y) ** 2 for yi in y)
        denominator = math.sqrt(sum_sq_x * sum_sq_y)
        
        if denominator == 0:
            return 0
        
        return numerator / denominator
    
    def _extract_skill_level(self, skill_cert: str) -> int:
        """Extrait le niveau de compétence depuis une certification."""
        if not skill_cert:
            return 1
        match = re.search(r'_X(\d+)$', skill_cert)
        if match:
            return int(match.group(1))
        return 1
    
    def _normalize_market_tag(self, market_id: str) -> str:
        """
        Normalise un ID de marché en tag Nostr.
        
        Ex: "Marché de Paris" -> "market_marche_de_paris"
        """
        import unicodedata
        
        # Normalisation NFKD
        nfkd = unicodedata.normalize('NFKD', market_id)
        # Retirer les diacritiques
        without_diacritics = ''.join(c for c in nfkd if not unicodedata.combining(c))
        # Minuscules et remplacement
        lower = without_diacritics.lower()
        sanitized = re.sub(r'[^a-z0-9]', '_', lower)
        cleaned = re.sub(r'_+', '_', sanitized).strip('_')
        
        return f"market_{cleaned}"


# ==================== Fonctions utilitaires standalone ====================

def calculate_c2_simple(
    loops_ages: List[int], 
    emitted_ttls: List[int], 
    expired_count: int,
    prev_loops_count: int
) -> Dict:
    """
    Version simplifiée du calcul C² sans dépendance Nostr.
    
    Utile pour les tests ou les calculs en mémoire.
    """
    engine = ParamsEngine(None)
    
    median_return = engine._median(loops_ages) if loops_ages else 0
    median_ttl = engine._median(emitted_ttls) if emitted_ttls else ParamsEngine.TTL_DEFAULT
    
    loops_count = len(loops_ages)
    health_ratio = loops_count / max(expired_count, 0.1)
    health_ratio = min(health_ratio, 2.0)
    
    n1_growth = max(0, (loops_count - prev_loops_count) / max(prev_loops_count, 1))
    n1_growth = min(n1_growth, 0.5)
    
    if median_return > 0 and median_ttl > 0:
        c2 = (median_return / median_ttl) * health_ratio * (1 + n1_growth)
        c2 = max(ParamsEngine.C2_MIN, min(c2, ParamsEngine.C2_MAX))
    else:
        c2 = ParamsEngine.C2_DEFAULT
    
    return {
        'c2': round(c2, 4),
        'median_return_age': median_return,
        'median_ttl': median_ttl,
        'health_ratio': round(health_ratio, 2),
        'n1_growth': round(n1_growth, 3)
    }