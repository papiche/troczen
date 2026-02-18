import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/image_cache_service.dart';
import '../../services/storage_service.dart';
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
  final _g1PublicKeyController = TextEditingController();
  
  final List<String> _selectedTags = [];
  final ImagePicker _imagePicker = ImagePicker();
  
  File? _selectedProfileImage;
  bool _uploadingImage = false;
  
  // Tags prédéfinis par catégorie
  final Map<String, List<String>> _predefinedTags = {
    'Alimentation': [
      'Boulanger',
      'Maraîcher',
      'Fromager',
      'Traiteur',
      'Épicerie',
    ],
    'Services': [
      'Artisan',
      'Plombier',
      'Électricien',
      'Coiffeur',
      'Réparateur',
    ],
    'Culture & Bien-être': [
      'Musicien',
      'Thérapeute',
      'Yoga',
      'Librairie',
      'Café',
    ],
    'Artisanat': [
      'Potier',
      'Tisserand',
      'Bijoutier',
      'Menuisier',
      'Couturier',
    ],
  };
  
  @override
  void dispose() {
    _displayNameController.dispose();
    _aboutController.dispose();
    _g1PublicKeyController.dispose();
    super.dispose();
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
                    
                    // Photo de profil
                    Center(
                      child: GestureDetector(
                        onTap: _pickProfileImage,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF2A2A2A),
                            border: Border.all(
                              color: const Color(0xFFFFB347),
                              width: 3,
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
                                  size: 48,
                                  color: Color(0xFFFFB347),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Toucher pour ajouter une photo',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
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
                      'Sélectionnez vos domaines d\'activité',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Tags par catégorie
                    ..._predefinedTags.entries.map((entry) => 
                      _buildCategoryTags(entry.key, entry.value)
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Section C: Clé Ğ1 (optionnelle)
                    _buildSectionTitle('Clé Ğ1 (optionnel pour v1.007)'),
                    const SizedBox(height: 8),
                    Text(
                      'Importez votre clé publique Ğ1 au format base58',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _g1PublicKeyController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Clé publique Ğ1 (facultatif)',
                        labelStyle: TextStyle(color: Colors.grey[400]),
                        hintText: 'ex: 4q3f7...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        prefixIcon: const Icon(Icons.key, color: Color(0xFFFFB347)),
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
                  onPressed: _uploadingImage ? null : _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB347),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _uploadingImage
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
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
              selectedColor: const Color(0xFFFFB347).withOpacity(0.3),
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
  
  void _pickProfileImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() => _selectedProfileImage = File(image.path));
    }
  }
  
  Future<void> _saveAndContinue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    final notifier = context.read<OnboardingNotifier>();
    final state = notifier.state;
    
    String? pictureUrl;
    
    // Upload de l'avatar si une image a été sélectionnée
    if (_selectedProfileImage != null) {
      setState(() => _uploadingImage = true);
      
      try {
        // Récupérer le npub de l'utilisateur (généré lors de l'étape seed)
        final storageService = StorageService();
        final user = await storageService.getUser();
        
        if (user != null) {
          final apiService = ApiService();
          // Configurer l'URL de l'API selon l'état de l'onboarding
          apiService.setCustomApi(state.apiUrl, state.relayUrl);
          final result = await apiService.uploadImage(
            npub: user.npub,
            imageFile: _selectedProfileImage!,
            type: 'avatar',
          );
          
          if (result != null) {
            // Utiliser ipfs_url en priorité, sinon url
            pictureUrl = result['ipfs_url'] ?? result['url'];
          }
        }
      } catch (e) {
        debugPrint('❌ Erreur upload avatar: $e');
        // Continuer même si l'upload échoue
      } finally {
        setState(() => _uploadingImage = false);
      }
    }
    
    notifier.setProfile(
      displayName: _displayNameController.text.trim(),
      about: _aboutController.text.trim().isEmpty
          ? null
          : _aboutController.text.trim(),
      activityTags: _selectedTags,
      g1PublicKey: _g1PublicKeyController.text.trim().isEmpty
          ? null
          : _g1PublicKeyController.text.trim(),
      pictureUrl: pictureUrl,
    );
    
    widget.onNext();
  }
}
