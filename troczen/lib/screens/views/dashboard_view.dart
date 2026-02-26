import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../services/storage_service.dart';
import '../../services/logger_service.dart';
// Import des nouveaux widgets Alchimiste
import '../../widgets/alchimiste/metric_card.dart';
import '../../widgets/alchimiste/time_filter_bar.dart';

/// DashboardView — Données économiques du marché
/// ✅ Intégration TimeFilterBar & MetricCards pour le mode Alchimiste
/// ✅ Nettoyage des imports inutilisés
class DashboardView extends StatefulWidget {
  final User user;

  const DashboardView({super.key, required this.user});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final _storageService = StorageService();
  
  late TabController _tabController;
  
  DashboardMetrics? _metrics;
  bool _isLoading = true;

  // État du filtrage temporel
  TimeFilter _selectedFilter = TimeFilter.days7;
  DateTimeRange? _customDateRange;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMetrics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Charge les données brutes et déclenche le calcul des métriques
  Future<void> _loadMetrics() async {
    await _updateCalculatedMetricsAsync();
  }

  /// Recalcule les métriques en fonction du filtre sélectionné via SQL
  Future<void> _updateCalculatedMetricsAsync() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      DateTime startCurrent;
      DateTime endCurrent = now;

      // Définition de la période actuelle
      switch (_selectedFilter) {
        case TimeFilter.days7:
          startCurrent = now.subtract(const Duration(days: 7));
          break;
        case TimeFilter.days30:
          startCurrent = now.subtract(const Duration(days: 30));
          break;
        case TimeFilter.quarter:
          startCurrent = now.subtract(const Duration(days: 90));
          break;
        case TimeFilter.custom:
          startCurrent = _customDateRange?.start ?? now.subtract(const Duration(days: 7));
          endCurrent = _customDateRange?.end ?? now;
          break;
      }

      // Période précédente pour le calcul de la tendance (trend)
      final duration = endCurrent.difference(startCurrent);
      final startPrevious = startCurrent.subtract(duration);
      final endPrevious = startCurrent;

      // Fetch metrics via SQL
      final currentMetrics = await _storageService.getDashboardMetricsForPeriod(startCurrent, endCurrent);
      final previousMetrics = await _storageService.getDashboardMetricsForPeriod(startPrevious, endPrevious);
      final totalMarketBons = await _storageService.getMarketBonsCount();

      if (!mounted) return;

      // --- Calcul des tendances (comparaison avec période précédente) ---
      double calcTrend(double current, double previous) {
        if (previous == 0) return current > 0 ? 100.0 : 0.0;
        return ((current - previous) / previous) * 100;
      }

      final totalVolume = currentMetrics['totalVolume'] as double;
      final prevVolume = previousMetrics['totalVolume'] as double;
      
      final activeMerchants = currentMetrics['activeMerchants'] as int;
      final prevMerchants = previousMetrics['activeMerchants'] as int;

      final newBonsCount = currentMetrics['newBonsCount'] as int;
      final prevBonsCount = previousMetrics['newBonsCount'] as int;

      final spentVolume = currentMetrics['spentVolume'] as double;

