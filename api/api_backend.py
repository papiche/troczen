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
import aiohttp
import threading
import concurrent.futures
from nostr_client import NostrClientSync  # Utiliser le client synchrone pour Flask

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
IPFS_TIMEOUT = int(os.getenv('IPFS_TIMEOUT', '30'))  # Timeout en secondes

# Pool de threads pour les uploads IPFS asynchrones
IPFS_EXECUTOR = concurrent.futures.ThreadPoolExecutor(max_workers=4, thread_name_prefix='ipfs_upload')

# Créer les dossiers
UPLOAD_FOLDER.mkdir(exist_ok=True)
APK_FOLDER.mkdir(exist_ok=True)

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['APK_FOLDER'] = APK_FOLDER
app.config['MAX_CONTENT_LENGTH'] = MAX_FILE_SIZE


# ==================== VALIDATION MIME MAGIC BYTES ====================

# Magic bytes pour les types MIME autorisés
MAGIC_BYTES = {
    'png': [b'\x89PNG\r\n\x1a\n'],
    'jpg': [b'\xff\xd8\xff'],
    'jpeg': [b'\xff\xd8\xff'],
    'webp': [b'RIFF', b'WEBP'],  # WEBP commence par RIFF....WEBP
}

# Mapping extension -> MIME type
MIME_TYPES = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
}


def validate_magic_bytes(file_content: bytes, extension: str) -> bool:
    """
    Valide les magic bytes d'un fichier pour s'assurer qu'il correspond à son extension.
    
    Args:
        file_content: Les premiers bytes du fichier (au moins 12 bytes)
        extension: L'extension du fichier (sans le point)
        
    Returns:
        True si les magic bytes correspondent à l'extension, False sinon
    """
    ext = extension.lower()
    
    if ext not in MAGIC_BYTES:
        return False
    
    magic_signatures = MAGIC_BYTES[ext]
    
    # Pour WEBP, vérifier RIFF au début et WEBP à l'offset 8
    if ext == 'webp':
        if len(file_content) < 12:
            return False
        return file_content[:4] == b'RIFF' and file_content[8:12] == b'WEBP'
    
    # Pour les autres formats, vérifier si le contenu commence par un des magic bytes
    for signature in magic_signatures:
        if file_content.startswith(signature):
            return True
    
    return False


def allowed_file(filename, file_content: bytes = None) -> tuple:
    """
    Vérifier extension fichier et optionnellement les magic bytes.
    
    Args:
        filename: Nom du fichier
        file_content: Contenu du fichier pour validation magic bytes (optionnel)
        
    Returns:
        Tuple (is_valid, error_message)
    """
    if '.' not in filename:
        return False, "Le fichier n'a pas d'extension"
    
    extension = filename.rsplit('.', 1)[1].lower()
    
    if extension not in ALLOWED_EXTENSIONS:
        return False, f"Extension '{extension}' non autorisée. Extensions autorisées: {', '.join(ALLOWED_EXTENSIONS)}"
    
    # Si le contenu est fourni, valider les magic bytes
    if file_content is not None:
        if len(file_content) < 12:
            return False, "Fichier trop petit pour validation"
        
        if not validate_magic_bytes(file_content[:12], extension):
            return False, f"Les magic bytes ne correspondent pas à l'extension '{extension}'. Fichier potentiellement malveillant."
    
    return True, None


def generate_checksum(filepath):
    """Générer SHA256 checksum"""
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


# ==================== IPFS ASYNCHRONE ====================

