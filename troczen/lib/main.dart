import 'package:flutter/material.dart';
import 'models/user.dart';
import 'models/nostr_profile.dart';
import 'models/bon.dart';
import 'services/crypto_service.dart';
import 'services/storage_service.dart';
import 'services/nostr_service.dart';
import 'services/logger_service.dart';
import 'services/audit_trail_service.dart';
import 'services/cache_database_service.dart';
import 'package:provider/provider.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'providers/app_mode_provider.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialiser le logger et vérifier le mode Marché Libre (transparence publique)
  await Logger.checkDebugMode();
  
  final storageService = StorageService();
  final cryptoService = CryptoService();
  final nostrService = NostrService(
    cryptoService: cryptoService,
    storageService: storageService,
  );
  
  NotificationService().init(storageService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppModeProvider(storageService),
        ),
        Provider<StorageService>.value(
          value: storageService,
        ),
        Provider<CryptoService>.value(
          value: cryptoService,
        ),
        Provider<NostrService>.value(
          value: nostrService,
        ),
      ],
      child: const TrocZenApp(),
    ),
  );
}

class TrocZenApp extends StatelessWidget {
  const TrocZenApp({super.key});

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
  const LoginScreen({super.key});

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
    // Exécuter la maintenance des bases de données (nettoyage, VACUUM)
    try {
      await AuditTrailService().runMaintenance();
      await CacheDatabaseService().runMaintenance();
    } catch (e) {
      Logger.error('Main', 'Erreur lors de la maintenance', e);
    }

    // ✅ WAL: Réconciliation des états via Kind 1 au démarrage
    // Cette opération doit être faite au démarrage avant toute autre chose
    final nostrService = NostrService(
      cryptoService: _cryptoService,
      storageService: _storageService,
    );
    
    final market = await _storageService.getMarket();
    if (market != null && market.relayUrl != null) {
      await nostrService.connect(market.relayUrl!);
    } else {
      await nostrService.connect('wss://relay.copylaradio.com');
    }

    final recoveredCount = await _storageService.reconcileBonsState(
      nostrService,
      onGhostTransferDetected: (bon) async {
        if (!mounted) return;
        
        // Demander à l'utilisateur ce qu'il s'est passé
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Transfert interrompu', style: TextStyle(color: Colors.white)),
            content: Text(
              'Un transfert de ${bon.value} ẐEN a été interrompu.\n\nL\'avez-vous finalisé avec le receveur ?',
              style: const TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Non, annulé', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB347)),
                child: const Text('Oui, finalisé', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        );
        
        if (result == true) {
          // Marquer comme dépensé
          final updatedBon = bon.copyWith(
            status: BonStatus.spent,
            p2: null,
            transferLockTimestamp: null,
            transferLockChallenge: null,
            transferLockTtlSeconds: null,
          );
          await _storageService.saveBon(updatedBon);
        } else {
          // Remettre actif
          final updatedBon = bon.copyWith(
            status: BonStatus.active,
            transferLockTimestamp: null,
            transferLockChallenge: null,
            transferLockTtlSeconds: null,
          );
          await _storageService.saveBon(updatedBon);
        }
      }
    );
    
    await nostrService.disconnect();

    if (recoveredCount > 0) {
      Logger.info('Main', 'Réconciliation: $recoveredCount bon(s) mis à jour');
    }
    
    // Vérifier d'abord si c'est un premier lancement
    final isFirstLaunch = await _storageService.isFirstLaunch();
    
    if (isFirstLaunch && mounted) {
      // Rediriger vers l'onboarding
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const OnboardingFlow(),
        ),
      );
      return;
    }
    
    // Sinon, vérifier l'utilisateur existant
    final user = await _storageService.getUser();
    if (user != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainShell(user: user),
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
      final seedBytes = await _cryptoService.deriveSeed(
        _loginController.text.trim(),
        _passwordController.text,
      );
      final privateKeyBytes = await _cryptoService.deriveNostrPrivateKey(seedBytes);
      _cryptoService.secureZeroiseBytes(seedBytes);

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

        await nostrService.connect(AppConfig.defaultRelayUrl);
        
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
          builder: (context) => MainShell(user: user),
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
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo / Titre
                const SizedBox(height: 20),
                const Icon(
                  Icons.wallet,
                  size: 72,
                  color: Color(0xFFFFB347),
                ),
                const SizedBox(height: 12),
                const Text(
                  'TrocZen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFB347),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Le troc local, simple et zen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 36),

                // Formulaire
                TextFormField(
                  controller: _loginController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  autofillHints: const ['username'],
                  decoration: InputDecoration(
                    labelText: 'Login (identifiant unique)',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.person, color: Color(0xFFFFB347)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[700]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFB347), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red[400]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red[400]!, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Veuillez entrer un login';
                    }
                    if (value.trim().length < 3) {
                      return 'Le login doit contenir au moins 3 caractères';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  autofillHints: const ['newPassword'],
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.lock, color: Color(0xFFFFB347)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[700]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFB347), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red[400]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red[400]!, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  autofillHints: const ['name'],
                  onFieldSubmitted: (_) => _createUser(),
                  decoration: InputDecoration(
                    labelText: 'Nom d\'affichage (optionnel)',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.badge, color: Color(0xFFFFB347)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[700]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFB347), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),

                const SizedBox(height: 28),

                // Bouton créer
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _createUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB347),
                      disabledBackgroundColor: Colors.grey[700],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Créer mon compte',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // Info box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[300], size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Votre login et mot de passe génèrent votre identité cryptographique. Ne les perdez pas !',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 12,
                          ),
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
    );
  }
}
