#!/usr/bin/env python3
"""
TrocZen API Backend
Gère l'upload des logos commerçants et la distribution d'APK
Intégration IPFS pour stockage décentralisé des images
Intégration Nostr pour récupération des profils marchands (kind 0) et bons (kind 30303)
"""
from flask import Flask, request, jsonify, send_file, render_template
from flask_cors import CORS
from werkzeug.utils import secure_filename
import os
import hashlib
import json
from datetime import datetime
from pathlib import Path
import qrcode
from io import BytesIO
import requests
import base64
import asyncio
from nostr_client import NostrClient

app = Flask(__name__)
CORS(app)

# Configuration
UPLOAD_FOLDER = Path('./uploads')
APK_FOLDER = Path('./apks')
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'webp'}
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB

# ✅ Configuration IPFS
IPFS_API_URL = os.getenv('IPFS_API_URL', 'http://127.0.0.1:5001')  # API locale IPFS
IPFS_GATEWAY = os.getenv('IPFS_GATEWAY', 'https://ipfs.copylaradio.com')  # Passerelle publique
IPFS_ENABLED = os.getenv('IPFS_ENABLED', 'true').lower() == 'true'

# Créer les dossiers
UPLOAD_FOLDER.mkdir(exist_ok=True)
APK_FOLDER.mkdir(exist_ok=True)

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['APK_FOLDER'] = APK_FOLDER
app.config['MAX_CONTENT_LENGTH'] = MAX_FILE_SIZE


def allowed_file(filename):
    """Vérifier extension fichier"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def generate_checksum(filepath):
    """Générer SHA256 checksum"""
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def upload_to_ipfs(filepath):
    """
    Upload un fichier vers IPFS via l'API locale
    Retourne: (cid, ipfs_url) ou (None, None) si échec
    """
    if not IPFS_ENABLED:
        return None, None
    
    try:
        # Lire le fichier
        with open(filepath, 'rb') as f:
            files = {'file': f}
            
            # Upload vers IPFS node local
            response = requests.post(
                f'{IPFS_API_URL}/api/v0/add',
                files=files,
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                cid = result['Hash']
                ipfs_url = f'{IPFS_GATEWAY}/ipfs/{cid}'
                
                print(f'✅ Fichier uploadé sur IPFS: {cid}')
                return cid, ipfs_url
            else:
                print(f'❌ Erreur IPFS API: {response.status_code}')
                return None, None
                
    except requests.exceptions.RequestException as e:
        print(f'❌ Erreur connexion IPFS: {e}')
        return None, None
    except Exception as e:
        print(f'❌ Erreur upload IPFS: {e}')
        return None, None


@app.route('/')
def index():
    """Page d'accueil"""
    return render_template('index.html')


@app.route('/health', methods=['GET'])
def health():
    """Health check"""
    return jsonify({
        'status': 'ok',
        'timestamp': datetime.now().isoformat(),
        'version': '1.0.0'
    })


# ==================== UPLOAD IMAGES ====================

@app.route('/api/upload/image', methods=['POST'])
def upload_image():
    """Upload image (logo, bandeau, avatar) pour profils Nostr"""
    
    # Vérifier présence fichier
    if 'file' not in request.files:
        return jsonify({'error': 'No file provided'}), 400
    
    file = request.files['file']
    
    if file.filename == '':
        return jsonify({'error': 'No file selected'}), 400
    
    if not allowed_file(file.filename):
        return jsonify({'error': 'Invalid file type'}), 400
    
    # Récupérer npub du commerçant/utilisateur
    npub = request.form.get('npub')
    if not npub:
        return jsonify({'error': 'Missing npub'}), 400
    
    # Récupérer le type d'image (logo, banner, avatar)
    image_type = request.form.get('type', 'logo')
    if image_type not in ['logo', 'banner', 'avatar']:
        return jsonify({'error': 'Invalid image type (must be logo, banner, or avatar)'}), 400
    
    # Nom sécurisé
    filename = secure_filename(file.filename)
    ext = filename.rsplit('.', 1)[1].lower()
    
    # Nouveau nom: npub_type_timestamp.ext
    new_filename = f"{npub[:16]}_{image_type}_{int(datetime.now().timestamp())}.{ext}"
    filepath = UPLOAD_FOLDER / new_filename
    
    # Sauvegarder localement
    file.save(filepath)
    
    # Générer checksum
    checksum = generate_checksum(filepath)
    
    # ✅ Upload vers IPFS
    ipfs_cid, ipfs_url = upload_to_ipfs(filepath)
    
    # URL de fallback (locale)
    local_url = f"/uploads/{new_filename}"
    
    # URL finale (IPFS si dispo, sinon locale)
    final_url = ipfs_url if ipfs_url else local_url
    
    return jsonify({
        'success': True,
        'url': final_url,           # URL IPFS ou locale
        'local_url': local_url,     # Toujours disponible en fallback
        'ipfs_url': ipfs_url,       # URL IPFS (ou null)
        'ipfs_cid': ipfs_cid,       # CID IPFS (ou null)
        'filename': new_filename,
        'checksum': checksum,
        'size': filepath.stat().st_size,
        'uploaded_at': datetime.now().isoformat(),
        'storage': 'ipfs' if ipfs_url else 'local',
        'type': image_type
    }), 201


