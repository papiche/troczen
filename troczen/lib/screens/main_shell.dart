import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/app_mode.dart';
import '../config/app_config.dart';
import '../providers/app_mode_provider.dart';
import '../providers/theme_provider.dart';
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu, color: Color(0xFFFFB347)),
            tooltip: 'Menu',
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: Text(
          _getTabTitle(appMode),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Theme Toggle
          Builder(
            builder: (context) {
              final themeProvider = Provider.of<ThemeProvider>(context);
              final isDark = themeProvider.themeMode == ThemeMode.dark;
              return IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: const Color(0xFFFFB347),
                ),
                onPressed: () {
                  themeProvider.toggleTheme();
                },
                tooltip: isDark ? 'Passer au thème clair' : 'Passer au thème sombre',
              );
            },
          ),
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
                      icon: Icon(Icons.notifications, color: Color(0xFFFFB347)),
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
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
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
              style: TextStyle(
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
            icon: Icon(Icons.qr_code_scanner),
            label: Text('Scanner / Recevoir'),
            backgroundColor: const Color(0xFFFFB347),
          );
        case 1: // Profil
          return null;
        default:
          return null;
      }
    }
    
    // Mode Artisan et Alchimiste
    // ✅ Action universelle de la caisse sur tous les onglets
    return FloatingActionButton.extended(
      onPressed: () => _navigateToScan(),
      heroTag: 'receive_bon',
      icon: Icon(Icons.qr_code_scanner),
      label: Text('Scanner / Recevoir'),
      backgroundColor: const Color(0xFFFFB347),
    );
  }

  /// Drawer — Paramètres avancés uniquement
  Widget _buildSettingsDrawer(AppMode appMode) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.settings, size: 48, color: Theme.of(context).colorScheme.onSurface),
                  const SizedBox(height: 12),
                  Text(
                    'Paramètres avancés',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.user.displayName,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // ✅ Affichage du mode actuel
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      appMode.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface,
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
                      child: Icon(Icons.share, color: Color(0xFFFFB347)),
                    ),
                    title: Text(
                      '📤 Partager TrocZen',
                      style: TextStyle(
                        color: Color(0xFFFFB347),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      'Diffuser l\'app à un smartphone proche (QR Code)',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, color: Color(0xFFFFB347), size: 16),
                    onTap: () => _navigateToApkShare(),
                  ),
                  
                  Divider(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),
                  
                  
                  // ✅ FEEDBACK : Accessible à TOUS les modes (priorité utilisateur)
                  ListTile(
                    leading: Icon(Icons.feedback_outlined, color: Color(0xFF4CAF50)),
                    title: Text('💬 Envoyer un feedback', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
                    subtitle: Text('Signaler un bug ou suggérer une amélioration', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                    onTap: () => _navigateToFeedback(),
                  ),
                  
                  Divider(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),
                  
                  // ✅ LOGS : Accessible à TOUS les modes (debugging)
                  ListTile(
                    leading: Icon(Icons.article_outlined, color: Color(0xFFFFB347)),
                    title: Text('📋 Logs de l\'application', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      'Voir les événements techniques (${Logger.logCount} entrées)',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                    onTap: () => _navigateToLogs(),
                  ),
                  
                  Divider(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),
                  
                  // ✅ SYNCHRONISATION MANUELLE
                  ListTile(
                    leading: Stack(
                      children: [
                        Icon(Icons.sync, color: Color(0xFF0A7EA4)),
                        if (_pendingEventsCount > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text('Synchroniser', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    subtitle: Text(
                      _pendingEventsCount > 0
                          ? '$_pendingEventsCount événement(s) en attente'
                          : 'Réseau à jour',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                    onTap: () => _triggerManualSync(),
                  ),
                  
                  Divider(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),

                  // Paramètres (tous modes)
                  ListTile(
                    leading: Icon(Icons.settings, color: Color(0xFFFFB347)),
                    title: Text('Paramètres', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    subtitle: Text('Mode, réseau, cache...', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                    onTap: () => _navigateToSettings(),
                  ),
                  
                  Divider(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),
                  
                  // Guide / Tutoriel
                  ListTile(
                    leading: Icon(Icons.help_outline, color: Color(0xFF0A7EA4)),
                    title: Text('Guide & Tutoriel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    subtitle: Text('Comment utiliser TrocZen', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => HelpScreen(user: widget.user)),
                      );
                    },
                  ),
                  
                  Divider(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),
                  
                  // À propos (tous modes)
                  ListTile(
                    leading: Icon(Icons.info_outline, color: Color(0xFF0A7EA4)),
                    title: Text('À propos', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    subtitle: Text('Version et informations', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.clear_all, color: Colors.grey),
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
                    return Center(
                      child: Text(
                        'Aucune notification pour le moment.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
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
                        title: Text(notif.message, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(notif.timestamp),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontSize: 12),
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
      applicationIcon: Icon(
        Icons.wallet,
        size: 64,
        color: Color(0xFFFFB347),
      ),
      applicationLegalese: '© 2026 TrocZen\nMonnaie locale ẐEN\nProtocole Nostr P3',
      children: [
        const SizedBox(height: 16),
        Text(
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
