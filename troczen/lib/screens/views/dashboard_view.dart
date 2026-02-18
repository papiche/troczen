import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../services/storage_service.dart';

/// DashboardView — Données économiques du marché
/// Analytics basées sur les événements Nostr (kind 30303)
/// Données calculées localement depuis le cache Nostr — pas de serveur central
class DashboardView extends StatefulWidget {
  final User user;

  const DashboardView({Key? key, required this.user}) : super(key: key);

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final _storageService = StorageService();
  
  late TabController _tabController;
  
  DashboardMetrics? _metrics;
  List<Bon> _allBons = [];
  bool _isLoading = true;

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

  Future<void> _loadMetrics() async {
    setState(() => _isLoading = true);
    
    try {
      final bons = await _storageService.getBons();
      final metrics = _calculateMetrics(bons);
      
      setState(() {
        _allBons = bons;
        _metrics = metrics;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement métriques: $e');
      setState(() => _isLoading = false);
    }
  }

  DashboardMetrics _calculateMetrics(List<Bon> bons) {
    final now = DateTime.now();
    final last7Days = now.subtract(const Duration(days: 7));
    final last30Days = now.subtract(const Duration(days: 30));
    
    // Volume total en circulation (bons actifs)
    final totalVolume = bons
        .where((b) => b.status == BonStatus.active)
        .fold<double>(0.0, (sum, bon) => sum + bon.value);
    
    // Nombre de commerçants actifs (émetteurs uniques)
    final activeMerchants = bons
        .map((b) => b.issuerNpub)
        .toSet()
        .length;
    
    // Flux de la semaine
    final weeklyInflow = bons
        .where((b) => b.createdAt.isAfter(last7Days) && b.status == BonStatus.active)
        .fold<double>(0.0, (sum, bon) => sum + bon.value);
    
    final weeklyOutflow = bons
        .where((b) => 
            b.createdAt.isAfter(last7Days) && 
            (b.status == BonStatus.spent || b.status == BonStatus.burned))
        .fold<double>(0.0, (sum, bon) => sum + bon.value);
    
    // Bons créés cette semaine
    final weeklyBons = bons.where((b) => b.createdAt.isAfter(last7Days)).length;
    
    // Bons créés ce mois
    final monthlyBons = bons.where((b) => b.createdAt.isAfter(last30Days)).length;
    
    // Top 5 émetteurs (agrégés par valeur)
    final issuerTotals = <String, double>{};
    for (final bon in bons) {
      if (bon.status == BonStatus.active) {
        issuerTotals[bon.issuerName] = (issuerTotals[bon.issuerName] ?? 0) + bon.value;
      }
    }
    final topIssuers = issuerTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = topIssuers.take(5).toList();
    
    // Taux de croissance (semaine vs semaine précédente)
    final previousWeek = now.subtract(const Duration(days: 14));
    final previousWeekBons = bons
        .where((b) => b.createdAt.isAfter(previousWeek) && b.createdAt.isBefore(last7Days))
        .length;
    final growthRate = previousWeekBons > 0
        ? ((weeklyBons - previousWeekBons) / previousWeekBons) * 100
        : 100.0;
    
    // Moyenne journalière
    final dailyAverage = totalVolume / 30;
    
    return DashboardMetrics(
      totalVolume: totalVolume,
      activeMerchants: activeMerchants,
      weeklyInflow: weeklyInflow,
      weeklyOutflow: weeklyOutflow,
      weeklyBons: weeklyBons,
      monthlyBons: monthlyBons,
      topIssuers: top5,
      growthRate: growthRate,
      dailyAverage: dailyAverage,
      totalBons: bons.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Dashboard Économique'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadMetrics(),
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
          ? const Center(child: CircularProgressIndicator())
          : _metrics == null
              ? _buildEmptyState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildChartsTab(),
                    _buildTopIssuersTab(),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bar_chart_outlined,
            size: 120,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 24),
          Text(
            'Aucune donnée disponible',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[400],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Commencez par créer des bons',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ONGLET 1 : VUE D'ENSEMBLE
  // ============================================================
  
  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadMetrics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Volume total en circulation
          _buildVolumeCard(),
          const SizedBox(height: 16),
          
          // Statistiques clés
          _buildKeyStatsGrid(),
          const SizedBox(height: 16),
          
          // Flux de la semaine
          _buildWeeklyFlowCard(),
          const SizedBox(height: 16),
          
          // Taux de croissance
          _buildGrowthCard(),
        ],
      ),
    );
  }

