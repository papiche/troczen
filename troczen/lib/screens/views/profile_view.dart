import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../services/storage_service.dart';
import '../user_profile_screen.dart';

/// ProfileView — Mon Profil
/// Affichage et édition du profil utilisateur
class ProfileView extends StatefulWidget {
  final User user;

  const ProfileView({Key? key, required this.user}) : super(key: key);

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> with AutomaticKeepAliveClientMixin {
  final _storageService = StorageService();
  User? _currentUser;
  ProfileStats? _stats;
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    
    try {
      final user = await _storageService.getUser();
      final market = await _storageService.getMarket();
      final bons = await _storageService.getBons();
      
      // Calculer les statistiques
      final stats = _calculateStats(user ?? widget.user, bons);
      
      setState(() {
        _currentUser = user ?? widget.user;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement profil: $e');
      setState(() {
        _currentUser = widget.user;
        _stats = null;
        _isLoading = false;
      });
    }
  }

  ProfileStats _calculateStats(User user, List<Bon> bons) {
    // Bons émis (où l'utilisateur est émetteur)
    final emittedBons = bons.where((b) => b.issuerNpub == user.npub).toList();
    final totalEmitted = emittedBons.fold<double>(0.0, (sum, bon) => sum + bon.value);
    
    // Bons reçus (où l'utilisateur a P2)
    final receivedBons = bons.where((b) => b.p2 != null).toList();
    final totalReceived = receivedBons.fold<double>(0.0, (sum, bon) => sum + bon.value);
    
    // Total échangé
    final totalExchanged = totalEmitted + totalReceived;
    
    // Bons actifs
    final activeBons = bons.where((b) => b.status == BonStatus.active).length;
    
    // Transferts totaux
    final totalTransfers = bons.fold<int>(0, (sum, bon) => sum + (bon.transferCount ?? 0));
    
    return ProfileStats(
      emittedBons: emittedBons.length,
      receivedBons: receivedBons.length,
      totalEmitted: totalEmitted,
      totalReceived: totalReceived,
      totalExchanged: totalExchanged,
      activeBons: activeBons,
      totalTransfers: totalTransfers,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Mon Profil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _navigateToEditProfile(),
            tooltip: 'Modifier le profil',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentUser == null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadUserProfile,
                  child: _buildProfileContent(),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 120,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 24),
          Text(
            'Erreur de chargement',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[400],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => _loadUserProfile(),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // En-tête avec avatar
        _buildProfileHeader(),
        const SizedBox(height: 24),
        
        // Statistiques
        if (_stats != null) ...[
          _buildStatsSection(),
          const SizedBox(height: 24),
        ],
        
        // Informations du profil
        _buildInfoSection(),
        const SizedBox(height: 24),
        
        // Clés cryptographiques
        _buildKeysSection(),
        const SizedBox(height: 24),
        
        // Ma seed de marché
        _buildMarketSeedSection(),
        const SizedBox(height: 24),
        
        // Actions
        _buildActionsSection(),
      ],
    );
  }

  Widget _buildProfileHeader() {
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
        children: [
          // Avatar
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _currentUser!.displayName.isNotEmpty
                    ? _currentUser!.displayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFB347),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Nom d'affichage
          Text(
            _currentUser!.displayName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          
          // Date de création
          Text(
            'Membre depuis ${_formatDate(_currentUser!.createdAt)}',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
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
            'Informations',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildInfoRow('Nom d\'affichage', _currentUser!.displayName),
          if (_currentUser!.website != null && _currentUser!.website!.isNotEmpty) ...[
            const Divider(color: Colors.white24, height: 24),
            _buildInfoRow('Site web', _currentUser!.website!),
          ],
          if (_currentUser!.g1pub != null && _currentUser!.g1pub!.isNotEmpty) ...[
            const Divider(color: Colors.white24, height: 24),
            _buildInfoRow('G1Pub', _currentUser!.g1pub!, copyable: true),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool copyable = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFB347),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (copyable) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  color: const Color(0xFFFFB347),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _copyToClipboard(value),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeysSection() {
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
          Row(
            children: const [
              Icon(Icons.key, color: Color(0xFFFFB347)),
              SizedBox(width: 8),
              Text(
                'Clés cryptographiques',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildKeyRow(
            'Clé publique (npub)',
            _currentUser!.npub,
            Icons.visibility,
          ),
          const Divider(color: Colors.white24, height: 24),
          _buildKeyRow(
            'Clé privée (nsec)',
            '•' * 32,
            Icons.lock,
            sensitive: true,
          ),
          
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: const [
                Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ne partagez jamais votre clé privée',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.3),
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
              Icon(Icons.bar_chart, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                'Mes statistiques',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Ligne 1
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Bons émis',
                  '${_stats!.emittedBons}',
                  Icons.upload,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  'Bons reçus',
                  '${_stats!.receivedBons}',
                  Icons.download,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Ligne 2
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Émis (Ẑ)',
                  '${_stats!.totalEmitted.toStringAsFixed(0)}',
                  Icons.account_balance_wallet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  'Reçus (Ẑ)',
                  '${_stats!.totalReceived.toStringAsFixed(0)}',
                  Icons.wallet,
                ),
              ),
            ],
          ),
          
          const Divider(color: Colors.white30, height: 32),
          
          // Total échangé
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.sync_alt, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Total échangé',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Text(
                '${_stats!.totalExchanged.toStringAsFixed(2)} Ẑ',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Bons actifs et transferts
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[300], size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${_stats!.activeBons} bons actifs',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.swap_horiz, color: Colors.blue[300], size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${_stats!.totalTransfers} transferts',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketSeedSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB347).withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.qr_code_2, color: Color(0xFFFFB347)),
              SizedBox(width: 8),
              Text(
                'Ma seed de marché',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Boutons d'action
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showMarketSeedQR(),
                  icon: const Icon(Icons.qr_code, size: 20),
                  label: const Text('Afficher QR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB347),
                    side: const BorderSide(color: Color(0xFFFFB347)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyMarketSeed(),
                  icon: const Icon(Icons.copy, size: 20),
                  label: const Text('Copier'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB347),
                    side: const BorderSide(color: Color(0xFFFFB347)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cette seed permet de rejoindre votre marché local',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMarketSeedQR() async {
    // Récupérer la seed du marché
    final market = await _storageService.getMarket();
    if (market == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Aucun marché configuré'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          children: const [
            Icon(Icons.qr_code_2, color: Color(0xFFFFB347)),
            SizedBox(width: 12),
            Text(
              'QR Seed du Marché',
              style: TextStyle(color: Colors.white),
            ),
          ],
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
                data: market.seedMarket,
                version: QrVersions.auto,
                size: 280,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              market.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Partagez ce QR pour inviter\nd\'autres commerçants',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[400],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _copyMarketSeed();
            },
            child: const Text('Copier la seed'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyMarketSeed() async {
    final market = await _storageService.getMarket();
    if (market == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Aucun marché configuré'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: market.seedMarket));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Seed du marché copiée'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildKeyRow(String label, String value, IconData icon, {bool sensitive = false}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value.length > 20 ? '${value.substring(0, 20)}...' : value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        if (!sensitive)
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            color: const Color(0xFFFFB347),
            onPressed: () => _copyToClipboard(value),
          ),
      ],
    );
  }

  Widget _buildActionsSection() {
    return Column(
      children: [
        _buildActionButton(
          'Modifier mon profil',
          Icons.edit,
          const Color(0xFFFFB347),
          () => _navigateToEditProfile(),
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          'Exporter mes données',
          Icons.download,
          const Color(0xFF0A7EA4),
          () => _exportUserData(),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _navigateToEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(user: _currentUser!),
      ),
    ).then((_) => _loadUserProfile());
  }

  void _exportUserData() {
    // TODO: Implémenter l'export des données utilisateur
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export des données à venir'),
        backgroundColor: Color(0xFF0A7EA4),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Copié dans le presse-papier'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// Modèle de statistiques du profil
class ProfileStats {
  final int emittedBons;
  final int receivedBons;
  final double totalEmitted;
  final double totalReceived;
  final double totalExchanged;
  final int activeBons;
  final int totalTransfers;

  ProfileStats({
    required this.emittedBons,
    required this.receivedBons,
    required this.totalEmitted,
    required this.totalReceived,
    required this.totalExchanged,
    required this.activeBons,
    required this.totalTransfers,
  });
}
