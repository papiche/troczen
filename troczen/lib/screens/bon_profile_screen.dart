import 'package:flutter/material.dart';
import 'dart:io';
import 'package:hex/hex.dart';
import '../config/app_config.dart';
import '../models/bon.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/image_compression_service.dart';

/// Écran de gestion du profil d'un bon
/// Permet à l'émetteur (détenteur P1) de modifier les métadonnées
class BonProfileScreen extends StatefulWidget {
  final User user;
  final Bon bon;

  const BonProfileScreen({
    super.key,
    required this.user,
    required this.bon,
  });

  @override
  State<BonProfileScreen> createState() => _BonProfileScreenState();
}

class _BonProfileScreenState extends State<BonProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _termsController = TextEditingController();
  
  final _apiService = ApiService();
  final _crypto = CryptoService();
  final _storage = StorageService();
  
  String _selectedCategory = 'generic';
  String? _selectedImage;
  bool _isSaving = false;
  bool _isUploading = false;
  bool _canEdit = false;

  final _categories = {
    'generic': {'label': '📦 Générique', 'icon': Icons.category},
    'food': {'label': '🍯 Alimentation', 'icon': Icons.restaurant},
    'artisanat': {'label': '🎨 Artisanat', 'icon': Icons.palette},
    'services': {'label': '🔧 Services', 'icon': Icons.build},
    'culture': {'label': '🎭 Culture', 'icon': Icons.theater_comedy},
    'wellness': {'label': '🧘 Bien-être', 'icon': Icons.spa},
  };

  @override
  void initState() {
    super.initState();
    _checkEditPermission();
    _loadProfile();
  }

  /// Vérifier si l'utilisateur peut éditer (a P1+P2)
  void _checkEditPermission() {
    // L'émetteur est le seul à avoir P1
    _canEdit = (widget.user.npub == widget.bon.issuerNpub && widget.bon.p1 != null);
  }

  void _loadProfile() {
    _titleController.text = widget.bon.issuerName;
    _descriptionController.text = widget.bon.wish ?? '';
    _selectedCategory = 'generic';  // TODO: Load from bon metadata
  }

  Future<void> _selectImage() async {
    final imageService = ImageCompressionService();
    
    setState(() => _isUploading = true);
    
    try {
      final dataUri = await imageService.pickAndCompressAvatar();
          
      if (dataUri != null) {
        setState(() {
          _selectedImage = dataUri;
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

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate() || !_canEdit) return;

    setState(() => _isSaving = true);

    try {
      // 1. Utiliser l'image Base64 si sélectionnée
      String? imageUrl = _selectedImage ?? widget.bon.picture;

      // 2. ✅ Profil mis à jour uniquement sur Nostr (kind 0 et 30303)
      // L'API backend n'est plus utilisée pour les profils

      // 3. Republier sur Nostr avec métadonnées mises à jour
      final market = await _storage.getMarket();
      if (market != null && widget.bon.p2 != null) {
        // ✅ SÉCURITÉ: Récupérer P3 en Uint8List directement
        final p3Bytes = await _storage.getP3FromCacheBytes(widget.bon.bonId);
        
        if (p3Bytes != null) {
          // ✅ SÉCURITÉ: Récupérer P2 en Uint8List directement
          final p2Bytes = widget.bon.p2Bytes;
          
          if (p2Bytes != null) {
            final nostrService = NostrService(
              cryptoService: _crypto,
              storageService: _storage,
            );

            await nostrService.connect(market.relayUrl ?? AppConfig.defaultRelayUrl);
            
            // ✅ SÉCURITÉ: Reconstruire sk_B en Uint8List
            final nsecBonBytes = _crypto.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);
            final nsecHex = HEX.encode(nsecBonBytes);
            
            // Publication du profil du bon (kind 0)
            await nostrService.publishUserProfile(
              npub: widget.bon.bonId,
              nsec: nsecHex,
              name: _titleController.text,
              displayName: _titleController.text,
              about: _descriptionController.text.isNotEmpty ? _descriptionController.text : 'Bon ${widget.bon.value} ẐEN - ${market.name}',
              picture: imageUrl,
              banner: imageUrl,  // Utilise la même image pour le bandeau
              website: widget.user.website,  // Par défaut: site du profil utilisateur
              g1pub: widget.user.g1pub,  // Par défaut: g1pub du profil utilisateur
            );
            
            // ✅ SÉCURITÉ: Nettoyer les clés de la RAM
            _crypto.secureZeroiseBytes(nsecBonBytes);
            _crypto.secureZeroiseBytes(p2Bytes);
            _crypto.secureZeroiseBytes(p3Bytes);

            // Republier P3 avec nouvelles métadonnées
            // Note: publishP3 attend des String, mais les parts sont déjà en RAM
            // On utilise les propriétés String du bon (déjà en mémoire)
            await nostrService.publishP3(
              bonId: widget.bon.bonId,
              p2Hex: widget.bon.p2!,
              p3Hex: widget.bon.p3 ?? (await _storage.getP3FromCache(widget.bon.bonId))!,
              seedMarket: market.seedMarket,
              issuerNpub: widget.user.npub,
              marketName: market.name,
              value: widget.bon.value,
              category: _selectedCategory,
              rarity: widget.bon.rarity,
            );

            await nostrService.disconnect();
          }
        }
      }

      // ✅ Sauvegarder les modifications du Profil du Bon en LOCAL
      final updatedBon = widget.bon.copyWith(
        picture: imageUrl ?? widget.bon.picture,
        logoUrl: imageUrl ?? widget.bon.logoUrl,
        issuerName: _titleController.text,
        wish: _descriptionController.text,
      );
      await _storage.saveBon(updatedBon);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profil mis à jour !'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } on ShamirReconstructionException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
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
    if (!_canEdit) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: const Text('Profil du Bon'),
          backgroundColor: const Color(0xFF1E1E1E),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 64, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text(
                  'Édition non autorisée',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Seul l\'émetteur du bon peut modifier son profil',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Éditer le Profil du Bon'),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          if (!_isSaving)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveProfile,
              tooltip: 'Sauvegarder',
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
              // Prévisualisation carte
              _buildPreviewCard(),
              
              const SizedBox(height: 24),

              // Catégorie
              _buildSectionTitle('Catégorie'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.entries.map((entry) {
                  final isSelected = _selectedCategory == entry.key;
                  final data = entry.value;
                  return FilterChip(
                    avatar: Icon(
                      data['icon'] as IconData,
                      color: isSelected ? Colors.white : Colors.grey,
                      size: 20,
                    ),
                    label: Text(data['label'] as String),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _selectedCategory = entry.key);
                    },
                    selectedColor: const Color(0xFFFFB347),
                    backgroundColor: const Color(0xFF2A2A2A),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[400],
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Titre
              _buildSectionTitle('Titre'),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Nom affiché du bon'),
                validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
              ),

              const SizedBox(height: 16),

              // Description
              _buildSectionTitle('Description'),
              TextFormField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                maxLines: 4,
                decoration: _inputDecoration('Décrivez votre bon...'),
              ),

              const SizedBox(height: 16),

              // Conditions d'utilisation
              _buildSectionTitle('Conditions (optionnel)'),
              TextFormField(
                controller: _termsController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: _inputDecoration('Ex: Valable 3 mois, réservation conseillée...'),
              ),

              const SizedBox(height: 24),

              // Image
              _buildSectionTitle('Image du Bon'),
              GestureDetector(
                onTap: _isUploading ? null : _selectImage,
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[700]!),
                  ),
                  child: _selectedImage != null || widget.bon.picture != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ImageCompressionService.buildImage(
                            uri: _selectedImage ?? widget.bon.picture,
                            width: double.infinity,
                            height: 150,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isUploading)
                                const CircularProgressIndicator()
                              else ...[
                                Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey[600]),
                                const SizedBox(height: 8),
                                Text(
                                  'Ajouter une photo',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                                Text(
                                  '(Sera stockée localement)',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 32),

              // Bouton sauvegarder
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isSaving ? 'Publication...' : 'Publier sur Nostr + API'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB347),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),

              const SizedBox(height: 16),

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
                    const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Les modifications seront publiées sur Nostr et l\'API backend',
                        style: TextStyle(color: Colors.blue[200], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFFF8E7)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB347), width: 3),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _categories[_selectedCategory]!['icon'] as IconData,
                      color: const Color(0xFFFFB347),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _selectedCategory.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${widget.bon.value} ẐEN',
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
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _categories[_selectedCategory]!['icon'] as IconData,
                      size: 48,
                      color: const Color(0xFFFFB347),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _titleController.text.isEmpty 
                          ? widget.bon.issuerName 
                          : _titleController.text,
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
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFB347),
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[600]),
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
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _termsController.dispose();
    super.dispose();
  }
}