async def upload_to_ipfs_async(filepath) -> tuple:
    """
    Upload un fichier vers IPFS de manière asynchrone avec aiohttp.
    
    Args:
        filepath: Chemin du fichier à uploader
        
    Returns:
        Tuple (cid, ipfs_url) ou (None, None) si échec
    """
    if not IPFS_ENABLED:
        return None, None
    
    try:
        # Lire le fichier
        with open(filepath, 'rb') as f:
            file_content = f.read()
        
        # Préparer le multipart/form-data pour aiohttp
        # L'API IPFS Kubo utilise multipart avec le fichier
        data = aiohttp.FormData()
        data.add_field(
            'file',
            file_content,
            filename=os.path.basename(filepath),
            content_type='application/octet-stream'
        )
        
        timeout = aiohttp.ClientTimeout(total=IPFS_TIMEOUT)
        
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f'{IPFS_API_URL}/api/v0/add',
                data=data
            ) as response:
                if response.status == 200:
                    result = await response.json()
                    cid = result['Hash']
                    ipfs_url = f'{IPFS_GATEWAY}/ipfs/{cid}'
                    
                    print(f'✅ Fichier uploadé sur IPFS (async): {IPFS_GATEWAY}/ipfs/{cid}')
                    return cid, ipfs_url
                else:
                    error_text = await response.text()
                    print(f'❌ Erreur IPFS API: {response.status} - {error_text}')
                    return None, None
                    
    except asyncio.TimeoutError:
        print(f'❌ Timeout IPFS après {IPFS_TIMEOUT}s')
        return None, None
    except aiohttp.ClientError as e:
        print(f'❌ Erreur connexion IPFS: {e}')
        return None, None
    except Exception as e:
        print(f'❌ Erreur upload IPFS: {e}')
        return None, None


def upload_to_ipfs_sync(filepath) -> tuple:
    """
    Upload synchrone vers IPFS (pour compatibilité et fallback).
    Utilisé dans le thread pool pour ne pas bloquer l'API.
    
    Args:
        filepath: Chemin du fichier à uploader
        
    Returns:
        Tuple (cid, ipfs_url) ou (None, None) si échec
    """
    if not IPFS_ENABLED:
        return None, None
    
    try:
        with open(filepath, 'rb') as f:
            files = {'file': f}
            
            response = requests.post(
                f'{IPFS_API_URL}/api/v0/add',
                files=files,
                timeout=IPFS_TIMEOUT
            )
            
            if response.status_code == 200:
                result = response.json()
                cid = result['Hash']
                ipfs_url = f'{IPFS_GATEWAY}/ipfs/{cid}'
                
                print(f'✅ Fichier uploadé sur IPFS (sync): {IPFS_GATEWAY}/ipfs/{cid}')
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


def upload_to_ipfs_background(filepath, callback=None):
    """
    Lance l'upload IPFS en arrière-plan dans le thread pool.
    Ne bloque pas la requête HTTP.
    
    Args:
        filepath: Chemin du fichier à uploader
        callback: Fonction optionnelle appelée avec (cid, ipfs_url) à la fin
        
    Returns:
        concurrent.futures.Future: Future représentant l'opération
    """
    def _upload_and_callback():
        result = upload_to_ipfs_sync(filepath)
        cid, ipfs_url = result
        
        # Sauvegarder les métadonnées si upload réussi
        if cid and ipfs_url:
            save_ipfs_metadata(Path(filepath), cid, ipfs_url)
        
        if callback:
            callback(cid, ipfs_url)
        return result
    
    return IPFS_EXECUTOR.submit(_upload_and_callback)


# Garder l'ancienne fonction pour compatibilité
def upload_to_ipfs(filepath):
    """
    Upload un fichier vers IPFS via l'API locale (version synchrone).
    DEPRECATED: Utiliser upload_to_ipfs_async ou upload_to_ipfs_background
    
    Retourne: (cid, ipfs_url) ou (None, None) si échec
    """
    return upload_to_ipfs_sync(filepath)


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
    """
    Upload image (logo, bandeau, avatar) pour profils Nostr
    
    Sécurité:
    - Validation de l'extension du fichier
    - Validation des magic bytes pour éviter les fichiers malveillants
    - Upload IPFS en arrière-plan pour ne pas bloquer la requête
    """
    
    # Vérifier présence fichier
    if 'file' not in request.files:
        return jsonify({'error': 'No file provided'}), 400
    
    file = request.files['file']
    
    if file.filename == '':
        return jsonify({'error': 'No file selected'}), 400
    
    # Lire le contenu du fichier pour validation magic bytes
    file_content = file.read()
    file.seek(0)  # Remettre le curseur au début pour sauvegarde
    
    # Validation extension ET magic bytes
    is_valid, error_msg = allowed_file(file.filename, file_content)
    if not is_valid:
        return jsonify({'error': error_msg}), 400
    
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
    
    # URL de fallback (locale) - toujours disponible
    local_url = f"/uploads/{new_filename}"
    
    # ✅ Upload IPFS en arrière-plan (non-bloquant)
    # Le client recevra l'URL locale immédiatement, et l'URL IPFS sera disponible plus tard
    ipfs_upload_future = upload_to_ipfs_background(filepath)
    
    # Pour la réponse initiale, on indique que l'upload IPFS est en cours
    # Le client peut vérifier le statut via /api/upload/status/<filename>
    
    return jsonify({
        'success': True,
        'url': local_url,              # URL locale immédiatement disponible
        'local_url': local_url,        # Toujours disponible en fallback
        'ipfs_url': None,              # Sera disponible après upload
        'ipfs_cid': None,              # Sera disponible après upload
        'ipfs_status': 'pending',      # pending, completed, failed
        'filename': new_filename,
        'checksum': checksum,
        'size': filepath.stat().st_size,
        'uploaded_at': datetime.now().isoformat(),
        'storage': 'local',            # Local pour l'instant, IPFS en cours
        'type': image_type,
        'message': 'Fichier uploadé localement. Upload IPFS en cours.'
    }), 201


