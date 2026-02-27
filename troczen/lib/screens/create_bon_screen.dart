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
import 'package:provider/provider.dart';

class CreateBonScreen extends StatefulWidget {
  final User user;
  final NostrProfile? initialReceiverProfile;

  const CreateBonScreen({
    super.key,
    required this.user,
    this.initialReceiverProfile,
  });

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
  Market? _selectedMarket;     // Marché actif pour l'émission
  final Color _selectedColor = Colors.blue; // Couleur par défaut
  File? _selectedImage;
  bool _isUploading = false;
  final _websiteController = TextEditingController();
  final _wishController = TextEditingController();
  List<String> _suggestedTags = [];
  double _availableDu = 0.0;
  
  static double? _cachedAvailableDu;
  static DateTime? _cacheTimestamp;
  
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
    
    if (widget.initialReceiverProfile != null) {
      _wishController.text = 'Pour ${widget.initialReceiverProfile!.name}';
    }
    
    _loadMarkets();
    _loadSuggestedTags();
    _loadAvailableDu();
  }

  Future<void> _loadAvailableDu() async {
    if (_cachedAvailableDu != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!).inMinutes < 5) {
      if (mounted) {
        setState(() {
          _availableDu = _cachedAvailableDu!;
        });
      }
      return;
    }

    try {
      final nostrService = context.read<NostrService>();
      final available = await nostrService.computeAvailableDu(widget.user.npub);
      
      _cachedAvailableDu = available;
      _cacheTimestamp = DateTime.now();
      
      if (mounted) {
        setState(() {
          _availableDu = available;
        });
      }
    } catch (e) {
      debugPrint('Erreur calcul DU disponible: $e');
      // Fallback sur le stockage local en cas d'erreur
      final available = await _storageService.getAvailableDuToEmit();
      if (mounted) {
        setState(() {
          _availableDu = available;
        });
      }
    }
  }

  Future<void> _loadSuggestedTags() async {
    try {
      final market = await _storageService.getMarket();
      if (market != null && market.relayUrl != null) {
        final nostrService = context.read<NostrService>();
        try {
          if (await nostrService.connect(market.relayUrl!)) {
            final tags = await nostrService.fetchActivityTagsFromProfiles(limit: 50);
            if (mounted) {
              setState(() {
                _suggestedTags = tags.take(10).toList(); // Garder les 10 premiers
              });
            }
            await nostrService.disconnect();
          }
        } finally {
          nostrService.dispose();
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement tags: $e');
    }
  }

  /// Charge le marché actif par défaut
  Future<void> _loadMarkets() async {
    final activeMarket = await _storageService.getActiveMarket();
    
    setState(() {
      _selectedMarket = activeMarket;
    });
  }

  String? _base64Logo;
  File? _selectedLogo;
  
  String? _base64Banner;
  File? _selectedBanner;

  /// Sélectionner un logo pour le bon
  Future<void> _selectLogo() async {
    final imageService = ImageCompressionService();
    
    setState(() => _isUploading = true);
    
    try {
      final result = await imageService.pickAvatarWithOriginal();
          
      if (result != null) {
        setState(() {
          _base64Logo = result.base64DataUri;
          _selectedLogo = File(result.originalPath);
        });
      }
    } catch (e) {
      debugPrint('Erreur sélection logo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sélection du logo: $e'),
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

  /// Sélectionner une bannière pour le bon
  Future<void> _selectBanner() async {
    final imageService = ImageCompressionService();
    
    setState(() => _isUploading = true);
    
    try {
      final result = await imageService.pickBannerWithOriginal();
          
      if (result != null) {
        setState(() {
          _base64Banner = result.base64DataUri;
          _selectedBanner = File(result.originalPath);
        });
      }
    } catch (e) {
      debugPrint('Erreur sélection bannière: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sélection de la bannière: $e'),
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

  /// Uploader une image vers IPFS
  Future<Map<String, String?>> _uploadImage(File? file, String? base64, String type) async {
    if (file == null) return {'url': null, 'base64': base64};
    
    setState(() => _isUploading = true);
    
    String? ipfsUrl;
    
    // Uploader vers IPFS
    try {
      final result = await _apiService.uploadImage(
        npub: widget.user.npub,
        imageFile: file,
        type: type,
      );
      
      if (result != null) {
        ipfsUrl = result['ipfs_url'] ?? result['url'];
      }
    } catch (e) {
      debugPrint('Erreur upload image bon: $e');
    } finally {
      setState(() => _isUploading = false);
    }
    
    return {'url': ipfsUrl, 'base64': base64};
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
      _showError('Erreur: Aucun marché actif ou marché expiré.');
      return;
    }

    final bonValue = double.tryParse(_valueController.text) ?? 0.0;
    
    if (bonValue > 0 && bonValue > _availableDu) {
      _showError('Vous n\'avez pas assez de DU disponible pour émettre ce montant.\nDisponible: ${_availableDu.toStringAsFixed(2)} ẐEN');
      return;
    }

    setState(() => _isCreating = true);

    try {
      // 1. Générer la paire de clés du bon
      final bonKeys = _cryptoService.generateNostrKeyPair();
      final bonNsecHex = bonKeys['privateKeyHex']!;  // Format hex pour shamirSplit
      final bonNpubHex = bonKeys['publicKeyHex']!;   // Format hex pour les identifiants

      // 2. Découper en 3 parts avec SSSS (utilise le format bytes)
      Uint8List bonNsecBytes;
      try {
        bonNsecBytes = Uint8List.fromList(HEX.decode(bonNsecHex));
      } catch (e) {
        throw Exception('Clé privée du bon invalide (non hexadécimale)');
      }
      final partsBytes = _cryptoService.shamirSplitBytes(bonNsecBytes);
      final p1 = HEX.encode(partsBytes[0]); // Ancre (reste chez l'émetteur)
      final p2 = HEX.encode(partsBytes[1]); // Voyageur (part active)
      final p3 = HEX.encode(partsBytes[2]); // Témoin (à publier)
      _cryptoService.secureZeroiseBytes(bonNsecBytes);

      // 3. Stocker P3 dans le cache local (utilise le format hex comme identifiant)
      await _storageService.saveP3ToCache(bonNpubHex, p3);

      // 4. ✅ Uploader les images du bon (si sélectionnées) AVANT la création de l'objet Bon
      String? logoUrl;
      String? logoBase64;
      if (_selectedLogo != null) {
        final logoResult = await _uploadImage(_selectedLogo, _base64Logo, 'logo');
        logoUrl = logoResult['url'];
        logoBase64 = logoResult['base64'];
      }

      String? bannerUrl;
      String? bannerBase64;
      if (_selectedBanner != null) {
        final bannerResult = await _uploadImage(_selectedBanner, _base64Banner, 'banner');
        bannerUrl = bannerResult['url'];
        bannerBase64 = bannerResult['base64'];
      }

      // 5. Créer le bon
      final nostrService = context.read<NostrService>();
      final duService = DuCalculationService(
        storageService: _storageService,
        nostrService: nostrService,
        cryptoService: _cryptoService,
      );
      final currentDu = await duService.getCurrentGlobalDu();

      final isBootstrap = bonValue == 0.0;

      final bon = Bon(
        bonId: bonNpubHex,
        value: bonValue,
        issuerName: _issuerNameController.text,
        issuerNpub: widget.user.npub,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(Duration(days: _expirationOptions[_expirationSliderValue.toInt()]['days'] as int)),
        status: BonStatus.active,
        p1: p1,
        p2: p2,
        p3: null,
        marketName: _selectedMarket!.name,
        color: _selectedColor.toARGB32(),
        duAtCreation: currentDu,
        rarity: isBootstrap ? 'bootstrap' : 'common',
        cardType: isBootstrap ? 'bootstrap' : 'DU',
        wish: _wishController.text.trim().isNotEmpty ? _wishController.text.trim() : null,
        picture: logoUrl,
        banner: bannerUrl,
        logoUrl: logoUrl,
        picture64: logoBase64,
        banner64: bannerBase64,
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
          Uint8List p2Bytes, p3Bytes;
          try {
            p2Bytes = Uint8List.fromList(HEX.decode(p2));
            p3Bytes = Uint8List.fromList(HEX.decode(p3));
          } catch (e) {
            throw Exception('Parts P2 ou P3 invalides (non hexadécimales)');
          }
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
            picture: logoUrl,
            banner: bannerUrl,
            picture64: logoBase64,
            banner64: bannerBase64,
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
            category: isBootstrap ? 'bootstrap' : 'DU',
            wish: _wishController.text.trim().isNotEmpty ? _wishController.text.trim() : null,
          );

          if (published) {
            debugPrint('✅ P3 publiée sur Nostr (signée par le bon)');
          }

          await nostrService.disconnect();
        }

        // 9. Déduire le montant du DU disponible
        if (bonValue > 0) {
          await _storageService.deductAvailableDuToEmit(bonValue);
        }

      } catch (e) {
        debugPrint('⚠️ Erreur publication Nostr: $e');
        // Non bloquant
      } finally {
        nostrService.dispose();
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
                  // ✅ NOUVEAU: Si une bannière est sélectionnée, l'afficher en fond
                  image: _selectedBanner != null || _base64Banner != null
                      ? DecorationImage(
                          image: _selectedBanner != null
                              ? FileImage(_selectedBanner!) as ImageProvider
                              : MemoryImage(ImageCompressionService.extractBytesFromDataUri(_base64Banner!)!),
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            Colors.white.withValues(alpha: 0.5), // Éclaircir l'image pour la lisibilité
                            BlendMode.lighten,
                          ),
                        )
                      : null,
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
                              if (_selectedLogo != null || _base64Logo != null)
                                CircleAvatar(
                                  radius: 32,
                                  backgroundColor: Colors.white,
                                  backgroundImage: _selectedLogo != null
                                      ? FileImage(_selectedLogo!) as ImageProvider
                                      : MemoryImage(ImageCompressionService.extractBytesFromDataUri(_base64Logo!)!),
                                )
                              else
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

              // Encart Pédagogique
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
                          'Émission de Bons',
                          style: TextStyle(
                            color: Color(0xFF0A7EA4),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'DU disponible à émettre : ${_availableDu.toStringAsFixed(2)} ẐEN\n\n'
                      'Vous pouvez émettre un "Bon Zéro" (0 ẐEN) pour tisser votre toile de confiance, '
                      'ou émettre un bon avec une valeur jusqu\'à votre DU disponible.',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _valueController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Valeur du bon (ẐEN)',
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
                    return 'Veuillez entrer une valeur';
                  }
                  final val = double.tryParse(value);
                  if (val == null || val < 0) {
                    return 'Valeur invalide';
                  }
                  if (val > _availableDu) {
                    return 'DU disponible insuffisant';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _issuerNameController,
                readOnly: widget.initialReceiverProfile != null,
                style: TextStyle(
                  color: widget.initialReceiverProfile != null ? Colors.grey : Colors.white,
                ),
                decoration: InputDecoration(
                  labelText: 'Bon pour',
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

              // Section Images du bon
              Text(
                'Images du bon (optionnel)',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Logo
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : _selectLogo,
                      icon: const Icon(Icons.image),
                      label: Text(_selectedLogo != null
                          ? 'Changer l\'icône'
                          : 'Icône / Logo (Carré)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A7EA4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_selectedLogo != null)
                    const SizedBox(width: 12),
                  if (_selectedLogo != null)
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[700]!),
                        image: DecorationImage(
                          image: FileImage(_selectedLogo!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Bannière
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : _selectBanner,
                      icon: const Icon(Icons.panorama),
                      label: Text(_selectedBanner != null
                          ? 'Changer la bannière'
                          : 'Visuel du Bon / Bannière (Paysage)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A7EA4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_selectedBanner != null)
                    const SizedBox(width: 12),
                  if (_selectedBanner != null)
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[700]!),
                        image: DecorationImage(
                          image: FileImage(_selectedBanner!),
                          fit: BoxFit.cover,
                        ),
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
                          'Erreur: Aucun marché actif ou marché expiré.',
                          style: TextStyle(color: Colors.grey[300]),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_selectedMarket == null || _selectedMarket!.isExpired)
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
