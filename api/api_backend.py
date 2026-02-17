#!/usr/bin/env python3
"""
TrocZen API Backend
Gère l'upload des logos commerçants et la distribution d'APK
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
        for byte_block in iter(lambda f.read(4096), b""):
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


# ==================== PAGE PRESENTATION ====================

@app.route('/market/<market_name>')
def market_page(market_name):
    """Page de présentation du marché"""
    
    # Récupérer profils du marché
    profiles = []
    for profile_file in UPLOAD_FOLDER.glob('*.json'):
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