@app.route('/api/upload/status/<filename>', methods=['GET'])
def upload_status(filename):
    """
    Vérifier le statut de l'upload IPFS pour un fichier.
    
    Cette endpoint permet au client de vérifier si l'upload IPFS
    a été complété avec succès.
    """
    filepath = UPLOAD_FOLDER / secure_filename(filename)
    
    if not filepath.exists():
        return jsonify({'error': 'File not found'}), 404
    
    # Vérifier si un fichier .ipfs_meta existe (créé après upload réussi)
    meta_file = filepath.with_suffix(filepath.suffix + '.ipfs_meta')
    
    if meta_file.exists():
        try:
            with open(meta_file, 'r') as f:
                meta = json.load(f)
            return jsonify({
                'filename': filename,
                'ipfs_status': 'completed',
                'ipfs_url': meta.get('ipfs_url'),
                'ipfs_cid': meta.get('ipfs_cid'),
                'uploaded_at': meta.get('uploaded_at')
            })
        except Exception as e:
            return jsonify({
                'filename': filename,
                'ipfs_status': 'unknown',
                'error': str(e)
            })
    
    return jsonify({
        'filename': filename,
        'ipfs_status': 'pending',
        'message': 'Upload IPFS en cours ou non démarré'
    })


def save_ipfs_metadata(filepath, cid, ipfs_url):
    """
    Sauvegarder les métadonnées IPFS après upload réussi.
    Permet au client de vérifier le statut via /api/upload/status/
    """
    meta_file = filepath.with_suffix(filepath.suffix + '.ipfs_meta')
    try:
        with open(meta_file, 'w') as f:
            json.dump({
                'ipfs_cid': cid,
                'ipfs_url': ipfs_url,
                'uploaded_at': datetime.now().isoformat()
            }, f)
    except Exception as e:
        print(f'❌ Erreur sauvegarde métadonnées IPFS: {e}')


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
        # Créer le client Nostr SYNCHRONE (adapté pour Flask)
        client = NostrClientSync(relay_url=NOSTR_RELAY)
        
        # Connexion synchrone
        if not client.connect():
            print(f"❌ Impossible de se connecter au relai Nostr")
            return fetch_local_marche_data(market_name)
        
        # Récupération synchrone des données
        data = client.get_merchants_with_bons(market_name)
        client.disconnect()
        
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
    print(f'🌻 [market_page] Rendu de la page pour: {market_name}')
    
    # Récupérer les données du marché depuis Nostr
    print(f'🌻 [market_page] Récupération des données Nostr...')
    marche_data = fetch_marche_data(market_name)
    
    merchants_count = len(marche_data.get('merchants', []))
    total_bons = marche_data.get('total_bons', 0)
    print(f'🌻 [market_page] Données reçues: {merchants_count} marchands, {total_bons} bons')
    
    # Log détaillé des marchands
    for i, m in enumerate(marche_data.get('merchants', [])[:5]):
        print(f'  └─ Marchand {i+1}: {m.get("name", "N/A")} ({m.get("bons_count", 0)} bons, issuer: {m.get("pubkey", "N/A")[:16]}...)')
    
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
    print(f'🌻 [API] GET /api/nostr/marche/{market_name}')
    
    marche_data = fetch_marche_data(market_name)
    
    print(f'🌻 [API] Réponse: {marche_data.get("total_merchants", 0)} marchands, {marche_data.get("total_bons", 0)} bons')
    
    return jsonify({
        'success': True,
        'data': marche_data,
        'source': 'nostr_strfry'
    })


