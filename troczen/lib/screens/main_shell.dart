import 'dart:async';
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
import 'settings_screen.dart';
import 'logs_screen.dart';
import 'feedback_screen.dart';
import 'apk_share_screen.dart';
import 'package:intl/intl.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';
import '../services/logger_service.dart';
import '../services/notification_service.dart';
import '../services/cache_database_service.dart';
import '../services/nostr_connection_service.dart';

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

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentTab = 0;
  final _storageService = StorageService();
  late final NostrService _nostrService;
  int _pendingEventsCount = 0;
  Timer? _pendingEventsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nostrService = context.read<NostrService>();
    _initAutoSync();
    _updatePendingEventsCount();
    _pendingEventsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updatePendingEventsCount();
    });
  }

  Future<void> _updatePendingEventsCount() async {
    final count = await CacheDatabaseService().getPendingEventsCount();
    if (mounted && count != _pendingEventsCount) {
      setState(() {
        _pendingEventsCount = count;
      });
    }
  }

  Future<void> _initAutoSync() async {
    // Activer la sync P3 automatique en arrière-plan
    final market = await _storageService.getMarket();
    if (market != null) {
      _nostrService.market.enableAutoSync(
        interval: const Duration(minutes: 5),
        initialMarket: market,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);    
    _pendingEventsTimer?.cancel();
    _nostrService.market.disableAutoSync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ PROGRESSIVE DISCLOSURE : Écoute du provider
    final appModeProvider = context.watch<AppModeProvider>();
    final appMode = appModeProvider.currentMode;
    final maxTabs = appMode.navigationTabsCount;
    if (_currentTab >= maxTabs) {
      // PostFrameCallback pour éviter une erreur setState durant le build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentTab = maxTabs - 1);
      });
      // On force temporairement l'affichage du dernier onglet valide
      _currentTab = maxTabs - 1; 
    }
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
          _getTabTitle(appMode),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Notifications
          StreamBuilder<List<MarketNotification>>(
            stream: NotificationService().notificationsStream,
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? [];
              final unreadCount = notifications.length;
              
              return Stack(
                alignment: Alignment.center,
                children: [
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.notifications, color: Color(0xFFFFB347)),
                      onPressed: () {
                        Scaffold.of(context).openEndDrawer();
                      },
                      tooltip: 'Notifications',
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Builder(
                        builder: (context) => GestureDetector(
                          onTap: () {
                            Scaffold.of(context).openEndDrawer();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
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
              appMode.label,
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
        children: _buildViews(appMode),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) {
          setState(() => _currentTab = index);
        },
        destinations: _buildDestinations(appMode),
      ),
      floatingActionButton: _buildMainFAB(appMode),
      drawer: _buildSettingsDrawer(appMode),
      endDrawer: _buildNotificationDrawer(),
    );
  }
  
  /// Retourne le titre de l'onglet actif
  String _getTabTitle(AppMode appMode) {
    switch (appMode) {
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
  List<Widget> _buildViews(AppMode appMode) {
    switch (appMode) {
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
  List<NavigationDestination> _buildDestinations(AppMode appMode) {
    switch (appMode) {
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
  Widget? _buildMainFAB(AppMode appMode) {
    // Mode Flâneur
    if (appMode.isFlaneur) {
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
      
      case 1: // Explorer
        // Le bouton "Créer un bon" a été déplacé dans la vue ExploreView
        // pour ne pas cacher le contenu en bas de l'écran
        return null;
      
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
  Widget _buildSettingsDrawer(AppMode appMode) {
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
                      appMode.label,
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
                  
                  // ✅ SYNCHRONISATION MANUELLE
                  ListTile(
                    leading: Stack(
                      children: [
                        const Icon(Icons.sync, color: Color(0xFF0A7EA4)),
                        if (_pendingEventsCount > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: const Text('Synchroniser', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      _pendingEventsCount > 0
                          ? '$_pendingEventsCount événement(s) en attente'
                          : 'Réseau à jour',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: () => _triggerManualSync(),
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

  /// Drawer — Notifications
  Widget _buildNotificationDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      child: SafeArea(
        child: Column(
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear_all, color: Colors.grey),
                    onPressed: () {
                      NotificationService().clearNotifications();
                      Navigator.pop(context);
                    },
                    tooltip: 'Tout effacer',
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: StreamBuilder<List<MarketNotification>>(
                stream: NotificationService().notificationsStream,
                builder: (context, snapshot) {
                  final notifications = snapshot.data ?? [];
                  
                  if (notifications.isEmpty) {
                    return const Center(
                      child: Text(
                        'Aucune notification pour le moment.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    );
                  }
                  
                  return ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notif = notifications[index];
                      IconData icon;
                      Color color;
                      
                      switch (notif.type) {
                        case NotificationType.loop:
                          icon = Icons.loop;
                          color = Colors.greenAccent;
                          break;
                        case NotificationType.bootstrap:
                          icon = Icons.eco;
                          color = Colors.purpleAccent;
                          break;
                        case NotificationType.expertise:
                          icon = Icons.verified_user;
                          color = Colors.blueAccent;
                          break;
                        case NotificationType.volume:
                          icon = Icons.warning_amber_rounded;
                          color = Colors.orangeAccent;
                          break;
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.2),
                          child: Icon(icon, color: color),
                        ),
                        title: Text(notif.message, style: const TextStyle(color: Colors.white, fontSize: 14)),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(notif.timestamp),
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      );
                    },
                  );
                },
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

  // ===== ACTIONS DRAWER =====
  
  Future<void> _triggerManualSync() async {
    Navigator.pop(context); // Fermer le drawer
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Synchronisation en cours...')),
    );
    
    final connection = NostrConnectionService();
    if (!connection.isConnected) {
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        await connection.connect(market!.relayUrl!);
      }
    }
    
    final syncedCount = await connection.flushPendingEvents();
    
    // Rafraîchir le cache local depuis le relai
    final market = await _storageService.getMarket();
    if (market != null) {
      await _nostrService.triggerImmediateSync(market);
    }
    
    // Si Alchimiste, lancer la sync Gossip
    final modeIndex = await _storageService.getAppMode();
    final mode = AppMode.fromIndex(modeIndex);
    int gossipCount = 0;
    if (mode.isAlchimiste) {
      gossipCount = await _nostrService.syncGossipData();
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$syncedCount événement(s) envoyé(s)${mode.isAlchimiste ? ', $gossipCount événement(s) gossip collecté(s)' : ''}'),
          backgroundColor: Colors.green,
        ),
      );
      _updatePendingEventsCount();
    }
  }

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
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _storageService.reconcileBonsState(_nostrService).then((count) {
        if (count > 0 && mounted) {
          // Déclencher un rafraîchissement global ou une notification
        }
      });
    }
  }
}
