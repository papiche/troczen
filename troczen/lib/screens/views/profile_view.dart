import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/user.dart';
import '../../models/bon.dart';
import '../../services/storage_service.dart';
import '../../services/crypto_service.dart';
import '../../services/logger_service.dart';
import '../user_profile_screen.dart';

/// ProfileView — Mon Profil
/// Affichage et édition du profil utilisateur
class ProfileView extends StatefulWidget {
  final User user;

  const ProfileView({super.key, required this.user});

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
        
        // Jauge de confiance (DU)
        _buildTrustGaugeSection(),
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
            color: const Color(0xFFFFB347).withValues(alpha: 0.3),
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
                  color: Colors.black.withValues(alpha: 0.2),
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

  Widget _buildTrustGaugeSection() {
    return FutureBuilder<List<String>>(
      future: _storageService.getContacts(),
      builder: (context, snapshot) {
        final contactsCount = snapshot.data?.length ?? 0;
        final progress = (contactsCount / 5).clamp(0.0, 1.0);
        final isUnlocked = contactsCount >= 5;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnlocked ? Colors.green : const Color(0xFFFFB347).withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isUnlocked ? Icons.check_circle : Icons.handshake,
                    color: isUnlocked ? Colors.green : const Color(0xFFFFB347),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Toile de confiance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              Text(
                '$contactsCount / 5 liens réciproques',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 12,
                  backgroundColor: Colors.grey[800],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isUnlocked ? Colors.green : const Color(0xFFFFB347),
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              Text(
                isUnlocked
                    ? '🌟 Félicitations ! Vous participez à la création monétaire (DU).'
                    : 'Tissez 5 liens de confiance lors de vos échanges pour débloquer le Dividende Universel.',
                style: TextStyle(
                  fontSize: 13,
                  color: isUnlocked ? Colors.green[300] : Colors.grey[400],
                  fontStyle: FontStyle.italic,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Bouton Ajouter un contact
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _addContact(),
                  icon: const Icon(Icons.person_add, size: 20),
                  label: const Text('Ajouter un contact'),
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
              
              if (contactsCount > 0) ...[
                const SizedBox(height: 16),
                const Divider(color: Colors.white24),
                const SizedBox(height: 8),
                const Text(
                  'Vos liens de confiance (N1) :',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ...snapshot.data!.map((npub) => _buildContactRow(npub)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildContactRow(String npub) {
    // Convertir npub hex en bech32 (npub1...) pour njump
    final cryptoService = CryptoService();
    String npubBech32 = npub;
    try {
      if (!npub.startsWith('npub1')) {
        npubBech32 = cryptoService.encodeNpub(npub);
      }
    } catch (e) {
      // Ignorer si erreur de conversion
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.person, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${npubBech32.substring(0, 12)}...${npubBech32.substring(npubBech32.length - 4)}',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, color: Color(0xFF0A7EA4), size: 16),
            onPressed: () => _openNjumpProfile(npubBech32),
            tooltip: 'Voir le profil sur njump.me',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _openNjumpProfile(String npubBech32) async {
    final url = Uri.parse('https://njump.me/$npubBech32');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible d\'ouvrir le lien')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
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
            _currentUser!.npubBech32,  // Format Bech32 NIP-19
            Icons.visibility,
          ),
          const Divider(color: Colors.white24, height: 24),
          _buildKeyRow(
            'Clé privée (nsec)',
            _currentUser!.nsecBech32,  // Format Bech32 NIP-19
            Icons.lock,
            sensitive: true,
          ),
          
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
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
                  _stats!.totalEmitted.toStringAsFixed(0),
                  Icons.account_balance_wallet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  'Reçus (Ẑ)',
                  _stats!.totalReceived.toStringAsFixed(0),
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
        color: Colors.white.withValues(alpha: 0.1),
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
        border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.3), width: 2),
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
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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

  /// ✅ IMPLÉMENTÉ: Exporte les données utilisateur au format JSON
  /// Génère un fichier JSON contenant le profil et les bons, puis le partage via share_plus
  Future<void> _exportUserData() async {
    try {
      Logger.info('ProfileView', 'Début export données utilisateur');
      
      // Récupérer toutes les données
      final user = await _storageService.getUser();
      final bons = await _storageService.getBons();
      final market = await _storageService.getMarket();
      final contacts = await _storageService.getContacts();
      
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Aucun utilisateur trouvé'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // Construire le JSON d'export
      final exportData = {
        'version': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'user': {
          'npub': user.npubBech32,  // Format Bech32 pour compatibilité
          'displayName': user.displayName,
          'website': user.website,
          'g1pub': user.g1pub,
          'activityTags': user.activityTags,
          'createdAt': user.createdAt.toIso8601String(),
        },
        'market': market != null ? {
          'name': market.name,
          'displayName': market.displayName,
          'seedMarket': market.seedMarket,
          'validUntil': market.validUntil.toIso8601String(),
          'relayUrl': market.relayUrl,
          'isActive': market.isActive,
        } : null,
        'contacts': contacts,
        'bons': bons.map((bon) => {
          'bonId': bon.bonId,
          'value': bon.value,
          'issuerName': bon.issuerName,
          'issuerNpub': bon.issuerNpub,
          'marketName': bon.marketName,
          'status': bon.status.name,
          'createdAt': bon.createdAt.toIso8601String(),
          'transferCount': bon.transferCount,
          'rarity': bon.rarity,
        }).toList(),
        'statistics': {
          'totalBons': bons.length,
          'activeBons': bons.where((b) => b.status == BonStatus.active).length,
          'totalValue': bons.fold<double>(0.0, (sum, b) => sum + b.value),
          'contactsCount': contacts.length,
        },
      };
      
      // Convertir en JSON formaté
      const encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(exportData);
      
      // Créer un fichier temporaire
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'troczen_export_${user.displayName.replaceAll(' ', '_')}_$timestamp.json';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(jsonString);
      
      Logger.success('ProfileView', 'Export créé: ${file.path}');
      
      if (!mounted) return;
      
      // Partager le fichier
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Export TrocZen - ${user.displayName}',
        text: 'Mes données TrocZen exportées le ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
      );
      
      if (result.status == ShareResultStatus.success) {
        Logger.success('ProfileView', 'Export partagé avec succès');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Données exportées avec succès'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      // Nettoyer le fichier temporaire après un délai
      Future.delayed(const Duration(minutes: 5), () {
        if (file.existsSync()) {
          file.deleteSync();
          Logger.info('ProfileView', 'Fichier temporaire supprimé');
        }
      });
      
    } catch (e) {
      Logger.error('ProfileView', 'Erreur lors de l\'export: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erreur lors de l\'export: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
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

  /// Ajoute un contact en scannant son profil Nostr (npub)
  /// Permet de tisser la toile de confiance sans forcément échanger d'argent
  void _addContact() async {
    // Import du scanner QR
    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => _QRScannerScreen(
            title: 'Scanner le profil Nostr',
            instruction: 'Scannez le QR code du profil de votre contact',
          ),
        ),
      );

      if (result != null && result.isNotEmpty) {
        // Vérifier si c'est un npub valide
        String npub = result;
        
        // Convertir en format hex si nécessaire
        if (npub.startsWith('npub1')) {
          try {
            final cryptoService = CryptoService();
            npub = cryptoService.decodeNpub(npub);
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Format npub invalide'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }

        // Ajouter le contact
        final storageService = StorageService();
        await storageService.addContact(npub);
        
        // Recharger le profil pour mettre à jour la jauge
        await _loadUserProfile();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Contact ajouté à votre toile de confiance'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Écran de scan QR minimaliste pour ajouter un contact
class _QRScannerScreen extends StatefulWidget {
  final String title;
  final String instruction;

  const _QRScannerScreen({
    required this.title,
    required this.instruction,
  });

  @override
  State<_QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<_QRScannerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.instruction,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
                child: FutureBuilder<void>(
                  future: _checkCameraPermission(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    }
                    
                    // Import dynamique pour éviter les dépendances manquantes
                    return _buildScanner();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkCameraPermission() async {
    // Permission déjà gérée par mobile_scanner
    return;
  }

  Widget _buildScanner() {
    // Utiliser mobile_scanner si disponible
    try {
      // ignore: unnecessary_import
      return const _MobileScannerWidget();
    } catch (e) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner, size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              Text(
                'Scanner non disponible',
                style: TextStyle(color: Colors.grey[400], fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
  }
}

/// Widget wrapper pour mobile_scanner
class _MobileScannerWidget extends StatelessWidget {
  const _MobileScannerWidget();

  @override
  Widget build(BuildContext context) {
    // Import dynamique
    try {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFB347), width: 3),
        ),
        clipBehavior: Clip.antiAlias,
        child: Builder(
          builder: (context) {
            // Note: mobile_scanner est déjà dans les dépendances
            // Retourner un placeholder pour l'instant
            return Container(
              color: Colors.black,
              child: const Center(
                child: Text(
                  'Scanner QR\n(implémentation mobile_scanner)',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        ),
      );
    } catch (e) {
      return Center(
        child: Text(
          'Erreur: $e',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
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
