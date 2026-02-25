import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../services/storage_service.dart';
import '../../services/logger_service.dart';
import '../../services/burn_service.dart';
import '../../services/crypto_service.dart';
import '../../widgets/panini_card.dart';
import '../../widgets/qr_explosion_widget.dart';
import '../../widgets/circuit_revelation_widget.dart';
import '../mirror_offer_screen.dart';
import '../bon_journey_screen.dart';

/// WalletView — Bons dont je détiens P2
/// Vue principale du commerçant receveur
class WalletView extends StatefulWidget {
  final User user;

  const WalletView({super.key, required this.user});

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> with AutomaticKeepAliveClientMixin {
  List<Bon> bons = [];
  List<Bon> filteredBons = [];
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isGridView = false;
  final _searchController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadBons();
    _loadAvailableDu();
    _searchController.addListener(_filterBons);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBons() async {
    if (_isLoading || _isUpdating) return;
    
    // Initialiser le mode debug au chargement
    await Logger.checkDebugMode();
    Logger.log('WalletView', 'Chargement des bons...');
    
    setState(() => _isLoading = true);
    try {
      final storageService = StorageService();
      
      // ✅ Nettoyage automatique des bons expirés (Monnaie fondante)
      final removedCount = await storageService.cleanupExpiredBons();
      if (removedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🧹 $removedCount bon(s) expiré(s) supprimé(s)'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      final loadedBons = await storageService.getBons();
      
      // LOG CRITIQUE POUR DEBUG - Afficher tous les bons trouvés
      Logger.log('WalletView', 'Total bons chargés: ${loadedBons.length}');
      for (var b in loadedBons) {
        Logger.log('WalletView', 'Bon: ${b.issuerName} | Status: ${b.status} | P1: ${b.p1 != null ? "présent" : "absent"} | P2: ${b.p2 != null ? "présent" : "absent"}');
      }
      
      if (!mounted) return;
      setState(() {
        // Afficher les bons non brûlés dont on possède P2 (bons créés ou reçus)
        bons = loadedBons.where((b) =>
          b.status != BonStatus.burned &&
          (b.p2 != null)
        ).toList();
        
        Logger.log('WalletView', 'Bons après filtrage: ${bons.length}');
        
        filteredBons = bons;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('WalletView', 'Erreur lors du chargement', e);
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

  double _availableDu = 0.0;

  Future<void> _loadAvailableDu() async {
    final storageService = StorageService();
    final available = await storageService.getAvailableDuToEmit();
    if (mounted) {
      setState(() {
        _availableDu = available;
      });
    }
  }

  Future<void> _refreshBons() async {
    await _loadAvailableDu();
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
          // Bouton bascule vue grille/liste
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? 'Vue liste' : 'Vue grille',
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
            color: Colors.black.withValues(alpha: 0.3),
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
          
          // DU disponible à émettre
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0A7EA4).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF0A7EA4).withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.add_circle_outline,
                  size: 16,
                  color: Color(0xFF0A7EA4),
                ),
                const SizedBox(width: 6),
                Text(
                  'DU disponible à émettre: ${_availableDu.toStringAsFixed(2)} ẐEN',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF0A7EA4),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
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

    // Vue grille
    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: sortedBons.length,
        itemBuilder: (context, index) {
          final bon = sortedBons[index];
          return PaniniCard(
            bon: bon,
            onTap: () => _showBonDetails(bon),
            onLongPress: () => _showContextMenu(bon),
            statusChip: _buildStatusChip(bon),
          );
        },
      );
    }

    // Vue liste (par défaut)
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
            child: PaniniCard(
              bon: bon,
              onTap: () => _showBonDetails(bon),
              onLongPress: () => _showContextMenu(bon),
              statusChip: _buildStatusChip(bon),
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
      backgroundColor = Colors.red.withValues(alpha: 0.9);
      textColor = Colors.white;
      label = 'Expiré';
      icon = Icons.error_outline;
    } else if (bon.status == BonStatus.pending) {
      backgroundColor = Colors.orange.withValues(alpha: 0.9);
      textColor = Colors.white;
      label = 'En attente';
      icon = Icons.pending_outlined;
    } else if (bon.status == BonStatus.active) {
      backgroundColor = Colors.green.withValues(alpha: 0.9);
      textColor = Colors.white;
      label = 'Actif';
      icon = Icons.check_circle_outline;
    } else {
      backgroundColor = Colors.grey.withValues(alpha: 0.9);
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
            color: Colors.black.withValues(alpha: 0.3),
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
    
    // ✅ RÈGLE MÉTIER: Un émetteur (P1) ne peut pas supprimer un bon transféré (P2 absent)
    // Whitepaper: P1 = Ancre détenue par l'émetteur, P2 = Voyageur détenu par le porteur
    // Si P1 présent mais P2 absent, le bon a été transféré et ne peut être supprimé
    if (bon.p1 != null && bon.p2 == null) {
      // Afficher l'explosion au lieu de supprimer
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: QrExplosionWidget(
            size: 300,
            type: QrExplosionType.bonTransferInProgress,
            bonId: bon.bonId,
            bonValue: bon.value,
            onRetry: () => Navigator.pop(context),
          ),
        ),
      );
      return;
    }
    
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
              if (bon.wish != null && bon.wish!.isNotEmpty)
                _buildDetailRow('Vœu', bon.wish!),
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

              // Bouton Carnet de Voyage
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BonJourneyScreen(bon: bon),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map, color: Color(0xFF0A7EA4)),
                  label: const Text(
                    'Carnet de Voyage',
                    style: TextStyle(
                      color: Color(0xFF0A7EA4),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF0A7EA4)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // ✅ Bouton ENCAISSER/DÉTRUIRE (si l'utilisateur est l'émetteur avec P1+P2+P3)
              // L'émetteur peut "encaisser" son propre bon = détruire la boucle
              if (_isEmitterWithAllParts(bon) && bon.status == BonStatus.active && !bon.isExpired) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_fire_department, color: Colors.orange.shade400),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Vous êtes l\'émetteur de ce bon',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Bouclez le circuit pour révéler le parcours accompli et célébrer la valeur créée.',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmBurnBon(bon),
                    icon: const Icon(Icons.celebration, color: Colors.white),
                    label: const Text(
                      '🎉 BOUCLER LE CIRCUIT',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              // Bouton Donner (si le bon est actif et non expiré)
              if (bon.status == BonStatus.active && !bon.isExpired)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // Fermer la modale
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MirrorOfferScreen(user: widget.user, bon: bon),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code, color: Colors.black),
                    label: const Text(
                      'Donner ce bon',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB347),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (bon.status == BonStatus.active && !bon.isExpired)
                const SizedBox(height: 12),
              
