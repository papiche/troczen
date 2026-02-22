#!/usr/bin/env python3
"""
TrocZen Permit Manager

Gestion des permits (définitions et progression WoTx2).

Kinds gérés:
- 30500: Définition de permit (création)
- 5: Suppression de permit
"""

import json
import time
import re
from typing import Dict, List, Optional
from datetime import datetime

# Logging simple
def log(level: str, message: str):
    """Log avec timestamp et niveau."""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [PERMIT] [{level}] {message}")


class PermitManager:
    """
    Gestionnaire de permits pour le système WoTx2.
    
    Fonctionnalités:
    - Création de permits (officiels et auto-proclamés)
    - Progression automatique X1 -> X2 -> X3...
    - Validation des IDs de permit
    """
    
    # Types de permits
    TYPE_OFFICIAL = "official"      # Créés par l'admin (UPLANETNAME_G1)
    TYPE_WOTX2 = "wotx2"           # Auto-proclamés par les utilisateurs
    
    # Pattern d'ID de permit
    PERMIT_ID_PATTERN = re.compile(r'^PERMIT_[A-Z0-9_]+(_X\d+|_V\d+)$')
    
    def __init__(self, relay_url: str, oracle_nsec_hex: str):
        """Initialise le gestionnaire de permits."""
        self.relay_url = relay_url
        self.oracle_nsec_hex = oracle_nsec_hex
    
    @staticmethod
    def is_valid_permit_id(permit_id: str) -> bool:
        """Vérifie si un ID de permit est valide."""
        return bool(PermitManager.PERMIT_ID_PATTERN.match(permit_id))
    
    @staticmethod
    def extract_level(permit_id: str) -> int:
        """Extrait le niveau du permit (X1, X2, V1, etc.)."""
        # WoTx2: X1, X2, X3...
        match = re.search(r'_X(\d+)$', permit_id)
        if match:
            return int(match.group(1))
        
        # Officiel: V1, V2...
        match = re.search(r'_V(\d+)$', permit_id)
        if match:
            return int(match.group(1))
        
        return 1
    
    @staticmethod
    def extract_base_name(permit_id: str) -> str:
        """Extrait le nom de base du permit (sans le niveau)."""
        # Retirer le suffixe _Xn ou _Vn
        return re.sub(r'_(X|V)\d+$', '', permit_id)
    
    @staticmethod
    def get_next_level_id(permit_id: str) -> str:
        """
        Génère l'ID du permit du niveau suivant.
        
        Exemples:
        - PERMIT_MARAICHAGE_X1 -> PERMIT_MARAICHAGE_X2
        - PERMIT_MARAICHAGE_X2 -> PERMIT_MARAICHAGE_X3
        """
        base = PermitManager.extract_base_name(permit_id)
        level = PermitManager.extract_level(permit_id)
        
        # Toujours utiliser le format X pour la progression
        return f"{base}_X{level + 1}"
    
    @staticmethod
    def get_parent_id(permit_id: str) -> Optional[str]:
        """
        Génère l'ID du permit parent.
        
        Exemples:
        - PERMIT_MARAICHAGE_X2 -> PERMIT_MARAICHAGE_X1
        - PERMIT_MARAICHAGE_X1 -> None
        """
        level = PermitManager.extract_level(permit_id)
        
        if level <= 1:
            return None
        
        base = PermitManager.extract_base_name(permit_id)
        return f"{base}_X{level - 1}"
    
    @staticmethod
    def get_permit_type(permit_id: str) -> str:
        """Détermine le type de permit (official ou wotx2)."""
        if '_V' in permit_id:
            return PermitManager.TYPE_OFFICIAL
        return PermitManager.TYPE_WOTX2
    
    @staticmethod
    def get_required_attestations(permit_id: str) -> int:
        """
        Détermine le nombre d'attestations requises.
        
        - Permits officiels: N+1 (où N est le nombre de maîtres existants)
        - WoTx2 X1: 1 (bootstrap)
        - WoTx2 X2+: 1 (un maître du niveau précédent suffit)
        """
        permit_type = PermitManager.get_permit_type(permit_id)
        level = PermitManager.extract_level(permit_id)
        
        if permit_type == PermitManager.TYPE_OFFICIAL:
            # Pour les officiels, le seuil est défini dans la définition
            # Par défaut: 2 (N+1 avec N=1 au bootstrap)
            return 2
        
        # WoTx2: 1 seule attestation suffit
        return 1
    
    def build_permit_definition_event(
        self,
        permit_id: str,
        name: str,
        description: str,
        skills: List[str],
        category: str = "skill",
        required_attestations: int = 1,
        parent_permit: Optional[str] = None,
        market: Optional[str] = None
    ) -> Dict:
        """
        Construit un événement de définition de permit (Kind 30500).
        
        Args:
            permit_id: ID unique du permit (ex: PERMIT_MARAICHAGE_X1)
            name: Nom lisible du permit
            description: Description détaillée
            skills: Liste des compétences associées
            category: Catégorie (skill, license, authority)
            required_attestations: Nombre d'attestations requises
            parent_permit: ID du permit parent (pour X2+)
            market: Marché associé (optionnel)
            
        Returns:
            Événement Nostr non signé
        """
        tags = [
            ["d", permit_id],
            ["name", name],
            ["category", category],
        ]
        
        if parent_permit:
            tags.append(["parent", parent_permit])
        
        if market:
            tags.append(["market", market])
        
        for skill in skills:
            tags.append(["skill", skill])
        
        content = {
            "name": name,
            "description": description,
            "category": category,
            "skills": skills,
            "required_attestations": required_attestations,
            "level": self.extract_level(permit_id),
            "type": self.get_permit_type(permit_id)
        }
        
        return {
            "kind": 30500,
            "created_at": int(time.time()),
            "tags": tags,
            "content": json.dumps(content)
        }
    
    def build_next_level_permit(
        self,
        current_permit_id: str,
        discovered_skills: List[str] = None
    ) -> Dict:
        """
        Construit automatiquement le permit du niveau suivant.
        
        Cette méthode est appelée quand un utilisateur obtient un credential X(n)
        pour créer automatiquement le permit X(n+1) s'il n'existe pas.
        
        Args:
            current_permit_id: ID du permit actuel (ex: PERMIT_MARAICHAGE_X1)
            discovered_skills: Compétences découvertes lors des attestations
            
        Returns:
            Événement de définition pour le niveau suivant
        """
        next_id = self.get_next_level_id(current_permit_id)
        base_name = self.extract_base_name(current_permit_id)
        current_level = self.extract_level(current_permit_id)
        
        # Nom lisible
        name = f"{base_name.replace('PERMIT_', '').replace('_', ' ')} - Niveau X{current_level + 1}"
        
        # Description
        description = f"Maîtrise avancée - Niveau {current_level + 1}"
        
        # Compétences: hériter des compétences découvertes
        skills = discovered_skills or []
        
        return self.build_permit_definition_event(
            permit_id=next_id,
            name=name,
            description=description,
            skills=skills,
            category="skill",
            required_attestations=1,  # WoTx2: 1 attestation d'un maître X(n)
            parent_permit=current_permit_id
        )
    
    @staticmethod
    def parse_permit_event(event: Dict) -> Dict:
        """Parse un événement de définition de permit."""
        tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
        skills = [t[1] for t in event.get('tags', []) if len(t) >= 2 and t[0] == 'skill']
        content = json.loads(event.get('content', '{}'))
        
        return {
            "permit_id": tags.get('d', ''),
            "name": tags.get('name', content.get('name', '')),
            "description": content.get('description', ''),
            "category": tags.get('category', content.get('category', 'skill')),
            "level": PermitManager.extract_level(tags.get('d', '')),
            "type": PermitManager.get_permit_type(tags.get('d', '')),
            "required_attestations": content.get('required_attestations', 1),
            "skills": skills,
            "parent_permit": tags.get('parent'),
            "market": tags.get('market'),
            "created_at": event.get('created_at', 0),
            "created_by": event.get('pubkey', '')
        }


