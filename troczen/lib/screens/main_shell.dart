import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/app_mode.dart';
import '../config/app_config.dart';
import '../providers/app_mode_provider.dart';
import 'help_screen.dart';
import 'views/wallet_view.dart';
import 'views/explore_view.dart';
import 'views/dashboard_view.dart';
import 'views/dashboard_simple_view.dart';
import 'views/profile_view.dart';
import 'mirror_receive_screen.dart';
import 'create_bon_screen.dart';
import 'settings_screen.dart';
import 'logs_screen.dart';
import 'feedback_screen.dart';
import 'apk_share_screen.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../services/logger_service.dart';

/// MainShell — Architecture de navigation principale adaptative
///
/// ✅ PROGRESSIVE DISCLOSURE : La navigation s'adapte au mode utilisateur
/// - Mode Flâneur (0) : 2 onglets (Wallet, Profil)
/// - Mode Artisan (1) : 4 onglets (Wallet, Explorer, Dashboard Simple, Profil)
/// - Mode Alchimiste (2) : 4 onglets (Wallet, Explorer, Dashboard Avancé, Profil)
///
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
    // ✅ PROGRESSIVE DISCLOSURE : Écoute du provider
    final appModeProvider = context.watch<AppModeProvider>();
    final _appMode = appModeProvider.currentMode;

    return Scaffold(
      // ✅ CORRECTION: Ajout d'un AppBar pour permettre l'accès au Drawer
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFFFFB347)),
            tooltip: 'Menu',
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: Text(
          _getTabTitle(_appMode),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Badge de mode utilisateur
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB347).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFB347)),
            ),
            child: Text(
              _appMode.label,
              style: const TextStyle(
                color: Color(0xFFFFB347),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: _buildViews(_appMode),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) {
          setState(() => _currentTab = index);
        },
        destinations: _buildDestinations(_appMode),
      ),
      floatingActionButton: _buildMainFAB(_appMode),
      drawer: _buildSettingsDrawer(_appMode),
    );
  }
  
  /// Retourne le titre de l'onglet actif
  String _getTabTitle(AppMode _appMode) {
    switch (_appMode) {
      case AppMode.flaneur:
        switch (_currentTab) {
          case 0:
            return 'Mon Wallet';
          case 1:
            return 'Mon Profil';
          default:
            return 'TrocZen';
        }
      
      case AppMode.artisan:
        switch (_currentTab) {
          case 0:
            return 'Mon Wallet';
          case 1:
            return 'Explorer';
          case 2:
            return 'Ma Caisse';
          case 3:
            return 'Mon Profil';
          default:
            return 'TrocZen';
        }
      
      case AppMode.alchimiste:
        switch (_currentTab) {
          case 0:
            return 'Mon Wallet';
          case 1:
            return 'Explorer';
          case 2:
            return 'Observatoire';
          case 3:
            return 'Mon Profil';
          default:
            return 'TrocZen';
        }
    }
  }
  
  /// ✅ PROGRESSIVE DISCLOSURE : Construction dynamique des vues selon le mode
  List<Widget> _buildViews(AppMode _appMode) {
    switch (_appMode) {
      case AppMode.flaneur:
        // Mode Flâneur : Wallet + Profil uniquement
        return [
          WalletView(user: widget.user),    // 0
          ProfileView(user: widget.user),   // 1
        ];
      
      case AppMode.artisan:
        // Mode Artisan : Wallet + Explorer + Dashboard Simple + Profil
        return [
          WalletView(user: widget.user),          // 0
          ExploreView(user: widget.user),         // 1
          DashboardSimpleView(user: widget.user), // 2
          ProfileView(user: widget.user),         // 3
        ];
      
      case AppMode.alchimiste:
        // Mode Alchimiste : Wallet + Explorer + Dashboard Avancé + Profil
        return [
          WalletView(user: widget.user),      // 0
          ExploreView(user: widget.user),     // 1
          DashboardView(user: widget.user),   // 2
          ProfileView(user: widget.user),     // 3
        ];
    }
  }
  
  /// ✅ PROGRESSIVE DISCLOSURE : Construction dynamique de la navigation selon le mode
  List<NavigationDestination> _buildDestinations(AppMode _appMode) {
    switch (_appMode) {
      case AppMode.flaneur:
        return const [
          NavigationDestination(
            icon: Icon(Icons.wallet),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ];
      
      case AppMode.artisan:
        return const [
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
            label: 'Caisse',
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ];
      
      case AppMode.alchimiste:
        return const [
          NavigationDestination(
            icon: Icon(Icons.wallet),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore),
            label: 'Explorer',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics),
            label: 'Observatoire',
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ];
    }
  }

  /// FAB contextuel selon l'onglet actif et le mode
  Widget? _buildMainFAB(AppMode _appMode) {
    // Mode Flâneur
    if (_appMode.isFlaneur) {
      switch (_currentTab) {
        case 0: // Wallet
          return FloatingActionButton.extended(
            onPressed: () => _navigateToScan(),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scanner / Recevoir'),
            backgroundColor: const Color(0xFFFFB347),
          );
        case 1: // Profil
          return null;
        default:
          return null;
      }
    }
    
    // Mode Artisan et Alchimiste
    switch (_currentTab) {
      case 0: // Wallet - ✅ Action universelle de la caisse
        return FloatingActionButton.extended(
          onPressed: () => _navigateToScan(),
          heroTag: 'receive_bon',
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scanner / Recevoir'),
          backgroundColor: const Color(0xFFFFB347),
        );
      
      case 1: // Explorer - ✅ Déplacé: Créer un bon
        return FloatingActionButton.extended(
          onPressed: () => _navigateToCreateBon(),
          heroTag: 'create_bon',
          icon: const Icon(Icons.add),
          label: const Text('Créer un bon'),
          backgroundColor: const Color(0xFFFFB347),
        );
      
      case 2: // Dashboard (Simple ou Avancé)
        // Masqué tant que non implémenté
        return null;
      
      case 3: // Profil
        // Pas de FAB sur le profil
        return null;
      
      default:
        return null;
    }
  }

  /// Drawer — Paramètres avancés uniquement
  Widget _buildSettingsDrawer(AppMode _appMode) {
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
                  const SizedBox(height: 4),
                  // ✅ Affichage du mode actuel
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _appMode.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // ✅ PARTAGE APK : Accessible à TOUS les modes (propagation virale)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB347).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.share, color: Color(0xFFFFB347)),
                    ),
                    title: const Text(
                      '📤 Partager TrocZen',
                      style: TextStyle(
                        color: Color(0xFFFFB347),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: const Text(
                      'Diffuser l\'app à un smartphone proche (QR Code)',
                      style: TextStyle(color: Colors.white70),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFFFFB347), size: 16),
                    onTap: () => _navigateToApkShare(),
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  
                  // ✅ FEEDBACK : Accessible à TOUS les modes (priorité utilisateur)
                  ListTile(
                    leading: const Icon(Icons.feedback_outlined, color: Color(0xFF4CAF50)),
                    title: const Text('💬 Envoyer un feedback', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: const Text('Signaler un bug ou suggérer une amélioration', style: TextStyle(color: Colors.white70)),
                    onTap: () => _navigateToFeedback(),
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  // ✅ LOGS : Accessible à TOUS les modes (debugging)
                  ListTile(
                    leading: const Icon(Icons.article_outlined, color: Color(0xFFFFB347)),
                    title: const Text('📋 Logs de l\'application', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      'Voir les événements techniques (${Logger.logCount} entrées)',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: () => _navigateToLogs(),
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  // Paramètres (tous modes)
                  ListTile(
                    leading: const Icon(Icons.settings, color: Color(0xFFFFB347)),
                    title: const Text('Paramètres', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Mode, réseau, cache...', style: TextStyle(color: Colors.white70)),
                    onTap: () => _navigateToSettings(),
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  // Guide / Tutoriel
                  ListTile(
                    leading: const Icon(Icons.help_outline, color: Color(0xFF0A7EA4)),
                    title: const Text('Guide & Tutoriel', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Comment utiliser TrocZen', style: TextStyle(color: Colors.white70)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => HelpScreen(user: widget.user)),
                      );
                    },
                  ),
                  
                  const Divider(color: Colors.white24),
                  
                  // À propos (tous modes)
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Color(0xFF0A7EA4)),
                    title: const Text('À propos', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Version et informations', style: TextStyle(color: Colors.white70)),
                    onTap: () => _showAboutDialog(),
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

  Future<void> _navigateToCreateBon() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateBonScreen(user: widget.user),
      ),
    );
    
    // On force la reconstruction de l'interface
    setState(() {});
  }

  Future<void> _exportDashboardData() async {
    // TODO: Implémenter l'export des données du dashboard
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export des données TODO...'),
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
  
  void _navigateToApkShare() {
    Navigator.pop(context); // Fermer le drawer
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ApkShareScreen(),
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
      
      // ✅ CORRECTION: Réutiliser l'instance existante au lieu d'en créer une nouvelle
      final connected = await _nostrService.connect(
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
      
      final syncedCount = await _nostrService.syncMarketP3s(market);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $syncedCount P3 synchronisés'),
          backgroundColor: Colors.green,
        ),
      );
      
      // ✅ Pas besoin de déconnecter - on garde la connexion pour l'auto-sync
      // await _nostrService.disconnect();
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
