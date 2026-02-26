import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../models/user.dart';
import '../../services/storage_service.dart';
import '../../services/logger_service.dart';
import '../../services/cache_database_service.dart';
// Import des nouveaux widgets Alchimiste
import '../../widgets/alchimiste/metric_card.dart';
import '../../widgets/alchimiste/time_filter_bar.dart';
import 'circuits_graph_view.dart';

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
      String groupBy = '%Y-%m-%d';
      if (duration.inDays > 60) {
        groupBy = '%Y-%m';
      }

      final currentAgg = await _storageService.getAggregatedMetrics(startCurrent, endCurrent, groupBy: groupBy);
      final previousAgg = await _storageService.getAggregatedMetrics(startPrevious, endPrevious, groupBy: groupBy);
      final topIssuers = await _storageService.getTopIssuers(startCurrent, endCurrent);
      final totalMarketBons = await _storageService.getMarketBonsCount();

      if (!mounted) return;

      // --- Calcul des tendances (comparaison avec période précédente) ---
      double calcTrend(double current, double previous) {
        if (previous == 0) return current > 0 ? 100.0 : 0.0;
        return ((current - previous) / previous) * 100;
      }

      setState(() {
        _metrics = DashboardMetrics(
          totalVolume: currentAgg.totalVolume,
          volumeTrend: calcTrend(currentAgg.totalVolume, previousAgg.totalVolume),
          activeMerchants: currentAgg.uniqueIssuers,
          merchantsTrend: calcTrend(currentAgg.uniqueIssuers.toDouble(), previousAgg.uniqueIssuers.toDouble()),
          newBonsCount: currentAgg.count,
          newBonsTrend: calcTrend(currentAgg.count.toDouble(), previousAgg.count.toDouble()),
          spentVolume: currentAgg.transfersVolume,
          dailyAverage: currentAgg.totalVolume / (duration.inDays > 0 ? duration.inDays : 1),
          totalMarketBons: totalMarketBons,
          series: currentAgg.series,
          topIssuers: topIssuers,
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
            icon: const Icon(Icons.hub),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CircuitsGraphView()),
              );
            },
            tooltip: 'Circuits du Marché',
          ),
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
  // ONGLET 2 : GRAPHIQUES
  // ============================================================
  
  Widget _buildChartsTab() {
    if (_metrics!.series.isEmpty) {
      return const Center(
        child: Text('Pas assez de données pour afficher un graphique', style: TextStyle(color: Colors.white54)),
      );
    }

    final spots = _metrics!.series.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value);
    }).toList();

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 300,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Évolution du Volume', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Expanded(
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() >= 0 && value.toInt() < _metrics!.series.length) {
                              final date = _metrics!.series[value.toInt()].date;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(DateFormat('dd/MM').format(date), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) {
                            return Text('${value.toInt()} Ẑ', style: const TextStyle(color: Colors.white54, fontSize: 10));
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    minX: 0,
                    maxX: (_metrics!.series.length - 1).toDouble(),
                    minY: 0,
                    maxY: maxY == 0 ? 10 : maxY,
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: const Color(0xFFFFB347),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                            radius: 4,
                            color: const Color(0xFFFFB347),
                            strokeWidth: 2,
                            strokeColor: const Color(0xFF1E1E1E),
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: const Color(0xFFFFB347).withValues(alpha: 0.2),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                        if (event is FlTapUpEvent && touchResponse != null && touchResponse.lineBarSpots != null) {
                          final index = touchResponse.lineBarSpots!.first.spotIndex;
                          _showBonsForDate(_metrics!.series[index].date);
                        }
                      },
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (touchedSpot) => Colors.blueGrey.shade900,
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            return LineTooltipItem(
                              '${spot.y.toStringAsFixed(1)} Ẑ',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showBonsForDate(DateTime date) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Activité du ${DateFormat('dd/MM/yyyy').format(date)}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Expanded(
                child: Center(
                  child: Text('Liste des bons concernés (à implémenter avec une requête spécifique)',
                      style: TextStyle(color: Colors.white54)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // ONGLET 3 : TOP ÉMETTEURS
  // ============================================================
  
  Widget _buildTopIssuersTab() {
    if (_metrics!.topIssuers.isEmpty) {
      return const Center(
        child: Text('Aucun émetteur pour cette période', style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _metrics!.topIssuers.length,
      itemBuilder: (context, index) {
        final issuer = _metrics!.topIssuers[index];
        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFFFB347).withValues(alpha: 0.2),
              child: Text('${index + 1}', style: const TextStyle(color: Color(0xFFFFB347), fontWeight: FontWeight.bold)),
            ),
            title: Text(issuer.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Moy. transferts: ${issuer.avgTransfers.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 4),
                SizedBox(
                  height: 20,
                  width: 100,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(show: false),
                      titlesData: FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: issuer.activitySeries.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                          isCurved: true,
                          color: const Color(0xFFFFB347),
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(show: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${issuer.totalEmitted.toStringAsFixed(0)} Ẑ', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                const Text('Volume émis', style: TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        );
      },
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
  final List<TimeSeriesPoint> series;
  final List<IssuerStats> topIssuers;

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
    required this.series,
    required this.topIssuers,
  });
}