import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../models/market.dart';
import '../../models/nostr_profile.dart';
import '../../services/storage_service.dart';
import '../../services/nostr_service.dart';
import '../../services/crypto_service.dart';
import '../../services/logger_service.dart';
import '../market_screen.dart';
import '../create_bon_screen.dart';

/// ExploreView — Bons émis (P1) + Marché
/// Vue de l'émetteur avec deux sous-onglets
class ExploreView extends StatefulWidget {
  final User user;

  const ExploreView({super.key, required this.user});

  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final _storageService = StorageService();
  late TabController _tabController;
  
  // ✅ NOUVEAU: Support multi-marchés
  List<Market> _markets = [];
  Market? _selectedMarket;  // Marché sélectionné pour le filtre (null = tous)
  String _filterMode = 'all';  // 'all', 'active', ou nom du marché
  
  List<Bon> _myIssuedBons = [];
  List<NostrProfile> _marketProfiles = [];
  bool _isLoading = true;
  
  // ✅ WOTX: Mode Expert - Certification des pairs
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoadingRequests = false;
  bool _isAttesting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);  // ✅ WOTX: 3 onglets
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // ✅ NOUVEAU: Charger tous les marchés
      final markets = await _storageService.getMarkets();
      final activeMarket = await _storageService.getActiveMarket();
      
      final allBons = await _storageService.getBons();
      
      // Filtrer les bons dont l'utilisateur est l'émetteur (possède P1)
      final myBons = allBons.where((bon) =>
        bon.issuerNpub == widget.user.npub && bon.p1 != null
      ).toList();
      
      // Charger les profils du marché (simulé pour l'instant)
      final profiles = <NostrProfile>[];
      
      setState(() {
        _markets = markets;
        _selectedMarket = activeMarket;
        _myIssuedBons = myBons;
        _marketProfiles = profiles;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement données Explorer: $e');
      setState(() => _isLoading = false);
    }
  }
  
  /// ✅ NOUVEAU: Filtre les bons selon le marché sélectionné
  List<Bon> _getFilteredBons() {
    if (_filterMode == 'all') {
      return _myIssuedBons;
    }
    return _myIssuedBons.where((bon) => bon.marketName == _filterMode).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(),
            tooltip: 'Actualiser',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFB347),
          labelColor: const Color(0xFFFFB347),
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Mes émissions'),
            Tab(text: 'Marché'),
            Tab(text: 'Savoir-faire'),  // ✅ WOTX: Nouvel onglet
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMyEmissionsTab(),
                _buildMarketTab(),
                _buildSkillsTab(),  // ✅ WOTX: Nouvel onglet
              ],
            ),
    );
  }

  // ============================================================
  // SOUS-ONGLET 1 : MES ÉMISSIONS (P1)
  // ============================================================
  
  Widget _buildMyEmissionsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _myIssuedBons.isEmpty
          ? _buildNoEmissionsState()
          : CustomScrollView(
              slivers: [
                // En-tête avec statistiques
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildEmissionsHeader(),
                  ),
                ),
                
                // Graphe d'évolution
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildEvolutionChart(),
                  ),
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                
                // Liste des bons émis
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final bon = _myIssuedBons[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildIssuedBonCard(bon),
                        );
                      },
                      childCount: _myIssuedBons.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildNoEmissionsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 120,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 24),
          Text(
            'Aucun bon émis',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[400],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Créez votre premier bon pour\ncommencer à émettre de la monnaie',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _navigateToCreateBon(),
            icon: const Icon(Icons.add),
            label: const Text('Créer un bon'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB347),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmissionsHeader() {
    final totalValue = _myIssuedBons.fold<double>(0.0, (sum, bon) => sum + bon.value);
    final activeBons = _myIssuedBons.where((b) => b.status == BonStatus.active).length;
    
    return Container(
      padding: const EdgeInsets.all(20),
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
            'Mes émissions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Valeur totale', '${totalValue.toStringAsFixed(2)} Ẑ'),
              _buildStatItem('Bons actifs', '$activeBons'),
              _buildStatItem('Total émis', '${_myIssuedBons.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildEvolutionChart() {
    if (_myIssuedBons.isEmpty) return const SizedBox.shrink();
    
    // Calculer les données du graphe (derniers 7 jours)
    final now = DateTime.now();
    final chartData = List.generate(7, (index) {
      final date = now.subtract(Duration(days: 6 - index));
      final dayBons = _myIssuedBons.where((bon) {
        return bon.createdAt.year == date.year &&
               bon.createdAt.month == date.month &&
               bon.createdAt.day == date.day;
      });
      final total = dayBons.fold<double>(0.0, (sum, bon) => sum + bon.value);
      return FlSpot(index.toDouble(), total);
    });
    
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Évolution (7 derniers jours)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
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
                          return Text(
                            days[value.toInt()],
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                    spots: chartData,
                    isCurved: true,
                    color: const Color(0xFFFFB347),
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFFFB347).withOpacity(0.2),
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

  Widget _buildIssuedBonCard(Bon bon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bon.issuerName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bon.marketName,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${bon.value.toStringAsFixed(2)} Ẑ',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFB347),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(bon.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      bon.status.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(bon.status),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                _formatDate(bon.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(width: 16),
              if (bon.transferCount != null && bon.transferCount! > 0) ...[
                Icon(Icons.swap_horiz, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '${bon.transferCount} transferts',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _editBonProfile(bon),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Modifier'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB347),
                    side: const BorderSide(color: Color(0xFFFFB347)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
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

  void _editBonProfile(Bon bon) {
    // TODO: Implémenter l'édition du profil Nostr (tags kind 30303)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Édition du profil de ${bon.issuerName}'),
        backgroundColor: const Color(0xFF0A7EA4),
      ),
    );
  }

  // ============================================================
  // SOUS-ONGLET 2 : MARCHÉ
  // ============================================================
  
  Widget _buildMarketTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _markets.isEmpty
          ? _buildNoMarketState()
          : CustomScrollView(
              slivers: [
                // ✅ NOUVEAU: Filtres de marché
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildMarketFilter(),
                  ),
                ),
                
                // En-tête du marché
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildMarketHeader(),
                  ),
                ),
                
                // Filtres par tag
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildTagFilters(),
                  ),
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                
                // Liste des profils
                _marketProfiles.isEmpty
                    ? SliverFillRemaining(
                        child: _buildNoProfilesState(),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.75,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final profile = _marketProfiles[index];
                              return _buildProfileCard(profile);
                            },
                            childCount: _marketProfiles.length,
                          ),
                        ),
                      ),
              ],
            ),
    );
  }

  Widget _buildNoMarketState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.store_outlined,
            size: 120,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 24),
          Text(
            'Aucun marché configuré',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[400],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Rejoignez un marché local pour\ndécouvrir les commerçants',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _navigateToMarketConfig(),
            icon: const Icon(Icons.add),
            label: const Text('Rejoindre un marché'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB347),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ NOUVEAU: Filtres de marché avec ChoiceChip
  Widget _buildMarketFilter() {
    if (_markets.length <= 1) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filtrer par marché',
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Option "Tous"
              ChoiceChip(
                label: const Text('Tous'),
                selected: _filterMode == 'all',
                selectedColor: Colors.orange,
                backgroundColor: const Color(0xFF2A2A2A),
                labelStyle: TextStyle(
                  color: _filterMode == 'all' ? Colors.black : Colors.white,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _filterMode = 'all';
                      _selectedMarket = null;
                    });
                  }
                },
              ),
              // Un chip par marché
              ..._markets.map((market) => ChoiceChip(
                label: Text(market.displayName),
                selected: _filterMode == market.name,
                selectedColor: Colors.orange,
                backgroundColor: const Color(0xFF2A2A2A),
                labelStyle: TextStyle(
                  color: _filterMode == market.name ? Colors.black : Colors.white,
                ),
                avatar: market.isExpired
                    ? const Icon(Icons.warning, size: 16, color: Colors.red)
                    : null,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _filterMode = market.name;
                      _selectedMarket = market;
                    });
                  }
                },
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMarketHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A7EA4), Color(0xFF0D99C6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A7EA4).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.store, size: 32, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedMarket?.displayName ?? 'Tous les marchés',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_marketProfiles.length} commerçants actifs',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagFilters() {
    final tags = ['Tous', 'Commerce', 'Service', 'Artisan', 'Culture', 'Alimentation'];
    
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tags.length,
        itemBuilder: (context, index) {
          final isSelected = index == 0; // Par défaut, "Tous" est sélectionné
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(tags[index]),
              selected: isSelected,
              onSelected: (selected) {
                // TODO: Implémenter le filtrage
              },
              backgroundColor: const Color(0xFF1E1E1E),
              selectedColor: const Color(0xFFFFB347),
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected ? const Color(0xFFFFB347) : Colors.white24,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNoProfilesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun commerçant trouvé',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Synchronisez avec le réseau Nostr',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(NostrProfile profile) {
    // ✅ WOTX2: Récupérer les badges de compétences
    final skillBadges = profile.getSkillBadges();
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showProfileDetails(profile),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar avec badge de niveau si credential
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFFFFB347),
                        backgroundImage: profile.picture != null && profile.picture!.isNotEmpty
                            ? NetworkImage(profile.picture!)
                            : null,
                        child: profile.picture == null || profile.picture!.isEmpty
                            ? Text(
                                profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      // ✅ WOTX2: Badge de niveau max sur l'avatar
                      if (profile.skillCredentials != null && profile.skillCredentials!.isNotEmpty)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: _buildMaxLevelBadge(profile.skillCredentials!),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Nom
                Text(
                  profile.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                
                // ✅ WOTX2: Afficher les badges de compétences
                if (skillBadges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: skillBadges.take(3).map((badge) => _buildSkillBadge(badge)).toList(),
                  ),
                ],
                
                const Spacer(),
                
                // Bouton créer bon
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _createBonForMerchant(profile),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB347),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Créer un bon',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// ✅ WOTX2: Construit le badge de niveau max pour l'avatar
  Widget _buildMaxLevelBadge(List<SkillCredential> credentials) {
    final maxLevel = credentials.map((c) => c.level).reduce((a, b) => a > b ? a : b);
    final color = _getLevelColor(maxLevel);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        'X$maxLevel',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
  
  /// ✅ WOTX2: Construit un badge de compétence individuel
  Widget _buildSkillBadge(String badgeText) {
    // Extraire le niveau du texte (ex: "maraîchage X2" → niveau 2)
    final levelMatch = RegExp(r'X(\d+)$').firstMatch(badgeText);
    final level = levelMatch != null ? int.parse(levelMatch.group(1)!) : 1;
    final color = _getLevelColor(level);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
  
  /// ✅ WOTX2: Couleur selon le niveau de credential
  Color _getLevelColor(int level) {
    switch (level) {
      case 1: return const Color(0xFF4CAF50); // Vert
      case 2: return const Color(0xFF2196F3); // Bleu
      case 3: return const Color(0xFF9C27B0); // Violet
      default: return const Color(0xFF9E9E9E); // Gris
    }
  }

  void _showProfileDetails(NostrProfile profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              // Avatar et nom
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: const Color(0xFFFFB347),
                      backgroundImage: profile.picture != null && profile.picture!.isNotEmpty
                          ? NetworkImage(profile.picture!)
                          : null,
                      child: profile.picture == null || profile.picture!.isEmpty
                          ? Text(
                              profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Bouton créer bon
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _createBonForMerchant(profile);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Créer un bon pour ce commerçant'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB347),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _createBonForMerchant(NostrProfile profile) {
    // TODO: Implémenter la création de bon pour un commerçant
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Créer un bon pour ${profile.name}'),
        backgroundColor: const Color(0xFF0A7EA4),
      ),
    );
  }

  void _navigateToMarketConfig() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MarketScreen(user: widget.user),
      ),
    ).then((_) => _loadData());
  }

  void _navigateToCreateBon() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateBonScreen(user: widget.user),
      ),
    ).then((_) => _loadData());
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ============================================================
  // SOUS-ONGLET 3 : SAVOIR-FAIRE (WOTX - Mode Expert)
  // ============================================================
  
  /// ✅ WOTX2: Construit la section affichant les credentials de l'utilisateur
  Widget _buildMyCredentialsSection() {
    // Récupérer les credentials depuis le profil utilisateur
    // Pour l'instant, on simule avec les activityTags
    final activityTags = widget.user.activityTags ?? <String>[];
    
    // TODO: Charger les vrais credentials depuis Nostr (Kind 30503)
    // Pour la démo, on affiche les compétences déclarées
    final hasCredentials = activityTags.isNotEmpty;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasCredentials
              ? [const Color(0xFF4CAF50).withOpacity(0.2), const Color(0xFF2196F3).withOpacity(0.2)]
              : [const Color(0xFF2A2A2A), const Color(0xFF2A2A2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasCredentials
              ? const Color(0xFF4CAF50).withOpacity(0.5)
              : Colors.white24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasCredentials ? Icons.verified : Icons.verified_outlined,
                color: hasCredentials ? const Color(0xFF4CAF50) : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Mes certifications',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: hasCredentials ? const Color(0xFF4CAF50) : Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (hasCredentials) ...[
            // Afficher les badges de compétences
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: activityTags.map((skill) {
                // Pour l'instant, on affiche X1 par défaut
                // TODO: Récupérer le vrai niveau depuis les credentials Kind 30503
                return _buildMySkillBadge(skill, level: 1);
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'Les badges X1, X2, X3 sont délivrés par l\'Oracle TrocZen Box '
              'après vérification de vos compétences par vos pairs.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[400],
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            Text(
              'Aucune certification pour le moment.\n'
              'Déclarez vos compétences dans votre profil pour recevoir des attestations.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[400],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  /// ✅ WOTX2: Construit un badge de compétence pour l'utilisateur courant
  Widget _buildMySkillBadge(String skill, {required int level}) {
    final color = _getLevelColor(level);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getSkillIcon(skill),
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            skill,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'X$level',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// ✅ WOTX2: Retourne l'icône associée à une compétence
  IconData _getSkillIcon(String skill) {
    final skillLower = skill.toLowerCase();
    if (skillLower.contains('maraîch') || skillLower.contains('jardin') || skillLower.contains('agricult')) {
      return Icons.grass;
    } else if (skillLower.contains('boulanger') || skillLower.contains('pain')) {
      return Icons.bakery_dining;
    } else if (skillLower.contains('boucher') || skillLower.contains('viande')) {
      return Icons.set_meal;
    } else if (skillLower.contains('informatique') || skillLower.contains('dev') || skillLower.contains('tech')) {
      return Icons.computer;
    } else if (skillLower.contains('artisan') || skillLower.contains('bois') || skillLower.contains('métal')) {
      return Icons.handyman;
    } else if (skillLower.contains('santé') || skillLower.contains('médecin') || skillLower.contains('soin')) {
      return Icons.health_and_safety;
    } else if (skillLower.contains('éducat') || skillLower.contains('formateur') || skillLower.contains('prof')) {
      return Icons.school;
    } else if (skillLower.contains('art') || skillLower.contains('musique') || skillLower.contains('peint')) {
      return Icons.palette;
    } else if (skillLower.contains('transport') || skillLower.contains('livraison')) {
      return Icons.local_shipping;
    } else if (skillLower.contains('restaur') || skillLower.contains('cuisine') || skillLower.contains('chef')) {
      return Icons.restaurant;
    }
    return Icons.verified;
  }

  /// Charge les demandes de certification en attente
  Future<void> _loadPendingRequests() async {
    if (widget.user.activityTags == null || widget.user.activityTags!.isEmpty) {
      Logger.info('ExploreView', 'Pas de compétences définies - Mode Expert non disponible');
      return;
    }
    
    final relayUrl = widget.user.relayUrl ?? 'wss://relay.copylaradio.com';
    Logger.info('ExploreView', 'Chargement demandes pour compétences: ${widget.user.activityTags}');
    
    setState(() => _isLoadingRequests = true);
    
    try {
      final nostrService = NostrService(
        cryptoService: CryptoService(),
        storageService: _storageService,
      );
      
      if (await nostrService.connect(relayUrl)) {
        final requests = await nostrService.fetchPendingSkillRequests(
          mySkills: widget.user.activityTags!,
          myNpub: widget.user.npub,
        );
        
        Logger.success('ExploreView', '${requests.length} demandes trouvées');
        setState(() => _pendingRequests = requests);
        await nostrService.disconnect();
      }
    } catch (e) {
      Logger.error('ExploreView', 'Erreur chargement demandes', e);
    } finally {
      setState(() => _isLoadingRequests = false);
    }
  }

  /// Publie une attestation pour un demandeur
  ///
  /// ✅ SÉCURITÉ: Le contenu est chiffré avec la Seed du Marché.
  Future<void> _attestUser(Map<String, dynamic> request) async {
    setState(() => _isAttesting = true);
    
    final relayUrl = widget.user.relayUrl ?? 'wss://relay.copylaradio.com';
    Logger.info('ExploreView', 'Attestation pour ${request['pubkey']} - skill: ${request['skill']}');
    
    try {
      // ✅ SÉCURITÉ: Récupérer la seed du marché pour le chiffrement
      final market = await _storageService.getMarket();
      final seedMarket = market?.seedMarket ?? '';
      
      final nostrService = NostrService(
        cryptoService: CryptoService(),
        storageService: _storageService,
      );
      
      if (await nostrService.connect(relayUrl)) {
        final success = await nostrService.publishSkillAttestation(
          myNpub: widget.user.npub,
          myNsec: widget.user.nsec,
          requestId: request['id'],
          requesterNpub: request['pubkey'],
          permitId: request['permit_id'] ?? 'PERMIT_${request['skill']?.toUpperCase()}_X1',
          seedMarket: seedMarket,  // ✅ SÉCURITÉ: Seed pour chiffrement
          motivation: 'Certification par pair',
        );
        
        await nostrService.disconnect();
        
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Attestation publiée avec succès !'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
          // Retirer de la liste locale
          setState(() {
            _pendingRequests.removeWhere((r) => r['id'] == request['id']);
          });
        }
      }
    } catch (e) {
      Logger.error('ExploreView', 'Erreur attestation', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isAttesting = false);
    }
  }

  /// Construit l'onglet Savoir-faire
  Widget _buildSkillsTab() {
    return RefreshIndicator(
      onRefresh: _loadPendingRequests,
      child: CustomScrollView(
        slivers: [
          // En-tête explicatif
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre
                  const Text(
                    'Mode Expert',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFB347),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // ✅ WOTX2: Mes badges de compétences
                  _buildMyCredentialsSection(),
                  
                  const SizedBox(height: 16),
                  
                  // Explication pédagogique
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFB347).withOpacity(0.3)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline, color: Color(0xFFFFB347), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Pourquoi attester les autres ?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFB347),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'En validant les compétences de vos pairs, vous augmentez la qualité de votre réseau local. '
                          'Plus votre réseau est compétent, plus le multiplicateur de votre Dividende Universel (Alpha) '
                          'sera élevé lors du prochain calcul de la TrocZen Box.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Mes compétences
                  Text(
                    'Vos compétences: ${widget.user.activityTags?.join(", ") ?? "Aucune"}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          
          // Liste des demandes en attente
          if (_isLoadingRequests)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFFFFB347)),
                ),
              ),
            )
          else if (_pendingRequests.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text(
                        'Aucune demande en attente',
                        style: TextStyle(color: Colors.grey[400], fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Les demandes de certification pour vos compétences apparaîtront ici',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadPendingRequests,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualiser'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB347),
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final request = _pendingRequests[index];
                  return _buildRequestCard(request);
                },
                childCount: _pendingRequests.length,
              ),
            ),
        ],
      ),
    );
  }

  /// Construit une carte de demande de certification
  Widget _buildRequestCard(Map<String, dynamic> request) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      (request['created_at'] as int) * 1000,
    );
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color(0xFFFFB347).withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête: Avatar + Nom
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFFFB347),
                  child: Text(
                    request['pubkey'].toString().substring(0, 2).toUpperCase(),
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['pubkey'].toString().substring(0, 16) + '...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Demande: ${request['skill']}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB347).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    request['permit_id']?.toString().replaceAll('PERMIT_', '') ?? 'X1',
                    style: const TextStyle(color: Color(0xFFFFB347), fontSize: 11),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Motivation
            if (request['content'] != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _extractMotivation(request['content']),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            
            const SizedBox(height: 12),
            
            // Date
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  _formatDate(createdAt),
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Bouton d'action
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAttesting ? null : () => _attestUser(request),
                icon: _isAttesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.check_circle, color: Colors.black),
                label: Text(
                  _isAttesting ? 'Signature...' : '✔️ Attester (Signer)',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB347),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Extrait la motivation du contenu JSON
  String _extractMotivation(String? content) {
    if (content == null) return 'Pas de motivation indiquée';
    try {
      final json = Map<String, dynamic>.from(
        Map<String, dynamic>.from(
          {}..addAll({'raw': content}),
        ),
      );
      // Essayer de parser le JSON
      if (content.startsWith('{')) {
        final decoded = Map<String, dynamic>.from(
          {}..addAll({'raw': content}),
        );
        return decoded['motivation']?.toString() ?? content;
      }
      return content;
    } catch (e) {
      return content;
    }
  }
}
