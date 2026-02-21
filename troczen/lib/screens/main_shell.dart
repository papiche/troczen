import 'package:flutter/material.dart';
import '../models/user.dart';
import '../config/app_config.dart';
import 'views/wallet_view.dart';
import 'views/explore_view.dart';
import 'views/dashboard_view.dart';
import 'views/profile_view.dart';
import 'mirror_receive_screen.dart';
import 'create_bon_screen.dart';
import 'settings_screen.dart';
import 'logs_screen.dart';
import 'feedback_screen.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../services/logger_service.dart';

/// MainShell — Architecture de navigation principale
/// 4 onglets : Wallet, Explorer, Dashboard, Profil
/// FAB contextuel selon l'onglet actif
/// Drawer pour paramètres avancés
class MainShell extends StatefulWidget {
  final User user;

  const MainShell({super.key, required this.user});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentTab = 0;
  final _storageService = StorageService();
  final _cryptoService = CryptoService();
  late final NostrService _nostrService;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _nostrService = NostrService(
      cryptoService: _cryptoService,
      storageService: _storageService,
    );
    _initAutoSync();
  }

  Future<void> _initAutoSync() async {
    // Activer la sync P3 automatique en arrière-plan
    final market = await _storageService.getMarket();
    if (market != null) {
      _nostrService.enableAutoSync(
        interval: const Duration(minutes: 5),
        initialMarket: market,
      );
    }
  }

  @override
  void dispose() {
    _nostrService.disableAutoSync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentTab,
        children: [
          WalletView(user: widget.user),      // 0 — Mon Wallet
          ExploreView(user: widget.user),     // 1 — Explorer / Marché
          DashboardView(user: widget.user),   // 2 — Dashboard économique
          ProfileView(user: widget.user),     // 3 — Mon Profil
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) {
          setState(() => _currentTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wallet),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore),
            label: 'Explorer',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
      floatingActionButton: _buildMainFAB(),
      drawer: _buildSettingsDrawer(),
    );
  }

  /// FAB contextuel selon l'onglet actif
  Widget? _buildMainFAB() {
    switch (_currentTab) {
      case 0: // Wallet
        return FloatingActionButton.extended(
          onPressed: () => _navigateToScan(),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Recevoir'),
          backgroundColor: const Color(0xFFFFB347),
        );
      
      case 1: // Explorer
        return FloatingActionButton.extended(
          onPressed: () => _navigateToCreateBon(),
          icon: const Icon(Icons.add),
          label: const Text('Créer un bon'),
          backgroundColor: const Color(0xFFFFB347),
        );
      
      case 2: // Dashboard
        return FloatingActionButton.extended(
          onPressed: () => _exportDashboardData(),
          icon: const Icon(Icons.upload),
          label: const Text('Exporter'),
          backgroundColor: const Color(0xFFFFB347),
        );
      
      case 3: // Profil
        return FloatingActionButton(
          onPressed: () => _navigateToEditProfile(),
          backgroundColor: const Color(0xFFFFB347),
          child: const Icon(Icons.edit),
        );
      
      default:
        return null;
    }
  }

  /// Drawer — Paramètres avancés uniquement
  Widget _buildSettingsDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      child: SafeArea(
        child: Column(
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.settings, size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  const Text(
                    'Paramètres avancés',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.user.displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Configuration réseau
                  ListTile(
                    leading: const Icon(Icons.network_check, color: Color(0xFFFFB347)),
                    title: const Text('Relais Nostr / API', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Configurer les relais et services', style: TextStyle(color: Colors.white70)),
                    onTap: () => _navigateToSettings(),
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  // Exporter seed de marché
                  ListTile(
                    leading: const Icon(Icons.qr_code, color: Color(0xFFFFB347)),
                    title: const Text('Exporter seed marché', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Afficher le QR code', style: TextStyle(color: Colors.white70)),
                    onTap: () => _exportMarketSeed(),
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  // Synchroniser Nostr
                  ListTile(
                    leading: _isSyncing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Color(0xFFFFB347)),
                            ),
                          )
                        : const Icon(Icons.sync, color: Color(0xFFFFB347)),
                    title: const Text('Synchroniser Nostr', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Actualiser les P3 du marché', style: TextStyle(color: Colors.white70)),
                    onTap: _isSyncing ? null : () => _syncNostr(),
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  // Vider cache P3
                  ListTile(
                    leading: const Icon(Icons.delete_sweep, color: Colors.orange),
                    title: const Text('Vider cache P3', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Supprimer les P3 locales', style: TextStyle(color: Colors.white70)),
                    onTap: () => _clearP3Cache(),
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  // Logs
                  ListTile(
                    leading: const Icon(Icons.article_outlined, color: Color(0xFFFFB347)),
                    title: const Text('Logs de l\'application', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'Voir les événements (${Logger.logCount} entrées)',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: () => _navigateToLogs(),
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  // À propos
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Color(0xFF0A7EA4)),
                    title: const Text('À propos', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Version et informations', style: TextStyle(color: Colors.white70)),
                    onTap: () => _showAboutDialog(),
                  ),
                  
                  // Feedback
                  ListTile(
                    leading: const Icon(Icons.feedback_outlined, color: Color(0xFF4CAF50)),
                    title: const Text('Envoyer un feedback', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Signaler un bug ou suggérer', style: TextStyle(color: Colors.white70)),
                    onTap: () => _navigateToFeedback(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== ACTIONS FAB =====
  
  void _navigateToScan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MirrorReceiveScreen(user: widget.user),
      ),
    );
  }

  void _navigateToCreateBon() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateBonScreen(user: widget.user),
      ),
    );
  }

  Future<void> _exportDashboardData() async {
    // TODO: Implémenter l'export des données du dashboard
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export des données en cours...'),
        backgroundColor: Color(0xFF0A7EA4),
      ),
    );
  }

  void _navigateToEditProfile() {
    // TODO: Naviguer vers l'écran d'édition de profil
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Édition du profil à venir'),
        backgroundColor: Color(0xFF0A7EA4),
      ),
    );
  }

  // ===== ACTIONS DRAWER =====
  
  void _navigateToSettings() {
    Navigator.pop(context); // Fermer le drawer
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(user: widget.user),
      ),
    );
  }

  void _navigateToLogs() {
    Navigator.pop(context); // Fermer le drawer
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LogsScreen(),
      ),
    );
  }

  void _navigateToFeedback() {
    Navigator.pop(context); // Fermer le drawer
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FeedbackScreen(user: widget.user),
      ),
    );
  }

  Future<void> _exportMarketSeed() async {
    Navigator.pop(context); // Fermer le drawer
    
    final market = await _storageService.getMarket();
    if (market == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun marché configuré'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Seed du marché', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                market.seedMarket,
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'monospace',
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Partagez ce code pour permettre à d\'autres utilisateurs de rejoindre votre marché.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncNostr() async {
    if (_isSyncing) return;
    
    setState(() => _isSyncing = true);
    
    try {
      final market = await _storageService.getMarket();
      
      if (market == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucun marché configuré pour synchroniser'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );
      
      final connected = await nostrService.connect(
        market.relayUrl ?? AppConfig.defaultRelayUrl,
      );
      
      if (!connected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossible de se connecter au relais ${market.relayUrl}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final syncedCount = await nostrService.syncMarketP3s(market);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $syncedCount P3 synchronisés'),
          backgroundColor: Colors.green,
        ),
      );
      
      await nostrService.disconnect();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erreur de synchronisation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _clearP3Cache() async {
    Navigator.pop(context); // Fermer le drawer
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Vider le cache P3', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer toutes les P3 locales ? Cette action est irréversible.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _storageService.clearP3Cache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Cache P3 vidé avec succès'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAboutDialog() {
    Navigator.pop(context); // Fermer le drawer
    
    showAboutDialog(
      context: context,
      applicationName: AppConfig.appName,
      applicationVersion: AppConfig.appVersion,
      applicationIcon: const Icon(
        Icons.wallet,
        size: 64,
        color: Color(0xFFFFB347),
      ),
      applicationLegalese: '© 2026 TrocZen\nMonnaie locale ẐEN\nProtocole Nostr P3',
      children: [
        const SizedBox(height: 16),
        const Text(
          'Application de gestion de bons locaux basée sur le protocole Nostr.',
          style: TextStyle(fontSize: 14),
        ),
      ],
    );
  }

}
