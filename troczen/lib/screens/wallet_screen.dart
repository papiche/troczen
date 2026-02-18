import 'package:flutter/material.dart';
import '../models/bon.dart';
import '../models/user.dart';
import '../services/storage_service.dart';
import '../services/crypto_service.dart';
import '../services/nostr_service.dart';
import '../widgets/panini_card.dart';
import '../screens/gallery_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/create_bon_screen.dart';
import '../screens/user_profile_screen.dart';
import '../screens/market_screen.dart';
import '../screens/merchant_dashboard_screen.dart';
import '../screens/help_screen.dart';
import '../screens/feedback_screen.dart';
import '../screens/atomic_swap_screen.dart';
import '../screens/offer_screen.dart';
import '../screens/ack_screen.dart';
import '../screens/ack_scanner_screen.dart';
import '../screens/bon_profile_screen.dart';
import '../screens/settings_screen.dart';

class WalletScreen extends StatefulWidget {
  final User user;

  const WalletScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  List<Bon> bons = [];
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadBons();
  }

  Future<void> _loadBons() async {
    setState(() => _isLoading = true);
    // Charger les bons depuis le stockage
    final storageService = StorageService();
    final loadedBons = await storageService.getBons();
    setState(() {
      bons = loadedBons;
      _isLoading = false;
    });
  }

  Future<void> _syncNostrCache() async {
    if (_isSyncing) return;
    
    setState(() => _isSyncing = true);
    
    try {
      final storageService = StorageService();
      final market = await storageService.getMarket();
      
      if (market == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucun marché configuré pour synchroniser'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      // Initialiser les services
      final cryptoService = CryptoService();
      final nostrService = NostrService(
        cryptoService: cryptoService,
        storageService: storageService,
      );
      
      // Se connecter au relais
      final connected = await nostrService.connect(
        market.relayUrl ?? 'wss://relay.copylaradio.com',
      );
      
      if (!connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossible de se connecter au relais ${market.relayUrl}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // Synchroniser les P3
      final syncedCount = await nostrService.syncMarketP3s(market);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synchronisation terminée: $syncedCount P3 récupérés'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Recharger les bons pour voir les changements
      await _loadBons();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur de synchronisation: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildBody() {
    if (_isLoading && _selectedIndex == 0) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_selectedIndex) {
      case 0: // Portefeuille
        if (bons.isEmpty) {
          return const Center(
            child: Text(
              'Aucun bon dans votre portefeuille',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          );
        }
        return ListView.builder(
          itemCount: bons.length,
          itemBuilder: (context, index) {
            final bon = bons[index];
            return PaniniCard(bon: bon);
          },
        );
      case 1: // Marché
        return MarketScreen(user: widget.user);
      case 2: // Dashboard
        // Créer un dashboard simplifié pour l'utilisateur courant
        return MerchantDashboardScreen(
          merchantNpub: widget.user.npub,
          merchantName: widget.user.displayName,
          marketName: 'Marché Local',
        );
      case 3: // Aide & Paramètres
        return SettingsScreen(user: widget.user);
      default:
        return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TrocZen'),
        backgroundColor: const Color(0xFF0A7EA4),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(user: widget.user),
                ),
              );
            },
            tooltip: 'Mon Profil',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'feedback':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FeedbackScreen(user: widget.user),
                    ),
                  );
                  break;
                case 'atomic_swap':
                  // Nécessite un bon sélectionné, on ne fait rien pour l'instant
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Veuillez d\'abord sélectionner un bon depuis votre portefeuille'),
                    ),
                  );
                  break;
                case 'offer':
                  // Nécessite un bon sélectionné
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Fonctionnalité à implémenter'),
                    ),
                  );
                  break;
                case 'ack':
                  // Nécessite un bon et un challenge
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Fonctionnalité à implémenter'),
                    ),
                  );
                  break;
                case 'ack_scanner':
                  // Nécessite un bon et un challenge
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Fonctionnalité à implémenter'),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'feedback',
                child: Text('Feedback'),
              ),
              const PopupMenuItem<String>(
                value: 'atomic_swap',
                child: Text('Échange Atomique'),
              ),
              const PopupMenuItem<String>(
                value: 'offer',
                child: Text('Offre'),
              ),
              const PopupMenuItem<String>(
                value: 'ack',
                child: Text('ACK'),
              ),
              const PopupMenuItem<String>(
                value: 'ack_scanner',
                child: Text('Scanner ACK'),
              ),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF0A7EA4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFFFB347),
                    radius: 30,
                    child: Text(
                      widget.user.displayName[0].toUpperCase(),
                      style: const TextStyle(fontSize: 24, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.user.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${widget.user.npub.substring(0, 8)}...',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wallet, color: Color(0xFF0A7EA4)),
              title: const Text('Portefeuille'),
              selected: _selectedIndex == 0,
              onTap: () {
                _onItemTapped(0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.store, color: Color(0xFF0A7EA4)),
              title: const Text('Marché'),
              selected: _selectedIndex == 1,
              onTap: () {
                _onItemTapped(1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dashboard, color: Color(0xFF0A7EA4)),
              title: const Text('Dashboard Économique'),
              selected: _selectedIndex == 2,
              onTap: () {
                _onItemTapped(2);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.help, color: Color(0xFF0A7EA4)),
              title: const Text('Aide & Paramètres'),
              selected: _selectedIndex == 3,
              onTap: () {
                _onItemTapped(3);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person, color: Color(0xFFFFB347)),
              title: const Text('Mon Profil'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(user: widget.user),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections, color: Color(0xFFFFB347)),
              title: const Text('Galerie'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GalleryScreen(user: widget.user),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.feedback, color: Color(0xFFFFB347)),
              title: const Text('Feedback & Support'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FeedbackScreen(user: widget.user),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Color(0xFFFFB347)),
              title: const Text('Paramètres Avancés'),
              onTap: () {
                // TODO: Écran paramètres avancés
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.grey),
              title: const Text('Déconnexion'),
              onTap: () {
                // TODO: Déconnexion
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.wallet),
            label: 'Portefeuille',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.store),
            label: 'Marché',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.help),
            label: 'Aide',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFFFB347),
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Bouton synchroniser cache Nostr
          FloatingActionButton(
            heroTag: 'sync',
            onPressed: () => _syncNostrCache(),
            backgroundColor: const Color(0xFF4CAF50),
            mini: true,
            child: const Icon(Icons.sync),
          ),
          const SizedBox(height: 8),
          // Bouton scanner
          FloatingActionButton(
            heroTag: 'scan',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ScanScreen(user: widget.user),
                ),
              ).then((_) => _loadBons());
            },
            backgroundColor: const Color(0xFF0A7EA4),
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 16),
          // Bouton créer bon
          FloatingActionButton(
            heroTag: 'create',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateBonScreen(user: widget.user),
                ),
              ).then((_) => _loadBons());
            },
            backgroundColor: const Color(0xFFFFB347),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
