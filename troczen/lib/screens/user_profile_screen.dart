import 'dart:io';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/nostr_service.dart';
import '../services/storage_service.dart';
import '../services/image_compression_service.dart';
import 'feedback_screen.dart';
import 'package:provider/provider.dart';

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
  final _skillController = TextEditingController();
  
  final _apiService = ApiService();
  final _storageService = StorageService();
  
  String? _base64Picture;
  String? _base64Banner;
  File? _selectedPictureFile;
  File? _selectedBannerFile;
  bool _isSaving = false;
  bool _isUploading = false;
  List<String> _activityTags = [];

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
    _activityTags = List.from(widget.user.activityTags ?? []);
    
    // Relais par défaut
    _relaysController.text = AppConfig.defaultRelayUrl;
    
    // ✅ CORRECTION: Charger le profil Nostr existant pour récupérer les images
    try {
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        final nostrService = context.read<NostrService>();
        
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
    
    setState(() => _isUploading = true);
    
    try {
      final result = type == 'picture'
          ? await imageService.pickAvatarWithOriginal()
          : await imageService.pickBannerWithOriginal();
      
      if (result != null) {
        setState(() {
          if (type == 'picture') {
            _base64Picture = result.base64DataUri;
            _selectedPictureFile = File(result.originalPath);
          } else {
            _base64Banner = result.base64DataUri;
            _selectedBannerFile = File(result.originalPath);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final market = await _storageService.getMarket();
      final relayUrl = market?.relayUrl ?? AppConfig.defaultRelayUrl;
      final nostrService = context.read<NostrService>();

      // 1. Capturer les valeurs des champs (évite les erreurs si le widget est détruit)
      final nameText = _nameController.text.trim();
      final displayNameText = _displayNameController.text.trim().isNotEmpty
          ? _displayNameController.text.trim()
          : widget.user.displayName;
      final aboutText = _aboutController.text.trim().isNotEmpty
          ? _aboutController.text.trim()
          : null;
      final websiteText = _websiteController.text.trim().isNotEmpty
          ? _websiteController.text.trim()
          : null;
      final g1pubText = _g1pubController.text.trim().isNotEmpty
          ? _g1pubController.text.trim()
          : null;
      final currentTags = List<String>.from(_activityTags);

      // 2. Mettre à jour l'utilisateur local avec les images actuelles ou Base64
      // L'UI est fluide car on n'attend pas IPFS
      final updatedUser = widget.user.copyWith(
        displayName: displayNameText,
        about: aboutText,
        website: websiteText,
        g1pub: g1pubText,
        // On conserve l'ancienne URL IPFS si elle existait, sinon on garde null
        picture64: _base64Picture ?? widget.user.picture64,
        banner64: _base64Banner ?? widget.user.banner64,
        activityTags: currentTags,
        relayUrl: relayUrl,
      );

      await _storageService.saveUser(updatedUser);

      // 3. Publier immédiatement sur Nostr (Kind 0)
      await nostrService.connect(relayUrl);
      
      // ✅ PUBLIER DANS TOUS LES CAS (la mise en file d'attente se fera automatiquement si hors-ligne)
      await nostrService.market.publishUserProfile(
        npub: updatedUser.npub,
        nsec: updatedUser.nsec,
        name: nameText,
        displayName: updatedUser.displayName,
        about: updatedUser.about,
        picture: updatedUser.picture,
        banner: updatedUser.banner,
        picture64: updatedUser.picture64,
        banner64: updatedUser.banner64,
        website: updatedUser.website,
        g1pub: updatedUser.g1pub,
        tags: updatedUser.activityTags,
      );

      // Publier la liste des relais
      final relays = _relaysController.text.trim().split(',').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();
      if (relays.isNotEmpty) {
        await nostrService.publishRelayList(
          npub: updatedUser.npub,
          nsec: updatedUser.nsec,
          relays: relays,
        );
      }
      await nostrService.disconnect();

      if (!mounted) return;

      // 4. Débloquer l'UI et afficher le succès
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedPictureFile != null || _selectedBannerFile != null
                ? '✅ Profil sauvegardé ! Upload IPFS en arrière-plan...'
                : '✅ Profil mis à jour avec succès !'
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context); // Rendre la main à l'utilisateur

      // 5. 🔥 Lancer l'upload IPFS en arrière-plan (Fire-and-forget)
      if (_selectedPictureFile != null || _selectedBannerFile != null) {
        _uploadImagesToIPFSInBackground(
          user: updatedUser,
          name: nameText,
          relayUrl: relayUrl,
          pictureFile: _selectedPictureFile,
          bannerFile: _selectedBannerFile,
        );
      }

    } catch (e) {
      if (!mounted) return;
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

  /// Tâche en arrière-plan pour ne pas bloquer l'UI pendant le polling IPFS
  void _uploadImagesToIPFSInBackground({
    required User user,
    required String name,
    required String relayUrl,
    File? pictureFile,
    File? bannerFile,
  }) async {
    try {
      debugPrint('Démarrage upload IPFS en arrière-plan...');
      String? newPictureUrl;
      String? newBannerUrl;
      bool isUpdated = false;

      if (pictureFile != null) {
        final result = await _apiService.uploadImage(
          npub: user.npub,
          imageFile: pictureFile,
          type: 'avatar',
          waitForIpfs: true,
        );
        if (result != null) {
          newPictureUrl = result['ipfs_url'] ?? result['url'];
          isUpdated = true;
        }
      }

      if (bannerFile != null) {
        final result = await _apiService.uploadImage(
          npub: user.npub,
          imageFile: bannerFile,
          type: 'banner',
          waitForIpfs: true,
        );
        if (result != null) {
          newBannerUrl = result['ipfs_url'] ?? result['url'];
          isUpdated = true;
        }
      }

      if (isUpdated) {
        // 1. Mettre à jour l'utilisateur avec les vraies URL IPFS
        final updatedUser = user.copyWith(
          picture: newPictureUrl ?? user.picture,
          banner: newBannerUrl ?? user.banner,
        );
        await _storageService.saveUser(updatedUser);

        // 2. Republier silencieusement sur Nostr
        final nostrService = context.read<NostrService>();
        await nostrService.market.publishUserProfile(
          npub: updatedUser.npub,
          nsec: updatedUser.nsec,
          name: name,
          displayName: updatedUser.displayName,
          about: updatedUser.about,
          picture: updatedUser.picture,
          banner: updatedUser.banner,
          picture64: updatedUser.picture64,
          banner64: updatedUser.banner64,
          website: updatedUser.website,
          g1pub: updatedUser.g1pub,
          tags: updatedUser.activityTags,
        );
        await nostrService.disconnect();
        debugPrint('✅ Profil Nostr mis à jour silencieusement avec les URLs IPFS');
      }
    } catch (e) {
      debugPrint('⚠️ Erreur upload IPFS arrière-plan: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      appBar: AppBar(
        title: const Text('Mon Profil'),
        backgroundColor: Theme.of(context).colorScheme.surface,
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
      color: Theme.of(context).colorScheme.surface,
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
      color: Theme.of(context).colorScheme.surface,
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

  Widget _buildSkillsSection() {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Savoir-faire (Compétences)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajoutez vos compétences pour participer au Web of Trust (WoTx).',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _activityTags.map((tag) {
                return Chip(
                  label: Text(tag),
                  backgroundColor: Colors.indigo.withValues(alpha: 0.3),
                  labelStyle: const TextStyle(color: Colors.white),
                  deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white70),
                  onDeleted: () {
                    setState(() {
                      _activityTags.remove(tag);
                    });
                  },
                );
              }).toList(),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _skillController,
                    decoration: const InputDecoration(
                      labelText: 'Nouvelle compétence',
                      hintText: 'ex: Maraîchage',
                      border: OutlineInputBorder(),
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                    onFieldSubmitted: (value) {
                      _addSkill();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.indigoAccent, size: 32),
                  onPressed: _addSkill,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addSkill() {
    final skill = _skillController.text.trim();
    if (skill.isNotEmpty && !_activityTags.contains(skill)) {
      setState(() {
        _activityTags.add(skill);
        _skillController.clear();
      });
    }
  }

  Widget _buildNostrSection() {
    return Card(
      color: Theme.of(context).colorScheme.surface,
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
            
            // TextFormField(
            //   controller: _nip05Controller,
            //   decoration: const InputDecoration(
            //     labelText: 'NIP-05',
            //     hintText: 'nom@domaine.com',
            //     border: OutlineInputBorder(),
            //     labelStyle: TextStyle(color: Colors.white70),
            //   ),
            //   style: const TextStyle(color: Colors.white),
            // ),
            
            // const SizedBox(height: 16),
            
            // TextFormField(
            //   controller: _lud16Controller,
            //   decoration: const InputDecoration(
            //     labelText: 'Lightning Address',
            //     hintText: 'user@domaine.com',
            //     border: OutlineInputBorder(),
            //     labelStyle: TextStyle(color: Colors.white70),
            //   ),
            //   style: const TextStyle(color: Colors.white),
            // ),
            
            // const SizedBox(height: 16),
            
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