# ==================== Fonctions utilitaires ====================

def generate_permit_id(name: str, level: int = 1, is_official: bool = False) -> str:
    """
    Génère un ID de permit depuis un nom.
    
    Args:
        name: Nom du permit (ex: "Maraîchage", "Permis de conduire")
        level: Niveau (1, 2, 3...)
        is_official: True pour un permit officiel (V), False pour WoTx2 (X)
        
    Returns:
        ID du permit (ex: PERMIT_MARAICHAGE_X1)
    """
    # Normaliser le nom
    normalized = name.upper().replace(' ', '_').replace('-', '_')
    normalized = re.sub(r'[^A-Z0-9_]', '', normalized)
    
    suffix = f"_V{level}" if is_official else f"_X{level}"
    
    return f"PERMIT_{normalized}{suffix}"


def get_permit_display_name(permit_id: str) -> str:
    """Obtient un nom d'affichage lisible pour un permit."""
    base = PermitManager.extract_base_name(permit_id)
    level = PermitManager.extract_level(permit_id)
    permit_type = PermitManager.get_permit_type(permit_id)
    
    # Convertir le nom de base en lisible
    readable = base.replace('PERMIT_', '').replace('_', ' ').title()
    
    # Ajouter le niveau
    level_str = f"X{level}" if permit_type == PermitManager.TYPE_WOTX2 else f"V{level}"
    
    return f"{readable} (Niveau {level_str})"