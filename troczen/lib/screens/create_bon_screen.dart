import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:hex/hex.dart';
import '../models/bon.dart';
import '../models/user.dart';
import '../models/market.dart';
import '../models/nostr_profile.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';
import '../services/api_service.dart';
import '../services/du_calculation_service.dart';
import '../services/image_compression_service.dart';

class CreateBonScreen extends StatefulWidget {
  final User user;

  const CreateBonScreen({super.key, required this.user});

  @override
  State<CreateBonScreen> createState() => _CreateBonScreenState();
}

class _CreateBonScreenState extends State<CreateBonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController(text: '0');
  final _issuerNameController = TextEditingController();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();
  final _apiService = ApiService();
  
  bool _isCreating = false;
  List<Market> _markets = [];  // ✅ NOUVEAU: Liste des marchés disponibles
  Market? _selectedMarket;     // ✅ NOUVEAU: Marché sélectionné pour l'émission
  Color _selectedColor = Colors.blue; // Couleur par défaut
  File? _selectedImage;
  bool _isUploading = false;
  final _websiteController = TextEditingController();
  final _wishController = TextEditingController();
  List<String> _suggestedTags = [];
  
  final List<Map<String, dynamic>> _expirationOptions = [
    {'label': '7 jours', 'days': 7},
    {'label': '28 jours', 'days': 28},
    {'label': '3 mois', 'days': 90},
    {'label': '6 mois', 'days': 180},
    {'label': '1 an', 'days': 365},
  ];
  double _expirationSliderValue = 1; // Index 1 = 28 jours par défaut

  @override
  void initState() {
    super.initState();
    _issuerNameController.text = widget.user.displayName;
    // Valeur par défaut: website du profil utilisateur
    _websiteController.text = widget.user.website ?? '';
    _loadMarkets();
    _loadSuggestedTags();
  }

  Future<void> _loadSuggestedTags() async {
    try {
      final market = await _storageService.getMarket();
      if (market != null && market.relayUrl != null) {
        final nostrService = NostrService(
          cryptoService: _cryptoService,
          storageService: _storageService,
        );
        if (await nostrService.connect(market.relayUrl!)) {
          final tags = await nostrService.fetchActivityTagsFromProfiles(limit: 50);
          if (mounted) {
            setState(() {
              _suggestedTags = tags.take(10).toList(); // Garder les 10 premiers
            });
          }
          await nostrService.disconnect();
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement tags: $e');
    }
  }

  /// ✅ NOUVEAU: Charge la liste des marchés et sélectionne l'actif par défaut
  Future<void> _loadMarkets() async {
    final markets = await _storageService.getMarkets();
    final activeMarket = await _storageService.getActiveMarket();
    
    setState(() {
      _markets = markets;
      _selectedMarket = activeMarket ?? (markets.isNotEmpty ? markets.first : null);
    });
  }

  String? _base64Image;

  /// Sélectionner une image pour le bon
  Future<void> _selectImage() async {
    final imageService = ImageCompressionService();
    
    setState(() => _isUploading = true);
    
    try {
      final result = await imageService.pickBannerWithOriginal();
          
      if (result != null) {
        setState(() {
          _base64Image = result.base64DataUri;
          _selectedImage = File(result.originalPath);
        });
      }
    } catch (e) {
      debugPrint('Erreur sélection image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sélection de l\'image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  /// Uploader l'image du bon vers IPFS
  Future<Map<String, String?>> _uploadImage() async {
    if (_selectedImage == null) return {'url': null, 'base64': _base64Image};
    
    setState(() => _isUploading = true);
    
    String? ipfsUrl;
    
    // Uploader vers IPFS
    try {
      final result = await _apiService.uploadImage(
        npub: widget.user.npub,
        imageFile: _selectedImage!,
        type: 'logo',
      );
      
      if (result != null) {
        ipfsUrl = result['ipfs_url'] ?? result['url'];
      }
    } catch (e) {
      debugPrint('Erreur upload image bon: $e');
    } finally {
      setState(() => _isUploading = false);
    }
    
    return {'url': ipfsUrl, 'base64': _base64Image};
  }

  @override
  void dispose() {
    _valueController.dispose();
    _issuerNameController.dispose();
    _websiteController.dispose();
    _wishController.dispose();
    super.dispose();
  }

  Future<void> _createBon() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedMarket == null || _selectedMarket!.isExpired) {
      _showError('Aucun marché configuré ou clé expirée.\nAllez dans Mes marchés pour rejoindre un marché.');
      return;
    }

    setState(() => _isCreating = true);

    try {
      // 1. Générer la paire de clés du bon
      final bonKeys = _cryptoService.generateNostrKeyPair();
      final bonNsecHex = bonKeys['privateKeyHex']!;  // Format hex pour shamirSplit
      final bonNpubHex = bonKeys['publicKeyHex']!;   // Format hex pour les identifiants

      // 2. Découper en 3 parts avec SSSS (utilise le format bytes)
      final bonNsecBytes = Uint8List.fromList(HEX.decode(bonNsecHex));
      final partsBytes = _cryptoService.shamirSplitBytes(bonNsecBytes);
      final p1 = HEX.encode(partsBytes[0]); // Ancre (reste chez l'émetteur)
      final p2 = HEX.encode(partsBytes[1]); // Voyageur (part active)
      final p3 = HEX.encode(partsBytes[2]); // Témoin (à publier)
      _cryptoService.secureZeroiseBytes(bonNsecBytes);

      // 3. Stocker P3 dans le cache local (utilise le format hex comme identifiant)
      await _storageService.saveP3ToCache(bonNpubHex, p3);

      // 4. ✅ Uploader l'image du bon (si sélectionnée) AVANT la création de l'objet Bon
      String? imageUrl;
      String? imageBase64;
      if (_selectedImage != null) {
        final imageResult = await _uploadImage();
        imageUrl = imageResult['url'];
        imageBase64 = imageResult['base64'];
      }

      // 5. Créer le bon
      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );
      final duService = DuCalculationService(
        storageService: _storageService,
        nostrService: nostrService,
        cryptoService: _cryptoService,
      );
      final currentDu = await duService.getCurrentGlobalDu();
      // Forcer la valeur à 0 (Bon manuels à 0)
      final bonValue = 0.0;

      final bon = Bon(
        bonId: bonNpubHex,
        value: 0.0, // Forcé à 0
        issuerName: _issuerNameController.text,
        issuerNpub: widget.user.npub,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(Duration(days: _expirationOptions[_expirationSliderValue.toInt()]['days'] as int)),
        status: BonStatus.active,
        p1: p1,
        p2: p2,
        p3: null,
        marketName: _selectedMarket!.name,
        color: _selectedColor.value,
        duAtCreation: currentDu,
        rarity: 'bootstrap', // FORCE EN BOOTSTRAP
        cardType: 'bootstrap', // FORCE EN BOOTSTRAP
        wish: _wishController.text.trim().isNotEmpty ? _wishController.text.trim() : null,
        picture: imageUrl ?? imageBase64, // 🔥 AJOUT CRITIQUE POUR LE WALLET LOCAL
        logoUrl: imageUrl ?? imageBase64, // 🔥 AJOUT CRITIQUE POUR LE WALLET LOCAL
        picture64: imageBase64,
      );

      // 6. Sauvegarder le bon
      await _storageService.saveBon(bon);

      // 8. ✅ PUBLIER PROFIL DU BON SUR NOSTR (kind 0)
      // SIGNÉ PAR LE BON LUI-MÊME (reconstruction éphémère P2+P3)
      try {
        // Connexion au relais
        final relayUrl = _selectedMarket!.relayUrl ?? NostrConstants.defaultRelay;
        final connected = await nostrService.connect(relayUrl);

        if (connected) {
          // Publication du profil du bon (kind 0)
          // Utilise les informations du profil utilisateur par défaut
          // Note: npub et nsec sont en format hex pour les opérations Nostr
          
          // ✅ SÉCURITÉ: Utiliser shamirCombineBytesDirect avec Uint8List
          final p2Bytes = Uint8List.fromList(HEX.decode(p2));
          final p3Bytes = Uint8List.fromList(HEX.decode(p3));
          final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);
          final nsecHex = HEX.encode(nsecBonBytes);
          
          await nostrService.publishUserProfile(
            npub: bonNpubHex,
            nsec: nsecHex,
            name: _issuerNameController.text,
            displayName: _issuerNameController.text,
            about: _wishController.text.trim().isNotEmpty
                ? _wishController.text.trim()
                : 'Bon ${bonValue.toString()} ẐEN - ${_selectedMarket!.name}',
            picture: imageUrl,
            banner: imageUrl,  // Utilise la même image pour le bandeau
            picture64: imageBase64,
            banner64: imageBase64,
            website: _websiteController.text.trim().isNotEmpty
                ? _websiteController.text.trim()
                : widget.user.website,  // Utilise la valeur saisie ou celle du profil utilisateur
            g1pub: widget.user.g1pub,  // ✅ GÉNÉRÉ AUTOMATIQUEMENT
          );
          
          // ✅ SÉCURITÉ: Nettoyer les clés de la RAM
          _cryptoService.secureZeroiseBytes(nsecBonBytes);
          _cryptoService.secureZeroiseBytes(p2Bytes);
          _cryptoService.secureZeroiseBytes(p3Bytes);

          // Publication P3 chiffrée - AVEC la clé de l'émetteur pour signature
          final published = await nostrService.publishP3(
            bonId: bonNpubHex,
            issuerNsecHex: widget.user.nsec,
            p3Hex: p3,
            seedMarket: _selectedMarket!.seedMarket,
            issuerNpub: widget.user.npub,
            marketName: _selectedMarket!.name,
            value: bonValue,
            category: 'generic',  // TODO: Sélection UI
            wish: _wishController.text.trim().isNotEmpty ? _wishController.text.trim() : null,
          );

          if (published) {
            debugPrint('✅ P3 publiée sur Nostr (signée par le bon)');
          }

          await nostrService.disconnect();
        }

        // 9. ✅ Profil du bon créé uniquement sur Nostr (kind 0 et 30303)
        // L'API backend n'est plus utilisée pour les profils

      } catch (e) {
        debugPrint('⚠️ Erreur publication Nostr: $e');
        // Non bloquant
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bon créé avec succès !'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      _showError('Erreur lors de la création du bon: $e');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Erreur',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
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
        title: const Text('Créer un bon'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Prévisualisation de la carte
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Icon(Icons.verified, color: Color(0xFFFFB347)),
                          Text(
                            '${_valueController.text.isEmpty ? '0' : _valueController.text} ẐEN',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB347).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFFB347).withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.star,
                                size: 48,
                                color: Color(0xFFFFB347),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _issuerNameController.text.isEmpty
                                    ? 'Votre nom'
                                    : _issuerNameController.text,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB347).withValues(alpha: 0.1),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                      child: Text(
                        _selectedMarket?.name.toUpperCase() ?? 'MARCHÉ',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Formulaire
              Text(
                'Informations du bon',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Encart Pédagogique Bon Zéro
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A7EA4).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0A7EA4).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.info_outline, color: Color(0xFF0A7EA4)),
                        SizedBox(width: 8),
                        Text(
                          'Création de Bon Zéro',
                          style: TextStyle(
                            color: Color(0xFF0A7EA4),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Vous créez un "Bon Zéro" (0 ẐEN). Ce bon sert de carte de visite pour tisser votre toile de confiance.\n\nLes vrais ẐEN seront générés automatiquement par le Dividende Universel une fois que vous aurez 5 liens réciproques.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _issuerNameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nom de l\'émetteur',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFFFB347)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer un nom';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 24),

              // ✅ Section Couleur (pour personnalisation visuelle UI uniquement)
              Text(
                'Couleur de la carte',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                children: [
                  Colors.blue, Colors.red, Colors.green, Colors.purple, Colors.orange, Colors.pink,
                  Colors.teal, Colors.indigo, Colors.amber, Colors.lime
                ].map((color) => GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: _selectedColor == color
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                    ),
                  ),
                )).toList(),
              ),

              const SizedBox(height: 24),

              // Section Vœu (Carnet de Voyage)
              Row(
                children: [
                  Text(
                    'Vœu / Petite Annonce',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Attachez une demande à ce bon (ex: "Je cherche du houblon").\n'
                        'Le bon va voyager de main en main (Effet Petit Monde).\n'
                        'S\'il atteint la bonne personne, la boucle de valeur est bouclée !',
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 5),
                    child: const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _wishController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Votre demande (ex: Je cherche du houblon)',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFFFB347)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                ),
              ),
              
              if (_suggestedTags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestedTags.map((tag) => ActionChip(
                    label: Text(tag),
                    backgroundColor: const Color(0xFF1E1E1E),
                    labelStyle: const TextStyle(color: Colors.orange, fontSize: 12),
                    side: const BorderSide(color: Colors.orange),
                    onPressed: () {
                      setState(() {
                        _wishController.text = tag;
                      });
                    },
                  )).toList(),
                ),
              ],

              const SizedBox(height: 24),

              // Section Website du bon
              Text(
                'Website du bon (optionnel)',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _websiteController,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Site web',
                  hintText: 'https://votre-site.com',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFFFB347)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                ),
              ),

              const SizedBox(height: 24),

              // Section Image du bon
              Text(
                'Image du bon (optionnel)',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : _selectImage,
                      icon: const Icon(Icons.image),
                      label: Text(_selectedImage != null
                          ? 'Changer l\'image'
                          : 'Sélectionner une image'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A7EA4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_selectedImage != null)
                    const SizedBox(width: 12),
                  if (_selectedImage != null)
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: const Center(
                        child: Icon(Icons.image, color: Colors.white70),
                      ),
                    ),
                ],
              ),

              if (_isUploading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),

              const SizedBox(height: 24),

              // Section Expiration
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Durée de validité',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB347).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFB347)),
                    ),
                    child: Text(
                      _expirationOptions[_expirationSliderValue.toInt()]['label'] as String,
                      style: const TextStyle(
                        color: Color(0xFFFFB347),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFFFFB347),
                  inactiveTrackColor: Colors.grey[800],
                  thumbColor: const Color(0xFFFFB347),
                  overlayColor: const Color(0xFFFFB347).withValues(alpha: 0.2),
                  tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 4),
                  activeTickMarkColor: Colors.white,
                  inactiveTickMarkColor: Colors.grey[600],
                ),
                child: Slider(
                  value: _expirationSliderValue,
                  min: 0,
                  max: (_expirationOptions.length - 1).toDouble(),
                  divisions: _expirationOptions.length - 1,
                  onChanged: (value) {
                    setState(() {
                      _expirationSliderValue = value;
                    });
                  },
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('7j', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    Text('1 an', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ✅ NOUVEAU: Sélecteur de marché
              if (_markets.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Marché d\'émission',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<Market>(
                        initialValue: _selectedMarket,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        dropdownColor: const Color(0xFF2A2A2A),
                        style: const TextStyle(color: Colors.white),
                        items: _markets.map((market) {
                          return DropdownMenuItem(
                            value: market,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.store,
                                  size: 18,
                                  color: market.isExpired ? Colors.red : Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    market.displayName,
                                    style: TextStyle(
                                      color: market.isExpired ? Colors.red : Colors.white,
                                    ),
                                  ),
                                ),
                                if (market.isExpired)
                                  Text(
                                    '(Expiré)',
                                    style: TextStyle(color: Colors.red[300], fontSize: 12),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (market) {
                          setState(() => _selectedMarket = market);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              
              if (_selectedMarket == null || _selectedMarket!.isExpired)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Rejoignez d\'abord un marché dans "Mes marchés"',
                          style: TextStyle(color: Colors.grey[300]),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isCreating ? null : _createBon,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB347),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isCreating
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Créer le bon',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
