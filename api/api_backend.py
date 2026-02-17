#!/usr/bin/env python3
"""
TrocZen API Backend
Gère l'upload des logos commerçants, la distribution d'APK et les profils Nostr
Intégration IPFS pour stockage décentralisé des images
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

app = Flask(__name__)
CORS(app)

# Configuration
UPLOAD_FOLDER = Path('./uploads')
APK_FOLDER = Path('./apks')
PROFILES_FOLDER = Path('./profiles')
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'webp'}
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB

# ✅ Configuration IPFS
IPFS_API_URL = os.getenv('IPFS_API_URL', 'http://127.0.0.1:5001')  # API locale IPFS
IPFS_GATEWAY = os.getenv('IPFS_GATEWAY', 'https://ipfs.copylaradio.com')  # Passerelle publique
IPFS_ENABLED = os.getenv('IPFS_ENABLED', 'true').lower() == 'true'

# Créer les dossiers
UPLOAD_FOLDER.mkdir(exist_ok=True)
APK_FOLDER.mkdir(exist_ok=True)
PROFILES_FOLDER.mkdir(exist_ok=True)

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

@app.route('/api/upload/logo', methods=['POST'])
def upload_logo():
    """Upload logo commerçant"""
    
    # Vérifier présence fichier
    if 'file' not in request.files:
        return jsonify({'error': 'No file provided'}), 400
    
    file = request.files['file']
    
    if file.filename == '':
        return jsonify({'error': 'No file selected'}), 400
    
    if not allowed_file(file.filename):
        return jsonify({'error': 'Invalid file type'}), 400
    
    # Récupérer npub du commerçant
    npub = request.form.get('npub')
    if not npub:
        return jsonify({'error': 'Missing npub'}), 400
    
    # Nom sécurisé
    filename = secure_filename(file.filename)
    ext = filename.rsplit('.', 1)[1].lower()
    
    # Nouveau nom: npub_timestamp.ext
    new_filename = f"{npub[:16]}_{int(datetime.now().timestamp())}.{ext}"
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
        'storage': 'ipfs' if ipfs_url else 'local'
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


# ==================== PROFILS NOSTR ====================
# Profils utilisateurs et bons avec métadonnées Nostr

@app.route('/api/profile/user/<npub>', methods=['GET'])
def get_user_profile(npub):
    """Récupérer profil utilisateur Nostr"""
    
    profile_file = PROFILES_FOLDER / f"user_{npub}.json"
    
    if not profile_file.exists():
        return jsonify({'error': 'User profile not found'}), 404
    
    with open(profile_file, 'r') as f:
        profile = json.load(f)
    
    return jsonify(profile)


@app.route('/api/profile/user/<npub>', methods=['POST'])
def create_update_user_profile(npub):
    """Créer/mettre à jour profil utilisateur Nostr"""
    
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    
    # Validation
    required_fields = ['name']
    for field in required_fields:
        if field not in data:
            return jsonify({'error': f'Missing field: {field}'}), 400
    
    # Structure profil utilisateur (NIP-01 metadata event)
    profile = {
        'npub': npub,
        'name': data['name'],
        'display_name': data.get('display_name', data['name']),
        'about': data.get('about', ''),
        'picture': data.get('picture'),  # URL avatar
        'banner': data.get('banner'),    # URL bannière
        'nip05': data.get('nip05'),      # Identifiant NIP-05 (email-like)
        'lud16': data.get('lud16'),      # Lightning Address
        'website': data.get('website'),
        'location': data.get('location'),
        'created_at': data.get('created_at', datetime.now().isoformat()),
        'updated_at': datetime.now().isoformat()
    }
    
    # Sauvegarder
    profile_file = PROFILES_FOLDER / f"user_{npub}.json"
    with open(profile_file, 'w') as f:
        json.dump(profile, f, indent=2)
    
    return jsonify({
        'success': True,
        'profile': profile
    }), 201


@app.route('/api/profile/bon/<bon_id>', methods=['GET'])
def get_bon_profile(bon_id):
    """Récupérer métadonnées d'un bon"""
    
    profile_file = PROFILES_FOLDER / f"bon_{bon_id}.json"
    
    if not profile_file.exists():
        return jsonify({'error': 'Bon profile not found'}), 404
    
    with open(profile_file, 'r') as f:
        profile = json.load(f)
    
    return jsonify(profile)


