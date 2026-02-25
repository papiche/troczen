import 'package:flutter/material.dart';
import '../models/bon.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/logger_service.dart';
import '../services/image_compression_service.dart';
import '../models/nostr_profile.dart';

class BonJourneyScreen extends StatefulWidget {
  final Bon bon;

  const BonJourneyScreen({super.key, required this.bon});

  @override
  State<BonJourneyScreen> createState() => _BonJourneyScreenState();
}

class _BonJourneyScreenState extends State<BonJourneyScreen> {
  final _storageService = StorageService();
  final _cryptoService = CryptoService();
  late NostrService _nostrService;

  bool _isLoading = true;
  List<Map<String, dynamic>> _transfers = [];
  NostrProfile? _issuerProfile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nostrService = NostrService(
      cryptoService: _cryptoService,
      storageService: _storageService,
    );
    _loadJourney();
  }

  Future<void> _loadJourney() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final market = await _storageService.getMarket();
      if (market == null || market.relayUrl == null) {
        throw Exception('Marché non configuré ou sans relais');
      }

      final connected = await _nostrService.connect(market.relayUrl!);
      if (!connected) {
        throw Exception('Impossible de se connecter au relais Nostr');
      }

      // Récupérer les événements de transfert (Kind 1) pour ce bon
      final transfers = await _nostrService.fetchBonTransfers(widget.bon.bonId);
      
      // Trier par date (du plus ancien au plus récent)
      transfers.sort((a, b) => (a['created_at'] as int).compareTo(b['created_at'] as int));

      // Récupérer le profil de l'émetteur pour afficher ses compétences
      final issuerProfile = await _nostrService.fetchUserProfile(widget.bon.issuerNpub);

      if (mounted) {
        setState(() {
          _transfers = transfers;
          _issuerProfile = issuerProfile;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('BonJourneyScreen', 'Erreur chargement carnet de voyage', e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      await _nostrService.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Carnet de Voyage'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _error != null
              ? _buildErrorState()
              : _buildJourneyContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              'Erreur de chargement',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadJourney,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Réessayer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJourneyContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // En-tête du bon
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB347).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Background (Banner or Gradient)
                if (widget.bon.picture != null || widget.bon.picture64 != null)
                  Positioned.fill(
                    child: ImageCompressionService.buildImage(
                      uri: widget.bon.picture,
                      fallbackUri: widget.bon.picture64,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  
                // Overlay to ensure text readability if banner is present
                if (widget.bon.picture != null || widget.bon.picture64 != null)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  
                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${widget.bon.value.toStringAsFixed(0)} ẐEN',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2))],
                            ),
                          ),
                          const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Émis par ${widget.bon.issuerName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))],
                        ),
                      ),
                      if (_issuerProfile?.skillCredentials != null && _issuerProfile!.skillCredentials!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Compétences vérifiées',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _issuerProfile!.skillCredentials!.map((cred) => _buildSkillBadgeWithReaction(cred, widget.bon.issuerNpub)).toList(),
                        ),
                      ],
                      if (widget.bon.wish != null && widget.bon.wish!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.campaign, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Petite Annonce (Vœu)',
                                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '"${widget.bon.wish}"',
                                      style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        const Text(
          'Le Voyage du Bon',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        if (_transfers.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: const Text(
              'Ce bon n\'a pas encore voyagé. Il est toujours chez son émetteur ou son premier destinataire.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          )
        else
          _buildTimeline(),
      ],
    );
  }

  Widget _buildTimeline() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _transfers.length + 1, // +1 pour la création initiale
      itemBuilder: (context, index) {
        if (index == 0) {
          // Étape de création
          return _buildTimelineItem(
            title: 'Création du bon',
            subtitle: 'Par ${widget.bon.issuerName}',
            date: widget.bon.createdAt,
            icon: Icons.add_circle,
            color: Colors.green,
            isFirst: true,
            isLast: _transfers.isEmpty,
          );
        }

        final transfer = _transfers[index - 1];
        final date = DateTime.fromMillisecondsSinceEpoch((transfer['created_at'] as int) * 1000);
        
        // Extraire le destinataire (tag 'p')
        String receiverNpub = 'Inconnu';
        final tags = transfer['tags'] as List;
        for (final tag in tags) {
          if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
            receiverNpub = tag[1].toString();
            // Convertir en bech32 pour affichage court
            try {
              if (!receiverNpub.startsWith('npub1')) {
                receiverNpub = _cryptoService.encodeNpub(receiverNpub);
              }
              receiverNpub = '${receiverNpub.substring(0, 8)}...${receiverNpub.substring(receiverNpub.length - 4)}';
            } catch (_) {}
            break;
          }
        }

        return _buildTimelineItem(
          title: 'Transfert',
          subtitle: 'Vers $receiverNpub',
          date: date,
          icon: Icons.swap_horiz,
          color: Colors.orange,
          isFirst: false,
          isLast: index == _transfers.length,
        );
      },
    );
  }

  Widget _buildTimelineItem({
    required String title,
    required String subtitle,
    required DateTime date,
    required IconData icon,
    required Color color,
    required bool isFirst,
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ligne et point
          SizedBox(
            width: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ligne verticale
                Positioned(
                  top: isFirst ? 20 : 0,
                  bottom: isLast ? null : 0,
                  height: isLast ? 20 : null,
                  child: Container(
                    width: 2,
                    color: Colors.white24,
                  ),
                ),
                // Point
                Positioned(
                  top: 20,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF121212), width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Contenu
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(date),
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// ✅ WOTX2: Construit un badge de compétence individuel avec boutons de réaction
  Widget _buildSkillBadgeWithReaction(SkillCredential cred, String artisanNpub) {
    final color = _getLevelColor(cred.level);
    final badgeText = '${cred.skillTag} ${cred.badgeLabel}';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            badgeText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (cred.eventId != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _reactToSkill(cred, artisanNpub, true),
              child: const Icon(Icons.thumb_up, size: 14, color: Colors.green),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _reactToSkill(cred, artisanNpub, false),
              child: const Icon(Icons.thumb_down, size: 14, color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }

  Color _getLevelColor(int level) {
    switch (level) {
      case 1: return const Color(0xFF4CAF50); // Vert
      case 2: return const Color(0xFF2196F3); // Bleu
      case 3: return const Color(0xFF9C27B0); // Violet
      default: return const Color(0xFF9E9E9E); // Gris
    }
  }

  Future<void> _reactToSkill(SkillCredential cred, String artisanNpub, bool isPositive) async {
    if (cred.eventId == null) return;
    
    try {
      final user = await _storageService.getUser();
      if (user == null) return;

      final market = await _storageService.getMarket();
      if (market == null || market.relayUrl == null) return;

      final connected = await _nostrService.connect(market.relayUrl!);
      if (connected) {
        final success = await _nostrService.publishSkillReaction(
          myNpub: user.npub,
          myNsec: user.nsec,
          artisanNpub: artisanNpub,
          eventId: cred.eventId!,
          isPositive: isPositive,
        );
        
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isPositive ? '✅ Avis positif envoyé !' : '✅ Avis négatif envoyé !'),
              backgroundColor: isPositive ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('BonJourneyScreen', 'Erreur réaction compétence', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
