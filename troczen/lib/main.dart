import 'package:flutter/material.dart';
import 'models/user.dart';
import 'models/nostr_profile.dart';
import 'services/crypto_service.dart';
import 'services/storage_service.dart';
import 'services/nostr_service.dart';
import 'screens/wallet_screen.dart';

void main() {
  runApp(const TrocZenApp());
}

class TrocZenApp extends StatelessWidget {
  const TrocZenApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrocZen',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFFFB347),
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB347),
          secondary: Color(0xFF0A7EA4),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _cryptoService = CryptoService();
  final _storageService = StorageService();
  
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkExistingUser();
  }

  Future<void> _checkExistingUser() async {
    final user = await _storageService.getUser();
    if (user != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => WalletScreen(user: user),
        ),
      );
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    try {
      // ✅ CORRECTION: Dériver réellement la clé privée depuis login/password
      final privateKeyBytes = await _cryptoService.derivePrivateKey(
        _loginController.text.trim(),
        _passwordController.text,
      );

      // Convertir en hex
      final privateKeyHex = privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // ✅ CORRECTION: Dériver la clé publique depuis la privée
      final publicKeyHex = _cryptoService.derivePublicKey(privateKeyBytes);
      
      // ✅ SÉCURITÉ 100%: Valider la clé générée
      if (!_cryptoService.isValidPublicKey(publicKeyHex)) {
        throw Exception('Clé publique invalide générée');
      }

      // ✅ GÉNÉRATION AUTOMATIQUE DE LA CLÉ PUBLIQUE Ğ1 (G1Pub)
      // La seed (privateKeyBytes) est utilisée pour générer une paire de clés Ed25519
      // puis encoder la clé publique en Base58
      final g1pub = _cryptoService.generateG1Pub(privateKeyBytes);

      final user = User(
        npub: publicKeyHex,
        nsec: privateKeyHex,
        displayName: _displayNameController.text.trim().isEmpty
            ? _loginController.text.trim()
            : _displayNameController.text.trim(),
        createdAt: DateTime.now(),
        website: null,  // À définir plus tard via l'écran de profil
        g1pub: g1pub,   // ✅ GÉNÉRÉ AUTOMATIQUEMENT
      );

      await _storageService.saveUser(user);

      // ✅ PUBLIER PROFIL UTILISATEUR SUR NOSTR
      try {
        final nostrService = NostrService(
          cryptoService: _cryptoService,
          storageService: _storageService,
        );

        await nostrService.connect(NostrConstants.defaultRelay);
        
        await nostrService.publishUserProfile(
          npub: user.npub,
          nsec: user.nsec,
          name: user.displayName,
          displayName: user.displayName,
          about: 'Utilisateur TrocZen - Monnaie locale ẐEN',
          website: user.website,
          g1pub: user.g1pub,
        );

        await nostrService.disconnect();
      } catch (e) {
        debugPrint('⚠️ Erreur publication profil Nostr: $e');
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => WalletScreen(user: user),
        ),
      );
    } catch (e) {
      _showError('Erreur lors de la création du compte: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
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
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo / Titre
                  const Icon(
                    Icons.wallet,
                    size: 80,
                    color: Color(0xFFFFB347),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'TrocZen',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFB347),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Le troc local, simple et zen',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Formulaire
                  TextFormField(
                    controller: _loginController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Login (identifiant unique)',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.person, color: Color(0xFFFFB347)),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[700]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFFB347)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer un login';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.lock, color: Color(0xFFFFB347)),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[700]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFFB347)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer un mot de passe';
                      }
                      if (value.length < 8) {
                        return 'Le mot de passe doit contenir au moins 8 caractères';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _displayNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nom d\'affichage (optionnel)',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.badge, color: Color(0xFFFFB347)),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[700]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFFB347)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                    ),
                  ),

                  const SizedBox(height: 32),

                  ElevatedButton(
                    onPressed: _isProcessing ? null : _createUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB347),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Créer mon compte',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                  ),

                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(height: 8),
                        Text(
                          'Votre login et mot de passe génèrent votre identité cryptographique. Ne les perdez pas !',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
