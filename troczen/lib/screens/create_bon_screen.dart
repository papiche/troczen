import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/bon.dart';
import '../models/user.dart';
import '../models/market.dart';
import '../models/nostr_profile.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';
import '../services/api_service.dart';

class CreateBonScreen extends StatefulWidget {
  final User user;

  const CreateBonScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<CreateBonScreen> createState() => _CreateBonScreenState();
}

class _CreateBonScreenState extends State<CreateBonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController(text: '5');
  final _issuerNameController = TextEditingController();
  final _expirationController = TextEditingController(text: '90'); // Jours par défaut
  final _cryptoService = CryptoService();
  final _storageService = StorageService();
  final _apiService = ApiService();
  final _uuid = const Uuid();
  
  bool _isCreating = false;
  Market? _market;
  bool _isLocalNetwork = false;
  Color _selectedColor = Colors.blue; // Couleur par défaut
  String _selectedRarity = 'common'; // Rareté sélectionnée
  bool _useAutoRarity = true; // Utiliser la génération automatique

  @override
  void initState() {
    super.initState();
    _issuerNameController.text = widget.user.displayName;
    _loadMarket();
    _detectNetwork();
  }

  Future<void> _loadMarket() async {
    final market = await _storageService.getMarket();
    setState(() => _market = market);
  }

  /// ✅ Détection automatique réseau local (borne wifi)
  Future<void> _detectNetwork() async {
    final isLocal = await _apiService.detectLocalNetwork();
    setState(() => _isLocalNetwork = isLocal);
    
    if (isLocal) {
      debugPrint('✅ Borne locale détectée: ${_apiService.apiUrl}');
    }
  }

  Color _getRarityColor(String rarity) {
    switch (rarity) {
      case 'legendary':
        return Colors.orangeAccent;
      case 'rare':
        return Colors.blueAccent;
      case 'uncommon':
        return Colors.greenAccent;
      case 'common':
        return Colors.grey;
      default:
        return Colors.purple;
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _issuerNameController.dispose();
    super.dispose();
  }

  Future<void> _createBon() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_market == null || _market!.isExpired) {
      _showError('Aucun marché configuré ou clé expirée.\nAllez dans Paramètres pour configurer le marché.');
      return;
    }

    setState(() => _isCreating = true);

    try {
      // 1. Générer la paire de clés du bon
      final bonKeys = _cryptoService.generateNostrKeyPair();
      final bonNsec = bonKeys['nsec']!;
      final bonNpub = bonKeys['npub']!;

      // 2. Découper en 3 parts avec SSSS
      final parts = _cryptoService.shamirSplit(bonNsec);
      final p1 = parts[0]; // Ancre (reste chez l'émetteur)
      final p2 = parts[1]; // Voyageur (part active)
      final p3 = parts[2]; // Témoin (à publier)

      // 3. Chiffrer P3 avec K_market
      final p3Encrypted = await _cryptoService.encryptP3(p3, _market!.kmarket);

      // 4. Stocker P3 dans le cache local
      await _storageService.saveP3ToCache(bonNpub, p3);

      // 5. Créer le bon (sans stocker bonNsec)
      final bon = Bon(
        bonId: bonNpub,
        // bonNsec retiré - reconstruction via P2+P3 uniquement
        value: double.parse(_valueController.text),
        issuerName: _issuerNameController.text,
        issuerNpub: widget.user.npub,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(Duration(days: int.parse(_expirationController.text))),
        status: BonStatus.active,
        p1: p1,
        p2: p2,
        p3: null, // P3 est dans le cache
        marketName: _market!.name,
        color: _selectedColor.value,
        rarity: _useAutoRarity ? Bon.generateRarity() : _selectedRarity,
        uniqueId: Bon.generateUniqueId(bonNpub),
        cardType: Bon.generateCardType(),
        specialAbility: Bon.generateSpecialAbility(_useAutoRarity ? Bon.generateRarity() : _selectedRarity),
        stats: Bon.generateStats(_useAutoRarity ? Bon.generateRarity() : _selectedRarity),
      );

      // 6. Sauvegarder le bon
      await _storageService.saveBon(bon);

      // 7. ✅ PUBLIER P3 SUR NOSTR (kind 30303)
      // SIGNÉ PAR LE BON LUI-MÊME (reconstruction éphémère P2+P3)
      try {
        final nostrService = NostrService(
          cryptoService: _cryptoService,
          storageService: _storageService,
        );

        // Connexion au relais
        final relayUrl = _market!.relayUrl ?? NostrConstants.defaultRelay;
        final connected = await nostrService.connect(relayUrl);

        if (connected) {
          // Publication P3 chiffrée - AVEC P2 pour signature par le bon
          final published = await nostrService.publishP3(
            bonId: bonNpub,
            p2Hex: p2,  // ✅ Pour reconstruction sk_B éphémère
            p3Hex: p3,
            kmarketHex: _market!.kmarket,
            issuerNpub: widget.user.npub,
            marketName: _market!.name,
            value: double.parse(_valueController.text),
            category: 'generic',  // TODO: Sélection UI
            rarity: Bon.generateRarity(),  // ✅ Génération aléatoire
          );

          if (published) {
            debugPrint('✅ P3 publiée sur Nostr (signée par le bon)');
          }

          await nostrService.disconnect();
        }

        // 8. ✅ Créer profil du bon sur l'API (pour dashboard web)
        if (_isLocalNetwork || _market!.relayUrl != null) {
          await _apiService.createBonProfile(
            bonId: bonNpub,
            issuerNpub: widget.user.npub,
            issuerName: _issuerNameController.text,
            value: double.parse(_valueController.text),
            marketName: _market!.name,
            rarity: Bon.generateRarity(),
            category: 'generic',
          );
        }

      } catch (e) {
        debugPrint('⚠️ Erreur publication Nostr: $e');
        // Non bloquant
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bon créé avec succès !'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      _showError('Erreur lors de la création du bon: $e');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Créer un bon'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Prévisualisation de la carte
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Icon(Icons.verified, color: Color(0xFFFFB347)),
                          Text(
                            '${_valueController.text.isEmpty ? '0' : _valueController.text} ẐEN',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB347).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFFB347).withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.star,
                                size: 48,
                                color: Color(0xFFFFB347),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _issuerNameController.text.isEmpty
                                    ? 'Votre nom'
                                    : _issuerNameController.text,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB347).withOpacity(0.1),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                      child: Text(
                        _market?.name.toUpperCase() ?? 'MARCHÉ',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Formulaire
              Text(
                'Informations du bon',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _valueController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Valeur (ẐEN)',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFFFB347)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer une valeur';
                  }
                  final number = double.tryParse(value);
                  if (number == null || number <= 0) {
                    return 'Valeur invalide';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _issuerNameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nom de l\'émetteur',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFFFB347)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer un nom';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 24),

              // Section Rareté
              Text(
                'Rareté de la carte',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RadioListTile<String>(
                          title: const Text('Auto', style: TextStyle(color: Colors.white)),
                          value: 'auto',
                          groupValue: _useAutoRarity ? 'auto' : _selectedRarity,
                          onChanged: (value) {
                            setState(() {
                              _useAutoRarity = true;
                            });
                          },
                          activeColor: const Color(0xFFFFB347),
                        ),
                        ...['common', 'uncommon', 'rare', 'legendary'].map((rarity) => RadioListTile<String>(
                          title: Text(
                            rarity[0].toUpperCase() + rarity.substring(1),
                            style: const TextStyle(color: Colors.white),
                          ),
                          value: rarity,
                          groupValue: _useAutoRarity ? 'auto' : _selectedRarity,
                          onChanged: (value) {
                            setState(() {
                              _useAutoRarity = false;
                              _selectedRarity = value!;
                            });
                          },
                          activeColor: const Color(0xFFFFB347),
                        )).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Aperçu de la rareté
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getRarityColor(_useAutoRarity ? 'auto' : _selectedRarity),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _useAutoRarity ? '?' : _selectedRarity[0].toUpperCase() + _selectedRarity.substring(1),
                        style: TextStyle(
                          color: _getRarityColor(_useAutoRarity ? 'auto' : _selectedRarity),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Section Couleur
              Text(
                'Couleur de la carte',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                children: [
                  Colors.blue, Colors.red, Colors.green, Colors.purple, Colors.orange, Colors.pink,
                  Colors.teal, Colors.indigo, Colors.amber, Colors.lime
                ].map((color) => GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: _selectedColor == color
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                    ),
                  ),
                )).toList(),
              ),

              const SizedBox(height: 24),

              // Section Expiration
              Text(
                'Durée de validité',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _expirationController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Jours avant expiration',
                  suffixText: 'jours',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFFFB347)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer une durée';
                  }
                  final days = int.tryParse(value);
                  if (days == null || days <= 0) {
                    return 'Durée invalide';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              if (_market == null || _market!.isExpired)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Configurez d\'abord le marché dans Paramètres',
                          style: TextStyle(color: Colors.grey[300]),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isCreating ? null : _createBon,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB347),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isCreating
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Créer le bon',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
