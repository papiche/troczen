import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:hex/hex.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../models/qr_payload_v2.dart';
import '../services/qr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../widgets/bon_reception_confirm_sheet.dart';
import 'ack_screen.dart';

class ScanScreen extends StatefulWidget {
  final User user;

  const ScanScreen({super.key, required this.user});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  MobileScannerController? _scannerController;
  final _qrService = QRService();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();

  bool _isProcessing = false;
  bool _permissionGranted = false;
  bool _isCheckingPermission = true;
  bool _permanentlyDenied = false;
  String _statusMessage = 'Scannez le QR code du bon';

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  /// ✅ UI/UX: Vérification et demande de permission caméra
  Future<void> _checkCameraPermission() async {
    setState(() => _isCheckingPermission = true);

    final status = await Permission.camera.status;
    
    if (status.isGranted) {
      _initScanner();
      setState(() {
        _permissionGranted = true;
        _isCheckingPermission = false;
      });
    } else if (status.isDenied) {
      // Première demande de permission
      final result = await Permission.camera.request();
      if (result.isGranted) {
        _initScanner();
        setState(() {
          _permissionGranted = true;
          _isCheckingPermission = false;
        });
      } else if (result.isPermanentlyDenied) {
        setState(() {
          _permanentlyDenied = true;
          _isCheckingPermission = false;
        });
      } else {
        setState(() {
          _permissionGranted = false;
          _isCheckingPermission = false;
          _statusMessage = 'Permission caméra refusée';
        });
      }
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _permanentlyDenied = true;
        _isCheckingPermission = false;
      });
    } else {
      setState(() => _isCheckingPermission = false);
    }
  }

  /// Initialise le scanner après obtention de la permission
  void _initScanner() {
    _scannerController = MobileScannerController(
      formats: [BarcodeFormat.qrCode],
    );
  }

  /// Ouvre les paramètres de l'application
  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final barcode = capture.barcodes.first;
    // ✅ CORRECTION P0: Utiliser rawValue au lieu de rawBytes
    // rawBytes contient les octets bruts du QR (headers, padding, etc.)
    // rawValue contient la chaîne proprement décodée par la bibliothèque
    final base64String = barcode.rawValue;
    if (base64String == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Vérification en cours...';
    });

    try {
      // ✅ CORRECTION P0: Le QR code est encodé en Base64
      // rawValue contient directement la chaîne Base64
      final decodedBytes = base64Decode(base64String);
      
      // Tenter de décoder en QR v2
      final qrV2Payload = _qrService.decodeQr(decodedBytes);
      
      if (qrV2Payload != null) {
        // Format QR v2 détecté - Fonctionnement offline complet
        await _handleQrV2(qrV2Payload);
        return;
      }

      // ❌ SÉCURITÉ: Format v1 (113 octets) rejeté - manque de métadonnées
      // Les QR codes V1 peuvent créer des bons avec valeur 0.0
      // Forcer l'usage du format V2 (240 octets) avec métadonnées complètes
      _showError('QR code obsolète (V1).\nVeuillez utiliser un QR code au format V2.');
      return;

    } catch (e) {
      _showError('Erreur de décodage: $e');
    } finally {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Scannez le QR code du bon';
      });
    }
  }

  /// Traite un QR code v2 (160 octets) avec toutes les métadonnées
  Future<void> _handleQrV2(QrPayloadV2 payload) async {
    if (!mounted) return;

    // Afficher la bottom sheet de confirmation AVANT d'accepter
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (context) => BonReceptionConfirmSheet(
        value: payload.value,
        issuerName: payload.issuerName,
        issuerNpub: payload.issuerNpub,
        onAccept: () => Navigator.pop(context, true),
        onDecline: () => Navigator.pop(context, false),
      ),
    );

    if (confirmed != true || !mounted) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Réception annulée';
      });
      return;
    }

    setState(() => _statusMessage = 'Déchiffrement en cours...');

    // Récupérer P3 depuis le cache
    final p3 = await _storageService.getP3FromCache(payload.bonId);
    if (p3 == null) {
      _showError('Part P3 non trouvée.\nSynchronisez d\'abord avec le marché.');
      return;
    }

    // Déchiffrer P2 avec AES-GCM (format v2 inclut le tag séparément)
    final encryptedP2WithTag = Uint8List.fromList([
      ...payload.encryptedP2,
      ...payload.p2Tag,
    ]);
    
    final p2 = await _cryptoService.decryptP2(
      HEX.encode(encryptedP2WithTag),
      HEX.encode(payload.p2Nonce),
      p3,
    );

    setState(() => _statusMessage = 'Bon validé ! Génération de la confirmation...');

    // Récupérer le nom du marché depuis storage
    final market = await _storageService.getMarket();
    final marketName = market?.name ?? 'Marché Local';

    // Créer le bon avec les métadonnées du payload v2
    final bon = Bon(
      bonId: payload.bonId,
      value: payload.value,
      issuerName: payload.issuerName,
      issuerNpub: payload.issuerNpub,
      p2: p2,
      p3: null, // P3 reste dans le cache
      status: BonStatus.active,
      createdAt: payload.emittedAt,
      marketName: marketName,
    );

    await _storageService.saveBon(bon);

    if (!mounted) return;

    // ✅ CORRECTION HANDSHAKE: Utiliser le challenge du payload QR v2
    // Whitepaper (§3.2 Étape 1): Le Donneur génère le challenge, le Receveur le signe.
    // Le challenge est déjà inclus dans le QrPayloadV2 et extrait lors du décodage.
    final challengeHex = payload.challengeHex;

    // Naviguer vers l'écran ACK avec le challenge du Donneur
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AckScreen(
          user: widget.user,
          bon: bon,
          challenge: challengeHex,  // ✅ Challenge du Donneur, pas généré localement
        ),
      ),
    );
  }

  /// Traite un QR code v1 (format 113 ou 177 octets)
  /// ✅ CORRECTION P0-C: Vérification de la signature du QR1
  Future<void> _handleQrV1(Uint8List rawBytes) async {
    // Décoder le QR binaire v1
    final offerData = _qrService.decodeOffer(rawBytes);

    // Vérifier le TTL
    if (_qrService.isExpired(offerData['timestamp'], offerData['ttl'])) {
      _showError('QR code expiré');
      return;
    }

    // ✅ CORRECTION P0-C: Vérifier la signature si présente
    // Whitepaper (007.md §3.2): Le QR1 doit être signé par le donneur
    final signature = offerData['signature'];
    if (signature != null && signature.isNotEmpty) {
      // Reconstruire le message signé: bonId || p2Cipher || nonce || challenge || timestamp || ttl
      final messageToVerify = offerData['bonId'] +
          offerData['p2Cipher'] +
          offerData['nonce'] +
          offerData['challenge'] +
          offerData['timestamp'].toRadixString(16).padLeft(8, '0') +
          offerData['ttl'].toRadixString(16).padLeft(2, '0');
      
      // Vérifier la signature avec la clé publique du bon (bonId = pk_B)
      final isSignatureValid = _cryptoService.verifySignature(
        messageToVerify,
        signature,
        offerData['bonId'],
      );
      
      if (!isSignatureValid) {
        _showError('⚠️ Signature invalide !\n\nCe QR code n\'a pas été généré par le propriétaire du bon.\nTransfert refusé pour votre sécurité.');
        return;
      }
      
      debugPrint('✅ Signature QR1 valide - le donneur prouve la propriété du bon');
    } else {
      // QR sans signature (ancien format) - avertir mais accepter
      debugPrint('⚠️ QR1 sans signature (format ancien) - accepté pour compatibilité');
    }

    // Récupérer P3 depuis le cache
    final p3 = await _storageService.getP3FromCache(offerData['bonId']);
    if (p3 == null) {
      _showError('Part P3 non trouvée.\nSynchronisez d\'abord avec le marché.');
      return;
    }

    // Déchiffrer P2 avec K_P2 = hash(P3)
    final p2 = await _cryptoService.decryptP2(
      offerData['p2Cipher'],
      offerData['nonce'],
      p3,
    );

    setState(() => _statusMessage = 'Bon validé ! Génération de la confirmation...');

    // ✅ CORRECTION BUG P0: Créer le bon à la volée au lieu de "Bon inconnu"
    // Le receveur n'a pas encore le bon dans son wallet avant réception
    final existingBon = await _storageService.getBonById(offerData['bonId']);
    
    // Récupérer le nom du marché depuis storage
    final market = await _storageService.getMarket();
    final marketName = market?.name ?? 'Marché Local';
    
    final bon = existingBon ?? Bon(
      bonId: offerData['bonId'],
      value: (offerData['value'] ?? 0.0).toDouble(),
      issuerName: offerData['issuerName'] ?? 'Inconnu',
      issuerNpub: offerData['issuerNpub'] ?? '',
      p2: p2,
      p3: null, // P3 reste dans le cache, pas dans l'objet
      status: BonStatus.active,
      createdAt: DateTime.fromMillisecondsSinceEpoch(offerData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      marketName: marketName,
    );

    // Si le bon existait déjà, mettre à jour avec P2
    final updatedBon = existingBon != null
      ? existingBon.copyWith(status: BonStatus.active, p2: p2)
      : bon;

    await _storageService.saveBon(updatedBon);

    if (!mounted) return;

    // Naviguer vers l'écran ACK
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AckScreen(
          user: widget.user,
          bon: updatedBon,
          challenge: offerData['challenge'],
        ),
      ),
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Erreur', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Scanner un bon'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: _buildBody(),
    );
  }

  /// ✅ UI/UX: Construction dynamique du body selon l'état de la permission
  Widget _buildBody() {
    // État de vérification en cours
    if (_isCheckingPermission) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFFFB347)),
            SizedBox(height: 24),
            Text(
              'Vérification des permissions...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Permission refusée définitivement
    if (_permanentlyDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                size: 80,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              const Text(
                'Accès caméra refusé',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'L\'application a besoin d\'accéder à votre caméra pour scanner les QR codes.\n\n'
                'Vous avez précédemment refusé cette permission. '
                'Veuillez l\'activer dans les paramètres de l\'application.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Ouvrir les paramètres'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A7EA4),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _checkCameraPermission,
                child: const Text(
                  'Réessayer',
                  style: TextStyle(color: Color(0xFFFFB347)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Permission non accordée
    if (!_permissionGranted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                size: 80,
                color: Colors.orange,
              ),
              const SizedBox(height: 24),
              const Text(
                'Permission caméra requise',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Pour scanner des QR codes, l\'application doit accéder à votre caméra.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _checkCameraPermission,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Autoriser la caméra'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A7EA4),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Permission accordée - afficher le scanner
    return Column(
      children: [
        // Instructions
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E1E1E),
          child: Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ),

        // Scanner
        Expanded(
          child: Stack(
            children: [
              if (_scannerController != null)
                MobileScanner(
                  controller: _scannerController!,
                  onDetect: _handleScan,
                ),
              
              // Overlay
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 3),
                ),
                margin: const EdgeInsets.all(48),
              ),

              if (_isProcessing)
                Container(
                  color: Colors.black.withOpacity(0.7),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFFB347),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Boutons
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _scannerController != null
                    ? () => _scannerController!.toggleTorch()
                    : null,
                icon: const Icon(Icons.flash_on),
                label: const Text('Flash'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2A2A),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _scannerController != null
                    ? () => _scannerController!.switchCamera()
                    : null,
                icon: const Icon(Icons.flip_camera_ios),
                label: const Text('Caméra'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2A2A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
