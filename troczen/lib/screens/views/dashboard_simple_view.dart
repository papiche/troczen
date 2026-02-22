import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../services/storage_service.dart';
import '../../services/logger_service.dart';

/// DashboardSimpleView — Tableau de bord simplifié pour les Artisans
/// 
/// Affiche uniquement les métriques comptables essentielles :
/// - Solde total en ẐEN
/// - Entrées/sorties de la semaine
/// - Bons actifs, expirés, utilisés
/// - Liste des dernières transactions
/// 
/// ✅ Mode Artisan : Simplicité et clarté, pas de mathématiques complexes
class DashboardSimpleView extends StatefulWidget {
  final User user;

  const DashboardSimpleView({super.key, required this.user});

  @override
  State<DashboardSimpleView> createState() => _DashboardSimpleViewState();
}

class _DashboardSimpleViewState extends State<DashboardSimpleView>
    with AutomaticKeepAliveClientMixin {
  final _storageService = StorageService();
  
  bool _isLoading = true;
  List<Bon> _bons = [];
  
  // Métriques simples
  double _totalBalance = 0.0;
  double _weeklyIncome = 0.0;
  double _weeklyExpense = 0.0;
  int _activeBonsCount = 0;
  int _expiredBonsCount = 0;
  int _spentBonsCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final bons = await _storageService.getBons();
      
      setState(() {
        _bons = bons;
        _calculateMetrics();
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('DashboardSimpleView', 'Erreur chargement données', e);
      setState(() => _isLoading = false);
    }
  }

  void _calculateMetrics() {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    
    // Réinitialiser les métriques
    _totalBalance = 0.0;
    _weeklyIncome = 0.0;
    _weeklyExpense = 0.0;
    _activeBonsCount = 0;
    _expiredBonsCount = 0;
    _spentBonsCount = 0;
    
    for (final bon in _bons) {
      // Compter par statut
      if (bon.status == BonStatus.active && !bon.isExpired) {
        _activeBonsCount++;
        _totalBalance += bon.value;
      } else if (bon.isExpired) {
        _expiredBonsCount++;
      } else if (bon.status == BonStatus.spent) {
        _spentBonsCount++;
      }
      
      // Calculer entrées/sorties de la semaine
      final createdThisWeek = bon.createdAt.isAfter(weekAgo);
      
      if (createdThisWeek) {
        // Si je suis l'émetteur, c'est une sortie (j'ai créé un bon)
        if (bon.issuerNpub == widget.user.npub) {
          _weeklyExpense += bon.value;
        } else {
          // Sinon, c'est un revenu (j'ai reçu un bon)
          _weeklyIncome += bon.value;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('📊 Ma Caisse', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFB347)))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFFFFB347),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Solde total (carte principale)
                    _buildBalanceCard(),
                    const SizedBox(height: 16),
                    
                    // Résumé de la semaine
                    _buildWeeklySummary(),
                    const SizedBox(height: 16),
                    
                    // Statistiques des bons
                    _buildBonsStats(),
                    const SizedBox(height: 24),
                    
                    // Dernières transactions
                    _buildRecentTransactions(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBalanceCard() {
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
          const Text(
            'Solde Total',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _totalBalance.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'ẐEN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$_activeBonsCount bon${_activeBonsCount > 1 ? 's' : ''} actif${_activeBonsCount > 1 ? 's' : ''}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklySummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cette semaine',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildWeeklyItem(
                  icon: Icons.arrow_downward,
                  label: 'Reçus',
                  value: _weeklyIncome,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildWeeklyItem(
                  icon: Icons.arrow_upward,
                  label: 'Émis',
                  value: _weeklyExpense,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white24),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Solde de la semaine',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                '${(_weeklyIncome - _weeklyExpense).toStringAsFixed(2)} ẐEN',
                style: TextStyle(
                  color: (_weeklyIncome - _weeklyExpense) >= 0 ? Colors.green : Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyItem({
    required IconData icon,
    required String label,
    required double value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(2)} ẐEN',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBonsStats() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'État des bons',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatRow('Actifs', _activeBonsCount, Colors.green),
          const SizedBox(height: 12),
          _buildStatRow('Utilisés', _spentBonsCount, Colors.blue),
          const SizedBox(height: 12),
          _buildStatRow('Expirés', _expiredBonsCount, Colors.red),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int count, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        Text(
          count.toString(),
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactions() {
    // Trier les bons par date (plus récents d'abord)
    final sortedBons = List<Bon>.from(_bons)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // Prendre les 10 derniers
    final recentBons = sortedBons.take(10).toList();
    
    if (recentBons.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long, color: Colors.white38, size: 48),
              SizedBox(height: 16),
              Text(
                'Aucune transaction',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dernières transactions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...recentBons.map((bon) => _buildTransactionItem(bon)),
      ],
    );
  }

  Widget _buildTransactionItem(Bon bon) {
    final isIssuer = bon.issuerNpub == widget.user.npub;
    final isExpired = bon.isExpired;
    final isSpent = bon.status == BonStatus.spent;
    
    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    
    if (isExpired) {
      statusColor = Colors.red;
      statusIcon = Icons.warning;
      statusLabel = 'Expiré';
    } else if (isSpent) {
      statusColor = Colors.blue;
      statusIcon = Icons.check_circle;
      statusLabel = 'Utilisé';
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.radio_button_unchecked;
      statusLabel = 'Actif';
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bon.wish ?? bon.issuerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${isIssuer ? "Émis" : "Reçu"} • $statusLabel',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isIssuer ? "-" : "+"}${bon.value.toStringAsFixed(2)} ẐEN',
            style: TextStyle(
              color: isIssuer ? Colors.orange : Colors.green,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
