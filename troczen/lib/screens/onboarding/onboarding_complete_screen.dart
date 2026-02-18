import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/storage_service.dart';
import '../../services/crypto_service.dart';
import '../../services/nostr_service.dart';
import '../../models/market.dart';
import '../../models/user.dart';
import '../views/wallet_view.dart';
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
  bool _accountCreated = false;
  
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
                      'Votre profil a été configuré avec succès',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[400],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Récapitulatif
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[800]!),
                      ),
                      child: Column(
                        children: [
                          _buildInfoRow(
                            icon: Icons.person,
                            label: 'Nom',
                            value: state.displayName ?? 'Non défini',
                          ),
                          const Divider(height: 24, color: Colors.grey),
                          _buildInfoRow(
                            icon: Icons.cloud,
                            label: 'Relais Nostr',
                            value: _shortenUrl(state.relayUrl),
                          ),
                          const Divider(height: 24, color: Colors.grey),
                          _buildInfoRow(
                            icon: Icons.sync,
                            label: 'Bons synchronisés',
                            value: '${state.p3Count} bon${state.p3Count > 1 ? 's' : ''}',
                          ),
                          if (state.activityTags.isNotEmpty) ...[
                            const Divider(height: 24, color: Colors.grey),
                            _buildInfoRow(
                              icon: Icons.label,
                              label: 'Tags',
                              value: state.activityTags.take(2).join(', ') +
                                  (state.activityTags.length > 2
                                      ? ' +${state.activityTags.length - 2}'
                                      : ''),
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
  
  Future<void> _completeOnboarding() async {
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
      
      // 2. Créer l'utilisateur avec credentials par défaut
      // (L'utilisateur pourra se connecter plus tard avec login/password)
      final tempLogin = 'user_${DateTime.now().millisecondsSinceEpoch}';
      final tempPassword = 'temp123456';
      
      final privateKeyBytes = await cryptoService.derivePrivateKey(
        tempLogin,
        tempPassword,
      );
      
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
          website: null,
          g1pub: user.g1pub,
        );
        
        await nostrService.disconnect();
      } catch (e) {
        debugPrint('⚠️ Erreur publication profil Nostr: $e');
        // Continuer même si la publication échoue
      }
      
      // 4. Marquer l'onboarding comme complété
      await storageService.markOnboardingComplete();
      
      setState(() {
        _accountCreated = true;
        _isCreatingAccount = false;
      });
      
      // 5. Navigation vers l'écran principal
      if (!mounted) return;
      
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => WalletView(user: user),
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
