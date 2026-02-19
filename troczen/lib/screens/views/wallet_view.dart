import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../services/storage_service.dart';
import '../../widgets/panini_card.dart';
import '../gallery_screen.dart';

/// WalletView — Bons dont je détiens P2
/// Vue principale du commerçant receveur
class WalletView extends StatefulWidget {
  final User user;

  const WalletView({Key? key, required this.user}) : super(key: key);

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> with AutomaticKeepAliveClientMixin {
  List<Bon> bons = [];
  List<Bon> filteredBons = [];
  bool _isLoading = true;
  bool _isUpdating = false;
  final _searchController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadBons();
    _searchController.addListener(_filterBons);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBons() async {
    if (_isLoading || _isUpdating) return;
    setState(() => _isLoading = true);
    try {
      final storageService = StorageService();
      final loadedBons = await storageService.getBons();
      if (!mounted) return;
      setState(() {
        bons = loadedBons;
        filteredBons = loadedBons;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erreur lors du chargement: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _filterBons() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        filteredBons = bons;
      } else {
        filteredBons = bons.where((bon) {
          return bon.issuerName.toLowerCase().contains(query) ||
                 bon.value.toString().contains(query) ||
                 (bon.cardType?.toLowerCase().contains(query) ?? false) ||
                 bon.marketName.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  double get _totalActiveBalance {
    return bons
        .where((b) => b.status == BonStatus.active)
        .fold(0.0, (sum, bon) => sum + bon.value);
  }

  double get _totalPendingBalance {
    return bons
        .where((b) => b.status == BonStatus.pending)
        .fold(0.0, (sum, bon) => sum + bon.value);
  }

  Future<void> _refreshBons() async {
    await _loadBons();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Liste actualisée'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Mon Wallet'),
        actions: [
          // Bouton galerie
          IconButton(
            icon: const Icon(Icons.grid_view),
            onPressed: () => _navigateToGallery(),
            tooltip: 'Voir en galerie',
          ),
          // Bouton rafraîchir
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadBons(),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : bons.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _refreshBons,
                  child: Column(
                    children: [
                      // En-tête avec soldes
                      _buildBalanceHeader(),
                      // Barre de recherche
                      _buildSearchBar(),
                      // Liste des bons
                      Expanded(child: _buildBonsList()),
                    ],
                  ),
                ),
    );
  }

  Widget _buildBalanceHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1E1E), Color(0xFF2A2A2A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Solde total actif
          Text(
            'Solde Total',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_totalActiveBalance.toStringAsFixed(2)} Ẑ',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFB347),
              letterSpacing: -1,
            ),
          ),
          
          // Solde en attente
          if (_totalPendingBalance > 0) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.pending_outlined,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 6),
                Text(
                  'En attente: ${_totalPendingBalance.toStringAsFixed(2)} Ẑ',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SearchBar(
        controller: _searchController,
        hintText: 'Rechercher par nom, valeur, type...',
        leading: const Icon(Icons.search),
        trailing: _searchController.text.isNotEmpty
            ? [
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              ]
            : null,
        backgroundColor: WidgetStateProperty.all(const Color(0xFF1E1E1E)),
        elevation: WidgetStateProperty.all(0),
        side: WidgetStateProperty.all(
          const BorderSide(color: Colors.white24, width: 1),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wallet_outlined,
            size: 120,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 24),
          Text(
            'Aucun bon dans votre wallet',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[400],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scannez un QR code pour recevoir\nou créez votre premier bon !',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonsList() {
    if (filteredBons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 16),
            Text(
              'Aucun bon trouvé',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    // Trier les bons par date de création (plus récent en premier)
    final sortedBons = List<Bon>.from(filteredBons)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sortedBons.length,
      itemBuilder: (context, index) {
        final bon = sortedBons[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 160,
              maxHeight: 220,
            ),
            child: GestureDetector(
              onTap: () => _showBonDetails(bon),
              onLongPress: () => _showContextMenu(bon),
              child: Stack(
                children: [
                  PaniniCard(
                    bon: bon,
                    onTap: () => _showBonDetails(bon),
                  ),
                  // Chip de statut
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _buildStatusChip(bon),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(Bon bon) {
    Color backgroundColor;
    Color textColor;
    String label;
    IconData icon;

    if (bon.isExpired) {
      backgroundColor = Colors.red.withOpacity(0.9);
      textColor = Colors.white;
      label = 'Expiré';
      icon = Icons.error_outline;
    } else if (bon.status == BonStatus.pending) {
      backgroundColor = Colors.orange.withOpacity(0.9);
      textColor = Colors.white;
      label = 'En attente';
      icon = Icons.pending_outlined;
    } else if (bon.status == BonStatus.active) {
      backgroundColor = Colors.green.withOpacity(0.9);
      textColor = Colors.white;
      label = 'Actif';
      icon = Icons.check_circle_outline;
    } else {
      backgroundColor = Colors.grey.withOpacity(0.9);
      textColor = Colors.white;
      label = bon.status.name;
      icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(Bon bon) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Titre
            Text(
              bon.issuerName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            
            // Options
            ListTile(
              leading: const Icon(Icons.qr_code, color: Color(0xFFFFB347)),
              title: const Text('Afficher QR P2', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showP2QRCode(bon);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history, color: Color(0xFF0A7EA4)),
              title: const Text('Voir historique', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showBonHistory(bon);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Supprimer', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteBon(bon);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showP2QRCode(Bon bon) {
    if (bon.p2 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ P2 non disponible pour ce bon'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'QR Code P2',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: bon.p2!,
                version: QrVersions.auto,
                size: 250,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Part P2 du bon',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _showBonHistory(Bon bon) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Historique du bon',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHistoryItem('Création', bon.createdAt, Icons.add_circle),
            if (bon.transferCount != null && bon.transferCount! > 0)
              _buildHistoryItem(
                'Transferts',
                bon.createdAt,
                Icons.swap_horiz,
                count: bon.transferCount,
              ),
            _buildHistoryItem(
              'Statut actuel: ${bon.status.name}',
              DateTime.now(),
              Icons.info,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String label, DateTime date, IconData icon, {int? count}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFB347), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count != null ? '$label ($count fois)' : label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _formatDate(date),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBon(Bon bon) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Supprimer le bon ?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Voulez-vous vraiment supprimer ce bon de ${bon.issuerName} (${bon.value} Ẑ) ?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteBon(bon);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBon(Bon bon) async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    try {
      final storageService = StorageService();
      await storageService.deleteBon(bon.bonId);
      await _loadBons();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Bon supprimé'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  void _navigateToGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GalleryScreen(user: widget.user),
      ),
    );
  }

  void _showBonDetails(Bon bon) {
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
              
              // Nom de l'émetteur
              Text(
                bon.issuerName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              
              // Détails
              _buildDetailRow('Valeur', '${bon.value.toStringAsFixed(2)} ẐEN'),
              _buildDetailRow('Commerçant', bon.issuerName),
              _buildDetailRow('Créé le', _formatDate(bon.createdAt)),
              _buildDetailRow('Marché', bon.marketName),
              if (bon.rarity != null && bon.rarity != 'common') ...[
                const SizedBox(height: 16),
                const Text(
                  'Rareté',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFB347),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  bon.rarity!.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Boutons d'action
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB347),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Fermer',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFB347),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} à ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}
