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
