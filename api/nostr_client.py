#!/usr/bin/env python3
"""
Client Nostr pour TrocZen
Connecté au relai Strfry local (ws://127.0.0.1:7777)
"""

import asyncio
import json
import websockets
import ssl
import os
from datetime import datetime
from typing import List, Dict, Optional

# Configuration de pagination (peut être surchargée par variables d'environnement)
DEFAULT_PAGE_SIZE = int(os.getenv('NOSTR_PAGE_SIZE', '500'))  # Taille de page par défaut
MAX_TOTAL_RESULTS = int(os.getenv('NOSTR_MAX_RESULTS', '10000'))  # Limite totale pour éviter les abus

class NostrClient:
    """Client Nostr pour interroger le relai Strfry local"""
    
    def __init__(self, relay_url: str = "ws://127.0.0.1:7777"):
        """
        Initialise le client Nostr
        
        Args:
            relay_url: URL du relai Strfry (ws://127.0.0.1:7777)
        """
        self.relay_url = relay_url
        self.websocket = None
        
    async def connect(self):
        """Se connecter au relai Nostr"""
        try:
            print(f'🌻 [NostrClient] Connexion au relai: {self.relay_url}')
            self.websocket = await websockets.connect(self.relay_url)
            print(f"✅ [NostrClient] Connecté au relai Nostr: {self.relay_url}")
            return True
        except Exception as e:
            print(f"❌ [NostrClient] Erreur de connexion au relai {self.relay_url}: {e}")
            return False
    
    async def disconnect(self):
        """Déconnecter du relai"""
        if self.websocket:
            await self.websocket.close()
            self.websocket = None
            print("✅ [NostrClient] Déconnecté du relai Nostr")
    
    async def query_events(self, filters: List[Dict]) -> List[Dict]:
        """
        Interroger les events depuis le relai
        
        Args:
            filters: Liste des filtres Nostr
            
        Returns:
            Liste des events trouvés
        """
        if not self.websocket:
            if not await self.connect():
                return []
        
        try:
            # Préparer la requête REQ
            subscription_id = f"troczen_{datetime.now().timestamp()}"
            request = ["REQ", subscription_id] + filters
            
            # Envoyer la requête
            await self.websocket.send(json.dumps(request))
            
            # Collecter les events
            events = []
            async for message in self.websocket:
                data = json.loads(message)
                
                if data[0] == "EVENT":
                    # Event reçu
                    event = data[2]
                    events.append(event)
                elif data[0] == "EOSE":
                    # Fin des résultats
                    break
                elif data[0] == "CLOSED":
                    # Subscription fermée
                    break
            
            # Fermer la subscription
            close_request = ["CLOSE", subscription_id]
            await self.websocket.send(json.dumps(close_request))
            
            return events
            
        except Exception as e:
            print(f"❌ Erreur lors de la requête: {e}")
            return []
    
    async def query_events_paginated(
        self,
        kinds: List[int],
        page_size: int = DEFAULT_PAGE_SIZE,
        max_results: int = MAX_TOTAL_RESULTS,
        additional_filters: Optional[Dict] = None
    ) -> List[Dict]:
        """
        Interroger les events avec pagination automatique
        
        Utilise la pagination par curseur (until) pour récupérer tous les résultats
        sans limite artificielle.
        
        Args:
            kinds: Liste des kinds Nostr à récupérer
            page_size: Nombre d'events par page
            max_results: Nombre maximum total de résultats (protection)
            additional_filters: Filtres additionnels (tags, etc.)
            
        Returns:
            Liste complète des events
        """
        all_events = []
        until_timestamp = None
        page_count = 0
        
        while len(all_events) < max_results:
            # Construire le filtre
            filter_dict = {
                "kinds": kinds,
                "limit": min(page_size, max_results - len(all_events))
            }
            
            # Ajouter le curseur de pagination (until)
            if until_timestamp:
                filter_dict["until"] = until_timestamp
            
            # Ajouter les filtres additionnels
            if additional_filters:
                filter_dict.update(additional_filters)
            
            filters = [filter_dict]
            
            # Récupérer la page
            events = await self.query_events(filters)
            page_count += 1
            
            if not events:
                # Plus de résultats
                break
            
            all_events.extend(events)
            
            # Mettre à jour le curseur avec le timestamp du plus ancien event
            if events:
                oldest_timestamp = min(e.get("created_at", 0) for e in events)
                until_timestamp = oldest_timestamp - 1
                
                # Si on a reçu moins que la page size, on a tout
                if len(events) < page_size:
                    break
            
            print(f'📄 [NostrClient] Page {page_count}: {len(events)} events (total: {len(all_events)})')
        
        print(f'✅ [NostrClient] Pagination terminée: {len(all_events)} events en {page_count} pages')
        return all_events[:max_results]
    
    async def get_merchant_profiles(self, max_results: int = MAX_TOTAL_RESULTS) -> List[Dict]:
        """
        Récupérer les profils marchands (kind 0) avec pagination
        
        Args:
            max_results: Nombre maximum de profils à récupérer
            
        Returns:
            Liste des profils marchands
        """
        # Récupérer avec pagination
        events = await self.query_events_paginated(
            kinds=[0],
            max_results=max_results
        )
        
        # Décoder le contenu JSON et dédoublonner par pubkey
        profiles_by_pubkey = {}
        for event in events:
            try:
                content = json.loads(event.get("content", "{}"))
                if content:
                    pubkey = event.get("pubkey", "")
                    # Garder le profil le plus récent pour chaque pubkey
                    if pubkey not in profiles_by_pubkey or \
                       event.get("created_at", 0) > profiles_by_pubkey[pubkey].get("created_at", 0):
                        profiles_by_pubkey[pubkey] = {
                            "pubkey": pubkey,
                            "created_at": event.get("created_at", 0),
                            "content": content,
                            "name": content.get("name", "Anonyme"),
                            "about": content.get("about", ""),
                            "picture": content.get("picture", ""),
                            "banner": content.get("banner", ""),
                            "nip05": content.get("nip05", ""),
                            "lud16": content.get("lud16", ""),
                            "website": content.get("website", "")
                        }
            except json.JSONDecodeError:
                continue
        
        return list(profiles_by_pubkey.values())
    
    async def get_bons(
        self,
        market_name: Optional[str] = None,
        max_results: int = MAX_TOTAL_RESULTS
    ) -> List[Dict]:
        """
        Récupérer les bons (kind 30303) avec pagination
        
        Args:
            market_name: Filtre par marché (optionnel)
            max_results: Nombre maximum de bons à récupérer
            
        Returns:
            Liste des bons
        """
        # Filtres additionnels pour le marché
        additional_filters = {}
        if market_name:
            # Note: Le filtre par tag 'market' se fait après récupération
            # car tous les relais supportent pas le filtrage par tags
            pass
        
        # Récupérer avec pagination
        events = await self.query_events_paginated(
            kinds=[30303],
            max_results=max_results,
            additional_filters=additional_filters
        )
        
        events = await self.query_events(filters)
        
        bons = []
        for event in events:
            try:
                # Extraire les tags - gérer les tags multiples
                tags = {}
                for tag in event.get("tags", []):
                    if len(tag) >= 2:
                        key = tag[0]
                        value = tag[1]
                        # Pour les tags qui peuvent apparaître plusieurs fois
                        if key in tags:
                            if isinstance(tags[key], list):
                                tags[key].append(value)
                            else:
                                tags[key] = [tags[key], value]
                        else:
                            tags[key] = value
                
                # Filtrer par market si spécifié
                if market_name and tags.get("market") != market_name:
                    continue
                
                # Extraire le bon ID depuis le tag 'd' (format: zen-{bonId})
                bon_id = tags.get("d", "")
                if bon_id.startswith("zen-"):
                    bon_id = bon_id[4:]
                else:
                    bon_id = event.get("id", "")
                
                # Le contenu est chiffré (P3), on garde les métadonnées
                # IMPORTANT: issuer = npub du marchand émetteur (pas pubkey qui est celle du bon)
                bon = {
                    "id": bon_id,
                    "event_id": event.get("id", ""),
                    "pubkey": event.get("pubkey", ""),  # Clé publique du BON
                    "issuer": tags.get("issuer", ""),    # npub du MARCHAND émetteur
                    "created_at": event.get("created_at", 0),
                    "content": event.get("content", ""),  # Chiffré
                    "tags": tags,
                    "market": tags.get("market", ""),
                    "status": tags.get("status", "active"),  # active, burned, expired
                    "value": float(tags.get("value", 0)) if tags.get("value") else 0,
                    "expiry": int(tags.get("expiry", 0)) if tags.get("expiry") else 0,
                    "category": tags.get("category", "autre"),
                    "rarity": tags.get("rarity", "common")
                }
                bons.append(bon)
            except Exception as e:
                print(f"Erreur traitement bon: {e}")
                continue
        
        return bons
    
    async def get_merchants_with_bons(self, market_name: str) -> Dict:
        """
        Récupérer les marchands et leurs bons pour un marché
        
        Args:
            market_name: Nom du marché
        
        Returns:
            Dictionnaire avec marchands et bons
        """
        print(f'🌻 [NostrClient] get_merchants_with_bons("{market_name}")')
        
        # Récupérer tous les marchands (kind 0)
        print(f'  └─ Récupération des profils (kind 0)...')
        merchants = await self.get_merchant_profiles()
        print(f'  └─ {len(merchants)} profils récupérés')
        
        # Créer un index des marchands par pubkey pour accès rapide
        merchants_by_pubkey = {m["pubkey"]: m for m in merchants}
        
        # Récupérer les bons du marché (kind 30303)
        print(f'  └─ Récupération des bons (kind 30303) pour {market_name}...')
        bons = await self.get_bons(market_name)
        print(f'  └─ {len(bons)} bons récupérés')
        
        # Associer les bons aux marchands via le tag 'issuer'
        # IMPORTANT: Le tag 'issuer' contient le npub du marchand émetteur
        merchant_bons = {}
        bons_with_issuer = 0
        bons_without_issuer = 0
        
        for bon in bons:
            # Utiliser 'issuer' (npub du marchand) et non 'pubkey' (clé du bon)
            issuer_pubkey = bon.get("issuer", "")
            if not issuer_pubkey:
                # Fallback: utiliser pubkey si pas d'issuer (ancien format)
                issuer_pubkey = bon.get("pubkey", "")
                bons_without_issuer += 1
            else:
                bons_with_issuer += 1
            
            if issuer_pubkey:
                if issuer_pubkey not in merchant_bons:
                    merchant_bons[issuer_pubkey] = []
                merchant_bons[issuer_pubkey].append(bon)
        
        print(f'  └─ Bons avec issuer: {bons_with_issuer}, sans issuer (fallback): {bons_without_issuer}')
        print(f'  └─ {len(merchant_bons)} émetteurs uniques détectés')
        
        # Construire la réponse
        result = {
            "market_name": market_name,
            "merchants": [],
            "total_bons": len(bons),
            "total_merchants": 0
        }
        
        # Ajouter les marchands qui ont des bons
        matched_merchants = 0
        unmatched_merchants = 0
        
        for issuer_pubkey, bons_list in merchant_bons.items():
            merchant = merchants_by_pubkey.get(issuer_pubkey, {})
            
            if merchant:
                matched_merchants += 1
            else:
                unmatched_merchants += 1
                print(f'  ⚠️ Émetteur sans profil kind 0: {issuer_pubkey[:16]}... ({len(bons_list)} bons)')
            
            merchant_data = {
                "pubkey": issuer_pubkey,
                "name": merchant.get("name", "Marchand inconnu"),
                "about": merchant.get("about", ""),
                "picture": merchant.get("picture", ""),
                "banner": merchant.get("banner", ""),
                "website": merchant.get("website", ""),
                "lud16": merchant.get("lud16", ""),
                "nip05": merchant.get("nip05", ""),
                "bons": bons_list,
                "bons_count": len(bons_list)
            }
            result["merchants"].append(merchant_data)
        
        result["total_merchants"] = len(result["merchants"])
        
        print(f'  └─ Résultat: {matched_merchants} marchands avec profil, {unmatched_merchants} sans profil')
        print(f'  └─ Total: {result["total_merchants"]} marchands, {result["total_bons"]} bons')
        
        return result


# Fonctions utilitaires
async def test_connection():
    """Tester la connexion au relai"""
    client = NostrClient()
    try:
        success = await client.connect()
        if success:
            print("✅ Connexion au relai Strfry OK")
            await client.disconnect()
            return True
        else:
            print("❌ Impossible de se connecter au relai")
            return False
    except Exception as e:
        print(f"❌ Erreur: {e}")
        return False


async def fetch_marche_toulouse():
    """Exemple: Récupérer les données pour le marché de Toulouse"""
    client = NostrClient()
    try:
        await client.connect()
        data = await client.get_merchants_with_bons("marche-toulouse")
        await client.disconnect()
        return data
    except Exception as e:
        print(f"❌ Erreur: {e}")
        return None


if __name__ == "__main__":
    # Test rapide
    asyncio.run(test_connection())