              // Bouton Fermer
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB347),
                    side: const BorderSide(color: Color(0xFFFFB347)),
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

  /// Vérifie si l'utilisateur est l'émetteur du bon avec toutes les parties (P1+P2+P3)
  /// Cela signifie qu'il peut "encaisser" le bon = détruire la boucle
  bool _isEmitterWithAllParts(Bon bon) {
    // L'émetteur possède P1 (ancre) + P2 (voyageur retourné) + P3 (témoin en cache)
    // P1 et P2 sont stockés dans le bon, P3 est dans le cache
    return bon.p1 != null && bon.p2 != null;
  }

  /// Affiche la confirmation de destruction du bon
  void _confirmBurnBon(Bon bon) {
    Navigator.pop(context); // Fermer la modale de détails
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          children: [
            Icon(Icons.celebration, color: Colors.orange.shade400),
            const SizedBox(width: 8),
            const Text(
              'Boucler le circuit ?',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vous êtes sur le point de révéler le parcours de ce bon de ${bon.value.toStringAsFixed(2)} ẐEN.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.celebration, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Le circuit est complet ! Le bon sera révélé comme preuve économique (Kind 30304).',
                      style: TextStyle(
                        color: Colors.green.shade300,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _burnBon(bon);
            },
            icon: const Icon(Icons.celebration, color: Colors.white),
            label: const Text(
              'BOUCLER',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  /// Brûle le bon avec animation de validation
  Future<void> _burnBon(Bon bon) async {
    if (_isUpdating) return;
    
    setState(() => _isUpdating = true);
    
    try {
      // Exécuter le burn/révélation via BurnService
      final burnService = BurnService(
        cryptoService: CryptoService(),
        storageService: StorageService(),
      );
      
      final success = await burnService.burnBon(
        bon: bon,
        p1: bon.p1!,
        reason: 'Encaissement par l\'émetteur',
      );
      
      if (success) {
        // Afficher l'animation de Révélation du Circuit après succès
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: CircuitRevelationWidget(
              size: 300,
              bonId: bon.bonId,
              valueZen: bon.value,
              hopCount: bon.transferCount ?? 0,
              ageDays: DateTime.now().difference(bon.createdAt).inDays,
              skillAnnotation: bon.specialAbility,
              rarity: bon.rarity,
              onClose: () => Navigator.pop(context),
            ),
          ),
        );
        
        await _loadBons();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔄 Circuit révélé: ${bon.value.toStringAsFixed(2)} ẐEN | ${bon.transferCount ?? 0} hops'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Erreur lors de la révélation du circuit'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Logger.error('WalletView', 'Erreur burn', e);
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