      setState(() {
        _metrics = DashboardMetrics(
          totalVolume: totalVolume,
          volumeTrend: calcTrend(totalVolume, prevVolume),
          activeMerchants: activeMerchants,
          merchantsTrend: calcTrend(activeMerchants.toDouble(), prevMerchants.toDouble()),
          newBonsCount: newBonsCount,
          newBonsTrend: calcTrend(newBonsCount.toDouble(), prevBonsCount.toDouble()),
          spentVolume: spentVolume,
          dailyAverage: totalVolume / (duration.inDays > 0 ? duration.inDays : 1),
          totalMarketBons: totalMarketBons,
        );
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('DashboardView', 'Erreur calcul métriques', e);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Dashboard Alchimiste'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMetrics,
            tooltip: 'Actualiser',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFB347),
          labelColor: const Color(0xFFFFB347),
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Vue d\'ensemble'),
            Tab(text: 'Graphiques'),
            Tab(text: 'Top émetteurs'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFB347)))
          : Column(
              children: [
                // Barre de filtre temporelle universelle
                TimeFilterBar(
                  selectedFilter: _selectedFilter,
                  onFilterChanged: (filter) {
                    _selectedFilter = filter;
                    _updateCalculatedMetricsAsync();
                  },
                  customDateRange: _customDateRange,
                  onCustomDateRangeChanged: (range) {
                    _customDateRange = range;
                    _updateCalculatedMetricsAsync();
                  },
                ),
                Expanded(
                  child: _metrics == null
                      ? _buildEmptyState()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOverviewTab(),
                            _buildChartsTab(),
                            _buildTopIssuersTab(),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_outlined, size: 120, color: Colors.grey[700]),
          const SizedBox(height: 24),
          const Text('Aucune donnée pour cette période', 
              style: TextStyle(fontSize: 18, color: Colors.white70)),
        ],
      ),
    );
  }

  // ============================================================
  // ONGLET 1 : VUE D'ENSEMBLE
  // ============================================================
  
  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Volume principal
        _buildVolumeHero(),
        const SizedBox(height: 16),
        
        // Grille de métriques avec les nouvelles MetricCards
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            MetricCard(
              label: 'Commerçants',
              value: '${_metrics!.activeMerchants}',
              trend: _metrics!.merchantsTrend,
              icon: Icons.store,
              color: const Color(0xFF0A7EA4),
            ),
            MetricCard(
              label: 'Nouveaux Bons',
              value: '${_metrics!.newBonsCount}',
              trend: _metrics!.newBonsTrend,
              icon: Icons.confirmation_number_outlined,
              color: const Color(0xFF10B981),
            ),
            MetricCard(
              label: 'Volume Sortant',
              value: '${_metrics!.spentVolume.toStringAsFixed(0)} Ẑ',
              icon: Icons.shopping_cart_checkout,
              color: Colors.redAccent,
            ),
            MetricCard(
              label: 'Moyenne/Jour',
              value: '${_metrics!.dailyAverage.toStringAsFixed(1)} Ẑ',
              icon: Icons.timeline,
              color: const Color(0xFFF59E0B),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Info sur le total historique
        _buildTotalHistoryInfo(),
      ],
    );
  }

  Widget _buildVolumeHero() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB347).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Volume en circulation',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              if (_metrics!.volumeTrend != 0)
                _buildTrendBadge(_metrics!.volumeTrend),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_metrics!.totalVolume.toStringAsFixed(2)} Ẑ',
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text('Sur la période sélectionnée', 
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTrendBadge(double trend) {
    final isPositive = trend >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPositive ? Colors.green.shade800 : Colors.red.shade800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward, 
              size: 14, color: Colors.white),
          Text(' ${trend.abs().toStringAsFixed(1)}%', 
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTotalHistoryInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: Colors.grey),
          const SizedBox(width: 12),
          Text(
            'Total historique du marché : ${_metrics!.totalMarketBons} bons émis',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ONGLET 2 : GRAPHIQUES (emplacements pour implémentation future)
  // ============================================================
  
  Widget _buildChartsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPlaceholderChart('Graphique d\'évolution temporel'),
        const SizedBox(height: 24),
        _buildPlaceholderChart('Répartition par statut'),
      ],
    );
  }

  Widget _buildPlaceholderChart(String title) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Center(
        child: Text(title, style: const TextStyle(color: Colors.white54)),
      ),
    );
  }

  // ============================================================
  // ONGLET 3 : TOP ÉMETTEURS
  // ============================================================
  
  Widget _buildTopIssuersTab() {
    return const Center(
      child: Text('Classement des émetteurs (en attente)', 
          style: TextStyle(color: Colors.white54))
    );
  }
}

/// Modèle de métriques étendu pour le Dashboard Alchimiste
class DashboardMetrics {
  final double totalVolume;
  final double volumeTrend;
  final int activeMerchants;
  final double merchantsTrend;
  final int newBonsCount;
  final double newBonsTrend;
  final double spentVolume;
  final double dailyAverage;
  final int totalMarketBons;

  DashboardMetrics({
    required this.totalVolume,
    required this.volumeTrend,
    required this.activeMerchants,
    required this.merchantsTrend,
    required this.newBonsCount,
    required this.newBonsTrend,
    required this.spentVolume,
    required this.dailyAverage,
    required this.totalMarketBons,
  });
}