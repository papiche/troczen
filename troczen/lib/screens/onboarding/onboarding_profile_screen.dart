import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_config.dart';
import '../../services/storage_service.dart';
import '../../services/nostr_service.dart';
import '../../services/crypto_service.dart';
import '../../services/image_compression_service.dart';
import '../../services/logger_service.dart';
import '../../models/user.dart';
import 'onboarding_flow.dart';

/// Étape 4: Création du Profil Nostr+Ğ1
class OnboardingProfileScreen extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback? onBack;
  
  const OnboardingProfileScreen({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<OnboardingProfileScreen> createState() => _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState extends State<OnboardingProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _customTagController = TextEditingController();
  final _focusNode = FocusNode();
  
  final List<String> _selectedTags = [];
  final List<String> _dynamicTags = [];
  final ImagePicker _imagePicker = ImagePicker();
  
  File? _selectedProfileImage;
  bool _loadingDynamicTags = false;
  
  /// ✅ v2.0.2: Miniature base64 pour l'événement Nostr (offline-first)
  /// Cette miniature est affichée instantanément, l'upload IPFS se fait en arrière-plan
  String? _base64Avatar;
  String? _base64Banner;
  
  /// URL IPFS une fois l'upload terminé (optionnel, en arrière-plan)
  String? _ipfsAvatarUrl;
  String? _ipfsBannerUrl;
  
  File? _selectedBannerImage;
  
  // Les skills prédéfinis sont maintenant centralisés dans AppConfig.defaultSkills
  
  @override
  void initState() {
    super.initState();
    _loadSkillsFromNostr();
  }
  
  @override
  void dispose() {
    _displayNameController.dispose();
    _aboutController.dispose();
    _customTagController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  
  /// Charge les savoir-faire depuis le relai Nostr (Kind 30500)
  /// Si le relai est vierge, l'ensemence avec les tags prédéfinis
  Future<void> _loadSkillsFromNostr() async {
    final state = context.read<OnboardingNotifier>().state;
    if (state.relayUrl.isEmpty) return;
    
    setState(() => _loadingDynamicTags = true);
    
    try {
      final storageService = StorageService();
      final cryptoService = CryptoService();
      final nostrService = NostrService(cryptoService: cryptoService, storageService: storageService);
      
      if (await nostrService.connect(state.relayUrl)) {
        // 1. Lire les Kind 30500
        var skills = await nostrService.fetchSkillDefinitions();
        
        // 2. Si le relai est vierge (ensemencement initial)
        if (skills.isEmpty) {
          Logger.info('Onboarding', 'Relai vierge. Ensemencement des savoir-faire (Kind 30500)...');
          
          // Récupérer les clés générées à l'étape 1
          final user = await storageService.getUser();
          // ✅ SÉCURITÉ: Récupérer la seed du marché pour le chiffrement
          final seedMarket = state.seedMarket;
          if (user != null && seedMarket != null) {
            final defaultSkills = AppConfig.allDefaultSkills;
            for (final skill in defaultSkills) {
               await nostrService.publishSkillPermit(
                 npub: user.npub,
                 nsec: user.nsec,
                 skillTag: skill,
                 seedMarket: seedMarket,  // ✅ SÉCURITÉ: Seed pour chiffrement
               );
            }
            skills = defaultSkills; // On les utilise immédiatement
          }
        }
        
        setState(() {
          _dynamicTags.clear();
          _dynamicTags.addAll(skills);
        });
        await nostrService.disconnect();
      }
    } catch (e) {
      Logger.error('Onboarding', 'Erreur chargement skills', e);
    } finally {
      if (mounted) setState(() => _loadingDynamicTags = false);
    }
  }
  
  /// Ajoute un tag personnalisé à la liste des tags sélectionnés
  /// Publie la définition (Kind 30500) sur le relai pour les autres utilisateurs
  void _addCustomTag() async {
    final tag = _customTagController.text.trim();
    if (tag.isEmpty || _selectedTags.contains(tag)) return;
    
    setState(() {
      _selectedTags.add(tag);
      if (!_dynamicTags.contains(tag)) _dynamicTags.add(tag);
    });
    
    _customTagController.clear();
    _focusNode.requestFocus();

    // Publier la définition sur le relai pour les autres
    final storageService = StorageService();
    final user = await storageService.getUser();
    final state = context.read<OnboardingNotifier>().state;
    
    // ✅ SÉCURITÉ: Récupérer la seed du marché pour le chiffrement
    final seedMarket = state.seedMarket;
    if (user != null && state.relayUrl.isNotEmpty && seedMarket != null) {
      final nostrService = NostrService(cryptoService: CryptoService(), storageService: storageService);
      if (await nostrService.connect(state.relayUrl)) {
        await nostrService.publishSkillPermit(
          npub: user.npub,
          nsec: user.nsec,
          skillTag: tag,
          seedMarket: seedMarket,  // ✅ SÉCURITÉ: Seed pour chiffrement
        );
        await nostrService.disconnect();
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Titre
          const Text(
            'Votre Profil',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFB347),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Créez votre identité sur le marché',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          
          // Formulaire
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section A: Identité
                    _buildSectionTitle('Identité'),
                    const SizedBox(height: 16),
                    
                    // Photo de profil et Bannière
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _pickProfileImage,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF2A2A2A),
                                    border: Border.all(
                                      color: const Color(0xFFFFB347),
                                      width: 2,
                                    ),
                                  ),
                                  child: _selectedProfileImage != null
                                      ? ClipOval(
                                          child: Image.file(
                                            _selectedProfileImage!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_a_photo,
                                          size: 32,
                                          color: Color(0xFFFFB347),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Avatar',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _pickBannerImage,
                                child: Container(
                                  width: double.infinity,
                                  height: 80,
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: const Color(0xFF2A2A2A),
                                    border: Border.all(
                                      color: const Color(0xFFFFB347),
                                      width: 2,
                                    ),
                                  ),
                                  child: _selectedBannerImage != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.file(
                                            _selectedBannerImage!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_photo_alternate,
                                          size: 32,
                                          color: Color(0xFFFFB347),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Bannière',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Nom affiché (obligatoire)
                    TextFormField(
                      controller: _displayNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nom affiché *',
                        labelStyle: TextStyle(color: Colors.grey[400]),
                        hintText: 'ex: Alice la Boulangère',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        prefixIcon: const Icon(Icons.person, color: Color(0xFFFFB347)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[700]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFFB347)),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.red),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Le nom est obligatoire';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Description courte (facultatif)
                    TextFormField(
                      controller: _aboutController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Description (facultatif)',
                        labelStyle: TextStyle(color: Colors.grey[400]),
                        hintText: 'Présentez-vous en quelques mots...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        prefixIcon: const Icon(Icons.description, color: Color(0xFFFFB347)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[700]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFFB347)),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Section B: Tags d'activité
                    _buildSectionTitle('Tags d\'activité'),
                    const SizedBox(height: 8),
                    Text(
                      'Sélectionnez vos domaines d\'activité ou ajoutez vos propres tags',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Tags par catégorie
                    ...AppConfig.defaultSkills.entries.map((entry) =>
                      _buildCategoryTags(entry.key, entry.value)
                    ),
                    
                    // Tags dynamiques depuis le relais
                    if (_dynamicTags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildDynamicTagsSection(),
                    ],
                    
                    // Indicateur de chargement des tags dynamiques
                    if (_loadingDynamicTags)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFFFB347),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Chargement des suggestions...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Section pour ajouter un tag personnalisé
                    const SizedBox(height: 16),
                    _buildCustomTagInput(),
                    
                    // Tags sélectionnés affichés en chips
                    if (_selectedTags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Vos tags sélectionnés:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[300],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedTags.map((tag) => Chip(
                          label: Text(tag),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () {
                            setState(() {
                              _selectedTags.remove(tag);
                            });
                          },
                          backgroundColor: const Color(0xFFFFB347).withValues(alpha: 0.3),
                          labelStyle: const TextStyle(color: Color(0xFFFFB347)),
                          deleteIconColor: const Color(0xFFFFB347),
                        )).toList(),
                      ),
                    ],
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Boutons de navigation
          Row(
            children: [
              if (widget.onBack != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Retour',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              if (widget.onBack != null) const SizedBox(width: 16),
              Expanded(
                flex: widget.onBack != null ? 2 : 1,
                child: ElevatedButton(
                  onPressed: _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB347),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continuer',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }
  
  Widget _buildCategoryTags(String category, List<String> tags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          category,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey[300],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags.map((tag) {
            final isSelected = _selectedTags.contains(tag);
            return FilterChip(
              label: Text(tag),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedTags.add(tag);
                  } else {
                    _selectedTags.remove(tag);
                  }
                });
              },
              selectedColor: const Color(0xFFFFB347).withValues(alpha: 0.3),
              checkmarkColor: const Color(0xFFFFB347),
              backgroundColor: const Color(0xFF2A2A2A),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFFFFB347) : Colors.white,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
  
  /// Construit la section des tags dynamiques récupérés depuis le relais
  Widget _buildDynamicTagsSection() {
    // Filtrer les tags dynamiques pour exclure ceux déjà dans les tags prédéfinis
    final allPredefinedTags = AppConfig.allDefaultSkills.toSet();
    final uniqueDynamicTags = _dynamicTags
        .where((tag) => !allPredefinedTags.contains(tag))
        .toList();
    
    if (uniqueDynamicTags.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.public, size: 16, color: Colors.grey[400]),
            const SizedBox(width: 8),
            Text(
              'Suggestions de la communauté',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[300],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: uniqueDynamicTags.take(20).map((tag) {
            final isSelected = _selectedTags.contains(tag);
            return FilterChip(
              label: Text(tag),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedTags.add(tag);
                  } else {
                    _selectedTags.remove(tag);
                  }
                });
              },
              selectedColor: const Color(0xFFFFB347).withValues(alpha: 0.3),
              checkmarkColor: const Color(0xFFFFB347),
              backgroundColor: const Color(0xFF2A2A2A),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFFFFB347) : Colors.white,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
  
  /// Construit le champ de saisie pour les tags personnalisés
  Widget _buildCustomTagInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.add_circle_outline, size: 16, color: Colors.grey[400]),
            const SizedBox(width: 8),
            Text(
              'Ajouter un tag personnalisé',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[300],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customTagController,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addCustomTag(),
                decoration: InputDecoration(
                  hintText: 'Ex: Boulanger, Artisan...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: const Icon(Icons.tag, color: Color(0xFFFFB347)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFFFB347)),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _addCustomTag,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB347),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              child: const Icon(
                Icons.add,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  void _pickProfileImage() async {
    final imageService = ImageCompressionService();
    final result = await imageService.pickAvatarWithOriginal();
    
    if (result != null) {
      setState(() {
        _base64Avatar = result.base64DataUri;
        _selectedProfileImage = File(result.originalPath);
      });
      
      Logger.log('OnboardingProfile', 'Avatar base64 généré: ${result.base64DataUri.length} chars, original: ${result.originalPath}');
    }
  }

  void _pickBannerImage() async {
    final imageService = ImageCompressionService();
    final result = await imageService.pickBannerWithOriginal();
    
    if (result != null) {
      setState(() {
        _base64Banner = result.base64DataUri;
        _selectedBannerImage = File(result.originalPath);
      });
      
      Logger.log('OnboardingProfile', 'Banner base64 généré: ${result.base64DataUri.length} chars, original: ${result.originalPath}');
    }
  }
  
  Future<void> _saveAndContinue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    final notifier = context.read<OnboardingNotifier>();
    final state = notifier.state;
    
    // ✅ UX OFFLINE-FIRST: Toujours utiliser la miniature base64 instantanée
    // L'utilisateur peut continuer immédiatement, l'upload IPFS se fait en arrière-plan
    String? pictureUrl = _base64Avatar;
    
    // Sauvegarder le profil immédiatement avec le base64
    notifier.setProfile(
      displayName: _displayNameController.text.trim(),
      about: _aboutController.text.trim().isEmpty
          ? null
          : _aboutController.text.trim(),
      activityTags: _selectedTags,
      // ✅ CORRECTION: La clé G1 est dérivée automatiquement, pas saisie manuellement
      g1PublicKey: null,
      pictureUrl: pictureUrl,
      bannerUrl: _base64Banner,
      profileImagePath: _selectedProfileImage?.path,
      bannerImagePath: _selectedBannerImage?.path,
    );
    
    // Mettre à jour l'utilisateur dans le StorageService
    final storageService = StorageService();
    final user = await storageService.getUser();
    if (user != null) {
      final updatedUser = User(
        npub: user.npub,
        nsec: user.nsec,
        displayName: _displayNameController.text.trim(),
        createdAt: user.createdAt,
        website: user.website,
        g1pub: user.g1pub,
        about: _aboutController.text.trim().isEmpty ? null : _aboutController.text.trim(),
        picture: pictureUrl,
        banner: _base64Banner,
        picture64: pictureUrl,
        banner64: _base64Banner,
        relayUrl: state.relayUrl,
        activityTags: _selectedTags,
      );
      await storageService.saveUser(updatedUser);
    }
    
    Logger.log('OnboardingProfile', 'Profil configuré avec base64: ${pictureUrl != null ? "${pictureUrl.length} chars" : "null"}');
    
    // Continuer immédiatement
    widget.onNext();
  }
}