  Widget _buildVolumeCard() {
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
            color: const Color(0xFFFFB347).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.account_balance_wallet, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                'Volume Total en Circulation',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${_metrics!.totalVolume.toStringAsFixed(2)} Ẑ',
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Moyenne: ${_metrics!.dailyAverage.toStringAsFixed(2)} Ẑ/jour',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Commerçants actifs',
          '${_metrics!.activeMerchants}',
          Icons.store,
          const Color(0xFF0A7EA4),
        ),
        _buildStatCard(
          'Total bons',
          '${_metrics!.totalBons}',
          Icons.receipt_long,
          const Color(0xFF8B5CF6),
        ),
        _buildStatCard(
          'Créés cette semaine',
          '${_metrics!.weeklyBons}',
          Icons.new_releases,
          const Color(0xFF10B981),
        ),
        _buildStatCard(
          'Créés ce mois',
          '${_metrics!.monthlyBons}',
          Icons.calendar_month,
          const Color(0xFFF59E0B),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyFlowCard() {
    final netFlow = _metrics!.weeklyInflow - _metrics!.weeklyOutflow;
    final isPositive = netFlow >= 0;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Flux de la semaine',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          
          // Entrées
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_downward, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Entrées', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      '${_metrics!.weeklyInflow.toStringAsFixed(2)} Ẑ',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Sorties
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_upward, color: Colors.red, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sorties', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      '${_metrics!.weeklyOutflow.toStringAsFixed(2)} Ẑ',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const Divider(color: Colors.white24, height: 32),
          
          // Flux net
          Row(
            children: [
              Icon(
                isPositive ? Icons.trending_up : Icons.trending_down,
                color: isPositive ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Flux net', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      '${isPositive ? '+' : ''}${netFlow.toStringAsFixed(2)} Ẑ',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthCard() {
    final isPositive = _metrics!.growthRate >= 0;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isPositive
            ? const Color(0xFF0A7EA4).withOpacity(0.2)
            : Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPositive ? const Color(0xFF0A7EA4) : Colors.red,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPositive ? Icons.trending_up : Icons.trending_down,
            color: isPositive ? const Color(0xFF0A7EA4) : Colors.red,
            size: 48,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Taux de croissance hebdo',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  '${isPositive ? '+' : ''}${_metrics!.growthRate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? const Color(0xFF0A7EA4) : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ONGLET 2 : GRAPHIQUES
  // ============================================================
  
  Widget _buildChartsTab() {
    return RefreshIndicator(
      onRefresh: _loadMetrics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Graphe en ligne : évolution sur 30 jours
          _buildLineChart(),
          const SizedBox(height: 24),
          
          // Graphe en barres : flux entrées/sorties
          _buildBarChart(),
          const SizedBox(height: 24),
          
          // Graphe circulaire : répartition par statut
          _buildPieChart(),
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    // Calculer l'évolution sur 30 jours
    final now = DateTime.now();
    final chartData = List.generate(30, (index) {
      final date = now.subtract(Duration(days: 29 - index));
      final dayBons = _allBons.where((bon) {
        return bon.createdAt.year == date.year &&
               bon.createdAt.month == date.month &&
               bon.createdAt.day == date.day &&
               bon.status == BonStatus.active;
      });
      final total = dayBons.fold<double>(0.0, (sum, bon) => sum + bon.value);
      return FlSpot(index.toDouble(), total);
    });
    
    // Calculer le cumul
    double cumul = 0;
    final cumulData = chartData.map((spot) {
      cumul += spot.y;
      return FlSpot(spot.x, cumul);
    }).toList();
    
    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Évolution du volume (30 jours)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white12,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 5,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() % 5 == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'J${value.toInt() + 1}',
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: cumulData,
                    isCurved: true,
                    color: const Color(0xFFFFB347),
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFFB347).withOpacity(0.3),
                          const Color(0xFFFFB347).withOpacity(0.05),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    // Flux des 7 derniers jours
    final now = DateTime.now();
    final barData = List.generate(7, (index) {
      final date = now.subtract(Duration(days: 6 - index));
      final dayInflowBons = _allBons.where((bon) {
        return bon.createdAt.year == date.year &&
               bon.createdAt.month == date.month &&
               bon.createdAt.day == date.day &&
               bon.status == BonStatus.active;
      });
      final inflow = dayInflowBons.fold<double>(0.0, (sum, bon) => sum + bon.value);
      
      final dayOutflowBons = _allBons.where((bon) {
        return bon.createdAt.year == date.year &&
               bon.createdAt.month == date.month &&
               bon.createdAt.day == date.day &&
               (bon.status == BonStatus.spent || bon.status == BonStatus.burned);
      });
      final outflow = dayOutflowBons.fold<double>(0.0, (sum, bon) => sum + bon.value);
      
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: inflow,
            color: Colors.green,
            width: 12,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          BarChartRodData(
            toY: outflow,
            color: Colors.red,
            width: 12,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    });
    
    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Flux entrées vs sorties (7 jours)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('Entrées', Colors.green),
              const SizedBox(width: 20),
              _buildLegendItem('Sorties', Colors.red),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: BarChart(
              BarChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
                        if (value.toInt() >= 0 && value.toInt() < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              days[value.toInt()],
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: barData,
                barTouchData: BarTouchData(enabled: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildPieChart() {
    // Répartition par statut
    final statusCounts = <BonStatus, int>{};
    for (final bon in _allBons) {
      statusCounts[bon.status] = (statusCounts[bon.status] ?? 0) + 1;
    }
    
    final sections = statusCounts.entries.map((entry) {
      final color = _getStatusColor(entry.key);
      final percentage = (entry.value / _allBons.length) * 100;
      
      return PieChartSectionData(
        value: entry.value.toDouble(),
        title: '${percentage.toStringAsFixed(1)}%',
        color: color,
        radius: 100,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
    
    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Répartition par statut',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sections: sections,
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: statusCounts.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getStatusColor(entry.key),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${entry.key.name} (${entry.value})',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(BonStatus status) {
    switch (status) {
      case BonStatus.active:
        return Colors.green;
      case BonStatus.pending:
        return Colors.orange;
      case BonStatus.expired:
        return Colors.red;
      case BonStatus.spent:
        return Colors.blue;
      case BonStatus.burned:
        return Colors.grey;
      default:
        return Colors.white70;
    }
  }

  // ============================================================
  // ONGLET 3 : TOP ÉMETTEURS
  // ============================================================
  
  Widget _buildTopIssuersTab() {
    return RefreshIndicator(
      onRefresh: _loadMetrics,
      child: _metrics!.topIssuers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.leaderboard_outlined,
                    size: 80,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucun émetteur actif',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // En-tête
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.emoji_events, color: Colors.white, size: 32),
                          SizedBox(width: 12),
                          Text(
                            'Top 5 Émetteurs',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Classement par valeur en circulation',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Liste des top émetteurs
                ...List.generate(_metrics!.topIssuers.length, (index) {
                  final issuer = _metrics!.topIssuers[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildTopIssuerCard(index + 1, issuer.key, issuer.value),
                  );
                }),
              ],
            ),
    );
  }

  Widget _buildTopIssuerCard(int rank, String issuerName, double value) {
    final medalColors = [
      const Color(0xFFFFD700), // Or
      const Color(0xFFC0C0C0), // Argent
      const Color(0xFFCD7F32), // Bronze
    ];
    final medalColor = rank <= 3 ? medalColors[rank - 1] : const Color(0xFF8B5CF6);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rank <= 3 ? medalColor.withOpacity(0.5) : Colors.white24,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          // Médaille/Rang
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: medalColor.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: medalColor, width: 2),
            ),
            child: Center(
              child: rank <= 3
                  ? Icon(Icons.emoji_events, color: medalColor, size: 28)
                  : Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: medalColor,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Infos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issuerName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'En circulation',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          
          // Valeur
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${value.toStringAsFixed(2)} Ẑ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: medalColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${((value / _metrics!.totalVolume) * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Modèle de métriques du dashboard
class DashboardMetrics {
  final double totalVolume;
  final int activeMerchants;
  final double weeklyInflow;
  final double weeklyOutflow;
  final int weeklyBons;
  final int monthlyBons;
  final List<MapEntry<String, double>> topIssuers;
  final double growthRate;
  final double dailyAverage;
  final int totalBons;

  DashboardMetrics({
    required this.totalVolume,
    required this.activeMerchants,
    required this.weeklyInflow,
    required this.weeklyOutflow,
    required this.weeklyBons,
    required this.monthlyBons,
    required this.topIssuers,
    required this.growthRate,
    required this.dailyAverage,
    required this.totalBons,
  });
}