@app.route('/uploads/<filename>')
def serve_upload(filename):
    """Servir fichier uploadé"""
    filepath = UPLOAD_FOLDER / filename
    if not filepath.exists():
        return jsonify({'error': 'File not found'}), 404
    return send_file(filepath)


# ==================== APK DISTRIBUTION ====================

@app.route('/api/apk/latest', methods=['GET'])
def get_latest_apk():
    """Informations sur la dernière version APK"""
    
    apk_files = list(APK_FOLDER.glob('*.apk'))
    
    if not apk_files:
        return jsonify({'error': 'No APK available'}), 404
    
    # Trier par date de modification
    latest_apk = max(apk_files, key=lambda p: p.stat().st_mtime)
    
    checksum = generate_checksum(latest_apk)
    
    return jsonify({
        'filename': latest_apk.name,
        'version': latest_apk.stem.replace('troczen-', ''),
        'size': latest_apk.stat().st_size,
        'checksum': checksum,
        'download_url': f'/api/apk/download/{latest_apk.name}',
        'updated_at': datetime.fromtimestamp(latest_apk.stat().st_mtime).isoformat()
    })


@app.route('/api/apk/download/<filename>')
def download_apk(filename):
    """Télécharger APK"""
    
    filepath = APK_FOLDER / secure_filename(filename)
    
    if not filepath.exists() or not filepath.suffix == '.apk':
        return jsonify({'error': 'APK not found'}), 404
    
    return send_file(
        filepath,
        as_attachment=True,
        download_name=filename,
        mimetype='application/vnd.android.package-archive'
    )


@app.route('/api/apk/qr')
def apk_qr_code():
    """Générer QR code pour téléchargement APK"""
    
    # URL de téléchargement
    apk_info = get_latest_apk().get_json()
    
    if 'error' in apk_info:
        return jsonify(apk_info), 404
    
    # URL complète
    base_url = request.host_url.rstrip('/')
    download_url = f"{base_url}{apk_info['download_url']}"
    
    # Générer QR code
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(download_url)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    
    # Convertir en bytes
    img_io = BytesIO()
    img.save(img_io, 'PNG')
    img_io.seek(0)
    
    return send_file(img_io, mimetype='image/png')


# ==================== NOSTR CLIENT ====================

def fetch_marche_data(market_name):
    """
    Récupère les données d'un marché depuis Nostr (relai Strfry)
    
    Structure retournée :
    {
        "market_name": "marche-toulouse",
        "merchants": [
            {
                "pubkey": "npub1...",
                "name": "Nom du marchand",
                "about": "Description",
                "picture": "URL logo",
                "banner": "URL banner",
                "website": "URL site",
                "lud16": "LNURL",
                "nip05": "nip05",
                "bons": [...],
                "bons_count": 5
            }
        ],
        "total_bons": 10,
        "total_merchants": 3
    }
    """
    
    # Configuration
    NOSTR_RELAY = os.getenv('NOSTR_RELAY', 'ws://127.0.0.1:7777')
    NOSTR_ENABLED = os.getenv('NOSTR_ENABLED', 'true').lower() == 'true'
    
    if not NOSTR_ENABLED:
        # Fallback: lire depuis les fichiers JSON locaux
        return fetch_local_marche_data(market_name)
    
    try:
        # Créer le client Nostr
        client = NostrClient(relay_url=NOSTR_RELAY)
        
        # Exécuter de manière asynchrone
        async def fetch_data():
            await client.connect()
            data = await client.get_merchants_with_bons(market_name)
            await client.disconnect()
            return data
        
        # Exécuter la coroutine
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        data = loop.run_until_complete(fetch_data())
        loop.close()
        
        return data
        
    except Exception as e:
        print(f"❌ Erreur récupération Nostr: {e}")
        # Fallback: lire depuis les fichiers JSON locaux
        return fetch_local_marche_data(market_name)


