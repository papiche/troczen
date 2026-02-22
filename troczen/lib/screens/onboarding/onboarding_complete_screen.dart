import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/storage_service.dart';
import '../../services/crypto_service.dart';
import '../../services/nostr_service.dart';
import '../../services/du_calculation_service.dart';
import '../../models/market.dart';
import '../../models/user.dart';
import '../main_shell.dart';
import 'onboarding_flow.dart';

/// Étape 5: Écran de Bienvenue et Récapitulatif
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
  
  // Contrôleurs pour les champs salt/pepper
  final _saltController = TextEditingController();
  final _pepperController = TextEditingController();
  bool _obscurePepper = true;
  
  // Validation
  String? _saltError;
  String? _pepperError;
  
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
    _saltController.dispose();
    _pepperController.dispose();
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
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icône de succès
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFB347).withOpacity(0.2),
                      ),
                      child: const Icon(
                        Icons.celebration,
                        size: 64,
                        color: Color(0xFFFFB347),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Titre
                    const Text(
                      'Bienvenue dans TrocZen !',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFB347),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    Text(
                      'Créez vos identifiants de récupération',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[400],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Formulaire Salt/Pepper
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[800]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Explication
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Color(0xFFFFB347), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Ces identifiants permettent de retrouver votre compte. Gardez-les précieusement !',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          // ✅ CORRECTION: Wording utilisateur-friendly (pas de jargon technique)
                          // Champ Login (identifiant)
                          Text(
                            'Login (Identifiant unique)',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[300],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _saltController,
                            decoration: InputDecoration(
                              hintText: 'Ex: mon.pseudo@domaine.com',
                              hintStyle: TextStyle(color: Colors.grey[600]),
                              filled: true,
                              fillColor: const Color(0xFF1A1A1A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              errorText: _saltError,
                              prefixIcon: const Icon(Icons.person, color: Color(0xFFFFB347)),
                            ),
                            style: const TextStyle(color: Colors.white),
                            onChanged: (_) => _clearErrors(),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // ✅ CORRECTION: Wording utilisateur-friendly (pas de jargon technique)
                          // Champ Mot de passe
                          Text(
                            'Mot de passe',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[300],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _pepperController,
                            obscureText: _obscurePepper,
                            decoration: InputDecoration(
                              hintText: 'Minimum 8 caractères',
                              hintStyle: TextStyle(color: Colors.grey[600]),
                              filled: true,
                              fillColor: const Color(0xFF1A1A1A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              errorText: _pepperError,
                              prefixIcon: const Icon(Icons.lock, color: Color(0xFFFFB347)),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePepper ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.grey[500],
                                ),
                                onPressed: () {
                                  setState(() => _obscurePepper = !_obscurePepper);
                                },
                              ),
                            ),
                            style: const TextStyle(color: Colors.white),
                            onChanged: (_) => _clearErrors(),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Avertissement de sécurité
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '⚠️ Ces identifiants sont irrécupérables si vous les perdez. Notez-les dans un endroit sûr !',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange[300],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
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
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
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
  
  /// Efface les messages d'erreur
  void _clearErrors() {
    if (_saltError != null || _pepperError != null) {
      setState(() {
        _saltError = null;
        _pepperError = null;
      });
    }
  }
  
  /// Valide les identifiants salt/pepper
  bool _validateCredentials() {
    bool isValid = true;
    
    // Validation du salt (identifiant)
    final salt = _saltController.text.trim();
    if (salt.isEmpty) {
      setState(() => _saltError = 'L\'identifiant est requis');
      isValid = false;
    } else if (salt.length < 3) {
      setState(() => _saltError = 'Minimum 3 caractères');
      isValid = false;
    }
    
    // Validation du pepper (mot de passe)
    final pepper = _pepperController.text;
    if (pepper.isEmpty) {
      setState(() => _pepperError = 'Le mot de passe est requis');
      isValid = false;
    } else if (pepper.length < 8) {
      setState(() => _pepperError = 'Minimum 8 caractères');
      isValid = false;
    }
    
    return isValid;
  }
  
  /// ✅ WOTX: Publie les demandes d'attestation (Kind 30501) en arrière-plan sans bloquer l'UI
  /// Utilise un fire-and-forget pour ne pas ralentir l'onboarding
  ///
  /// ✅ SÉCURITÉ: Le contenu est chiffré avec la Seed du Marché.
  void _publishSkillPermitsInBackground({
    required NostrService nostrService,
    required String npub,
    required String nsec,
    required List<String> skillTags,
    required String seedMarket,  // ✅ SÉCURITÉ: Seed pour chiffrement
  }) {
    // Lancer la publication en arrière-plan sans attendre
    Future(() async {
      try {
        int successCount = 0;
        for (final tag in skillTags) {
          try {
            // ✅ WOTX: Émettre les requêtes d'attestation (Kind 30501) pour chaque savoir-faire
            final success = await nostrService.publishSkillRequest(
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
      } catch (e) {
        debugPrint('⚠️ Erreur générale publication Skill Requests: $e');
      }
    });
  }
  
  Future<void> _completeOnboarding() async {
    // Valider les identifiants avant de continuer
    if (!_validateCredentials()) {
      return;
    }
    
    setState(() => _isCreatingAccount = true);
    
    try {
      final notifier = context.read<OnboardingNotifier>();
      final state = notifier.state;
      
      final storageService = StorageService();
      final cryptoService = CryptoService();
      
      // 1. Sauvegarder le marché
      final market = Market(
        name: state.marketName ?? 'Marché Local',
        seedMarket: state.seedMarket!,
        validUntil: DateTime.now().add(const Duration(days: 365)),
        relayUrl: state.relayUrl,
      );
      await storageService.saveMarket(market);
      
      // 2. Créer l'utilisateur avec les identifiants fournis (salt/pepper)
      // Ces identifiants permettent de régénérer la clé privée de manière déterministe
      final salt = _saltController.text.trim();
      final pepper = _pepperController.text;
      
      final seedBytes = await cryptoService.deriveSeed(
        salt,
        pepper,
      );
      final privateKeyBytes = await cryptoService.deriveNostrPrivateKey(seedBytes);
      cryptoService.secureZeroiseBytes(seedBytes);
      
      final privateKeyHex = privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final publicKeyHex = cryptoService.derivePublicKey(privateKeyBytes);
      final g1pub = state.g1PublicKey ?? cryptoService.generateG1Pub(privateKeyBytes);
      
      final user = User(
        npub: publicKeyHex,
        nsec: privateKeyHex,
        displayName: state.displayName!,
        createdAt: DateTime.now(),
        website: null,
        g1pub: g1pub,
      );
      
      await storageService.saveUser(user);
      
      // 3. Publier le profil sur Nostr
      try {
        final nostrService = NostrService(
          cryptoService: cryptoService,
          storageService: storageService,
        );
        
        await nostrService.connect(state.relayUrl);
        
        await nostrService.publishUserProfile(
          npub: user.npub,
          nsec: user.nsec,
          name: user.displayName,
          displayName: user.displayName,
          about: state.about ?? 'Utilisateur TrocZen - Monnaie locale ẐEN',
          picture: state.pictureUrl,  // ✅ Image profil IPFS
          website: null,
          g1pub: user.g1pub,
          tags: state.activityTags,  // ✅ Tags d'activité/centres d'intérêt
        );
        
        // ✅ NOUVEAU: Publier les Skill Permits en arrière-plan (ne pas attendre)
        // Cela permet de ne pas ralentir la finalisation de l'onboarding
        if (state.activityTags != null && state.activityTags!.isNotEmpty) {
          _publishSkillPermitsInBackground(
            nostrService: nostrService,
            npub: user.npub,
            nsec: user.nsec,
            skillTags: state.activityTags!,
            seedMarket: market.seedMarket,  // ✅ SÉCURITÉ: Seed pour chiffrement
          );
        }
        
        await nostrService.disconnect();
      } catch (e) {
        debugPrint('⚠️ Erreur publication profil Nostr: $e');
        // Continuer même si la publication échoue
      }
      
      // 4. Générer le Bon Zéro de bootstrap (0 ẐEN, TTL 28j)
      try {
        final nostrService = NostrService(
          cryptoService: cryptoService,
          storageService: storageService,
        );
        
        final duService = DuCalculationService(
          storageService: storageService,
          nostrService: nostrService,
          cryptoService: cryptoService,
        );
        
        // Vérifier que l'utilisateur n'a pas déjà reçu le bootstrap
        if (!await storageService.hasReceivedBootstrap()) {
          await duService.generateBootstrapAllocation(user, market);
          debugPrint('✅ Bon Zéro (bootstrap) créé pour ${user.displayName}');
        }
      } catch (e) {
        debugPrint('⚠️ Erreur génération Bon Zéro: $e');
        // Continuer même si le bootstrap échoue
      }
      
      // 5. Marquer l'onboarding comme complété
      await storageService.markOnboardingComplete();
      
      setState(() => _isCreatingAccount = false);
      
      // 5. Navigation vers l'écran principal
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
