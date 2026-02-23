#!/usr/bin/env python3
"""
Tests unitaires pour le DU Engine - Optimisation des requêtes Nostr
"""

import asyncio
import sys
from pathlib import Path

# Ajouter le chemin parent pour importer les modules
sys.path.insert(0, str(Path(__file__).parent))

from dragon.du_engine import DUEngine


class MockNostrClient:
    """Mock client Nostr pour les tests"""
    
    def __init__(self):
        self.query_count = 0
        self.last_query = None
        
    async def query_events(self, filters):
        """Simule une requête Nostr"""
        self.query_count += 1
        self.last_query = filters
        
        # Simuler des réponses basées sur le filtre
        if filters[0].get('kinds') == [3]:
            authors = filters[0].get('authors', [])
            
            # Cas 1: Récupération des follows de l'utilisateur
            if len(authors) == 1 and 'user1' in authors:
                return [{
                    'pubkey': 'user1',
                    'tags': [
                        ['p', 'user2'],
                        ['p', 'user3'],
                        ['p', 'user4'],
                        ['p', 'user5']
                    ]
                }]
            
            # Cas 2: Récupération des kind 3 des follows (batch)
            elif len(authors) > 1:
                # Simuler que user2 et user3 suivent user1 (réciprocité)
                # user4 et user5 ne suivent pas user1
                events = []
                if 'user2' in authors:
                    events.append({
                        'pubkey': 'user2',
                        'tags': [
                            ['p', 'user1'],  # Suit user1 (réciprocité)
                            ['p', 'user6']
                        ]
                    })
                if 'user3' in authors:
                    events.append({
                        'pubkey': 'user3',
                        'tags': [
                            ['p', 'user1'],  # Suit user1 (réciprocité)
                            ['p', 'user7']
                        ]
                    })
                if 'user4' in authors:
                    events.append({
                        'pubkey': 'user4',
                        'tags': [
                            ['p', 'user8']  # Ne suit pas user1
                        ]
                    })
                if 'user5' in authors:
                    events.append({
                        'pubkey': 'user5',
                        'tags': [
                            ['p', 'user9']  # Ne suit pas user1
                        ]
                    })
                return events
        
        return []


class MockParamsEngine:
    """Mock params engine pour les tests"""
    
    async def get_all_params(self, user_pubkey, market_id):
        return {
            'c2': 0.07,
            'alpha': 0.3
        }


async def test_get_n1_list_optimization():
    """Teste l'optimisation de _get_n1_list"""
    print("🧪 Test 1: Optimisation _get_n1_list")
    
    client = MockNostrClient()
    params_engine = MockParamsEngine()
    du_engine = DUEngine(client, params_engine)
    
    # Exécuter la méthode
    n1_list = await du_engine._get_n1_list('user1')
    
    # Vérifier les résultats
    print(f"   N1 list: {n1_list}")
    print(f"   Nombre de requêtes: {client.query_count}")
    
    # Vérifier que la réciprocité est correcte
    # user2 et user3 suivent user1, donc ils devraient être dans N1
    # user4 et user5 ne suivent pas user1, donc ils ne devraient pas être dans N1
    expected_n1 = ['user2', 'user3']
    
    if set(n1_list) == set(expected_n1):
        print("   ✅ N1 list correcte")
    else:
        print(f"   ❌ N1 list incorrecte. Attendu: {expected_n1}, Obtenu: {n1_list}")
        return False
    
    # Vérifier l'optimisation: on devrait avoir 2 requêtes au maximum
    # 1 pour récupérer les follows de user1
    # 1 pour récupérer les kind 3 des follows (batch)
    if client.query_count <= 2:
        print(f"   ✅ Optimisation réussie: {client.query_count} requêtes au lieu de 4 (1 par follow)")
    else:
        print(f"   ❌ Trop de requêtes: {client.query_count}")
        return False
    
    return True


async def test_get_n2_list_optimization():
    """Teste l'optimisation de _get_n2_list"""
    print("\n🧪 Test 2: Optimisation _get_n2_list")
    
    client = MockNostrClient()
    params_engine = MockParamsEngine()
    du_engine = DUEngine(client, params_engine)
    
    # Exécuter la méthode
    n2_list = await du_engine._get_n2_list('user1')
    
    # Vérifier les résultats
    print(f"   N2 list: {n2_list}")
    print(f"   Nombre de requêtes: {client.query_count}")
    
    # Vérifier que N2 contient les follows des N1 (user2 et user3)
    # user2 suit user6, user3 suit user7
    # user6 et user7 ne sont ni user1 ni dans N1, donc ils devraient être dans N2
    expected_n2 = ['user6', 'user7']
    
    if set(n2_list) == set(expected_n2):
        print("   ✅ N2 list correcte")
    else:
        print(f"   ❌ N2 list incorrecte. Attendu: {expected_n2}, Obtenu: {n2_list}")
        return False
    
    # Vérifier l'optimisation: on devrait avoir 3 requêtes au maximum
    # 1 pour récupérer les follows de user1
    # 1 pour récupérer les kind 3 des follows (batch)
    # 1 pour récupérer les kind 3 des N1 (batch)
    if client.query_count <= 3:
        print(f"   ✅ Optimisation réussie: {client.query_count} requêtes au lieu de 5 (1 par N1)")
    else:
        print(f"   ❌ Trop de requêtes: {client.query_count}")
        return False
    
    return True


async def test_empty_follows():
    """Teste le cas où l'utilisateur n'a pas de follows"""
    print("\n🧪 Test 3: Cas utilisateur sans follows")
    
    class EmptyClient:
        async def query_events(self, filters):
            return []
    
    client = EmptyClient()
    params_engine = MockParamsEngine()
    du_engine = DUEngine(client, params_engine)
    
    n1_list = await du_engine._get_n1_list('user1')
    n2_list = await du_engine._get_n2_list('user1')
    
    if n1_list == [] and n2_list == []:
        print("   ✅ Retourne des listes vides correctement")
        return True
    else:
        print(f"   ❌ Erreur: n1={n1_list}, n2={n2_list}")
        return False


async def main():
    """Exécuter tous les tests"""
    print("=" * 60)
    print("TESTS DU ENGINE - OPTIMISATION REQUÊTES NOSTR")
    print("=" * 60)
    
    tests = [
        test_get_n1_list_optimization,
        test_get_n2_list_optimization,
        test_empty_follows
    ]
    
    results = []
    for test in tests:
        try:
            result = await test()
            results.append(result)
        except Exception as e:
            print(f"   ❌ Erreur: {e}")
            results.append(False)
    
    print("\n" + "=" * 60)
    print("RÉSULTATS")
    print("=" * 60)
    
    passed = sum(results)
    total = len(results)
    
    print(f"Tests passés: {passed}/{total}")
    
    if passed == total:
        print("✅ Tous les tests ont réussi!")
        return 0
    else:
        print("❌ Certains tests ont échoué")
        return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