@app.route('/api/profile/bon/<bon_id>', methods=['POST'])
def create_bon_profile(bon_id):
    """Créer métadonnées pour un bon au moment de sa création"""
    
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    
    # Validation
    required_fields = ['issuer_name', 'value', 'issuer_npub']
    for field in required_fields:
        if field not in data:
            return jsonify({'error': f'Missing field: {field}'}), 400
    
    # Structure métadonnées bon
    bon_profile = {
        'bon_id': bon_id,
        'issuer_npub': data['issuer_npub'],
        'issuer_name': data['issuer_name'],
        'value': data['value'],
        'unit': data.get('unit', 'ZEN'),
        'market_name': data.get('market_name', ''),
        
        # Métadonnées visuelles
        'logo_url': data.get('logo_url'),
        'image_url': data.get('image_url'),       # Image du bon
        'color': data.get('color', '#FFB347'),     # Couleur dominante
        'rarity': data.get('rarity', 'common'),    # common, uncommon, rare, legendary
        
        # Description
        'title': data.get('title', f"Bon {data['value']} ẐEN"),
        'description': data.get('description', ''),
        'terms': data.get('terms', ''),            # Conditions d'utilisation
        
        # Métadonnées commerçant
        'merchant_category': data.get('merchant_category', ''),  # food, artisanat, services...
        'merchant_location': data.get('merchant_location', ''),
        'merchant_website': data.get('merchant_website', ''),
        
        # Dates
        'created_at': data.get('created_at', datetime.now().isoformat()),
        'expires_at': data.get('expires_at'),
        
        # Stats
        'transfer_count': data.get('transfer_count', 0),
        'view_count': data.get('view_count', 0),
        
        'updated_at': datetime.now().isoformat()
    }
    
    # Sauvegarder
    profile_file = PROFILES_FOLDER / f"bon_{bon_id}.json"
    with open(profile_file, 'w') as f:
        json.dump(bon_profile, f, indent=2)
    
    return jsonify({
        'success': True,
        'bon_profile': bon_profile
    }), 201


@app.route('/api/profile/bon/<bon_id>/stats', methods=['POST'])
def update_bon_stats(bon_id):
    """Mettre à jour les statistiques d'un bon"""
    
    profile_file = PROFILES_FOLDER / f"bon_{bon_id}.json"
    
    if not profile_file.exists():
        return jsonify({'error': 'Bon profile not found'}), 404
    
    # Charger profil existant
    with open(profile_file, 'r') as f:
        profile = json.load(f)
    
    # Mettre à jour les stats
    data = request.get_json() or {}
    
    if 'transfer_count' in data:
        profile['transfer_count'] = data['transfer_count']
    
    if 'view_count' in data:
        profile['view_count'] = data['view_count']
    
    if 'increment_transfers' in data and data['increment_transfers']:
        profile['transfer_count'] = profile.get('transfer_count', 0) + 1
    
    if 'increment_views' in data and data['increment_views']:
        profile['view_count'] = profile.get('view_count', 0) + 1
    
    profile['updated_at'] = datetime.now().isoformat()
    
    # Sauvegarder
    with open(profile_file, 'w') as f:
        json.dump(profile, f, indent=2)
    
    return jsonify({
        'success': True,
        'bon_profile': profile
    })


@app.route('/api/profile/<npub>', methods=['GET'])
def get_profile(npub):
    """Récupérer profil commerçant (legacy - redirige vers user)"""
    return get_user_profile(npub)


@app.route('/api/profile/<npub>', methods=['POST'])
def update_profile(npub):
    """Mettre à jour profil commerçant"""
    
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    
    # Validation
    required_fields = ['name', 'description']
    for field in required_fields:
        if field not in data:
            return jsonify({'error': f'Missing field: {field}'}), 400
    
    # Structure profil
    profile = {
        'npub': npub,
        'name': data['name'],
        'description': data['description'],
        'logo_url': data.get('logo_url'),
        'location': data.get('location'),
        'hours': data.get('hours'),
        'phone': data.get('phone'),
        'website': data.get('website'),
        'social': data.get('social', {}),
        'updated_at': datetime.now().isoformat()
    }
    
    # Sauvegarder
    profile_file = PROFILES_FOLDER / f"{npub}.json"
    with open(profile_file, 'w') as f:
        json.dump(profile, f, indent=2)
    
    return jsonify({
        'success': True,
        'profile': profile
    }), 201


