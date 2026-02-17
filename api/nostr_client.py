#!/usr/bin/env python3
"""
Client Nostr pour TrocZen
Connecté au relai Strfry local (ws://127.0.0.1:7777)
"""

import asyncio
import json
import websockets
import ssl
from datetime import datetime
from typing import List, Dict, Optional

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
            self.websocket = await websockets.connect(self.relay_url)
            print(f"✅ Connecté au relai Nostr: {self.relay_url}")
            return True
        except Exception as e:
            print(f"❌ Erreur de connexion au relai {self.relay_url}: {e}")
            return False
    
    async def disconnect(self):
        """Déconnecter du relai"""
        if self.websocket:
            await self.websocket.close()
            self.websocket = None
            print("✅ Déconnecté du relai Nostr")
    
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
    
    async def get_merchant_profiles(self) -> List[Dict]:
        """
        Récupérer les profils marchands (kind 0)
        
        Returns:
            Liste des profils marchands
        """
        # Filtre pour kind 0
        filters = [{
            "kinds": [0],
            "limit": 100
        }]
        
        events = await self.query_events(filters)
        
        # Décoder le contenu JSON
        profiles = []
        for event in events:
            try:
                content = json.loads(event.get("content", "{}"))
                if content:  # Vérifier que le contenu n'est pas vide
                    profile = {
                        "pubkey": event.get("pubkey", ""),
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
                    profiles.append(profile)
            except json.JSONDecodeError:
                continue
        
        return profiles
    
    async def get_bons(self, market_name: Optional[str] = None) -> List[Dict]:
        """
        Récupérer les bons (kind 30303)
        
        Args:
            market_name: Filtre par marché (optionnel)
        
        Returns:
            Liste des bons
        """
        # Filtre pour kind 30303
        filters = [{
            "kinds": [30303],
            "limit": 1000
        }]
        
        events = await self.query_events(filters)
        
        bons = []
        for event in events:
            try:
                # Extraire les tags
                tags = {tag[0]: tag[1] for tag in event.get("tags", [])}
                
                # Filtrer par market si spécifié
                if market_name and tags.get("market") != market_name:
                    continue
                
                # Le contenu est chiffré (P3), on garde les métadonnées
                bon = {
                    "id": event.get("id", ""),
                    "pubkey": event.get("pubkey", ""),
                    "created_at": event.get("created_at", 0),
                    "content": event.get("content", ""),  # Chiffré
                    "tags": tags,
                    "market": tags.get("market", ""),
                    "status": tags.get("status", "active"),  # active, burned, expired
                    "value": float(tags.get("value", 0)),
                    "expiry": int(tags.get("expiry", 0)),
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
        # Récupérer tous les marchands
        merchants = await self.get_merchant_profiles()
        
        # Récupérer les bons du marché
        bons = await self.get_bons(market_name)
        
        # Associer les marchands à leurs bons
        merchant_bons = {}
        for bon in bons:
            merchant_pubkey = bon["pubkey"]
            if merchant_pubkey not in merchant_bons:
                merchant_bons[merchant_pubkey] = []
            merchant_bons[merchant_pubkey].append(bon)
        
        # Construire la réponse
        result = {
            "market_name": market_name,
            "merchants": [],
            "total_bons": len(bons),
            "total_merchants": 0
        }
        
        for merchant in merchants:
            pubkey = merchant["pubkey"]
            if pubkey in merchant_bons:
                merchant_data = {
                    "pubkey": pubkey,
                    "name": merchant["name"],
                    "about": merchant["about"],
                    "picture": merchant["picture"],
                    "banner": merchant["banner"],
                    "website": merchant["website"],
                    "lud16": merchant["lud16"],
                    "nip05": merchant["nip05"],
                    "bons": merchant_bons[pubkey],
                    "bons_count": len(merchant_bons[pubkey])
                }
                result["merchants"].append(merchant_data)
        
        result["total_merchants"] = len(result["merchants"])
        
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
