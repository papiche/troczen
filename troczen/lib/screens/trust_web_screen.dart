import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../services/logger_service.dart';
import '../services/cache_database_service.dart';
import 'package:provider/provider.dart';

class TrustWebScreen extends StatefulWidget {
  final User user;

  const TrustWebScreen({super.key, required this.user});

  @override
  State<TrustWebScreen> createState() => _TrustWebScreenState();
}

class _TrustWebScreenState extends State<TrustWebScreen> with SingleTickerProviderStateMixin {
  final _storageService = StorageService();
  late NostrService _nostrService;
  late TabController _tabController;

  bool _isLoading = true;
  List<String> _n1 = []; // Mes contacts (Kind 3)
  List<String> _followers = []; // Ceux qui me suivent (P21)
  
  List<String> _p2p = []; // Mutuel
  List<String> _12p = []; // Sortant (Je suis, ils ne me suivent pas)
  List<String> _p21 = []; // Entrant (Ils me suivent, je ne les suis pas)

  bool _isSyncingN2 = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _nostrService = context.read<NostrService>();
    _loadNetwork();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadNetwork() async {
    setState(() => _isLoading = true);

    try {
      // 1. Charger mes contacts locaux (N1)
      _n1 = await _storageService.getContacts();

      // 2. Se connecter au relais pour récupérer les followers
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        if (await _nostrService.connect(market!.relayUrl!)) {
          _followers = await _nostrService.fetchFollowers(widget.user.npub);
          await _nostrService.disconnect();
        }
      }

      // 3. Calculer les listes
      _p2p = _n1.where((npub) => _followers.contains(npub)).toList();
      _12p = _n1.where((npub) => !_followers.contains(npub)).toList();
      _p21 = _followers.where((npub) => !_n1.contains(npub)).toList();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      Logger.error('TrustWebScreen', 'Erreur chargement réseau', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncN2() async {
    setState(() => _isSyncingN2 = true);

    try {
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        if (await _nostrService.connect(market!.relayUrl!)) {
          // Récupérer les Kind 3 de tous mes P2P
          final contactLists = await _nostrService.fetchMultipleContactLists(_p2p);
          
          // Extraire tous les p tags et les sauvegarder dans SQLite
          final cacheDb = CacheDatabaseService();
          await cacheDb.clearN2Cache(); // On vide l'ancien cache
          
          final n2Contacts = <Map<String, String>>[];
          int n2Count = 0;
          
          for (final entry in contactLists.entries) {
            final viaNpub = entry.key;
            final contacts = entry.value;
            for (final contact in contacts) {
              if (contact != widget.user.npub && !_n1.contains(contact)) {
                n2Contacts.add({
                  'npub': contact,
                  'via_n1_npub': viaNpub,
                });
                n2Count++;
              }
            }
          }

          await cacheDb.saveN2ContactsBatch(n2Contacts);
          await _nostrService.disconnect();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Réseau N2 synchronisé ($n2Count contacts)'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      Logger.error('TrustWebScreen', 'Erreur sync N2', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingN2 = false);
      }
    }
  }

  Future<void> _acceptFollower(String npub) async {
    try {
      await _storageService.addContact(npub);
      
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        if (await _nostrService.connect(market!.relayUrl!)) {
          final contacts = await _storageService.getContacts();
          await _nostrService.publishContactList(
            npub: widget.user.npub,
            nsec: widget.user.nsec,
            contactsNpubs: contacts,
          );
          await _nostrService.disconnect();
        }
      }
      
      await _loadNetwork();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Contact ajouté et publié'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      Logger.error('TrustWebScreen', 'Erreur acceptation follower', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Toile de Confiance'),
        backgroundColor: const Color(0xFF1E1E1E),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFB347),
          labelColor: const Color(0xFFFFB347),
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Mes Liens (N1)'),
            Tab(text: 'Réseau Étendu (N2)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildN1Tab(),
                _buildN2Tab(),
              ],
            ),
    );
  }

  Widget _buildN1Tab() {
    return RefreshIndicator(
      onRefresh: _loadNetwork,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('🤝 P2P (Mutuel)', 'Vous vous suivez mutuellement. Crucial pour le calcul du DU.'),
          if (_p2p.isEmpty)
            _buildEmptyState('Aucun lien mutuel')
          else
            ..._p2p.map((npub) => _buildContactRow(npub, type: 'p2p')),
            
          const SizedBox(height: 24),
          
          _buildSectionHeader('➡️ 12P (Sortant)', 'Vous les suivez, mais ils ne vous suivent pas.'),
          if (_12p.isEmpty)
            _buildEmptyState('Aucun lien sortant en attente')
          else
            ..._12p.map((npub) => _buildContactRow(npub, type: '12p')),
            
          const SizedBox(height: 24),
          
          _buildSectionHeader('⬅️ P21 (Entrant)', 'Ils vous suivent, mais vous ne les suivez pas.'),
          if (_p21.isEmpty)
            _buildEmptyState('Aucun lien entrant en attente')
          else
            ..._p21.map((npub) => _buildContactRow(npub, type: 'p21')),
        ],
      ),
    );
  }

  Widget _buildN2Tab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.hub, size: 80, color: Color(0xFFFFB347)),
          const SizedBox(height: 24),
          const Text(
            'Réseau Étendu (N2)',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'Synchronisez les contacts de vos liens mutuels (P2P) pour étendre votre toile de confiance hors-ligne.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSyncingN2 ? null : _syncN2,
              icon: _isSyncingN2 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.sync),
              label: Text(_isSyncingN2 ? 'Synchronisation...' : 'Synchroniser mon Réseau'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB347),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
      ),
    );
  }

  Widget _buildContactRow(String npub, {required String type}) {
    final cryptoService = CryptoService();
    String npubBech32 = npub;
    try {
      if (!npub.startsWith('npub1')) {
        npubBech32 = cryptoService.encodeNpub(npub);
      }
    } catch (_) {}

    final shortNpub = '${npubBech32.substring(0, 12)}...${npubBech32.substring(npubBech32.length - 4)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: type == 'p2p' ? Colors.green : (type == '12p' ? Colors.orange : Colors.blue),
            child: const Icon(Icons.person, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              shortNpub,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          if (type == '12p')
            IconButton(
              icon: const Icon(Icons.qr_code, color: Color(0xFFFFB347), size: 20),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Demandez-lui de scanner votre QR-ID !')),
                );
              },
              tooltip: 'Rappeler de scanner',
            )
          else if (type == 'p21')
            ElevatedButton(
              onPressed: () => _acceptFollower(npub),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Accepter', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
