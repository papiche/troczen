import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/nostr_service.dart';
import '../../services/crypto_service.dart';
import '../../services/storage_service.dart';
import 'onboarding_flow.dart';

/// Étape 3: Synchronisation P3 depuis Nostr
class OnboardingNostrSyncScreen extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback? onBack;
  
  const OnboardingNostrSyncScreen({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<OnboardingNostrSyncScreen> createState() => _OnboardingNostrSyncScreenState();
}

class _OnboardingNostrSyncScreenState extends State<OnboardingNostrSyncScreen> {
  bool _isSyncing = false;
  bool _syncCompleted = false;
  bool _syncFailed = false;
  int _p3Count = 0;
  String _currentStep = '';
  
  @override
  void initState() {
    super.initState();
    // Démarrer la synchronisation automatiquement
    Future.delayed(const Duration(milliseconds: 500), _startSync);
  }
  
  Future<void> _startSync() async {
    if (_isSyncing) return;
    
    // ✅ CORRECTION: Vérifier mounted avant setState
    if (!mounted) return;
    
    setState(() {
      _isSyncing = true;
      _syncFailed = false;
      _syncCompleted = false;
      _p3Count = 0;
    });
    
    try {
      final notifier = context.read<OnboardingNotifier>();
      final state = notifier.state;
      final relayUrl = state.relayUrl;
      final seedMarket = state.seedMarket;
      
      if (seedMarket == null || seedMarket.isEmpty) {
        throw Exception('Seed du marché non disponible');
      }
      
      // Étape 1: Connexion au relais Nostr
      if (!mounted) return;
      setState(() => _currentStep = 'Connexion au relais Nostr...');
      await Future.delayed(const Duration(milliseconds: 500));
      
      final cryptoService = CryptoService();
      final storageService = StorageService();
      final nostrService = NostrService(
        cryptoService: cryptoService,
        storageService: storageService,
      );
      
      final connected = await nostrService.connect(relayUrl);
      
      if (!connected) {
        throw Exception('Impossible de se connecter au relais');
      }
      
      // Étape 2: Requête des événements kind:30303 (P3)
      if (!mounted) {
        await nostrService.disconnect();
        return;
      }
      setState(() => _currentStep = 'Requête des événements P3 (kind:30303)...');
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Récupérer les P3 depuis le marché
      final market = await storageService.getMarket();
      final marketName = market?.name ?? 'troczen-global';
      
      // Stocker les P3 reçus
      final List<Map<String, String>> receivedP3s = [];
      
      // Configurer le callback pour recevoir les P3
      nostrService.onP3Received = (bonId, p3Hex) async {
        receivedP3s.add({'bonId': bonId, 'p3': p3Hex});
        // ✅ CORRECTION: Vérifier mounted dans le callback
        if (!mounted) return;
        setState(() {
          _p3Count = receivedP3s.length;
          _currentStep = 'Réception des P3... ($_p3Count trouvés)';
        });
      };
      
      // S'abonner aux événements du marché
      await nostrService.subscribeToMarket(marketName);
      
      // Étape 3: Attendre la réception des événements (5 secondes)
      if (!mounted) {
        await nostrService.disconnect();
        return;
      }
      setState(() => _currentStep = 'Écoute des événements P3...');
      await Future.delayed(const Duration(seconds: 5));
      
      // Étape 4: Déchiffrement et stockage des P3
      if (!mounted) {
        await nostrService.disconnect();
        return;
      }
      if (receivedP3s.isNotEmpty) {
        setState(() => _currentStep = 'Déchiffrement et stockage des P3...');
        
        for (final p3Data in receivedP3s) {
          try {
            // Sauvegarder le P3 en cache
            await storageService.saveP3ToCache(
              p3Data['bonId']!,
              p3Data['p3']!,
            );
          } catch (e) {
            debugPrint('⚠️ Erreur sauvegarde P3 ${p3Data['bonId']}: $e');
          }
        }
      }
      
      // Étape 5: Synchronisation terminée
      if (!mounted) {
        await nostrService.disconnect();
        return;
      }
      setState(() {
        _currentStep = 'Synchronisation terminée — $_p3Count bons trouvés';
        _syncCompleted = true;
        _isSyncing = false;
      });
      
      // Sauvegarder le résultat
      notifier.setSyncCompleted(_p3Count);
      
      await nostrService.disconnect();
      
    } catch (e) {
      debugPrint('❌ Erreur sync P3: $e');
      // ✅ CORRECTION: Vérifier mounted avant setState
      if (!mounted) return;
      setState(() {
        _currentStep = 'Erreur: ${e.toString()}';
        _syncFailed = true;
        _isSyncing = false;
      });
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
            'Synchronisation',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFB347),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Récupération des bons depuis le réseau',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 48),
          
          // Contenu principal
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icône d'état
                  if (_isSyncing)
                    const SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        strokeWidth: 6,
                        color: Color(0xFFFFB347),
                      ),
                    )
                  else if (_syncCompleted)
                    const Icon(
                      Icons.check_circle,
                      size: 80,
                      color: Colors.green,
                    )
                  else if (_syncFailed)
                    const Icon(
                      Icons.error,
                      size: 80,
                      color: Colors.orange,
                    ),
                  
                  const SizedBox(height: 32),
                  
                  // Message d'état
                  Text(
                    _currentStep,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  if (_syncCompleted) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '$_p3Count bons disponibles',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  
                  if (_syncFailed) ...[
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _startSync,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A7EA4),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        // Passer en mode hors-ligne
                        final notifier = context.read<OnboardingNotifier>();
                        notifier.setSyncCompleted(0);
                        widget.onNext();
                      },
                      child: const Text(
                        'Passer (mode hors-ligne)',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Boutons de navigation
          if (_syncCompleted || _syncFailed)
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
                    onPressed: _syncCompleted
                        ? widget.onNext
                        : _syncFailed
                            ? () {
                                // Continuer quand même en mode hors-ligne
                                final notifier = context.read<OnboardingNotifier>();
                                notifier.setSyncCompleted(0);
                                widget.onNext();
                              }
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB347),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _syncFailed ? 'Continuer quand même' : 'Continuer',
                      style: const TextStyle(
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
}