@app.route('/api/profiles/users', methods=['GET'])
def list_user_profiles():
    """Lister tous les profils utilisateurs"""
    
    profiles = []
    for profile_file in PROFILES_FOLDER.glob('user_*.json'):
        with open(profile_file, 'r') as f:
            profile = json.load(f)
            profiles.append(profile)
    
    # Trier par nom
    profiles.sort(key=lambda p: p.get('name', ''))
    
    return jsonify({
        'count': len(profiles),
        'profiles': profiles
    })


@app.route('/api/profiles/bons', methods=['GET'])
def list_bon_profiles():
    """Lister tous les profils de bons"""
    
    # Filtres optionnels
    market = request.args.get('market')
    rarity = request.args.get('rarity')
    issuer = request.args.get('issuer')
    
    bons = []
    for profile_file in PROFILES_FOLDER.glob('bon_*.json'):
        with open(profile_file, 'r') as f:
            bon = json.load(f)
            
            # Appliquer filtres
            if market and bon.get('market_name') != market:
                continue
            if rarity and bon.get('rarity') != rarity:
                continue
            if issuer and bon.get('issuer_npub') != issuer:
                continue
            
            bons.append(bon)
    
    # Trier par date de création (plus récent d'abord)
    bons.sort(key=lambda b: b.get('created_at', ''), reverse=True)
    
    return jsonify({
        'count': len(bons),
        'bons': bons
    })


@app.route('/api/profiles', methods=['GET'])
def list_profiles():
    """Lister tous les profils (legacy - mixte users et commerçants)"""
    
    profiles = []
    for profile_file in PROFILES_FOLDER.glob('*.json'):
        if profile_file.name.startswith('bon_') or profile_file.name.startswith('user_'):
            continue
        with open(profile_file, 'r') as f:
            profile = json.load(f)
            profiles.append(profile)
    
    # Trier par nom
    profiles.sort(key=lambda p: p.get('name', ''))
    
    return jsonify({
        'count': len(profiles),
        'profiles': profiles
    })


# ==================== STATISTIQUES ====================

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Statistiques globales"""
    
    apk_count = len(list(APK_FOLDER.glob('*.apk')))
    logo_count = len(list(UPLOAD_FOLDER.glob('*')))
    
    user_count = len(list(PROFILES_FOLDER.glob('user_*.json')))
    bon_count = len(list(PROFILES_FOLDER.glob('bon_*.json')))
    merchant_count = len(list(PROFILES_FOLDER.glob('*.json'))) - user_count - bon_count
    
    # Calculer valeur totale des bons
    total_value = 0
    for bon_file in PROFILES_FOLDER.glob('bon_*.json'):
        with open(bon_file, 'r') as f:
            bon = json.load(f)
            total_value += bon.get('value', 0)
    
    # Comptage par rareté
    rarity_counts = {'common': 0, 'uncommon': 0, 'rare': 0, 'legendary': 0}
    for bon_file in PROFILES_FOLDER.glob('bon_*.json'):
        with open(bon_file, 'r') as f:
            bon = json.load(f)
            rarity = bon.get('rarity', 'common')
            if rarity in rarity_counts:
                rarity_counts[rarity] += 1
    
    return jsonify({
        'apks': apk_count,
        'logos': logo_count,
        'users': user_count,
        'bons': bon_count,
        'merchants': merchant_count,
        'total_bon_value': total_value,
        'bon_rarity': rarity_counts,
        'timestamp': datetime.now().isoformat()
    })


# ==================== PAGE PRESENTATION ====================

@app.route('/market/<market_name>')
def market_page(market_name):
    """Page de présentation du marché"""
    
    # Récupérer profils du marché
    profiles = []
    for profile_file in PROFILES_FOLDER.glob('*.json'):
        with open(profile_file, 'r') as f:
            profile = json.load(f)
            profiles.append(profile)
    
    return render_template(
        'market.html',
        market_name=market_name,
        profiles=profiles,
        apk_info=get_latest_apk().get_json()
    )


if __name__ == '__main__':
    # Mode dev
    app.run(host='0.0.0.0', port=5000, debug=True)
