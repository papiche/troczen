import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:crypto/crypto.dart';
import '../models/user.dart';
import '../models/market.dart';
import '../models/market_profile_info.dart';
import '../services/storage_service.dart';
import '../services/qr_service.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../services/logger_service.dart';
import '../services/image_compression_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Écran de gestion des marchés multi-marchés
/// 
/// Fonctionnalités:
/// - Liste des marchés rejoints
/// - Génération de QR pour partager un marché
/// - Scan de QR pour rejoindre un marché
/// - Sélection du marché actif
class MarketScreen extends StatefulWidget {
  final User user;

  const MarketScreen({super.key, required this.user});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final _storageService = StorageService();
  final _qrService = QRService();
  final _cryptoService = CryptoService();
  
  List<Market> _markets = [];
  Market? _activeMarket;
  bool _isLoading = true;
  bool _isScanning = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadMarkets();
  }

  Future<void> _loadMarkets() async {
    setState(() => _isLoading = true);
    
    try {
      final markets = await _storageService.getMarkets();
      final activeMarket = await _storageService.getActiveMarket();
      
      setState(() {
        _markets = markets;
        _activeMarket = activeMarket;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('MarketScreen', 'Erreur chargement marchés', e);
      setState(() => _isLoading = false);
    }
  }

  /// Active un marché comme marché par défaut
  /// ✅ AMÉLIORÉ: Utilise marketId pour l'unicité
  Future<void> _setActiveMarket(Market market) async {
    final success = await _storageService.setActiveMarket(market.marketId);
    if (success) {
      setState(() => _activeMarket = market);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marché "${market.fullName}" défini comme actif'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  /// Supprime un marché de la liste
  /// ✅ AMÉLIORÉ: Utilise marketId pour l'unicité
  Future<void> _removeMarket(Market market) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirmer', style: TextStyle(color: Colors.white)),
        content: Text(
          'Voulez-vous quitter le marché "${market.fullName}" ?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitter', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storageService.removeMarket(market.marketId);
      await _loadMarkets();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marché "${market.fullName}" quitté'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Affiche le QR de connexion Wi-Fi pour un marché
  void _showWifiQr(Market market) {
    final wifiPassword = _cryptoService.deriveWifiPassword(market.seedMarket);
    final qrData = _qrService.generateWifiQrData('TrocZen-Marche', wifiPassword);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[800],
                    ),
                    child: Icon(
                      Icons.wifi,
                      color: Colors.blue[400],
                      size: 24,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Réseau Wi-Fi du marché',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          market.displayName,
                          style: TextStyle(
                            color: Colors.blue[300],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // QR Code
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: const Color(0xFFFFFFFF),
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
              const SizedBox(height: 24),
              
              // Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[300], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Scannez ce QR avec l\'appareil photo de votre téléphone pour vous connecter au réseau Wi-Fi du marché.',
                        style: TextStyle(color: Colors.blue[300], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Détails
              _buildDetailRow('Réseau (SSID)', 'TrocZen-Marche'),
              _buildDetailRow('Mot de passe', wifiPassword),
            ],
          ),
        ),
      ),
    );
  }

  /// Affiche le QR de partage pour un marché
  void _showMarketQr(Market market) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // ✅ v2.0.1: Logo et nom du marché
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo du marché (si disponible)
                  if (market.picture != null)
                    Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[800],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          market.picture!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.store,
                            color: Colors.orange[700],
                            size: 24,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[800],
                      ),
                      child: Icon(
                        Icons.store,
                        color: Colors.orange[700],
                        size: 24,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Partager le marché',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          market.displayName,
                          style: TextStyle(
                            color: Colors.orange[300],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // QR Code
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _qrService.buildMarketQrWidget(
                  name: market.name,
                  seedMarket: market.seedMarket,
                  relayUrl: market.relayUrl,
                  validUntil: market.validUntil,
                  size: 220,
                ),
              ),
              const SizedBox(height: 24),
              
              // Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[300], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ce QR permet à un autre commerçant de rejoindre ce marché.',
                        style: TextStyle(color: Colors.blue[300], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Détails
              _buildDetailRow('Nom', market.name),
              if (market.relayUrl != null)
                _buildDetailRow('Relais', market.relayUrl!),
              _buildDetailRow('Expire le', _formatDate(market.validUntil)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Ouvre le scanner QR pour rejoindre un marché
  void _startScanMarket() {
    setState(() => _isScanning = true);
  }

  /// Traite le résultat du scan QR
  /// ✅ v2.0.1: Affiche une carte d'invitation avec les métadonnées du marché
  Future<void> _handleQrScan(String data) async {
    setState(() => _isScanning = false);
    
    try {
      // Décoder le QR marché
      final marketData = _qrService.decodeMarketQr(data);
      
      if (marketData == null) {
        _showError('QR code invalide. Ce n\'est pas un QR de marché ẐEN.');
        return;
      }
      
      // Vérifier si le marché n'est pas expiré
      final validUntil = marketData['validUntil'] as DateTime;
      if (validUntil.isBefore(DateTime.now())) {
        _showError('Ce marché a expiré. Demandez un nouveau QR à l\'organisateur.');
        return;
      }
      
      final seedMarket = marketData['seedMarket'] as String;
      final marketName = marketData['name'] as String;
      final relayUrl = marketData['relayUrl'] as String?;
      
      // Vérifier si déjà membre (par marketId)
      final marketId = Market.generateMarketId(seedMarket);
      final existingMarkets = await _storageService.getMarkets();
      if (existingMarkets.any((m) => m.marketId == marketId)) {
        _showError('Vous êtes déjà membre de ce marché.');
        return;
      }
      
      // ✅ v2.0.1: Récupérer le profil Nostr du marché pour afficher la carte d'invitation
      MarketProfileInfo? profileInfo;
      if (relayUrl != null) {
        profileInfo = await _fetchMarketProfile(seedMarket, relayUrl);
      }
      
      // ✅ v2.0.1: Afficher la carte d'invitation
      if (mounted) {
        final accepted = await _showMarketInvitationCard(
          marketName: marketName,
          marketId: marketId,
          seedMarket: seedMarket,
          validUntil: validUntil,
          relayUrl: relayUrl,
          profileInfo: profileInfo,
        );
        
        if (accepted != true) return;
      }
      
      // Créer l'objet Market avec les métadonnées récupérées
      final market = Market(
        name: marketName,
        seedMarket: seedMarket,
        validUntil: validUntil,
        relayUrl: relayUrl,
        about: profileInfo?.about,
        picture: profileInfo?.picture,
        banner: profileInfo?.banner,
      );
      
      // Ajouter le marché
      final added = await _storageService.addMarket(market);
      if (!added) {
        _showError('Erreur lors de l\'ajout du marché.');
        return;
      }
      
      // Synchroniser immédiatement les P3 de ce marché
      await _syncNewMarket(market);
      
      // Recharger la liste
      await _loadMarkets();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marché "${market.displayName}" rejoint avec succès !'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      Logger.error('MarketScreen', 'Erreur scan QR marché', e);
      _showError('Erreur lors du traitement du QR: $e');
    }
  }
  
  /// ✅ v2.0.1: Récupère le profil Nostr du marché (Kind 0)
  Future<MarketProfileInfo?> _fetchMarketProfile(String seedMarket, String relayUrl) async {
    try {
      // Dériver l'identité du marché
      final marketIdentity = _cryptoService.deriveMarketIdentity(seedMarket);
      final npubMarket = marketIdentity['npub']!;
      
      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );
      
      await nostrService.connect(relayUrl);
      
      // Récupérer le profil (Kind 0)
      final profile = await nostrService.fetchUserProfile(npubMarket);
      await nostrService.disconnect();
      
      if (profile != null) {
        return MarketProfileInfo(
          about: profile.about,
          picture: profile.picture,
          banner: profile.banner,
        );
      }
    } catch (e) {
      Logger.error('MarketScreen', 'Erreur récupération profil marché', e);
    }
    return null;
  }
  
  /// ✅ v2.0.1: Affiche la carte d'invitation du marché
  Future<bool?> _showMarketInvitationCard({
    required String marketName,
    required String marketId,
    required String seedMarket,
    required DateTime validUntil,
    String? relayUrl,
    MarketProfileInfo? profileInfo,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: EdgeInsets.zero,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ v2.0.1: Bannière (support Base64 et URL)
              ImageCompressionService.buildImage(
                uri: profileInfo?.banner,
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                errorWidget: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.3),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Center(
                    child: Icon(Icons.store, size: 48, color: Colors.orange[700]),
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Logo et nom
                    Row(
                      children: [
                        // ✅ v2.0.1: Logo (support Base64 et URL)
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ImageCompressionService.buildImage(
                              uri: profileInfo?.picture,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorWidget: Icon(
                                Icons.store,
                                size: 28,
                                color: Colors.orange[700],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                marketName.replaceAll('_', ' '),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ID: $marketId',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    // Description
                    if (profileInfo?.about != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          profileInfo!.about!,
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 16),
                    
                    // Informations
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: Column(
                        children: [
                          _buildInfoRow(
                            icon: Icons.calendar_today,
                            label: 'Valide jusqu\'au',
                            value: '${validUntil.day.toString().padLeft(2, '0')}/${validUntil.month.toString().padLeft(2, '0')}/${validUntil.year}',
                          ),
                          if (relayUrl != null) ...[
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              icon: Icons.dns,
                              label: 'Relais',
                              value: relayUrl.replaceAll('wss://', '').replaceAll('ws://', ''),
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      'Vous avez été invité à rejoindre ce marché',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Rejoindre'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.orange[700]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Synchronise les P3 d'un nouveau marché
  Future<void> _syncNewMarket(Market market) async {
    setState(() => _isSyncing = true);
    
    try {
      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );
      
      if (market.relayUrl != null) {
        await nostrService.connect(market.relayUrl!);
        await nostrService.syncMarketP3s(market);
      }
      
      Logger.success('MarketScreen', 'Synchronisation terminée pour ${market.name}');
    } catch (e) {
      Logger.error('MarketScreen', 'Erreur sync nouveau marché', e);
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  /// Affiche le formulaire pour créer un nouveau marché manuellement
  /// ✅ v2.0.1: Inclut les métadonnées de profil Nostr (about, picture, banner)
  void _showCreateMarketDialog() {
    final nameController = TextEditingController();
    final seedController = TextEditingController();
    final relayController = TextEditingController();
    final aboutController = TextEditingController();
    final pictureController = TextEditingController();
    final bannerController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isGeneratingSeed = false;
    bool isPublishingProfile = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Créer un marché', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section: Informations de base
                  Text(
                    'Informations de base',
                    style: TextStyle(color: Colors.orange[300], fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nom du marché *',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Le nom est obligatoire';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Seed avec bouton de génération
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: seedController,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Seed (64 caractères hex) *',
                            labelStyle: TextStyle(color: Colors.grey),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.length != 64) {
                              return 'La seed doit faire 64 caractères';
                            }
                            if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
                              return 'La seed doit être en hexadécimal';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: isGeneratingSeed ? null : () {
                          // Générer une seed aléatoire
                          final random = DateTime.now().millisecondsSinceEpoch.toString() +
                              DateTime.now().microsecond.toString();
                          final bytes = <int>[];
                          for (int i = 0; i < 32; i++) {
                            bytes.add((random.hashCode + i) % 256);
                          }
                          // Utiliser SHA256 pour avoir une seed de 32 bytes
                          final digest = sha256.convert(bytes);
                          seedController.text = digest.toString();
                          setDialogState(() {});
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Générer', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[700],
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: relayController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'URL du relais Nostr (optionnel)',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      hintText: 'wss://relay.example.com',
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(color: Colors.grey),
                  const SizedBox(height: 16),
                  
                  // Section: Profil Nostr (optionnel)
                  Text(
                    'Profil Nostr du marché (optionnel)',
                    style: TextStyle(color: Colors.orange[300], fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ces informations seront visibles par tous les membres',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: aboutController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      hintText: 'Marché bio du samedi matin...',
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  
                  // ✅ v2.0.1: Logo avec sélection d'image locale (Base64)
                  Row(
                    children: [
                      // Aperçu du logo
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: pictureController.text.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ImageCompressionService.isBase64DataUri(pictureController.text)
                                    ? Image.memory(
                                        ImageCompressionService.extractBytesFromDataUri(pictureController.text)!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(Icons.store, color: Colors.orange[700], size: 24),
                                      )
                                    : Image.network(
                                        pictureController.text,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(Icons.store, color: Colors.orange[700], size: 24),
                                      ),
                              )
                            : Icon(Icons.store, color: Colors.orange[700], size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Logo / Avatar', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final imageService = ImageCompressionService();
                                    final dataUri = await imageService.pickAndCompressAvatar();
                                    if (dataUri != null) {
                                      pictureController.text = dataUri;
                                      setDialogState(() {});
                                    }
                                  },
                                  icon: const Icon(Icons.photo_library, size: 16),
                                  label: const Text('Galerie', style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange[700],
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (pictureController.text.isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      pictureController.clear();
                                      setDialogState(() {});
                                    },
                                    child: const Text('Effacer', style: TextStyle(fontSize: 11)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // ✅ v2.0.1: Bannière avec sélection d'image locale (Base64)
                  Row(
                    children: [
                      // Aperçu de la bannière
                      Container(
                        width: 80,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: bannerController.text.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: ImageCompressionService.isBase64DataUri(bannerController.text)
                                    ? Image.memory(
                                        ImageCompressionService.extractBytesFromDataUri(bannerController.text)!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.orange.withValues(alpha: 0.3),
                                          child: Icon(Icons.image, color: Colors.orange[700], size: 16),
                                        ),
                                      )
                                    : Image.network(
                                        bannerController.text,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.orange.withValues(alpha: 0.3),
                                          child: Icon(Icons.image, color: Colors.orange[700], size: 16),
                                        ),
                                      ),
                              )
                            : Container(
                                color: Colors.orange.withValues(alpha: 0.3),
                                child: Icon(Icons.image, color: Colors.orange[700], size: 16),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bannière', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final imageService = ImageCompressionService();
                                    final dataUri = await imageService.pickAndCompressBanner();
                                    if (dataUri != null) {
                                      bannerController.text = dataUri;
                                      setDialogState(() {});
                                    }
                                  },
                                  icon: const Icon(Icons.photo_library, size: 16),
                                  label: const Text('Galerie', style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange[700],
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (bannerController.text.isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      bannerController.clear();
                                      setDialogState(() {});
                                    },
                                    child: const Text('Effacer', style: TextStyle(fontSize: 11)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: isPublishingProfile ? null : () async {
              if (!formKey.currentState!.validate()) return;
              
              // Créer le marché avec les métadonnées
              final market = Market(
                name: nameController.text.trim(),
                seedMarket: seedController.text.trim().toLowerCase(),
                validUntil: DateTime.now().add(const Duration(days: 365)),
                relayUrl: relayController.text.trim().isEmpty
                    ? null
                    : relayController.text.trim(),
                about: aboutController.text.trim().isEmpty ? null : aboutController.text.trim(),
                picture: pictureController.text.trim().isEmpty ? null : pictureController.text.trim(),
                banner: bannerController.text.trim().isEmpty ? null : bannerController.text.trim(),
              );
              
              await _storageService.addMarket(market);
              
              // ✅ v2.0.1: Publier le profil Nostr du marché si un relais est configuré
              if (market.relayUrl != null &&
                  (market.about != null || market.picture != null || market.banner != null)) {
                setDialogState(() => isPublishingProfile = true);
                
                try {
                  final nostrService = NostrService(
                    cryptoService: _cryptoService,
                    storageService: _storageService,
                  );
                  
                  await nostrService.connect(market.relayUrl!);
                  
                  // Dériver l'identité du marché
                  final marketIdentity = _cryptoService.deriveMarketIdentity(market.seedMarket);
                  
                  // Publier le profil du marché (Kind 0)
                  await nostrService.publishUserProfile(
                    npub: marketIdentity['npub']!,
                    nsec: marketIdentity['nsec']!,
                    name: market.name,
                    displayName: market.displayName,
                    about: market.about,
                    picture: market.picture,
                    banner: market.banner,
                  );
                  
                  await nostrService.disconnect();
                  Logger.success('MarketScreen', 'Profil Nostr du marché publié');
                } catch (e) {
                  Logger.error('MarketScreen', 'Erreur publication profil marché', e);
                  // On continue même si la publication échoue
                }
              }
              
              Navigator.pop(context);
              await _loadMarkets();
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Marché "${market.displayName}" créé'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: isPublishingProfile
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Créer'),
          ),
        ],
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    // Mode scanner
    if (_isScanning) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: const Text('Scanner un marché'),
          backgroundColor: const Color(0xFF1E1E1E),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _isScanning = false),
          ),
        ),
        body: Stack(
          children: [
            MobileScanner(
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    _handleQrScan(barcode.rawValue!);
                    return;
                  }
                }
              },
            ),
            // Overlay
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            // Instructions
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Scannez le QR du marché',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Mode liste
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Mes marchés'),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateMarketDialog,
            tooltip: 'Créer un marché',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isSyncing
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Synchronisation du marché...',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                )
              : _markets.isEmpty
                  ? _buildEmptyState()
                  : _buildMarketsList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startScanMarket,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Rejoindre un marché'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.store_outlined,
              size: 80,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 24),
            Text(
              'Aucun marché rejoint',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Scannez le QR code fourni par l\'organisateur du marché pour rejoindre.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _startScanMarket,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner un QR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _showCreateMarketDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ou créer un marché manuellement'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _markets.length,
      itemBuilder: (context, index) {
        final market = _markets[index];
        final isActive = _activeMarket?.name == market.name;
        
        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isActive 
                ? const BorderSide(color: Colors.orange, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: () => _setActiveMarket(market),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ v2.0.1: Header avec logo du marché
                  Row(
                    children: [
                      // Logo du marché (si disponible) ou icône par défaut
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(10),
                          border: isActive
                              ? Border.all(color: Colors.orange, width: 2)
                              : null,
                        ),
                        child: market.picture != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  market.picture!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.store,
                                    color: isActive ? Colors.orange : Colors.grey[400],
                                    size: 24,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.store,
                                color: isActive ? Colors.orange : Colors.grey[400],
                                size: 24,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              market.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              market.isExpired
                                  ? 'Expiré'
                                  : market.remainingTimeDescription,
                              style: TextStyle(
                                color: market.isExpired ? Colors.red : Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Actif',
                            style: TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Actions
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      // Partager Wi-Fi
                      TextButton.icon(
                        onPressed: () => _showWifiQr(market),
                        icon: const Icon(Icons.wifi, size: 18),
                        label: const Text('Wi-Fi'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue[300],
                        ),
                      ),
                      // Partager (QR)
                      TextButton.icon(
                        onPressed: () => _showMarketQr(market),
                        icon: const Icon(Icons.qr_code, size: 18),
                        label: const Text('Partager'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange,
                        ),
                      ),
                      // Quitter
                      TextButton.icon(
                        onPressed: () => _removeMarket(market),
                        icon: const Icon(Icons.exit_to_app, size: 18),
                        label: const Text('Quitter'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
