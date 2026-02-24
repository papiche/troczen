import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../models/nostr_profile.dart';
import '../services/api_service.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/image_compression_service.dart';
import 'feedback_screen.dart';

/// Écran de gestion du profil utilisateur
/// Permet à l'utilisateur de modifier son profil et d'uploader des images
class UserProfileScreen extends StatefulWidget {
  final User user;

  const UserProfileScreen({
    super.key,
    required this.user,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _nip05Controller = TextEditingController();
  final _lud16Controller = TextEditingController();
  final _websiteController = TextEditingController();
  final _g1pubController = TextEditingController();
  final _relaysController = TextEditingController();
  
  final _apiService = ApiService();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();
  
  String? _base64Picture;
  String? _base64Banner;
  bool _isSaving = false;
  final bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _aboutController.dispose();
    _nip05Controller.dispose();
    _lud16Controller.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  void _loadProfile() async {
    // Charger le profil depuis le stockage local
    _nameController.text = widget.user.displayName;
    _displayNameController.text = widget.user.displayName;
    _aboutController.text = widget.user.about ?? '';
    _websiteController.text = widget.user.website ?? '';
    _g1pubController.text = widget.user.g1pub ?? '';
    
    // Relais par défaut
    _relaysController.text = AppConfig.defaultRelayUrl;
    
    // ✅ CORRECTION: Charger le profil Nostr existant pour récupérer les images
    try {
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        final nostrService = NostrService(
          cryptoService: _cryptoService,
          storageService: _storageService,
        );
        
        final connected = await nostrService.connect(market!.relayUrl!);
        if (connected) {
          // Récupérer le profil kind 0
          final profile = await nostrService.fetchUserProfile(widget.user.npub);
          
          if (profile != null) {
            if (mounted) {
              setState(() {
                if (profile.about != null && profile.about!.isNotEmpty) {
                  _aboutController.text = profile.about!;
                }
                // Les images seront affichées via les URL Nostr
                // On ne peut pas les charger comme File localement
              });
            }
          }
          
          await nostrService.disconnect();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Impossible de charger le profil Nostr: $e');
      // Continuer quand même avec les données locales
    }
  }

  Future<void> _selectImage(String type) async {
    final imageService = ImageCompressionService();
    final dataUri = type == 'picture'
        ? await imageService.pickAndCompressAvatar()
        : await imageService.pickAndCompressBanner();
    
    if (dataUri != null) {
      setState(() {
        if (type == 'picture') {
          _base64Picture = dataUri;
        } else {
          _base64Banner = dataUri;
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Remplacer l'attente de l'API par la récupération directe des Strings
      String? pictureUrl = _base64Picture ?? widget.user.picture;
      String? bannerUrl = _base64Banner ?? widget.user.banner;

      // 3. Publier sur Nostr (kind 0)
      final market = await _storageService.getMarket();
      final relayUrl = market?.relayUrl ?? NostrConstants.defaultRelay;
      
      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );

      final connected = await nostrService.connect(relayUrl);
      
      if (connected) {
        // Publier le profil utilisateur (kind 0)
        await nostrService.publishUserProfile(
          npub: widget.user.npub,
          nsec: widget.user.nsec,
          name: _nameController.text.trim(),
          displayName: _displayNameController.text.trim().isNotEmpty
              ? _displayNameController.text.trim()
              : null,
          about: _aboutController.text.trim().isNotEmpty
              ? _aboutController.text.trim()
              : null,
          picture: pictureUrl,
          banner: bannerUrl,
          picture64: _base64Picture,
          banner64: _base64Banner,
          website: _websiteController.text.trim().isNotEmpty
              ? _websiteController.text.trim()
              : null,
          g1pub: _g1pubController.text.trim().isNotEmpty
              ? _g1pubController.text.trim()
              : null,
        );

        // Publier la liste des relais (kind 10002)
        final relays = _relaysController.text.trim().split(',').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();
        if (relays.isNotEmpty) {
          await nostrService.publishRelayList(
            npub: widget.user.npub,
            nsec: widget.user.nsec,
            relays: relays,
          );
        }

        await nostrService.disconnect();
      }

      // 4. Mettre à jour l'utilisateur local avec les URLs des images
      final updatedUser = User(
        npub: widget.user.npub,
        nsec: widget.user.nsec,
        displayName: _displayNameController.text.trim().isNotEmpty
            ? _displayNameController.text.trim()
            : widget.user.displayName,
        createdAt: widget.user.createdAt,
        website: _websiteController.text.trim().isNotEmpty
            ? _websiteController.text.trim()
            : widget.user.website,
        g1pub: _g1pubController.text.trim().isNotEmpty
            ? _g1pubController.text.trim()
            : widget.user.g1pub,
        about: _aboutController.text.trim().isNotEmpty
            ? _aboutController.text.trim()
            : widget.user.about,
        // ✅ NOUVEAU: Sauvegarder les URLs des images
        picture: pictureUrl ?? widget.user.picture,
        banner: bannerUrl ?? widget.user.banner,
        picture64: _base64Picture ?? widget.user.picture64,
        banner64: _base64Banner ?? widget.user.banner64,
      );
      await _storageService.saveUser(updatedUser);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profil mis à jour localement et sur Nostr !'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Signaler',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FeedbackScreen(user: widget.user),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Mon Profil'),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          if (!_isSaving)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveProfile,
              tooltip: 'Sauvegarder',
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section Images
              _buildImagesSection(),
              
              const SizedBox(height: 24),
              
              // Section Informations
              _buildInfoSection(),
              
              const SizedBox(height: 24),
              
              // Section Nostr
              _buildNostrSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagesSection() {
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Images du Profil',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Avatar
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Avatar',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _isUploading ? null : () => _selectImage('picture'),
                        child: ImageCompressionService.buildImage(
                          uri: _base64Picture ?? widget.user.picture,
                          fallbackUri: widget.user.picture64,
                          width: 60,
                          height: 60,
                          borderRadius: BorderRadius.circular(8),
                          placeholder: const Icon(Icons.add_a_photo, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bandeau',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _isUploading ? null : () => _selectImage('banner'),
                        child: ImageCompressionService.buildImage(
                          uri: _base64Banner ?? widget.user.banner,
                          fallbackUri: widget.user.banner64,
                          width: double.infinity,
                          height: 60,
                          borderRadius: BorderRadius.circular(8),
                          placeholder: const Icon(Icons.add_a_photo, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            if (_isUploading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informations',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nom',
                hintText: 'Votre nom',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Le nom est requis';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Nom d\'affichage',
                hintText: 'Nom visible (optionnel)',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _aboutController,
              decoration: const InputDecoration(
                labelText: 'À propos',
                hintText: 'Description de votre profil',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNostrSection() {
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Identifiants Nostr',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _nip05Controller,
              decoration: const InputDecoration(
                labelText: 'NIP-05',
                hintText: 'nom@domaine.com',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _lud16Controller,
              decoration: const InputDecoration(
                labelText: 'Lightning Address',
                hintText: 'user@domaine.com',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _websiteController,
              decoration: const InputDecoration(
                labelText: 'Site web',
                hintText: 'https://votre-site.com',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
