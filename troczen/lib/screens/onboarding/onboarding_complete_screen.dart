import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/storage_service.dart';
import '../../services/api_service.dart';
import '../../services/crypto_service.dart';
import '../../services/nostr_service.dart';
import '../../services/du_calculation_service.dart';
import '../../services/logger_service.dart';
import '../../config/app_config.dart';
import '../../models/market.dart';
import '../../models/user.dart';
import '../../models/onboarding_state.dart';
import '../main_shell.dart';
import 'onboarding_flow.dart';

/// Étape 7: Écran de Bienvenue et Récapitulatif
class OnboardingCompleteScreen extends StatefulWidget {
  const OnboardingCompleteScreen({super.key});

  @override
  State<OnboardingCompleteScreen> createState() => _OnboardingCompleteScreenState();
}

class _OnboardingCompleteScreenState extends State<OnboardingCompleteScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  bool _isCreatingAccount = false;
  
  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );
    
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<OnboardingNotifier>();
    final state = notifier.state;
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      
                      const Text(
                        'Bienvenue !',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFB347),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Votre compte est prêt',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[400],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Récapitulatif compact
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[800]!),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              icon: Icons.person,
                              label: 'Nom',
                              value: state.displayName ?? 'Non défini',
                            ),
                            const Divider(height: 16, color: Colors.grey),
                            _buildInfoRow(
                              icon: Icons.cloud,
                              label: 'Relais',
                              value: _shortenUrl(state.relayUrl),
                            ),
                            if (state.p3Count > 0) ...[
                              const Divider(height: 16, color: Colors.grey),
                              _buildInfoRow(
                                icon: Icons.sync,
                                label: 'Bons',
                                value: '${state.p3Count}',
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Bouton principal
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isCreatingAccount ? null : _completeOnboarding,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB347),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCreatingAccount
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Entrer dans TrocZen',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
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
        Icon(icon, color: const Color(0xFFFFB347), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  String _shortenUrl(String url) {
    if (url.length <= 30) return url;
    return '${url.substring(0, 27)}...';
  }
  
  /// ✅ WOTX: Publie les demandes d'attestation (Kind 30501) en arrière-plan sans bloquer l'UI
  /// Utilise un fire-and-forget pour ne pas ralentir l'onboarding
  ///
  /// ✅ SÉCURITÉ: Le contenu est chiffré avec la Seed du Marché.
  /// Upload IPFS en arrière-plan (fire-and-forget)
  /// Met à jour le profil local et republie sur Nostr une fois terminé
  void _uploadImagesToIPFSInBackground({
    required OnboardingState state,
    required User user,
    required StorageService storageService,
    required CryptoService cryptoService,
  }) async {
    try {
      final apiService = ApiService();
      apiService.setCustomApi(state.apiUrl, state.relayUrl);
      
      String? newPictureUrl;
      String? newBannerUrl;
      bool updated = false;
      
      // Upload Avatar
      if (state.profileImagePath != null) {
        debugPrint('Démarrage upload IPFS avatar en arrière-plan...');
        final result = await apiService.uploadImage(
          npub: user.npub,
          imageFile: File(state.profileImagePath!),
          type: 'avatar',
          waitForIpfs: true, // On attend l'URL IPFS car on est en background
        );
        if (result != null) {
          newPictureUrl = result['ipfs_url'] ?? result['url'];
          if (newPictureUrl != null) updated = true;
        }
      }
      
      // Upload Banner
      if (state.bannerImagePath != null) {
        debugPrint('Démarrage upload IPFS banner en arrière-plan...');
        final result = await apiService.uploadImage(
          npub: user.npub,
          imageFile: File(state.bannerImagePath!),
          type: 'banner',
          waitForIpfs: true, // On attend l'URL IPFS car on est en background
        );
        if (result != null) {
          newBannerUrl = result['ipfs_url'] ?? result['url'];
          if (newBannerUrl != null) updated = true;
        }
      }
      
      // Si au moins une image a été uploadée avec succès
      if (updated) {
        // 1. Mettre à jour l'utilisateur local
        final updatedUser = User(
          npub: user.npub,
          nsec: user.nsec,
          displayName: user.displayName,
          createdAt: user.createdAt,
          website: user.website,
          g1pub: user.g1pub,
          picture: newPictureUrl ?? user.picture,
          banner: newBannerUrl ?? user.banner,
          picture64: user.picture64,
          banner64: user.banner64,
          relayUrl: user.relayUrl,
          activityTags: user.activityTags,
        );
        await storageService.saveUser(updatedUser);
        
        // 2. Republier le profil sur Nostr avec les nouvelles URLs
        try {
          final nostrService = context.read<NostrService>();
          
          if (await nostrService.connect(state.relayUrl)) {
            await nostrService.publishUserProfile(
              npub: updatedUser.npub,
              nsec: updatedUser.nsec,
              name: updatedUser.displayName,
              displayName: updatedUser.displayName,
              about: state.about ?? 'Utilisateur TrocZen - Monnaie locale ẐEN',
              picture: updatedUser.picture,
              banner: updatedUser.banner,
              picture64: updatedUser.picture64,
              banner64: updatedUser.banner64,
              website: null,
              g1pub: updatedUser.g1pub,
              tags: updatedUser.activityTags,
            );
            await nostrService.disconnect();
            debugPrint('✅ Profil Nostr mis à jour avec les URLs IPFS');
          }
        } catch (e) {
          debugPrint('⚠️ Erreur republication profil Nostr (IPFS): $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Erreur upload IPFS arrière-plan: $e');
    }
  }

  /// ✅ WOTX: Publie les demandes d'attestation (Kind 30501) en arrière-plan sans bloquer l'UI
  void _publishSkillPermitsInBackground({
    required String relayUrl,
    required String npub,
    required String nsec,
    required List<String> skillTags,
    required String seedMarket,  // ✅ SÉCURITÉ: Seed pour chiffrement
    required StorageService storageService,
    required CryptoService cryptoService,
  }) {
    // Lancer la publication en arrière-plan sans attendre
    Future(() async {
      try {
        final bgNostrService = context.read<NostrService>();
        
        if (await bgNostrService.connect(relayUrl)) {
          int successCount = 0;
          for (final tag in skillTags) {
            try {
              // ✅ WOTX: Émettre les requêtes d'attestation (Kind 30501) pour chaque savoir-faire
              final success = await bgNostrService.publishSkillRequest(
                npub: npub,
                nsec: nsec,
                skill: tag,
                seedMarket: seedMarket,  // ✅ SÉCURITÉ: Seed pour chiffrement
              );
              if (success) {
                successCount++;
                debugPrint('✅ Skill Request (Kind 30501) publiée pour: $tag');
              } else {
                debugPrint('⚠️ Échec publication Skill Request pour: $tag');
              }
            } catch (e) {
              debugPrint('⚠️ Erreur publication Skill Request pour $tag: $e');
              // Continuer avec les autres tags même si un échoue
            }
          }
          debugPrint('✅ WOTX: $successCount/${skillTags.length} demandes de savoir-faire (Kind 30501) publiées');
          await bgNostrService.disconnect();
        }
      } catch (e) {
        debugPrint('⚠️ Erreur générale publication Skill Requests: $e');
      }
    });
  }
  
  Future<void> _checkClipboardForReferrer() async {
    try {
      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      String? text = data?.text;

      if (text != null && text.startsWith('npub1')) {
        final storageService = StorageService();
        // C'est un lien d'invitation !
        // On stocke l'npub dans le StorageService comme "contact en attente"
        await storageService.addContact(text);
        
        // On peut aussi déclencher le follow direct sur Nostr
        final nostrService = context.read<NostrService>();
        final user = await storageService.getUser();
        if (user != null) {
           await nostrService.connect(AppConfig.defaultRelayUrl);
           await nostrService.publishContactList(
             npub: user.npub,
             nsec: user.nsec,
             contactsNpubs: [text]
           );
           await nostrService.disconnect();
        }
        
        Logger.success('Onboarding', 'Parrain détecté et suivi : $text');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vous avez suivi automatiquement l\'ami qui vous a invité !'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Onboarding', 'Erreur lecture presse-papier', e);
    }
  }

Future<void> _completeOnboarding() async {
    setState(() => _isCreatingAccount = true);
    
    try {
      final notifier = context.read<OnboardingNotifier>();
      final state = notifier.state;
      
      final storageService = StorageService();
      final cryptoService = CryptoService();
      final apiService = ApiService();
      apiService.setCustomApi(state.apiUrl, state.relayUrl);
      
      // 1. Sauvegarder le marché
      final market = Market(
        name: state.marketName ?? 'Marché Local',
        seedMarket: state.seedMarket!,
        validUntil: DateTime.now().add(const Duration(days: 36500)), // Valable 100 ans par défaut
        relayUrl: state.relayUrl,
      );
      await storageService.saveMarket(market);
      
      // 2. Récupérer l'utilisateur
      User user = (await storageService.getUser())!;
      
      // 3. ✅ ATTENDRE L'UPLOAD IPFS ICI (Finie la Race Condition)
      String? finalPictureUrl = user.picture;
      String? finalBannerUrl = user.banner;

      if (state.profileImagePath != null) {
        final result = await apiService.uploadImage(
          npub: user.npub,
          imageFile: File(state.profileImagePath!),
          type: 'avatar',
          waitForIpfs: true,
        );
        if (result != null) finalPictureUrl = result['ipfs_url'] ?? result['url'];
      }

      if (state.bannerImagePath != null) {
        final result = await apiService.uploadImage(
          npub: user.npub,
          imageFile: File(state.bannerImagePath!),
          type: 'banner',
          waitForIpfs: true,
        );
        if (result != null) finalBannerUrl = result['ipfs_url'] ?? result['url'];
      }

      // Mettre à jour l'utilisateur localement avec les vraies URLs IPFS
      user = user.copyWith(
        picture: finalPictureUrl,
        banner: finalBannerUrl,
      );
      await storageService.saveUser(user);
      
      // 4. Publier le profil sur Nostr avec les bonnes URLs
      try {
        final nostrService = context.read<NostrService>();
        await nostrService.connect(state.relayUrl);
        
        await nostrService.publishUserProfile(
          npub: user.npub,
          nsec: user.nsec,
          name: user.displayName,
          displayName: user.displayName,
          about: state.about ?? 'Utilisateur TrocZen - Monnaie locale ẐEN',
          picture: user.picture,
          banner: user.banner,
          picture64: user.picture64,
          banner64: user.banner64,
          website: null,
          g1pub: user.g1pub,
          tags: state.activityTags, // ✅ Tags d'activité
        );
        
        if (state.activityTags.isNotEmpty) {
          _publishSkillPermitsInBackground(
            relayUrl: state.relayUrl,
            npub: user.npub,
            nsec: user.nsec,
            skillTags: state.activityTags,
            seedMarket: market.seedMarket,
            storageService: storageService,
            cryptoService: cryptoService,
          );
        }
        
        // 5. Générer le Bon Zéro
        try {
          final duService = DuCalculationService(
            storageService: storageService,
            nostrService: nostrService,
            cryptoService: cryptoService,
          );
          if (!await storageService.hasReceivedBootstrap()) {
            await duService.generateBootstrapAllocation(user, market);
          }
        } catch (e) {
          debugPrint('⚠️ Erreur génération Bon Zéro: $e');
        }
        
        await nostrService.disconnect();
      } catch (e) {
        debugPrint('⚠️ Erreur publication Nostr: $e');
      }
      
      // 6. Finaliser
      await storageService.markOnboardingComplete();
      await _checkClipboardForReferrer();
      
      setState(() => _isCreatingAccount = false);
      
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => MainShell(user: user)),
        (route) => false,
      );
      
      // 6. Marquer l'onboarding comme complété
      await storageService.markOnboardingComplete();
      
      // Vérifier le presse-papier pour un parrain
      await _checkClipboardForReferrer();
      
      setState(() => _isCreatingAccount = false);
      
      // 7. Navigation vers l'écran principal
      if (!mounted) return;
      
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => MainShell(user: user),
        ),
        (route) => false,
      );
      
    } catch (e) {
      setState(() => _isCreatingAccount = false);
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Erreur',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Impossible de finaliser la configuration: $e',
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
  }
}
