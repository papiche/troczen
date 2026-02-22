#!/usr/bin/env python3
"""
TrocZen ORACLE Service - Stateless Implementation

Service de certification par pairs (WoTx2) sans base de données locale.
Le relai Nostr (Strfry) est la source de vérité.

Workflow:
1. Réception attestation (30502)
2. Vérification si VC (30503) existe déjà
3. Comptage des attestations pour la demande
4. Si seuil atteint: émission du VC (30503)

Auteur: TrocZen Team
License: AGPL-3.0
"""

import json
import time
import hashlib
import re
from typing import Dict, List, Optional, Set
from datetime import datetime

# Import du client Nostr existant
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from nostr_client import NostrClient

# Logging simple
def log(level: str, message: str):
    """Log avec timestamp et niveau."""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [ORACLE] [{level}] {message}")


class OracleService:
    """
    Service ORACLE stateless pour la gestion des Verifiable Credentials.
    
    Architecture:
    - Pas de base de données locale
    - Interroge le relai Nostr pour l'état de la toile de confiance
    - Publie les credentials directement sur Nostr
    """
    
    # Seuils d'attestation par défaut
    DEFAULT_THRESHOLDS = {
        'official': 2,      # Permits officiels: N+1 attestations
        'wotx2': 1,         # WoTx2 auto-proclamé: 1 attestation suffit
    }
    
    # Durée de validité des credentials (en jours)
    CREDENTIAL_VALIDITY_DAYS = 365
    
    def __init__(self, relay_url: str, oracle_nsec_hex: str):
        """
        Initialise le service ORACLE.
        
        Args:
            relay_url: URL du relai Nostr (ex: ws://127.0.0.1:7777)
            oracle_nsec_hex: Clé privée de l'Oracle en hex (pour signer les VC)
        """
        self.relay_url = relay_url
        self.oracle_nsec_hex = oracle_nsec_hex
        self.client = NostrClient(relay_url=relay_url)
        
        # Dérivation de la pubkey Oracle
        # Note: Dans une implémentation complète, utiliser nostr-protocol
        self.oracle_pubkey = self._derive_pubkey(oracle_nsec_hex)
        
        log("INFO", f"Oracle initialisé - Pubkey: {self.oracle_pubkey[:16]}...")
    
    def _derive_pubkey(self, nsec_hex: str) -> str:
        """
        Dérive la pubkey depuis la nsec.
        
        Note: Implémentation simplifiée. En production, utiliser
        la bibliothèque nostr-protocol ou secp256k1.
        """
        try:
            # Tenter d'importer la bibliothèque nostr
            from nostr_protocol import PrivateKey
            pk = PrivateKey(bytes.fromhex(nsec_hex))
            return pk.public_key.hex()
        except ImportError:
            # Fallback: hash de la nsec (non cryptographique, pour dev uniquement)
            log("WARN", "nostr-protocol non disponible, utilisation d'un dérivation simplifiée")
            return hashlib.sha256(bytes.fromhex(nsec_hex)).hexdigest()[:64]
    
    async def process_attestation(self, attestation_event: Dict, websocket) -> bool:
        """
        Traite une attestation (Kind 30502) et émet un VC si le seuil est atteint.
        
        Args:
            attestation_event: Événement Nostr Kind 30502
            websocket: Connexion WebSocket pour publier le VC
            
        Returns:
            True si un VC a été émis, False sinon
        """
        tags = self._parse_tags(attestation_event.get('tags', []))
        
        # Extraire l'ID de la demande (tag 'e' ou 'a')
        request_id = tags.get('e') or tags.get('a')
        if not request_id:
            log("WARN", "Attestation sans référence à une demande")
            return False
        
        attestor_pubkey = attestation_event['pubkey']
        log("INFO", f"Traitement attestation pour demande {request_id[:16]}...")
        
        # Connexion au relai pour les requêtes
        await self.client.connect()
        
        try:
            # 1. Vérifier si un VC existe déjà pour cette demande
            existing_vc = await self._check_existing_credential(request_id)
            if existing_vc:
                log("INFO", f"VC déjà émis pour cette demande")
                return False
            
            # 2. Récupérer la demande originale (Kind 30501)
            request_event = await self._get_request_event(request_id)
            if not request_event:
                log("WARN", f"Demande {request_id[:16]} non trouvée")
                return False
            
            request_tags = self._parse_tags(request_event.get('tags', []))
            requester_pubkey = request_event['pubkey']
            permit_id = request_tags.get('permit_id', '')
            
            # 3. Vérifier que l'attestateur n'est pas le demandeur
            if attestor_pubkey == requester_pubkey:
                log("WARN", "Auto-attestation non autorisée")
                return False
            
            # 4. Vérifier que l'attestateur possède le credential correspondant
            # (pour les permits de niveau > X1)
            if not await self._verify_attestor_qualification(attestor_pubkey, permit_id):
                log("WARN", f"Attestateur {attestor_pubkey[:16]} non qualifié")
                return False
            
            # 5. Compter toutes les attestations uniques pour cette demande
            all_attestations = await self._get_all_attestations(request_id)
            unique_attestors = set(e['pubkey'] for e in all_attestations)
            unique_attestors.add(attestor_pubkey)  # Inclure la nouvelle
            
            log("INFO", f"Attestations uniques: {len(unique_attestors)}")
            
            # 6. Déterminer le seuil requis
            threshold = self._get_required_threshold(permit_id)
            
            # 7. Si seuil atteint, émettre le credential
            if len(unique_attestors) >= threshold:
                log("INFO", f"Seuil atteint ({len(unique_attestors)}/{threshold}) - Émission du VC")
                return await self._issue_credential(
                    request_event, 
                    list(unique_attestors),
                    websocket
                )
            else:
                log("INFO", f"Seuil non atteint ({len(unique_attestors)}/{threshold})")
                return False
                
        finally:
            await self.client.disconnect()
    
    async def _check_existing_credential(self, request_id: str) -> Optional[Dict]:
        """Vérifie si un VC existe déjà pour cette demande."""
        events = await self.client.query_events([{
            "kinds": [30503],
            "authors": [self.oracle_pubkey],
            "#e": [request_id]
        }])
        return events[0] if events else None
    
    async def _get_request_event(self, request_id: str) -> Optional[Dict]:
        """Récupère l'événement de demande (Kind 30501)."""
        # D'abord essayer par ID d'événement
        events = await self.client.query_events([{
            "ids": [request_id]
        }])
        
        if events:
            return events[0]
        
        # Sinon chercher par tag 'd' (NIP-33)
        events = await self.client.query_events([{
            "kinds": [30501],
            "#d": [request_id]
        }])
        
        return events[0] if events else None
    
    async def _verify_attestor_qualification(self, attestor_pubkey: str, permit_id: str) -> bool:
        """
        Vérifie que l'attestateur possède le credential pour attester.
        
        Pour X1: Tout le monde peut attester (bootstrap)
        Pour X2+: L'attestateur doit avoir le niveau précédent
        """
        # Extraire le niveau du permit
        level = self._extract_permit_level(permit_id)
        
        if level <= 1:
            # X1: Bootstrap - tout le monde peut attester
            return True
        
        # Pour X2+: vérifier que l'attestateur a le niveau précédent
        parent_permit = self._get_parent_permit(permit_id)
        
        events = await self.client.query_events([{
            "kinds": [30503],
            "authors": [self.oracle_pubkey],
            "#p": [attestor_pubkey],
            "#permit_id": [parent_permit]
        }])
        
        return len(events) > 0
    
    async def _get_all_attestations(self, request_id: str) -> List[Dict]:
        """Récupère toutes les attestations pour une demande."""
        return await self.client.query_events([{
            "kinds": [30502],
            "#e": [request_id]
        }])
    
    def _get_required_threshold(self, permit_id: str) -> int:
        """
        Détermine le seuil d'attestations requis.
        
        - Permits officiels (PERMIT_*_V1): N+1
        - WoTx2 auto-proclamés (PERMIT_*_X1): 1
        """
        if '_V' in permit_id:
            # Permit officiel
            return self.DEFAULT_THRESHOLDS['official']
        else:
            # WoTx2
            return self.DEFAULT_THRESHOLDS['wotx2']
    
    async def _issue_credential(
        self, 
        request_event: Dict, 
        attestors: List[str],
        websocket
    ) -> bool:
        """
        Émet un Verifiable Credential (Kind 30503).
        
        Args:
            request_event: Événement de demande original
            attestors: Liste des pubkeys des attestateurs
            websocket: Connexion pour publication
            
        Returns:
            True si publié avec succès
        """
        request_tags = self._parse_tags(request_event.get('tags', []))
        requester_pubkey = request_event['pubkey']
        permit_id = request_tags.get('permit_id', '')
        request_id = request_event.get('id', request_tags.get('d', ''))
        
        # Calculer la date d'expiration
        issued_at = int(time.time())
        expires_at = issued_at + (self.CREDENTIAL_VALIDITY_DAYS * 86400)
        
        # Construire le contenu du VC (format W3C)
        vc_content = {
            "@context": [
                "https://www.w3.org/2018/credentials/v1",
                "https://troczen.org/credentials/v1"
            ],
            "type": ["VerifiableCredential", "TrocZenPermitCredential"],
            "issuer": f"did:nostr:{self.oracle_pubkey}",
            "issuanceDate": datetime.utcfromtimestamp(issued_at).isoformat() + "Z",
            "expirationDate": datetime.utcfromtimestamp(expires_at).isoformat() + "Z",
            "credentialSubject": {
                "id": f"did:nostr:{requester_pubkey}",
                "permit_id": permit_id,
                "level": self._extract_permit_level(permit_id),
                "attestations_count": len(attestors)
            }
        }
        
        # Construire l'événement Nostr
        vc_event = {
            "kind": 30503,
            "pubkey": self.oracle_pubkey,
            "created_at": issued_at,
            "tags": [
                ["d", f"vc_{requester_pubkey}_{permit_id}_{issued_at}"],
                ["e", request_id],
                ["p", requester_pubkey],
                ["permit_id", permit_id],
                ["expires", str(expires_at)],
                ["attestations", str(len(attestors))]
            ],
            "content": json.dumps(vc_content)
        }
        
        # Signer l'événement
        signed_event = await self._sign_event(vc_event)
        
        # Publier sur le relai
        try:
            await websocket.send(json.dumps(["EVENT", signed_event]))
            log("INFO", f" Credential {permit_id} émis pour {requester_pubkey[:16]}!")
            return True
        except Exception as e:
            log("ERROR", f"Erreur publication VC: {e}")
            return False
    
    async def _sign_event(self, event: Dict) -> Dict:
        """
        Signe un événement Nostr avec la clé de l'Oracle.
        
        Note: Implémentation simplifiée. En production, utiliser
        nostr-protocol pour la signature Schnorr.
        """
        try:
            from nostr_protocol import Event, PrivateKey, Keys
            
            # Créer l'événement
            pk = PrivateKey(bytes.fromhex(self.oracle_nsec_hex))
            
            # Construire l'événement pour signature
            nostr_event = Event(
                kind=event['kind'],
                pubkey=event['pubkey'],
                created_at=event['created_at'],
                tags=event['tags'],
                content=event['content']
            )
            
            # Signer
            pk.sign_event(nostr_event)
            
            # Retourner l'événement signé
            return {
                "id": nostr_event.id,
                "pubkey": nostr_event.pubkey,
                "created_at": nostr_event.created_at,
                "kind": nostr_event.kind,
                "tags": nostr_event.tags,
                "content": nostr_event.content,
                "sig": nostr_event.signature
            }
            
        except ImportError:
            # Fallback pour le développement (non sécurisé)
            log("WARN", "nostr-protocol non disponible - signature factice")
            
            # Calculer l'ID de l'événement
            serialized = json.dumps([
                0,
                event['pubkey'],
                event['created_at'],
                event['kind'],
                event['tags'],
                event['content']
            ], separators=(',', ':'))
            event_id = hashlib.sha256(serialized.encode()).hexdigest()
            
            event['id'] = event_id
            event['sig'] = "MOCK_SIGNATURE_" + hashlib.sha256(
                (event_id + self.oracle_nsec_hex).encode()
            ).hexdigest()
            
            return event
    
    def _parse_tags(self, tags: List) -> Dict[str, str]:
        """Parse les tags Nostr en dictionnaire."""
        result = {}
        for tag in tags:
            if len(tag) >= 2:
                result[tag[0]] = tag[1]
        return result
    
    def _extract_permit_level(self, permit_id: str) -> int:
        """Extrait le niveau X du permit (X1, X2, etc.)."""
        match = re.search(r'_X(\d+)$', permit_id)
        if match:
            return int(match.group(1))
        
        # Permits officiels (V1, V2...)
        match = re.search(r'_V(\d+)$', permit_id)
        if match:
            return int(match.group(1))
        
        return 1  # Niveau par défaut
    
    def _get_parent_permit(self, permit_id: str) -> str:
        """Obtient l'ID du permit parent (X2 -> X1)."""
        level = self._extract_permit_level(permit_id)
        if level <= 1:
            return permit_id
        
        # Remplacer X(n) par X(n-1)
        return re.sub(rf'_X{level}$', f'_X{level-1}', permit_id)
    
    # ==================== API Methods ====================
    
    async def get_permit_definitions(self, market: str = None) -> List[Dict]:
        """Récupère toutes les définitions de permits (Kind 30500)."""
        await self.client.connect()
        try:
            filters = {"kinds": [30500]}
            if market:
                filters["#market"] = [market]
            
            events = await self.client.query_events([filters])
            return [self._parse_permit_definition(e) for e in events]
        finally:
            await self.client.disconnect()
    
    def _parse_permit_definition(self, event: Dict) -> Dict:
        """Parse un événement de définition de permit."""
        tags = self._parse_tags(event.get('tags', []))
        content = json.loads(event.get('content', '{}'))
        
        return {
            "permit_id": tags.get('d', ''),
            "name": content.get('name', ''),
            "description": content.get('description', ''),
            "category": content.get('category', 'skill'),
            "level": self._extract_permit_level(tags.get('d', '')),
            "required_attestations": content.get('required_attestations', 1),
            "skills": content.get('skills', []),
            "created_at": event.get('created_at', 0),
            "created_by": event.get('pubkey', '')
        }
    
    async def get_credentials(self, npub: str) -> List[Dict]:
        """Récupère les credentials d'un utilisateur."""
        await self.client.connect()
        try:
            events = await self.client.query_events([{
                "kinds": [30503],
                "authors": [self.oracle_pubkey],
                "#p": [npub]
            }])
            return [self._parse_credential(e) for e in events]
        finally:
            await self.client.disconnect()
    
    def _parse_credential(self, event: Dict) -> Dict:
        """Parse un événement de credential."""
        tags = self._parse_tags(event.get('tags', []))
        content = json.loads(event.get('content', '{}'))
        
        return {
            "credential_id": tags.get('d', ''),
            "permit_id": tags.get('permit_id', ''),
            "holder": tags.get('p', ''),
            "issued_at": event.get('created_at', 0),
            "expires_at": int(tags.get('expires', 0)),
            "content": content
        }
    
    async def get_stats(self) -> Dict:
        """Récupère les statistiques Oracle."""
        await self.client.connect()
        try:
            # Compter les permits
            permits = await self.client.query_events([{"kinds": [30500]}])
            
            # Compter les demandes
            requests = await self.client.query_events([{"kinds": [30501]}])
            
            # Compter les attestations
            attestations = await self.client.query_events([{"kinds": [30502]}])
            
            # Compter les credentials
            credentials = await self.client.query_events([
                {"kinds": [30503], "authors": [self.oracle_pubkey]}
            ])
            
            return {
                "permits_count": len(permits),
                "requests_count": len(requests),
                "attestations_count": len(attestations),
                "credentials_count": len(credentials),
                "oracle_pubkey": self.oracle_pubkey
            }
        finally:
            await self.client.disconnect()