@app.route('/api/nostr/profiles', methods=['GET'])
def get_nostr_profiles():
    """
    API pour récupérer tous les profils Nostr (kind 0)
    Utile pour l'affichage du dashboard principal
    """
    NOSTR_RELAY = os.getenv('NOSTR_RELAY', 'ws://127.0.0.1:7777')
    NOSTR_ENABLED = os.getenv('NOSTR_ENABLED', 'true').lower() == 'true'
    
    if not NOSTR_ENABLED:
        return jsonify({
            'success': False,
            'error': 'Nostr disabled',
            'profiles': []
        })
    
    try:
        # Utiliser le client synchrone (adapté pour Flask)
        client = NostrClientSync(relay_url=NOSTR_RELAY)
        
        if not client.connect():
            return jsonify({
                'success': False,
                'error': 'Failed to connect to Nostr relay',
                'profiles': []
            })
        
        profiles = client.get_merchant_profiles()
        client.disconnect()
        
        return jsonify({
            'success': True,
            'profiles': profiles,
            'count': len(profiles),
            'source': 'nostr_strfry'
        })
        
    except Exception as e:
        print(f"❌ Erreur récupération profils Nostr: {e}")
        return jsonify({
            'success': False,
            'error': str(e),
            'profiles': []
        })


@app.route('/api/nostr/bons/all', methods=['GET'])
def get_all_bons_no_filter():
    """
    API pour récupérer TOUS les bons (kind 30303) sans filtre de marché
    Utile pour diagnostiquer quels bons existent sur le relai
    """
    print('🌻 [API] GET /api/nostr/bons/all (sans filtre marché)')
    
    NOSTR_RELAY = os.getenv('NOSTR_RELAY', 'ws://127.0.0.1:7777')
    NOSTR_ENABLED = os.getenv('NOSTR_ENABLED', 'true').lower() == 'true'
    
    if not NOSTR_ENABLED:
        return jsonify({
            'success': False,
            'error': 'Nostr disabled',
            'bons': []
        })
    
    try:
        # Utiliser le client synchrone (adapté pour Flask)
        client = NostrClientSync(relay_url=NOSTR_RELAY)
        
        if not client.connect():
            return jsonify({
                'success': False,
                'error': 'Failed to connect to Nostr relay',
                'bons': []
            })
        
        # Passer None pour récupérer tous les bons sans filtre
        bons = client.get_bons(None)
        client.disconnect()
        
        # Grouper par marché pour stats
        markets = {}
        for bon in bons:
            m = bon.get('market', 'unknown')
            markets[m] = markets.get(m, 0) + 1
        
        print(f'🌻 [API] {len(bons)} bons trouvés sur {len(markets)} marchés: {markets}')
        
        return jsonify({
            'success': True,
            'bons': bons,
            'count': len(bons),
            'markets': markets,
            'source': 'nostr_strfry'
        })
        
    except Exception as e:
        print(f"❌ Erreur récupération bons Nostr: {e}")
        return jsonify({
            'success': False,
            'error': str(e),
            'bons': []
        })