def fetch_local_marche_data(market_name):
    """
    Fallback: lire les données depuis les fichiers JSON locaux
    """
    profiles = []
    bons = []
    
    # Lire les profils
    for profile_file in UPLOAD_FOLDER.glob('*.json'):
        try:
            with open(profile_file, 'r') as f:
                profile = json.load(f)
                if profile.get('market') == market_name:
                    profiles.append(profile)
        except Exception as e:
            print(f"Erreur lecture profil {profile_file}: {e}")
            continue
    
    # Lire les bons (simulés)
    # Dans une vraie implémentation, on lirait depuis Nostr
    for bon_file in UPLOAD_FOLDER.glob('*.json'):
        try:
            with open(bon_file, 'r') as f:
                data = json.load(f)
                if data.get('market') == market_name:
                    # Simuler un bon
                    bons.append({
                        'id': f"bon_{len(bons)}",
                        'pubkey': data.get('npub', ''),
                        'value': data.get('value', 10),
                        'status': 'active',
                        'category': data.get('category', 'autre'),
                        'rarity': data.get('rarity', 'common')
                    })
        except Exception as e:
            continue
    
    # Associer les marchands à leurs bons
    merchant_bons = {}
    for bon in bons:
        pubkey = bon["pubkey"]
        if pubkey not in merchant_bons:
            merchant_bons[pubkey] = []
        merchant_bons[pubkey].append(bon)
    
    # Construire la réponse
    result = {
        "market_name": market_name,
        "merchants": [],
        "total_bons": len(bons),
        "total_merchants": 0
    }
    
    for profile in profiles:
        pubkey = profile.get('npub', '')
        if pubkey in merchant_bons:
            merchant_data = {
                "pubkey": pubkey,
                "name": profile.get('name', 'Anonyme'),
                "about": profile.get('description', ''),
                "picture": profile.get('logo_url', ''),
                "banner": profile.get('banner_url', ''),
                "website": profile.get('website', ''),
                "lud16": profile.get('lud16', ''),
                "nip05": profile.get('nip05', ''),
                "bons": merchant_bons[pubkey],
                "bons_count": len(merchant_bons[pubkey])
            }
            result["merchants"].append(merchant_data)
    
    result["total_merchants"] = len(result["merchants"])
    
    return result


# ==================== PAGE PRESENTATION ====================

@app.route('/market/<market_name>')
def market_page(market_name):
    """Page de présentation du marché"""
    
    # Récupérer les données du marché depuis Nostr
    marche_data = fetch_marche_data(market_name)
    
    return render_template(
        'market.html',
        market_name=marche_data.get('market_name', market_name),
        merchants=marche_data.get('merchants', []),
        total_bons=marche_data.get('total_bons', 0),
        total_merchants=marche_data.get('total_merchants', 0),
        apk_info=get_latest_apk().get_json()
    )


@app.route('/api/nostr/marche/<market_name>', methods=['GET'])
def get_marche_data(market_name):
    """
    API pour récupérer les données d'un marché depuis Nostr
    """
    marche_data = fetch_marche_data(market_name)
    return jsonify({
        'success': True,
        'data': marche_data,
        'source': 'nostr_strfry'
    })


@app.route('/api/nostr/sync', methods=['POST'])
def sync_nostr_profiles():
    """
    Synchroniser les données depuis Nostr
    """
    market_name = request.args.get('market', 'marche-toulouse')
    
    try:
        # Récupérer les données
        marche_data = fetch_marche_data(market_name)
        
        return jsonify({
            'success': True,
            'message': f'Synchronisation terminée pour {market_name}',
            'data': {
                'merchants': marche_data.get('total_merchants', 0),
                'bons': marche_data.get('total_bons', 0)
            },
            'source': 'nostr_strfry'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Retourne les statistiques globales de l'API"""
    
    # Compter les APK disponibles
    apk_files = list(APK_FOLDER.glob('*.apk'))
    apk_count = len(apk_files)
    
    # Compter les logos uploadés
    logo_files = list(UPLOAD_FOLDER.glob('*_logo.*'))
    logo_count = len(logo_files)
    
    # Compter les profils commerçants (fichiers JSON)
    profile_files = list(UPLOAD_FOLDER.glob('*.json'))
    profile_count = len(profile_files)
    
    # Compter les marchés détectés via Nostr
    # Pour l'instant, on compte les fichiers JSON avec un champ market
    market_count = 0
    markets = set()
    for profile_file in profile_files:
        try:
            with open(profile_file, 'r') as f:
                profile = json.load(f)
                if 'market' in profile:
                    markets.add(profile['market'])
        except:
            continue
    market_count = len(markets)
    
    return jsonify({
        'apk_count': apk_count,
        'logo_count': logo_count,
        'profile_count': profile_count,
        'market_count': market_count,
        'markets': list(markets),
        'timestamp': datetime.now().isoformat()
    })


if __name__ == '__main__':
    # Mode dev
    app.run(host='0.0.0.0', port=5000, debug=True)
