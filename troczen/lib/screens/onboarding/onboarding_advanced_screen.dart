import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../config/app_config.dart';
import 'onboarding_flow.dart';

/// Étape 2: Configuration Avancée (optionnelle)
class OnboardingAdvancedScreen extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  
  const OnboardingAdvancedScreen({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<OnboardingAdvancedScreen> createState() => _OnboardingAdvancedScreenState();
}

class _OnboardingAdvancedScreenState extends State<OnboardingAdvancedScreen> {
  // Modes de sélection
  String _relayMode = 'default'; // default, local, custom
  String _apiMode = 'default';
  String _ipfsMode = 'default';
  
  // Contrôleurs pour saisie personnalisée
  final _relayController = TextEditingController();
  final _apiController = TextEditingController();
  final _ipfsController = TextEditingController();
  
  // États de test de connexion
  bool _testingRelay = false;
  bool _testingApi = false;
  bool _testingIpfs = false;
  
  bool? _relayOk;
  bool? _apiOk;
  bool? _ipfsOk;
  
  @override
  void dispose() {
    _relayController.dispose();
    _apiController.dispose();
    _ipfsController.dispose();
    super.dispose();
  }
  
  String get _selectedRelayUrl {
    switch (_relayMode) {
      case 'local':
        return AppConfig.localRelayUrl;
      case 'custom':
        return _relayController.text;
      default:
        return AppConfig.defaultRelayUrl;
    }
  }
  
  String get _selectedApiUrl {
    switch (_apiMode) {
      case 'local':
        return AppConfig.localApiUrl;
      case 'custom':
        return _apiController.text;
      default:
        return AppConfig.defaultApiUrl;
    }
  }
  
  String get _selectedIpfsGateway {
    switch (_ipfsMode) {
      case 'local':
        return 'http://ipfs.zen:8080';
      case 'custom':
        return _ipfsController.text;
      default:
        return 'https://ipfs.copylaradio.com';
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
            'Configuration Avancée',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFB347),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Configurez vos services réseau (optionnel)',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          
          // Bouton Passer
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                // Sauvegarder les valeurs par défaut et continuer
                _saveAndContinue();
              },
              child: const Text(
                'Passer →',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFFFFB347),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Configuration
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Relais Nostr
                  _buildServiceSection(
                    title: 'Relais Nostr',
                    icon: Icons.cloud,
                    mode: _relayMode,
                    controller: _relayController,
                    isTesting: _testingRelay,
                    testResult: _relayOk,
                    onModeChanged: (mode) => setState(() => _relayMode = mode),
                    onTest: _testRelayConnection,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // API REST
                  _buildServiceSection(
                    title: 'API REST',
                    icon: Icons.api,
                    mode: _apiMode,
                    controller: _apiController,
                    isTesting: _testingApi,
                    testResult: _apiOk,
                    onModeChanged: (mode) => setState(() => _apiMode = mode),
                    onTest: _testApiConnection,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Passerelle IPFS
                  _buildServiceSection(
                    title: 'Passerelle IPFS',
                    icon: Icons.storage,
                    mode: _ipfsMode,
                    controller: _ipfsController,
                    isTesting: _testingIpfs,
                    testResult: _ipfsOk,
                    onModeChanged: (mode) => setState(() => _ipfsMode = mode),
                    onTest: _testIpfsConnection,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Boutons de navigation
          Row(
            children: [
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
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
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
  
  Widget _buildServiceSection({
    required String title,
    required IconData icon,
    required String mode,
    required TextEditingController controller,
    required bool isTesting,
    required bool? testResult,
    required Function(String) onModeChanged,
    required VoidCallback onTest,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFFFB347)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Option par défaut
          RadioListTile<String>(
            title: const Text(
              'Par défaut (copylaradio.com)',
              style: TextStyle(color: Colors.white),
            ),
            value: 'default',
            groupValue: mode,
            activeColor: const Color(0xFFFFB347),
            onChanged: (value) => onModeChanged(value!),
          ),
          
          // Option locale
          RadioListTile<String>(
            title: const Text(
              'Box locale (*.zen)',
              style: TextStyle(color: Colors.white),
            ),
            value: 'local',
            groupValue: mode,
            activeColor: const Color(0xFFFFB347),
            onChanged: (value) => onModeChanged(value!),
          ),
          
          // Option personnalisée
          RadioListTile<String>(
            title: const Text(
              'Personnalisé',
              style: TextStyle(color: Colors.white),
            ),
            value: 'custom',
            groupValue: mode,
            activeColor: const Color(0xFFFFB347),
            onChanged: (value) => onModeChanged(value!),
          ),
          
          // Champ de saisie si personnalisé
          if (mode == 'custom') ...[
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Entrez l\'URL personnalisée',
                hintStyle: TextStyle(color: Colors.grey[600]),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[700]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFFB347)),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
              ),
            ),
          ],
          
          const SizedBox(height: 12),
          
          // Bouton de test
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: isTesting ? null : onTest,
                icon: isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.wifi_find, size: 16),
                label: Text(isTesting ? 'Test en cours...' : 'Tester la connexion'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A7EA4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
              if (testResult != null) ...[
                const SizedBox(width: 12),
                Icon(
                  testResult ? Icons.check_circle : Icons.error,
                  color: testResult ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  testResult ? 'Connexion OK' : 'Échec',
                  style: TextStyle(
                    color: testResult ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
  
  Future<void> _testRelayConnection() async {
    setState(() {
      _testingRelay = true;
      _relayOk = null;
    });
    
    try {
      final uri = Uri.parse(_selectedRelayUrl);
      final channel = WebSocketChannel.connect(uri);
      
      // Attendre une courte connexion
      await Future.delayed(const Duration(seconds: 2));
      await channel.sink.close();
      
      setState(() {
        _relayOk = true;
        _testingRelay = false;
      });
    } catch (e) {
      setState(() {
        _relayOk = false;
        _testingRelay = false;
      });
    }
  }
  
  Future<void> _testApiConnection() async {
    setState(() {
      _testingApi = true;
      _apiOk = null;
    });
    
    try {
      final response = await http.head(
        Uri.parse('$_selectedApiUrl/health'),
      ).timeout(const Duration(seconds: 5));
      
      setState(() {
        _apiOk = response.statusCode == 200 || response.statusCode == 404;
        _testingApi = false;
      });
    } catch (e) {
      setState(() {
        _apiOk = false;
        _testingApi = false;
      });
    }
  }
  
  Future<void> _testIpfsConnection() async {
    setState(() {
      _testingIpfs = true;
      _ipfsOk = null;
    });
    
    try {
      final response = await http.head(
        Uri.parse(_selectedIpfsGateway),
      ).timeout(const Duration(seconds: 5));
      
      setState(() {
        _ipfsOk = response.statusCode == 200 || response.statusCode == 404;
        _testingIpfs = false;
      });
    } catch (e) {
      setState(() {
        _ipfsOk = false;
        _testingIpfs = false;
      });
    }
  }
  
  void _saveAndContinue() {
    final notifier = context.read<OnboardingNotifier>();
    notifier.setAdvancedConfig(
      relayUrl: _selectedRelayUrl,
      apiUrl: _selectedApiUrl,
      ipfsGateway: _selectedIpfsGateway,
    );
    
    widget.onNext();
  }
}
