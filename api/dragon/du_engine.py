#!/usr/bin/env python3
"""
TrocZen DU Engine - Calcul du Dividende Universel

Moteur de calcul du DU selon la Théorie Relativiste de la Monnaie (TRM)
étendue avec le multiplicateur de compétence.

Formules:
- DU_base = DU_prev + C² × (M_N1 + M_N2/sqrt(N2)) / (N1 + sqrt(N2))
- DU_final = DU_base × (1 + alpha × S_i)

Architecture Stateless: Toutes les données sont lues depuis le relai Nostr.
"""

import json
import math
import time
from typing import Dict, List, Optional, Tuple
from datetime import datetime
import sys
from pathlib import Path

# Ajouter le répertoire parent au path pour les imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import du module de logging centralisé
from logger import get_logger

# Logger spécifique pour le module DU
logger = get_logger('du_engine')


class DUEngine:
    """
    Moteur de calcul du Dividende Universel (DU).
    
    Implémente la formule TRM étendue avec:
    - Paramètres dynamiques C² et alpha
    - Multiplicateur de compétence
    - Graphe social N1/N2
    """
    
    # Constante fondamentale
    DU_INITIAL = 10.0  # 10 Zen/jour - DU(0) universel
    
    # Seuil minimum N1 pour DU actif
    MIN_N1_FOR_DU = 5
    
    def __init__(self, nostr_client, params_engine, oracle_pubkey: str = None):
        """
        Initialise le moteur DU.
        
        Args:
            nostr_client: Client Nostr pour les requêtes
            params_engine: Moteur de paramètres (C², alpha)
            oracle_pubkey: Pubkey de l'Oracle pour vérifier les credentials
        """
        self.client = nostr_client
        self.params_engine = params_engine
        self.oracle_pubkey = oracle_pubkey
    
    async def calculate_du(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> Dict:
        """
        Calcule le DU complet pour un utilisateur dans un marché.
        
        Args:
            user_pubkey: Pubkey de l'utilisateur
            market_id: ID du marché
            
        Returns:
            Dictionnaire avec DU et toutes les métriques
        """
        logger.info(f"Calcul DU pour {user_pubkey[:16]}... dans {market_id}")
        
        # 1. Récupérer le graphe social (N1, N2)
        n1_list = await self._get_n1_list(user_pubkey)
        n2_list = await self._get_n2_list(user_pubkey)
        
        n1_count = len(n1_list)
        n2_count = len(n2_list)
        
        # Vérifier le seuil minimum
        if n1_count < self.MIN_N1_FOR_DU:
            logger.info(f"N1={n1_count} < {self.MIN_N1_FOR_DU}, DU inactif")
            return {
                'du': 0,
                'du_base': 0,
                'du_skill': 0,
                'reason': f'N1 < {self.MIN_N1_FOR_DU}',
                'n1': n1_count,
                'n2': n2_count,
                'active': False
            }
        
        # 2. Calculer les masses monétaires actives
        now = int(time.time())
        m_n1 = await self._calculate_active_mass(n1_list, market_id, now)
        m_n2 = await self._calculate_active_mass(n2_list, market_id, now)
        
        logger.debug(f"M_N1={m_n1:.1f}, M_N2={m_n2:.1f}")
        
        # 3. Récupérer les paramètres dynamiques
        params = await self.params_engine.get_all_params(user_pubkey, market_id)
        c2 = params['c2']
        alpha = params['alpha']
        
        # 4. Récupérer le DU précédent
        prev_du = await self._get_prev_du(user_pubkey, market_id)
        
        # 5. Calcul DU de base (formule TRM)
        sq_n2 = math.sqrt(max(n2_count, 1))
        du_increment = c2 * (m_n1 + m_n2 / sq_n2) / (n1_count + sq_n2)
        du_base = prev_du + du_increment
        
        # 6. Calculer le score de compétence S_i
        s_i = await self._calculate_skill_score(user_pubkey, market_id)
        
        # 7. Calcul DU final avec multiplicateur
        multiplier = 1 + alpha * s_i
        du_final = du_base * multiplier
        du_skill = du_base * (multiplier - 1)
        
        # Stocker pour le prochain calcul
        await self._save_du(user_pubkey, market_id, du_final)
        
        logger.info(f"DU calculé: {du_final:.2f} Zen/jour (base: {du_base:.2f}, bonus: {du_skill:.2f})")
        
        return {
            'du': round(du_final, 2),
            'du_base': round(du_base, 2),
            'du_skill': round(du_skill, 2),
            'du_monthly': round(du_final * 30, 2),
            'c2': c2,
            'alpha': alpha,
            's_i': round(s_i, 2),
            'multiplier': round(multiplier, 2),
            'n1': n1_count,
            'n2': n2_count,
            'm_n1': round(m_n1, 2),
            'm_n2': round(m_n2, 2),
            'active': True,
            'computed_at': int(time.time())
        }
    
    async def calculate_du_simple(
        self,
        n1_count: int,
        n2_count: int,
        m_n1: float,
        m_n2: float,
        c2: float,
        alpha: float,
        s_i: float,
        prev_du: float = None
    ) -> Dict:
        """
        Version simplifiée du calcul DU sans dépendance Nostr.
        
        Utile pour les tests ou les calculs en mémoire.
        """
        if n1_count < self.MIN_N1_FOR_DU:
            return {
                'du': 0,
                'reason': f'N1 < {self.MIN_N1_FOR_DU}',
                'active': False
            }
        
        if prev_du is None:
            prev_du = self.DU_INITIAL
        
        sq_n2 = math.sqrt(max(n2_count, 1))
        du_increment = c2 * (m_n1 + m_n2 / sq_n2) / (n1_count + sq_n2)
        du_base = prev_du + du_increment
        
        multiplier = 1 + alpha * s_i
        du_final = du_base * multiplier
        du_skill = du_base * (multiplier - 1)
        
        return {
            'du': round(du_final, 2),
            'du_base': round(du_base, 2),
            'du_skill': round(du_skill, 2),
            'du_monthly': round(du_final * 30, 2),
            'multiplier': round(multiplier, 2),
            'active': True
        }
    
    # ==================== Méthodes de récupération des données ====================
    
    async def _get_n1_list(self, user_pubkey: str) -> List[str]:
        """
        Récupère la liste N1 (liens réciproques).
        
        N1 = ensemble des utilisateurs qui se suivent mutuellement.
        Optimisé: Récupère tous les kind 3 des follows en une seule requête.
        """
        # Récupérer les follows de l'utilisateur (Kind 3)
        events = await self.client.query_events([{
            "kinds": [3],
            "authors": [user_pubkey],
            "limit": 1
        }])
        
        if not events:
            return []
        
        # Extraire les follows
        follows = set()
        for tag in events[0].get('tags', []):
            if len(tag) >= 2 and tag[0] == 'p':
                follows.add(tag[1])
        
        if not follows:
            return []
        
        # Récupérer tous les kind 3 des follows en une seule requête
        # On utilise un filtre authors avec la liste des follows
        follows_list = list(follows)
        follow_events = await self.client.query_events([{
            "kinds": [3],
            "authors": follows_list,
            "limit": len(follows_list)  # Un événement par auteur au maximum
        }])
        
        # Créer un dictionnaire pour accéder rapidement aux follows de chaque auteur
        follows_by_author = {}
        for event in follow_events:
            author = event.get('pubkey')
            if author:
                follows_by_author[author] = set()
                for tag in event.get('tags', []):
                    if len(tag) >= 2 and tag[0] == 'p':
                        follows_by_author[author].add(tag[1])
        
        # Vérifier la réciprocité: un follow est dans N1 si:
        # 1. L'utilisateur suit ce follow (déjà dans `follows`)
        # 2. Le follow suit l'utilisateur (présent dans les tags de son kind 3)
        n1 = []
        for follow_pubkey in follows:
            # Vérifier si le follow a un kind 3 et s'il suit l'utilisateur
            if follow_pubkey in follows_by_author:
                if user_pubkey in follows_by_author[follow_pubkey]:
                    n1.append(follow_pubkey)
        
        return n1
    
    async def _get_n2_list(self, user_pubkey: str) -> List[str]:
        """
        Récupère la liste N2 (amis des amis réciproques, sans doublons avec N1).
        
        N2 = ensemble des N1 des N1, moins N1 et l'utilisateur.
        Optimisé: Récupère tous les kind 3 des N1 en une seule requête batch.
        """
        n1 = await self._get_n1_list(user_pubkey)
        
        if not n1:
            return []
        
        # Récupérer tous les kind 3 des N1 en une seule requête batch
        n1_events = await self.client.query_events([{
            "kinds": [3],
            "authors": n1,
            "limit": len(n1)  # Un événement par N1 au maximum
        }])
        
        # Extraire tous les follows des N1
        n2_set = set()
        for event in n1_events:
            for tag in event.get('tags', []):
                if len(tag) >= 2 and tag[0] == 'p':
                    pubkey = tag[1]
                    # Exclure l'utilisateur et les N1
                    if pubkey != user_pubkey and pubkey not in n1:
                        n2_set.add(pubkey)
        
        return list(n2_set)
    
    async def _calculate_active_mass(
        self, 
        pubkeys: List[str], 
        market_id: str, 
        now: int
    ) -> float:
        """
        Calcule la masse monétaire active (Zen non expirés) d'un ensemble de pubkeys.
        
        Args:
            pubkeys: Liste des pubkeys
            market_id: ID du marché
            now: Timestamp actuel
            
        Returns:
            Masse totale en Zen
        """
        if not pubkeys:
            return 0.0
        
        # Récupérer les bons actifs de tous les pubkeys
        # Note: Cette requête peut être coûteuse, à optimiser en production
        total_mass = 0.0
        
        # Batch par groupes de 50 pour éviter les requêtes trop grosses
        batch_size = 50
        for i in range(0, len(pubkeys), batch_size):
            batch = pubkeys[i:i + batch_size]
            
            events = await self.client.query_events([{
                "kinds": [30303],
                "authors": batch,
                "#market": [market_id]
            }])
            
            for event in events:
                tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
                expires_at = int(tags.get('expires', 0))
                
                # Vérifier que le bon n'est pas expiré
                if expires_at > now:
                    value = float(tags.get('value', 0))
                    total_mass += value
        
        return total_mass
    
    async def _calculate_skill_score(
        self, 
        user_pubkey: str, 
        market_id: str
    ) -> float:
        """
        Calcule le score de compétence S_i depuis les credentials.
        
        S_i = moyenne pondérée des niveaux de compétences certifiées.
        
        Note: Seuls les Kind 30503 signés par l'Oracle sont pris en compte.
        """
        if not self.oracle_pubkey:
            return 0.0
        
        # Récupérer les credentials de l'utilisateur
        events = await self.client.query_events([{
            "kinds": [30503],
            "authors": [self.oracle_pubkey],
            "#p": [user_pubkey]
        }])
        
        if not events:
            return 0.0
        
        # Calculer le score
        total_level = 0
        count = 0
        
        for event in events:
            tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
            permit_id = tags.get('permit_id', '')
            
            # Extraire le niveau
            level = self._extract_permit_level(permit_id)
            total_level += level
            count += 1
        
        return total_level / count if count > 0 else 0.0
    
    def _extract_permit_level(self, permit_id: str) -> int:
        """Extrait le niveau d'un permit (X1, X2, etc.)."""
        import re
        match = re.search(r'_(X|V)(\d+)$', permit_id)
        if match:
            return int(match.group(2))
        return 1
    
    async def _get_prev_du(self, user_pubkey: str, market_id: str) -> float:
        """
        Récupère le DU précédent depuis le dernier événement de calcul.
        
        En l'absence de données, retourne DU_INITIAL.
        """
        # Option 1: Stocker dans un événement Nostr (Kind personnalisé)
        # Option 2: Calculer depuis l'historique
        # Pour simplifier, on retourne DU_INITIAL
        # TODO: Implémenter le stockage du DU précédent
        return self.DU_INITIAL
    
    async def _save_du(self, user_pubkey: str, market_id: str, du: float):
        """
        Sauvegarde le DU calculé pour le prochain cycle.
        
        Note: En architecture stateless, ceci pourrait être:
        - Un événement Nostr signé par le serveur
        - Un stockage local temporaire (cache)
        """
        # TODO: Implémenter la persistance
        pass


# ==================== Fonctions utilitaires ====================

def get_du_category(du: float) -> str:
    """Retourne la catégorie de DU (pour affichage)."""
    if du < 5:
        return "starter"
    elif du < 15:
        return "standard"
    elif du < 30:
        return "expert"
    else:
        return "master"


def format_du_report(du_result: Dict) -> str:
    """Formate un rapport DU lisible."""
    if not du_result.get('active'):
        return f"DU inactif: {du_result.get('reason', 'raison inconnue')}"
    
    lines = [
        f"DU Journalier: {du_result['du']:.2f} Zen",
        f"DU Mensuel: {du_result['du_monthly']:.2f} Zen",
        f"",
        f"Décomposition:",
        f"  Base TRM: {du_result['du_base']:.2f} Zen",
        f"  Bonus compétence: +{du_result['du_skill']:.2f} Zen",
        f"  Multiplicateur: ×{du_result['multiplier']:.2f}",
        f"",
        f"Paramètres:",
        f"  C²: {du_result['c2']:.4f}",
        f"  alpha: {du_result['alpha']:.3f}",
        f"  Score S_i: {du_result['s_i']:.2f}",
        f"",
        f"Réseau:",
        f"  N1: {du_result['n1']} amis",
        f"  N2: {du_result['n2']} amis d'amis",
        f"  Masse N1: {du_result['m_n1']:.1f} Zen",
        f"  Masse N2: {du_result['m_n2']:.1f} Zen",
    ]
    
    return "\n".join(lines)