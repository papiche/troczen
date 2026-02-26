import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive.dart';
import '../../models/user.dart';
import '../../services/storage_service.dart';
import '../../services/logger_service.dart';
import '../../services/cache_database_service.dart';
// Import des nouveaux widgets Alchimiste
import '../../widgets/alchimiste/metric_card.dart';
import '../../widgets/alchimiste/time_filter_bar.dart';
import 'circuits_graph_view.dart';
import '../../services/notification_service.dart';

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
    _tabController = TabController(length: 4, vsync: this);
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

      // Calcul de la vélocité
      double velocity = 0.0;
      if (currentAgg.count > 0) {
        velocity = currentAgg.transfersCount / currentAgg.count;
      }

      // TODO: Calcul de l'indice de confiance global (nécessite les profils Nostr)
      double globalTrustIndex = 0.0;

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
          velocity: velocity,
          globalTrustIndex: globalTrustIndex,
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
            icon: const Icon(Icons.download),
            onPressed: _exportMarketReport,
            tooltip: 'Exporter Rapport de Marché',
          ),
          StreamBuilder<List<MarketNotification>>(
            stream: NotificationService().notificationsStream,
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? [];
              final unreadCount = notifications.length; // Simplification: on compte tout comme non lu
              
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () => _showNotificationsDialog(context, notifications),
                    tooltip: 'Signaux Alchimiques',
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
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
                ],
              );
            },
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
          isScrollable: true,
          tabs: const [
            Tab(text: 'Vue d\'ensemble'),
            Tab(text: 'Graphiques'),
            Tab(text: 'Top émetteurs'),
            Tab(text: 'Journal'),
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
                            _buildJournalTab(),
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
            MetricCard(
              label: 'Vélocité (V)',
              value: _metrics!.velocity.toStringAsFixed(2),
              icon: Icons.speed,
              color: Colors.purpleAccent,
            ),
            MetricCard(
              label: 'Confiance Globale',
              value: '${(_metrics!.globalTrustIndex * 100).toStringAsFixed(0)}%',
              icon: Icons.verified_user,
              color: Colors.blueAccent,
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Info sur le total historique
        _buildTotalHistoryInfo(),
      ],
    );
  }

  void _showNotificationsDialog(BuildContext context, List<MarketNotification> notifications) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Signaux Alchimiques', style: TextStyle(color: Colors.white)),
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
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: notifications.isEmpty
                ? const Center(child: Text('Aucun signal pour le moment.', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
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
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer', style: TextStyle(color: Color(0xFFFFB347))),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportMarketReport() async {
    if (_metrics == null) return;

    try {
      setState(() => _isLoading = true);

      final archive = Archive();

      // 1. market_summary.json
      final summary = {
        'totalVolume': _metrics!.totalVolume,
        'activeMerchants': _metrics!.activeMerchants,
        'newBonsCount': _metrics!.newBonsCount,
        'spentVolume': _metrics!.spentVolume,
        'velocity': _metrics!.velocity,
        'globalTrustIndex': _metrics!.globalTrustIndex,
        'totalMarketBons': _metrics!.totalMarketBons,
        'generatedAt': DateTime.now().toIso8601String(),
      };
      final summaryBytes = utf8.encode(jsonEncode(summary));
      archive.addFile(ArchiveFile('market_summary.json', summaryBytes.length, summaryBytes));

      // 2. ledger.csv
      final edges = await _storageService.getTransferSummary();
      final ledgerBuffer = StringBuffer();
      ledgerBuffer.writeln('from_npub,to_npub,total_value,transfer_count,is_loop');
      for (final edge in edges) {
        ledgerBuffer.writeln('${edge.fromNpub},${edge.toNpub},${edge.totalValue},${edge.transferCount},${edge.isLoop}');
      }
      final ledgerBytes = utf8.encode(ledgerBuffer.toString());
      archive.addFile(ArchiveFile('ledger.csv', ledgerBytes.length, ledgerBytes));

      // 3. trust_graph.csv
      final n2Contacts = await _storageService.getN2Contacts();
      final trustBuffer = StringBuffer();
      trustBuffer.writeln('from_npub,to_npub');
      for (final contact in n2Contacts) {
        trustBuffer.writeln('${contact['via_n1_npub']},${contact['npub']}');
      }
      final trustBytes = utf8.encode(trustBuffer.toString());
      archive.addFile(ArchiveFile('trust_graph.csv', trustBytes.length, trustBytes));

      // Créer le ZIP
      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      final tempDir = await getTemporaryDirectory();
      final zipFile = File('${tempDir.path}/market_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip');
      await zipFile.writeAsBytes(zipData);

      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(zipFile.path)],
            text: 'Rapport de Marché TrocZen',
            subject: 'Export Marché TrocZen',
          ),
        );
      }
    } catch (e) {
      Logger.error('DashboardView', 'Erreur export rapport', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'export : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    
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
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _storageService.getBonsForDate(dateStr),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB347)));
                    }
                    
                    if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('Aucun bon créé à cette date', style: TextStyle(color: Colors.white54)),
                      );
                    }

                    final bons = snapshot.data!;
                    
                    return ListView.builder(
                      itemCount: bons.length,
                      itemBuilder: (context, index) {
                        final bon = bons[index];
                        final value = (bon['value'] as num?)?.toDouble() ?? 0.0;
                        final issuerName = bon['issuerName'] as String? ?? 'Anonyme';
                        final rarity = bon['rarity'] as String? ?? 'common';
                        
                        return Card(
                          color: const Color(0xFF2A2A2A),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.confirmation_number, color: Color(0xFFFFB347)),
                            title: Text(
                              '${value.toStringAsFixed(0)} Ẑ',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Émis par: $issuerName • $rarity',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ),
                        );
                      },
                    );
                  },
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

  // ============================================================
  // ONGLET 4 : JOURNAL D'AUDIT
  // ============================================================
  
  double _minAmountFilter = 0.0;
  String _rarityFilter = 'Toutes';

  Widget _buildJournalTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<double>(
                  initialValue: _minAmountFilter,
                  decoration: const InputDecoration(
                    labelText: 'Montant Min',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  dropdownColor: const Color(0xFF1E1E1E),
                  items: const [
                    DropdownMenuItem(value: 0.0, child: Text('> 0 ẐEN')),
                    DropdownMenuItem(value: 10.0, child: Text('> 10 ẐEN')),
                    DropdownMenuItem(value: 50.0, child: Text('> 50 ẐEN')),
                    DropdownMenuItem(value: 100.0, child: Text('> 100 ẐEN')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _minAmountFilter = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _rarityFilter,
                  decoration: const InputDecoration(
                    labelText: 'Rareté',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  dropdownColor: const Color(0xFF1E1E1E),
                  items: const [
                    DropdownMenuItem(value: 'Toutes', child: Text('Toutes')),
                    DropdownMenuItem(value: 'common', child: Text('Commune')),
                    DropdownMenuItem(value: 'rare', child: Text('Rare')),
                    DropdownMenuItem(value: 'epic', child: Text('Épique')),
                    DropdownMenuItem(value: 'legendary', child: Text('Légendaire')),
                    DropdownMenuItem(value: 'bootstrap', child: Text('Bootstrap')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _rarityFilter = value);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _storageService.getMarketBonsData(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB347)));
              }
              
              if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text('Aucun événement dans le journal', style: TextStyle(color: Colors.white54)),
                );
              }

              var events = snapshot.data!;
              
              // Appliquer les filtres
              events = events.where((e) {
                final value = (e['value'] as num?)?.toDouble() ?? 0.0;
                final rarity = e['rarity'] as String? ?? 'common';
                
                if (value < _minAmountFilter) return false;
                if (_rarityFilter != 'Toutes' && rarity != _rarityFilter) return false;
                
                return true;
              }).toList();

              if (events.isEmpty) {
                return const Center(
                  child: Text('Aucun événement ne correspond aux filtres', style: TextStyle(color: Colors.white54)),
                );
              }

              // Trier par date décroissante
              events.sort((a, b) {
                final dateA = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
                final dateB = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
                return dateB.compareTo(dateA);
              });

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  final isBurn = event['status'] == 'burned';
                  final value = (event['value'] as num?)?.toDouble() ?? 0.0;
                  final date = DateTime.tryParse(event['createdAt'] ?? '') ?? DateTime.now();
                  final rarity = event['rarity'] as String? ?? 'common';
                  
                  return Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        isBurn ? Icons.local_fire_department : Icons.swap_horiz,
                        color: isBurn ? Colors.redAccent : Colors.greenAccent,
                      ),
                      title: Text(
                        isBurn ? 'Destruction de Bon' : 'Émission de Bon',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${DateFormat('dd/MM/yyyy HH:mm').format(date)} • $rarity',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      trailing: Text(
                        '${value.toStringAsFixed(0)} Ẑ',
                        style: TextStyle(
                          color: isBurn ? Colors.redAccent : Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
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
  final double velocity;
  final double globalTrustIndex;

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
    this.velocity = 0.0,
    this.globalTrustIndex = 0.0,
  });
}