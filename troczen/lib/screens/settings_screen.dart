import 'dart:math';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../models/market.dart';
import '../services/storage_service.dart';
import '../services/crypto_service.dart';
import '../services/logger_service.dart';
import 'logs_screen.dart';

/// Écran de paramètres pour configurer le marché, relais, etc.
class SettingsScreen extends StatefulWidget {
  final User user;

  const SettingsScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _marketNameController = TextEditingController();
  final _seedMarketController = TextEditingController();
  final _relayUrlController = TextEditingController();
  final _validUntilController = TextEditingController();

  final _storageService = StorageService();
  final _cryptoService = CryptoService();

  Market? _currentMarket;
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
    setState(() {
      _currentMarket = market;
      _marketNameController.text = market.name;
      _seedMarketController.text = market.seedMarket;
      _relayUrlController.text = market.relayUrl ?? AppConfig.defaultRelayUrl;
      _validUntilController.text = market.validUntil.toIso8601String().split('T').first;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final market = Market(
        name: _marketNameController.text.trim(),
        seedMarket: _seedMarketController.text.trim(),
        validUntil: DateTime.parse(_validUntilController.text.trim()),
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

  Future<void> _generateNewKey() async {
    final random = Random.secure();
    final randomBytes = List<int>.generate(32, (i) => random.nextInt(256));
    final hexKey = randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    setState(() {
      _seedMarketController.text = hexKey;
    });
  }

  @override
  void dispose() {
    _marketNameController.dispose();
    _seedMarketController.dispose();
    _relayUrlController.dispose();
    _validUntilController.dispose();
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
              const Text(
                'Configuration du Marché',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _marketNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du marché',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer un nom';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _seedMarketController,
                      decoration: const InputDecoration(
                        labelText: 'Graine du marché (seed_market)',
                        border: OutlineInputBorder(),
                        hintText: '32 bytes en hex',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'La clé est requise';
                        }
                        if (value.length != 64) {
                          return 'La clé doit faire 64 caractères hex (32 bytes)';
                        }
                        return null;
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: _generateNewKey,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Générer une nouvelle clé',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Clé symétrique utilisée pour chiffrer les P3. Gardez-la secrète.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _validUntilController,
                decoration: const InputDecoration(
                  labelText: 'Date d\'expiration',
                  border: OutlineInputBorder(),
                  hintText: 'YYYY-MM-DD',
                ),
                readOnly: true,
                onTap: () async {
                  final selectedDate = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (selectedDate != null) {
                    setState(() {
                      _validUntilController.text = selectedDate.toIso8601String().split('T').first;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Date jusqu\'à laquelle la clé est valide. Après cette date, les nouveaux bons ne pourront plus être créés.',
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
              
              // Bouton Logs HACKATHON (visible uniquement en mode debug)
              if (Logger.isDebugMode) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LogsScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.bug_report),
                  label: Text('🐛 Logs HACKATHON (${Logger.logCount})'),
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
              ElevatedButton(
                onPressed: () {
                  // TODO: Réinitialiser le marché
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('Réinitialiser le marché'),
              ),
              
              // Indicateur mode HACKATHON
              if (_currentMarket?.name.toUpperCase() == 'HACKATHON') ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '⚠️ Mode HACKATHON actif\n'
                          'Seed à zéro - Sécurité réduite\n'
                          'Chiffrement P3 affaibli',
                          style: TextStyle(fontSize: 12),
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
}