import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/bon.dart';
import '../services/storage_service.dart';
import '../services/audit_trail_service.dart';
import '../services/logger_service.dart';

/// Dashboard Marchand TrocZen
/// Analytics économiques basées uniquement sur P3 (kind 30303)
/// ZÉRO donnée client - Offline-first - Temps réel
class MerchantDashboardScreen extends StatefulWidget {
  final String merchantNpub;
  final String merchantName;
  final String marketName;

  const MerchantDashboardScreen({
    super.key,
    required this.merchantNpub,
    required this.merchantName,
    required this.marketName,
  });

  @override
  State<MerchantDashboardScreen> createState() => _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState extends State<MerchantDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _storageService = StorageService();
  final _auditService = AuditTrailService();

  late TabController _tabController;

  // Métriques calculées
  DashboardMetrics? _metrics;
  bool _isLoading = true;

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
      final transfers = await _auditService.getAllTransfers();

      _metrics = _calculateMetrics(bons, transfers);
    } catch (e) {
      Logger.error('MerchantDashboard', 'Erreur chargement metrics', e);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  DashboardMetrics _calculateMetrics(
    List<Bon> bons,
    List<Map<String, dynamic>> transfers,
  ) {
    final now = DateTime.now();

    // Filtrer bons du marchand
    final myBons = bons.where((b) => b.issuerNpub == widget.merchantNpub).toList();

    // 1️⃣ Bons actifs (non expirés)
    final activeBons = myBons.where((b) => 
      b.expiresAt != null && b.expiresAt!.isAfter(now)
    ).toList();

    // 2️⃣ Valeur totale
    final totalValue = activeBons.fold<double>(
      0.0,
      (sum, b) => sum + b.value,
    );

    // 3️⃣ Bons brûlés (encaissés)
    final burnedBons = myBons.where((b) => b.status == BonStatus.burned).length;

    // 4️⃣ Bons expirés
    final expiredBons = myBons.where((b) => 
      b.expiresAt != null && 
      b.expiresAt!.isBefore(now) && 
      b.status != BonStatus.burned
    ).length;

    // 5️⃣ Taux d'encaissement
    final encashRate = myBons.isNotEmpty ? burnedBons / myBons.length : 0.0;

    // 6️⃣ Taux d'expiration
    final expireRate = myBons.isNotEmpty ? expiredBons / myBons.length : 0.0;

    // 7️⃣ Vitesse de circulation moyenne (en heures par transfert)
    final circulationSpeeds = <double>[];
    for (final bon in myBons) {
      if (bon.transferCount != null && bon.transferCount! > 0) {
        final ageHours = now.difference(bon.createdAt).inHours;
        final speed = ageHours / bon.transferCount!;
        circulationSpeeds.add(speed);
      }
    }
    final avgSpeed = circulationSpeeds.isNotEmpty
        ? circulationSpeeds.reduce((a, b) => a + b) / circulationSpeeds.length
        : 0.0;

    // 8️⃣ Distribution par valeur
    final valueDistribution = <double, int>{};
    for (final bon in myBons) {
      valueDistribution[bon.value] = (valueDistribution[bon.value] ?? 0) + 1;
    }

    // 9️⃣ Distribution par rareté
    final rarityDistribution = <String, int>{};
    for (final bon in myBons) {
      final rarity = bon.rarity ?? 'common';
      rarityDistribution[rarity] = (rarityDistribution[rarity] ?? 0) + 1;
    }

    // 🔟 Flux temporel (par heure)
    final hourlyFlow = List.generate(24, (_) => 0);
    for (final bon in myBons) {
      final hour = bon.createdAt.hour;
      hourlyFlow[hour]++;
    }

    // 1️⃣1️⃣ Réseau (acceptation croisée)
    final acceptedByOthers = transfers.where((t) =>
      t['receiver_npub'] != widget.merchantNpub &&
      myBons.any((b) => b.bonId == t['bon_id'])
    ).length;
    final networkRate = myBons.isNotEmpty ? acceptedByOthers / myBons.length : 0.0;

    // 1️⃣2️⃣ Score santé (0-100)
    final healthScore = _calculateHealthScore(
      encashRate: encashRate,
      expireRate: expireRate,
      avgSpeed: avgSpeed,
      networkRate: networkRate,
    );

    // 1️⃣3️⃣ Dernière activité
    final lastTransfer = transfers.isNotEmpty
        ? DateTime.fromMillisecondsSinceEpoch(transfers.first['timestamp'] as int)
        : null;

    return DashboardMetrics(
      totalBons: myBons.length,
      activeBons: activeBons.length,
      totalValue: totalValue,
      burnedBons: burnedBons,
      expiredBons: expiredBons,
      encashRate: encashRate,
      expireRate: expireRate,
      avgCirculationSpeed: avgSpeed,
      valueDistribution: valueDistribution,
      rarityDistribution: rarityDistribution,
      hourlyFlow: hourlyFlow,
      networkRate: networkRate,
      healthScore: healthScore,
      lastActivity: lastTransfer,
    );
  }

  double _calculateHealthScore({
    required double encashRate,
    required double expireRate,
    required double avgSpeed,
    required double networkRate,
  }) {
    // Score normalisé [0-100]
    // avgSpeed est maintenant en heures par transfert
    final encashScore = encashRate * 30; // Max 30 points
    // Vitesse rapide = < 24h, normale = < 7 jours, lente = > 7 jours
    // Score inversement proportionnel : plus c'est rapide, plus le score est élevé
    final speedScore = avgSpeed > 0 ? (24 / avgSpeed).clamp(0.0, 1.0) * 30 : 0; // Max 30 points
    final expireScore = (1 - expireRate) * 20; // Max 20 points
    final networkScore = networkRate * 20; // Max 20 points

    return (encashScore + speedScore + expireScore + networkScore).clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🐝 ${widget.merchantName}'),
            Text(
              widget.marketName,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFB347),
          tabs: const [
            Tab(text: 'Vue Live'),
            Tab(text: 'Analyse'),
            Tab(text: 'Pilotage'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMetrics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLiveView(),
                _buildAnalysisView(),
                _buildControlView(),
              ],
            ),
    );
  }

  // ==================== ÉCRAN 1 : VUE LIVE ====================

  Widget _buildLiveView() {
    if (_metrics == null) return const SizedBox();

    final health = _metrics!.healthScore;
    final healthColor = health >= 70
        ? Colors.green
        : health >= 40
            ? Colors.orange
            : Colors.red;
    final healthLabel = health >= 70
        ? '🟢 Fluide'
        : health >= 40
            ? '🟡 Attention'
            : '🔴 Problème';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // État du stand
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [healthColor.withOpacity(0.2), healthColor.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: healthColor, width: 2),
            ),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: healthColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${health.toInt()}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: healthColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'État du Stand',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        healthLabel,
                        style: TextStyle(
                          color: healthColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Métriques principales
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Bons actifs',
                  value: '${_metrics!.activeBons}',
                  color: const Color(0xFFFFB347),
                  icon: Icons.local_offer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  title: 'Valeur totale',
                  value: '${_metrics!.totalValue.toInt()} ẐEN',
                  color: Colors.green,
                  icon: Icons.account_balance_wallet,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Vitesse de circulation
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vitesse de circulation',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSpeedIndicator(_metrics!.avgCirculationSpeed),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Dernière activité
          if (_metrics!.lastActivity != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text(
                    'Dernier encaissement : ${_formatTimeSince(_metrics!.lastActivity!)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Alertes
          if (_metrics!.expiredBons > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 12),
                  Text(
                    '⏳ ${_metrics!.expiredBons} bon(s) proche(s) expiration',
                    style: const TextStyle(color: Colors.orange),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedIndicator(double avgHours) {
    // Seuils réalistes pour une monnaie locale physique/numérique
    // Rapide : < 24h par transfert
    // Normal : < 7 jours (168h) par transfert
    // Lent : > 7 jours par transfert
    final speed = avgHours < 24
        ? 'Rapide'
        : avgHours < (24 * 7)
            ? 'Normal'
            : 'Lent';

    final color = avgHours < 24
        ? Colors.green
        : avgHours < (24 * 7)
            ? Colors.orange
            : Colors.red;

    final bars = avgHours < 24
        ? 5
        : avgHours < (24 * 7)
            ? 3
            : 1;

    return Row(
      children: [
        ...List.generate(5, (i) {
          return Container(
            width: 30,
            height: 40 + (i * 10.0),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: i < bars ? color : Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
        const SizedBox(width: 16),
        Text(
          speed,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ==================== ÉCRAN 2 : ANALYSE ====================

  Widget _buildAnalysisView() {
    if (_metrics == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flux temporel
          _buildSectionTitle('Flux temporel (aujourd\'hui)'),
          const SizedBox(height: 16),
          _buildHourlyFlowChart(),

          const SizedBox(height: 32),

          // Distribution par valeur
          _buildSectionTitle('Distribution par valeur'),
          const SizedBox(height: 16),
          _buildValueDistributionChart(),

          const SizedBox(height: 32),

          // Taux d'encaissement
          _buildSectionTitle('Taux d\'encaissement'),
          const SizedBox(height: 16),
          _buildEncashmentStats(),

          const SizedBox(height: 32),

          // Réseau marchand
          _buildSectionTitle('Circulation réseau'),
          const SizedBox(height: 16),
          _buildNetworkStats(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildHourlyFlowChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() % 4 == 0) {
                    return Text(
                      '${value.toInt()}h',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                24,
                (i) => FlSpot(i.toDouble(), _metrics!.hourlyFlow[i].toDouble()),
              ),
              isCurved: true,
              color: const Color(0xFFFFB347),
              barWidth: 3,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFFFFB347).withOpacity(0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValueDistributionChart() {
    final sorted = _metrics!.valueDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: sorted.map((entry) {
          final percentage = _metrics!.totalBons > 0
              ? (entry.value / _metrics!.totalBons) * 100
              : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${entry.key.toInt()} ẐEN',
                      style: const TextStyle(color: Colors.white),
                    ),
                    Text(
                      '${entry.value} (${percentage.toStringAsFixed(0)}%)',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: Colors.grey[800],
                    color: const Color(0xFFFFB347),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEncashmentStats() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildStatRow('Bons émis', '${_metrics!.totalBons}'),
          _buildStatRow('Bons encaissés', '${_metrics!.burnedBons}'),
          _buildStatRow('Expirés', '${_metrics!.expiredBons}'),
          _buildStatRow('En circulation', '${_metrics!.activeBons}'),
          const Divider(color: Colors.white24, height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Taux d\'encaissement',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${(_metrics!.encashRate * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Color(0xFFFFB347),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkStats() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Taux réseau : ${(_metrics!.networkRate * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Ton bon est aussi accepté chez :',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          // TODO: Liste dynamique depuis P3
          _buildMerchantChip('Boulanger'),
          _buildMerchantChip('Fromager'),
          _buildMerchantChip('Maraîcher'),
        ],
      ),
    );
  }

  Widget _buildMerchantChip(String name) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Text(name, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  // ==================== ÉCRAN 3 : PILOTAGE ====================

  Widget _buildControlView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildControlSection(
            title: 'Gestion des bons',
            actions: [
              _buildActionButton(
                label: 'Émettre un bon',
                icon: Icons.add_circle,
                color: Colors.green,
                onTap: () {
                  // TODO: Navigation vers CreateBonScreen
                },
              ),
              _buildActionButton(
                label: 'Réémettre un bon perdu',
                icon: Icons.refresh,
                color: Colors.orange,
                onTap: () {},
              ),
              _buildActionButton(
                label: 'Révoquer un bon',
                icon: Icons.block,
                color: Colors.red,
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 24),

          _buildControlSection(
            title: 'Export & Partage',
            actions: [
              _buildActionButton(
                label: 'Export PDF (fin de marché)',
                icon: Icons.picture_as_pdf,
                color: Colors.blue,
                onTap: () async {
                  // TODO: Générer PDF
                },
              ),
              _buildActionButton(
                label: 'QR Statistiques publiques',
                icon: Icons.qr_code,
                color: const Color(0xFFFFB347),
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlSection({
    required String title,
    required List<Widget> actions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...actions,
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(16),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }

  String _formatTimeSince(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    return 'il y a ${diff.inDays}j';
  }
}

// ==================== MODÈLE DE DONNÉES ====================

class DashboardMetrics {
  final int totalBons;
  final int activeBons;
  final double totalValue;
  final int burnedBons;
  final int expiredBons;
  final double encashRate;
  final double expireRate;
  final double avgCirculationSpeed; // en minutes
  final Map<double, int> valueDistribution;
  final Map<String, int> rarityDistribution;
  final List<int> hourlyFlow;
  final double networkRate;
  final double healthScore;
  final DateTime? lastActivity;

  DashboardMetrics({
    required this.totalBons,
    required this.activeBons,
    required this.totalValue,
    required this.burnedBons,
    required this.expiredBons,
    required this.encashRate,
    required this.expireRate,
    required this.avgCirculationSpeed,
    required this.valueDistribution,
    required this.rarityDistribution,
    required this.hourlyFlow,
    required this.networkRate,
    required this.healthScore,
    this.lastActivity,
  });
}
