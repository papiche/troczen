#!/usr/bin/env python3
"""
TrocZen Credential Generator

Génération de Verifiable Credentials (Kind 30503) au format W3C.

Format W3C Verifiable Credentials:
- @context: Contextes JSON-LD
- type: Types de credential
- issuer: Émetteur (Oracle)
- issuanceDate: Date d'émission
- expirationDate: Date d'expiration
- credentialSubject: Sujet du credential
- proof: Preuve cryptographique (signature Nostr)
"""

import json
import time
import hashlib
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import re


def log(level: str, message: str):
    """Log avec timestamp et niveau."""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [CREDENTIAL] [{level}] {message}")


class CredentialGenerator:
    """
    Générateur de Verifiable Credentials pour TrocZen.
    
    Génère des credentials au format W3C VC Data Model,
    publiés sur Nostr via Kind 30503.
    """
    
    # Contextes JSON-LD standards
    DEFAULT_CONTEXTS = [
        "https://www.w3.org/2018/credentials/v1",
        "https://troczen.org/credentials/v1"
    ]
    
    # Types de credentials
    DEFAULT_TYPES = ["VerifiableCredential", "TrocZenPermitCredential"]
    
    # Durée de validité par défaut (jours)
    DEFAULT_VALIDITY_DAYS = 365
    
    # Durée de validité par type de permit
    VALIDITY_BY_TYPE = {
        'skill': 365,       # Compétences: 1 an
        'license': 1825,    # Licences: 5 ans
        'authority': 3650,  # Autorités: 10 ans
    }
    
    def __init__(self, oracle_pubkey: str, oracle_nsec_hex: str):
        """
        Initialise le générateur de credentials.
        
        Args:
            oracle_pubkey: Pubkey de l'Oracle (émetteur)
            oracle_nsec_hex: Clé privée de l'Oracle pour signature
        """
        self.oracle_pubkey = oracle_pubkey
        self.oracle_nsec_hex = oracle_nsec_hex
    
    def generate(
        self,
        holder_pubkey: str,
        permit_id: str,
        request_id: str,
        attestors: List[str],
        skills: List[str] = None,
        validity_days: int = None
    ) -> Dict:
        """
        Génère un Verifiable Credential complet.
        
        Args:
            holder_pubkey: Pubkey du titulaire
            permit_id: ID du permit (ex: PERMIT_MARAICHAGE_X2)
            request_id: ID de la demande (Kind 30501)
            attestors: Liste des pubkeys des attestateurs
            skills: Compétences certifiées
            validity_days: Durée de validité (optionnel)
            
        Returns:
            Dictionnaire avec le VC et l'événement Nostr
        """
        # Dates
        issued_at = int(time.time())
        
        # Déterminer la durée de validité
        if validity_days is None:
            validity_days = self._get_validity_for_permit(permit_id)
        
        expires_at = issued_at + (validity_days * 86400)
        
        # Niveau du permit
        level = self._extract_level(permit_id)
        
        # Construire le contenu W3C VC
        vc_content = {
            "@context": self.DEFAULT_CONTEXTS,
            "type": self.DEFAULT_TYPES,
            "issuer": {
                "id": f"did:nostr:{self.oracle_pubkey}",
                "name": "TrocZen Oracle"
            },
            "issuanceDate": self._timestamp_to_iso(issued_at),
            "expirationDate": self._timestamp_to_iso(expires_at),
            "credentialSubject": {
                "id": f"did:nostr:{holder_pubkey}",
                "permit": {
                    "id": permit_id,
                    "level": level,
                    "name": self._permit_to_name(permit_id)
                },
                "skills": skills or [],
                "attestations": {
                    "count": len(attestors),
                    "attestors": [f"did:nostr:{a}" for a in attestors]
                }
            }
        }
        
        # Construire l'événement Nostr (Kind 30503)
        nostr_event = {
            "kind": 30503,
            "pubkey": self.oracle_pubkey,
            "created_at": issued_at,
            "tags": [
                ["d", self._generate_credential_id(holder_pubkey, permit_id, issued_at)],
                ["e", request_id],
                ["p", holder_pubkey],
                ["permit_id", permit_id],
                ["level", str(level)],
                ["expires", str(expires_at)],
                ["attestations", str(len(attestors))]
            ],
            "content": json.dumps(vc_content, separators=(',', ':'))
        }
        
        # Ajouter les attestateurs en tags
        for attestor in attestors:
            nostr_event["tags"].append(["attestor", attestor])
        
        # Ajouter les compétences en tags
        for skill in (skills or []):
            nostr_event["tags"].append(["skill", skill])
        
        return {
            "vc": vc_content,
            "event": nostr_event,
            "credential_id": nostr_event["tags"][0][1]
        }
    
    def generate_badge_event(
        self,
        holder_pubkey: str,
        permit_id: str,
        credential_id: str,
        badge_image_url: str = None
    ) -> Dict:
        """
        Génère un événement de badge NIP-58 pour le credential.
        
        Le badge est une représentation visuelle du credential obtenu.
        
        Args:
            holder_pubkey: Pubkey du titulaire
            permit_id: ID du permit
            credential_id: ID du credential
            badge_image_url: URL de l'image du badge (optionnel)
            
        Returns:
            Événement Nostr Kind 8 (Badge definition) ou Kind 30008 (Badge award)
        """
        level = self._extract_level(permit_id)
        badge_name = self._permit_to_name(permit_id)
        
        # Badge definition (Kind 30008) - publié une fois par type de permit
        badge_definition = {
            "kind": 30008,
            "pubkey": self.oracle_pubkey,
            "created_at": int(time.time()),
            "tags": [
                ["d", f"badge_{permit_id}"],
                ["name", badge_name],
                ["description", f"Badge de maîtrise - Niveau X{level}"],
                ["image", badge_image_url or f"https://troczen.org/badges/{permit_id}.png"],
                ["thumb", badge_image_url or f"https://troczen.org/badges/{permit_id}_thumb.png"]
            ],
            "content": ""
        }
        
        # Badge award (Kind 8) - publié pour chaque obtention
        badge_award = {
            "kind": 8,
            "pubkey": self.oracle_pubkey,
            "created_at": int(time.time()),
            "tags": [
                ["a", f"30008:{self.oracle_pubkey}:badge_{permit_id}"],
                ["p", holder_pubkey],
                ["e", credential_id]
            ],
            "content": f"Félicitations ! Vous avez obtenu le badge {badge_name}"
        }
        
        return {
            "definition": badge_definition,
            "award": badge_award
        }
    
    def _get_validity_for_permit(self, permit_id: str) -> int:
        """Détermine la durée de validité selon le type de permit."""
        # Détecter le type depuis l'ID
        if 'LICENSE' in permit_id or 'DRIVER' in permit_id:
            return self.VALIDITY_BY_TYPE['license']
        elif 'AUTHORITY' in permit_id or 'ADMIN' in permit_id:
            return self.VALIDITY_BY_TYPE['authority']
        else:
            return self.VALIDITY_BY_TYPE['skill']
    
    def _extract_level(self, permit_id: str) -> int:
        """Extrait le niveau du permit."""
        match = re.search(r'_(X|V)(\d+)$', permit_id)
        if match:
            return int(match.group(2))
        return 1
    
    def _permit_to_name(self, permit_id: str) -> str:
        """Convertit un ID de permit en nom lisible."""
        # Retirer le préfixe et le niveau
        name = re.sub(r'^PERMIT_', '', permit_id)
        name = re.sub(r'_(X|V)\d+$', '', name)
        # Convertir en titre
        return name.replace('_', ' ').title()
    
    def _generate_credential_id(self, holder: str, permit: str, issued_at: int) -> str:
        """Génère un ID unique pour le credential."""
        data = f"{holder}:{permit}:{issued_at}"
        return "vc_" + hashlib.sha256(data.encode()).hexdigest()[:16]
    
    def _timestamp_to_iso(self, ts: int) -> str:
        """Convertit un timestamp Unix en ISO 8601."""
        return datetime.utcfromtimestamp(ts).strftime('%Y-%m-%dT%H:%M:%SZ')
    
    @staticmethod
    def parse_credential_event(event: Dict) -> Dict:
        """Parse un événement de credential (Kind 30503)."""
        tags = {t[0]: t[1] for t in event.get('tags', []) if len(t) >= 2}
        attestors = [t[1] for t in event.get('tags', []) if len(t) >= 2 and t[0] == 'attestor']
        skills = [t[1] for t in event.get('tags', []) if len(t) >= 2 and t[0] == 'skill']
        
        content = json.loads(event.get('content', '{}'))
        
        return {
            "credential_id": tags.get('d', ''),
            "permit_id": tags.get('permit_id', ''),
            "level": int(tags.get('level', 1)),
            "holder": tags.get('p', ''),
            "issuer": event.get('pubkey', ''),
            "request_id": tags.get('e', ''),
            "expires_at": int(tags.get('expires', 0)),
            "issued_at": event.get('created_at', 0),
            "attestors": attestors,
            "attestations_count": int(tags.get('attestations', 0)),
            "skills": skills,
            "vc_content": content,
            "is_valid": int(time.time()) < int(tags.get('expires', 0))
        }
    
    @staticmethod
    def is_credential_valid(credential: Dict) -> bool:
        """Vérifie si un credential est encore valide (non expiré)."""
        expires_at = credential.get('expires_at', 0)
        return time.time() < expires_at
    
    @staticmethod
    def get_days_until_expiry(credential: Dict) -> int:
        """Retourne le nombre de jours avant expiration."""
        expires_at = credential.get('expires_at', 0)
        remaining = expires_at - time.time()
        return max(0, int(remaining / 86400))


# ==================== Fonctions utilitaires ====================

def build_credential_proof(event: Dict, signature: str) -> Dict:
    """
    Construit la preuve cryptographique pour un VC.
    
    Format conforme au W3C VC Data Model.
    """
    return {
        "type": "NostrSignature2024",
        "created": datetime.utcfromtimestamp(event['created_at']).isoformat() + "Z",
        "proofPurpose": "assertionMethod",
        "verificationMethod": f"did:nostr:{event['pubkey']}#key-1",
        "proofValue": signature
    }


def verify_credential_proof(credential: Dict, pubkey: str) -> bool:
    """
    Vérifie la signature d'un credential.
    
    Note: Implémentation simplifiée. En production, utiliser
    la bibliothèque nostr-protocol pour la vérification Schnorr.
    """
    # TODO: Implémenter la vérification complète
    # Pour l'instant, on vérifie juste que l'émetteur correspond
    return credential.get('issuer', '').endswith(pubkey) or credential.get('pubkey') == pubkey