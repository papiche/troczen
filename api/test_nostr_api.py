#!/usr/bin/env python3
"""
Tests de l'API Nostr pour la récupération des marchands et bons
"""

import requests
import json
import sys

BASE_URL = "http://localhost:5000"

def test_health():
    """Test le endpoint health"""
    print("🧪 Test 1: Health check")
    try:
        response = requests.get(f"{BASE_URL}/health")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Health OK: {data}")
            return True
        else:
            print(f"❌ Health failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Erreur: {e}")
        return False

def test_nostr_marche():
    """Test le endpoint Nostr marche"""
    print("\n🧪 Test 2: Récupération données marché Nostr")
    try:
        response = requests.get(f"{BASE_URL}/api/nostr/marche/marche-toulouse")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Nostr marche OK")
            print(f"   - Source: {data.get('source', 'inconnu')}")
            if data.get('data'):
                marche_data = data['data']
                print(f"   - Marché: {marche_data.get('market_name', 'inconnu')}")
                print(f"   - Marchands: {marche_data.get('total_merchants', 0)}")
                print(f"   - Bons: {marche_data.get('total_bons', 0)}")
                if marche_data.get('merchants'):
                    print(f"   - Marchands récupérés:")
                    for merchant in marche_data['merchants']:
                        print(f"     * {merchant.get('name', 'Sans nom')} ({merchant.get('bons_count', 0)} bons)")
            return True
        else:
            print(f"❌ Nostr marche failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Erreur: {e}")
        return False

def test_market_page():
    """Test la page marché"""
    print("\n🧪 Test 3: Page marché")
    try:
        response = requests.get(f"{BASE_URL}/market/marche-toulouse")
        if response.status_code == 200:
            print(f"✅ Page marché OK")
            # Vérifier que la page contient la source Nostr
            if "Strfry" in response.text:
                print(f"   - Page contient mention Strfry")
            if "Statistiques" in response.text:
                print(f"   - Page contient statistiques")
            return True
        else:
            print(f"❌ Page marché failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Erreur: {e}")
        return False

def test_nostr_sync():
    """Test la synchronisation Nostr"""
    print("\n🧪 Test 4: Synchronisation Nostr")
    try:
        response = requests.post(f"{BASE_URL}/api/nostr/sync?market=marche-toulouse")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Nostr sync OK")
            print(f"   - Message: {data.get('message', 'inconnu')}")
            if data.get('data'):
                print(f"   - Marchands: {data['data'].get('merchants', 0)}")
                print(f"   - Bons: {data['data'].get('bons', 0)}")
            return True
        else:
            print(f"❌ Nostr sync failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Erreur: {e}")
        return False

def test_apk_latest():
    """Test le endpoint APK latest"""
    print("\n🧪 Test 5: APK latest")
    try:
        response = requests.get(f"{BASE_URL}/api/apk/latest")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ APK latest OK")
            print(f"   - Version: {data.get('version', 'inconnu')}")
            print(f"   - Fichier: {data.get('filename', 'inconnu')}")
            return True
        else:
            print(f"❌ APK latest failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Erreur: {e}")
        return False

def main():
    """Exécuter tous les tests"""
    print("=" * 60)
    print("TESTS API NOSTR TROCZEN")
    print("=" * 60)
    
    tests = [
        test_health,
        test_nostr_marche,
        test_market_page,
        test_nostr_sync,
        test_apk_latest
    ]
    
    results = []
    for test in tests:
        results.append(test())
    
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
    sys.exit(main())