@app.route('/api/nostr/bons', methods=['GET'])
def get_all_bons():
    """
    API pour récupérer tous les bons (kind 30303)
    Optionnel: filtrer par marché avec ?market=nom_marche
    """
    NOSTR_RELAY = os.getenv('NOSTR_RELAY', 'ws://127.0.0.1:7777')
    NOSTR_ENABLED = os.getenv('NOSTR_ENABLED', 'true').lower() == 'true'
    market_name = request.args.get('market')
    
    print(f'🌻 [API] GET /api/nostr/bons (market={market_name})')
    
    if not NOSTR_ENABLED:
        return jsonify({
            'success': False,
            'error': 'Nostr disabled',
            'bons': []
        })
    
    try:
        # Utiliser le client synchrone (adapté pour Flask)
        client = NostrClientSync(relay_url=NOSTR_RELAY)
        
        if not client.connect():
            return jsonify({
                'success': False,
                'error': 'Failed to connect to Nostr relay',
                'bons': []
            })
        
        bons = client.get_bons(market_name)
        client.disconnect()
        
        print(f'🌻 [API] {len(bons)} bons trouvés pour market={market_name}')
        
        return jsonify({
            'success': True,
            'bons': bons,
            'count': len(bons),
            'market': market_name,
            'source': 'nostr_strfry'
        })
        
    except Exception as e:
        print(f"❌ Erreur récupération bons Nostr: {e}")
        return jsonify({
            'success': False,
            'error': str(e),
            'bons': []
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


# ==================== FEEDBACK GITHUB ====================

@app.route('/api/feedback', methods=['POST'])
def submit_feedback():
    """
    Soumettre un feedback utilisateur vers GitHub Issues
    🔒 Sécurisé: Le token GitHub reste côté serveur (.env)
    """
    
    # Configuration GitHub
    GITHUB_TOKEN = os.getenv('GITHUB_TOKEN')
    GITHUB_REPO = os.getenv('GITHUB_REPO', 'copylaradio/TrocZen')
    
    if not GITHUB_TOKEN:
        return jsonify({
            'success': False,
            'error': 'GitHub integration not configured on server'
        }), 503
    
    # Récupérer les données du feedback
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    
    title = data.get('title', '')
    description = data.get('description', '')
    feedback_type = data.get('type', 'feedback')  # bug, feature, feedback
    user_email = data.get('email', 'anonymous')
    app_version = data.get('app_version', 'unknown')
    platform = data.get('platform', 'unknown')
    
    if not title or not description:
        return jsonify({'error': 'Title and description are required'}), 400
    
    # Formater le titre avec emoji selon le type
    type_emoji = {
        'bug': '🐛',
        'feature': '✨',
        'feedback': '💬',
        'question': '❓'
    }
    emoji = type_emoji.get(feedback_type, '💬')
    issue_title = f"{emoji} [{feedback_type.upper()}] {title}"
    
    # Formater le corps de l'issue
    issue_body = f"""## Feedback Utilisateur

**Type**: {feedback_type}
**Version**: {app_version}
**Plateforme**: {platform}
**Email**: {user_email}
**Date**: {datetime.now().isoformat()}

---

### Description

{description}

---

*Ce feedback a été soumis automatiquement via l'application TrocZen.*
"""
    
    # Préparer la requête GitHub
    github_api_url = f'https://api.github.com/repos/{GITHUB_REPO}/issues'
    headers = {
        'Authorization': f'token {GITHUB_TOKEN}',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json'
    }
    
    # Labels selon le type
    labels = [feedback_type]
    if feedback_type == 'bug':
        labels.append('user-reported')
    
    payload = {
        'title': issue_title,
        'body': issue_body,
        'labels': labels
    }
    
    try:
        # Envoyer vers GitHub
        response = requests.post(
            github_api_url,
            headers=headers,
            json=payload,
            timeout=10
        )
        
        if response.status_code == 201:
            issue_data = response.json()
            print(f"✅ Issue GitHub créée: #{issue_data['number']}")
            
            return jsonify({
                'success': True,
                'message': 'Feedback envoyé avec succès',
                'issue_number': issue_data['number'],
                'issue_url': issue_data['html_url']
            }), 201
        else:
            print(f"❌ Erreur GitHub API: {response.status_code} - {response.text}")
            return jsonify({
                'success': False,
                'error': f'GitHub API error: {response.status_code}'
            }), 500
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Erreur connexion GitHub: {e}")
        return jsonify({
            'success': False,
            'error': 'Failed to connect to GitHub'
        }), 500
    except Exception as e:
        print(f"❌ Erreur feedback: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


if __name__ == '__main__':
    # Mode dev
    app.run(host='0.0.0.0', port=5000, debug=True)
