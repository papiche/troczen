import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../../services/crypto_service.dart';
import '../../models/user.dart';

/// Étape 1: Création du compte utilisateur
class OnboardingAccountScreen extends StatefulWidget {
  final VoidCallback onNext;
  
  const OnboardingAccountScreen({
    super.key,
    required this.onNext,
  });

  @override
  State<OnboardingAccountScreen> createState() => _OnboardingAccountScreenState();
}

class _OnboardingAccountScreenState extends State<OnboardingAccountScreen> with SingleTickerProviderStateMixin {
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
  
  Future<void> _createAccountAndContinue() async {
    if (!_validateCredentials()) {
      return;
    }
    
    setState(() => _isCreatingAccount = true);
    
    try {
      final storageService = StorageService();
      final cryptoService = CryptoService();
      
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
      final g1pub = cryptoService.generateG1Pub(privateKeyBytes);
      
      // Créer l'utilisateur avec un nom par défaut
      final user = User(
        npub: publicKeyHex,
        nsec: privateKeyHex,
        displayName: 'Utilisateur',
        createdAt: DateTime.now(),
        website: null,
        g1pub: g1pub,
        activityTags: [],
      );
      
      await storageService.saveUser(user);
      
      // Initialisation silencieuse du marché global
      await storageService.initializeDefaultMarket(name: 'Marché Global Ğ1');
      
      setState(() => _isCreatingAccount = false);
      
      if (mounted) {
        widget.onNext();
      }
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
            'Impossible de créer le compte: $e',
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

  @override
  Widget build(BuildContext context) {
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
                        'Création du compte',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFB347),
                        ),
                      ),
                      const SizedBox(height: 8),
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
                                const Icon(Icons.info_outline, color: Color(0xFFFFB347), size: 20),
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
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
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
              onPressed: _isCreatingAccount ? null : _createAccountAndContinue,
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
                      'Continuer',
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
}
