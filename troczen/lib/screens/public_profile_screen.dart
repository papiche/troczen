import 'package:flutter/material.dart';
import '../models/nostr_profile.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import 'package:provider/provider.dart';

class PublicProfileScreen extends StatefulWidget {
  final String npub;

  const PublicProfileScreen({super.key, required this.npub});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  NostrProfile? _profile;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final storageService = StorageService();
      final cryptoService = CryptoService();
      final nostrService = context.read<NostrService>();

      final market = await storageService.getMarket();
      if (market?.relayUrl != null) {
        final connected = await nostrService.connect(market!.relayUrl!);
        if (connected) {
          final profile = await nostrService.fetchUserProfile(widget.npub);
          if (mounted) {
            setState(() {
              _profile = profile;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _error = 'Impossible de se connecter au relais';
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Aucun relais configuré';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Erreur lors du chargement du profil: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Profil Public'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadProfile,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : _profile == null
                  ? const Center(
                      child: Text('Profil introuvable', style: TextStyle(color: Colors.white)),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: const Color(0xFFFFB347),
                            backgroundImage: _profile!.picture != null && _profile!.picture!.isNotEmpty
                                ? NetworkImage(_profile!.picture!)
                                : null,
                            child: _profile!.picture == null || _profile!.picture!.isEmpty
                                ? Text(
                                    _profile!.name.isNotEmpty ? _profile!.name[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _profile!.name.isNotEmpty ? _profile!.name : 'Anonyme',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_profile!.nip05 != null && _profile!.nip05!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              _profile!.nip05!,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          if (_profile!.about != null && _profile!.about!.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                _profile!.about!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white70,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Clé publique (npub)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  widget.npub,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
