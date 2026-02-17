import 'package:flutter/material.dart';
import '../models/bon.dart';
import '../models/user.dart';
import '../services/storage_service.dart';
import '../widgets/panini_card.dart';

/// Écran gallerie/collection de bons style Instagram
/// Avec tri, filtres, et vue grille
class GalleryScreen extends StatefulWidget {
  final User user;

  const GalleryScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> with SingleTickerProviderStateMixin {
  final StorageService _storage = StorageService();
  
  List<Bon> _allBons = [];
  List<Bon> _filteredBons = [];
  bool _isLoading = true;
  
  // Filtres
  String _currentFilter = 'all';
  String _currentSort = 'recent';
  bool _isGridView = false;
  
  late TabController _tabController;

  final _filters = {
    'all': 'Tous',
    'active': 'Actifs',
    'rare': 'Rares',
    'food': 'Alimentation',
    'artisanat': 'Artisanat',
  };

  final _sortOptions = {
    'recent': {'label': 'Plus récents', 'icon': Icons.schedule},
    'value': {'label': 'Valeur', 'icon': Icons.attach_money},
    'rarity': {'label': 'Rareté', 'icon': Icons.star},
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBons();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBons() async {
    setState(() => _isLoading = true);
    final bons = await _storage.getBons();
    setState(() {
      _allBons = bons;
      _applyFiltersAndSort();
      _isLoading = false;
    });
  }

  void _applyFiltersAndSort() {
    var filtered = List<Bon>.from(_allBons);

    // Filtre
    switch (_currentFilter) {
      case 'active':
        filtered = filtered.where((b) => b.isValid).toList();
        break;
      case 'rare':
        filtered = filtered.where((b) => b.isRare).toList();
        break;
      case 'food':
        // TODO: Filter par catégorie quand implémenté
        break;
    }

    // Tri
    switch (_currentSort) {
      case 'recent':
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'value':
        filtered.sort((a, b) => b.value.compareTo(a.value));
        break;
      case 'rarity':
        filtered.sort((a, b) => _rarityScore(b.rarity ?? 'common').compareTo(_rarityScore(a.rarity ?? 'common')));
        break;
    }

    setState(() => _filteredBons = filtered);
  }

  int _rarityScore(String rarity) {
    switch (rarity) {
      case 'legendary': return 4;
      case 'rare': return 3;
      case 'uncommon': return 2;
      default: return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // AppBar style moderne
            SliverAppBar(
              floating: true,
              pinned: true,
              expandedHeight: 120,
              backgroundColor: const Color(0xFF1E1E1E),
              flexibleSpace: FlexibleSpaceBar(
                title: const Text(
                  'Ma Collection',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1E1E1E),
                        const Color(0xFFFFB347).withOpacity(0.1),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                // Toggle vue grille/liste
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                  onPressed: () {
                    setState(() => _isGridView = !_isGridView);
                  },
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: Container(
                  color: const Color(0xFF1E1E1E),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFFFFB347),
                    labelColor: const Color(0xFFFFB347),
                    unselectedLabelColor: Colors.grey,
                    tabs: const [
                      Tab(text: 'Collection'),
                      Tab(text: 'Statistiques'),
                    ],
                  ),
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            // Onglet Collection
            _buildCollectionView(),
            
            // Onglet Stats
            _buildStatsView(),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionView() {
    return Column(
      children: [
        // Barre de filtres style Instagram
        _buildFilterBar(),
        
        // Stats rapides
        _buildQuickStats(),
        
        // Liste/Grille de bons
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredBons.isEmpty
                  ? _buildEmptyState()
                  : _isGridView
                      ? _buildGridView()
                      : _buildListView(),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length + _sortOptions.length,
        itemBuilder: (context, index) {
          if (index < _filters.length) {
            // Filtres
            final entry = _filters.entries.elementAt(index);
            final isSelected = _currentFilter == entry.key;
            
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(entry.value),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _currentFilter = entry.key;
                    _applyFiltersAndSort();
                  });
                },
                selectedColor: const Color(0xFFFFB347),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.grey[400],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          } else {
            // Tri (après les filtres)
            if (index == _filters.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: VerticalDivider(color: Colors.grey),
              );
            }
            
            final sortIndex = index - _filters.length - 1;
            final entry = _sortOptions.entries.elementAt(sortIndex);
            final isSelected = _currentSort == entry.key;
            
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(
                  entry.value['icon'] as IconData,
                  size: 16,
                  color: isSelected ? Colors.black : Colors.grey,
                ),
                label: Text(entry.value['label'] as String),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _currentSort = entry.key;
                    _applyFiltersAndSort();
                  });
                },
                selectedColor: const Color(0xFF0A7EA4),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[400],
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildQuickStats() {
    final actifs = _allBons.where((b) => b.isValid).length;
    final valeurTotale = _allBons.where((b) => b.isValid).fold<double>(0, (sum, b) => sum + b.value);
    final rares = _allBons.where((b) => b.isRare).length;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatChip(actifs.toString(), 'Actifs', Icons.verified, Colors.green),
          _buildStatChip('${valeurTotale.toStringAsFixed(0)} Ẑ', 'Valeur', Icons.monetization_on, const Color(0xFFFFB347)),
          _buildStatChip(rares.toString(), 'Rares', Icons.star, Colors.purple),
        ],
      ),
    );
  }

  Widget _buildStatChip(String value, String label, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _filteredBons.length,
      itemBuilder: (context, index) {
        final bon = _filteredBons[index];
        return PaniniCard(bon: bon,showActions: true);
      },
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _filteredBons.length,
      itemBuilder: (context, index) {
        final bon = _filteredBons[index];
        return PaniniCard(bon: bon, showActions: true);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.collections_bookmark, size: 80, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text(
            'Aucun bon dans cette catégorie',
            style: TextStyle(color: Colors.grey[500], fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsView() {
    // TODO: Statistiques détaillées (graphiques avec fl_chart)
    return const Center(
      child: Text(
        '📊 Statistiques (à venir)',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }
}
