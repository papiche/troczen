import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../models/market.dart';
import '../models/app_mode.dart';
import '../services/storage_service.dart';
import '../services/logger_service.dart';
import 'logs_screen.dart';
import 'apk_share_screen.dart';

/// Écran de paramètres pour configurer le marché, relais, etc.
class SettingsScreen extends StatefulWidget {
  final User user;

  const SettingsScreen({super.key, required this.user});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _relayUrlController = TextEditingController();

  final _storageService = StorageService();

  Market? _currentMarket;
  AppMode _currentMode = AppMode.flaneur;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Initialiser un marché par défaut si aucun n'existe
    final market = await _storageService.initializeDefaultMarket();
    
    // Charger le mode actuel
    final modeIndex = await _storageService.getAppMode();
    final mode = AppMode.fromIndex(modeIndex);
    
    setState(() {
      _currentMarket = market;
      _currentMode = mode;
      _relayUrlController.text = market.relayUrl ?? AppConfig.defaultRelayUrl;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    if (_currentMarket == null) return;

    setState(() => _isSaving = true);

    try {
      final market = _currentMarket!.copyWith(
        relayUrl: _relayUrlController.text.trim().isNotEmpty
            ? _relayUrlController.text.trim()
            : null,
      );

      await _storageService.saveMarket(market);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paramètres sauvegardés avec succès'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _relayUrlController.dispose();
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
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: const Color(0xFF0A7EA4),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ Sélecteur de mode d'utilisation
              const Text(
                'Mode d\'utilisation',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choisissez comment vous utilisez principalement TrocZen',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _buildModeSelector(),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),
              
              const Text(
                'Réseau',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _relayUrlController,
                decoration: const InputDecoration(
                  labelText: 'URL du relais Nostr',
                  border: OutlineInputBorder(),
                  hintText: 'wss://relay.example.com',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Relais utilisé pour synchroniser les P3. Laissez vide pour utiliser le relais par défaut.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB347),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : const Text(
                          'Sauvegarder les paramètres',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Actions avancées',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // Bouton Logs (visible uniquement en mode debug)
              if (Logger.isDebugMode) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LogsScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.bug_report),
                  label: Text('🐛 Logs Debug (${Logger.logCount})'),
                ),
                const SizedBox(height: 8),
              ],
              
              ElevatedButton(
                onPressed: () {
                  // TODO: Exporter les données
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A7EA4),
                ),
                child: const Text('Exporter les données (CSV)'),
              ),
              const SizedBox(height: 8),
              
              // Bouton Partager l'application
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ApkShareScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB347),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.share),
                label: const Text('📤 Partager l\'application'),
              ),
              const SizedBox(height: 8),
              // Indicateur Marché Global (seed à zéro = transparence publique)
              if (_currentMarket?.seedMarket == ('0' * 64)) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.public, color: Colors.blue),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '🌐 Marché Global Public\n'
                          'Les transactions de ce marché sont totalement transparentes et auditables par tous.\n'
                          'Équivalence : 1 ẐEN ≈ 0.1 Ğ1',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  /// ✅ PROGRESSIVE DISCLOSURE : Sélecteur de mode d'utilisation
  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        children: AppMode.values.map((mode) {
          final isSelected = _currentMode == mode;
          return GestureDetector(
            onTap: () => _changeMode(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      mode.label.split(' ')[0], // Emoji uniquement
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mode.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.grey[300],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mode.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white.withValues(alpha: 0.8) : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 24,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
  
  /// Change le mode d'utilisation
  Future<void> _changeMode(AppMode newMode) async {
    if (newMode == _currentMode) return;
    
    // Confirmation si passage à un mode inférieur
    if (newMode.value < _currentMode.value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Changer de mode', style: TextStyle(color: Colors.white)),
          content: Text(
            'Passer en mode ${newMode.label} masquera certaines fonctionnalités avancées. Continuer ?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFFFB347)),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      );
      
      if (confirm != true) return;
    }
    
    try {
      await _storageService.setAppMode(newMode.value);
      setState(() => _currentMode = newMode);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mode changé en ${newMode.label}. Redémarrez l\'application pour appliquer les changements.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}