import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../services/logger_service.dart';
import '../services/cache_database_service.dart';
import 'skill_swap_screen.dart';
import 'package:provider/provider.dart';

class TrustWebScreen extends StatefulWidget {
  final User user;

  const TrustWebScreen({super.key, required this.user});

  @override
  State<TrustWebScreen> createState() => _TrustWebScreenState();
}

class _TrustWebScreenState extends State<TrustWebScreen> with SingleTickerProviderStateMixin {
  final _storageService = StorageService();
  final _cacheService = CacheDatabaseService();
  late NostrService _nostrService;
  late TabController _tabController;

  // Réseau social
  bool _isLoading = true;
  List<String> _n1 = [];
  List<String> _followers = [];
  List<String> _p2p = [];
  List<String> _outgoing = [];
  List<String> _p21 = [];
  bool _isSyncingN2 = false;

  // Skills WoTx
  bool _skillsLoading = false;
  Map<String, int> _mySkillLevels = {};
  // holders groupés par skill : { skill -> [{holder_npub, max_level, score}] }
  Map<String, List<_SkillHolder>> _holdersBySkill = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _nostrService = context.read<NostrService>();
    _loadNetwork();
    // Charge les données skills en parallèle
    _tabController.addListener(() {
      if ((_tabController.index == 2 || _tabController.index == 3) &&
          _holdersBySkill.isEmpty &&
          !_skillsLoading) {
        _loadSkillsData();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // CHARGEMENT RÉSEAU SOCIAL
  // ----------------------------------------------------------------

  Future<void> _loadNetwork() async {
    setState(() => _isLoading = true);
    try {
      _n1 = await _storageService.getContacts();
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        if (await _nostrService.connect(market!.relayUrl!)) {
          _followers = await _nostrService.fetchFollowers(widget.user.npub);
          await _nostrService.disconnect();
        }
      }
      _p2p = _n1.where((npub) => _followers.contains(npub)).toList();
      _outgoing = _n1.where((npub) => !_followers.contains(npub)).toList();
      _p21 = _followers.where((npub) => !_n1.contains(npub)).toList();
    } catch (e) {
      Logger.error('TrustWebScreen', 'Erreur chargement réseau', e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncN2() async {
    setState(() => _isSyncingN2 = true);
    try {
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        if (await _nostrService.connect(market!.relayUrl!)) {
          final contactLists = await _nostrService.fetchMultipleContactLists(_p2p);
          final n2Contacts = <Map<String, String>>[];
          await _cacheService.clearN2Cache();
          for (final entry in contactLists.entries) {
            for (final contact in entry.value) {
              if (contact != widget.user.npub && !_n1.contains(contact)) {
                n2Contacts.add({'npub': contact, 'via_n1_npub': entry.key});
              }
            }
          }
          await _cacheService.saveN2ContactsBatch(n2Contacts);
          await _nostrService.disconnect();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Réseau N2 synchronisé (${n2Contacts.length} contacts)'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      Logger.error('TrustWebScreen', 'Erreur sync N2', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingN2 = false);
    }
  }

  Future<void> _acceptFollower(String npub) async {
    try {
      await _storageService.addContact(npub);
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        if (await _nostrService.connect(market!.relayUrl!)) {
          final contacts = await _storageService.getContacts();
          await _nostrService.publishContactList(
            npub: widget.user.npub,
            nsec: widget.user.nsec,
            contactsNpubs: contacts,
          );
          await _nostrService.disconnect();
        }
      }
      await _loadNetwork();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact ajouté'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      Logger.error('TrustWebScreen', 'Erreur acceptation follower', e);
    }
  }

  // ----------------------------------------------------------------
  // CHARGEMENT SKILLS WOTX
  // ----------------------------------------------------------------

  Future<void> _loadSkillsData() async {
    if (_skillsLoading) return;
    setState(() => _skillsLoading = true);

    try {
      // 1. Synchroniser tous les achievements depuis le relay
      final market = await _storageService.getMarket();
      if (market?.relayUrl != null) {
        if (await _nostrService.connect(market!.relayUrl!)) {
          final events = await _nostrService.wotx.fetchAllSkillAchievements();
          for (final event in events) {
            await _cacheService.saveSkillAchievement(event);
          }
          await _nostrService.disconnect();
        }
      }

      // 2. Charger mes niveaux
      _mySkillLevels = await _cacheService.getAllMySkillLevels(widget.user.npub);

      // 3. Charger tous les holders avec scoring subjectif
      final rawHolders = await _cacheService.getAllSkillHolders();
      final grouped = <String, List<_SkillHolder>>{};

      for (final row in rawHolders) {
        final holderNpub = row['holder_npub'] as String;
        if (holderNpub == widget.user.npub) continue; // exclure soi-même
        final skill = row['skill'] as String;
        final level = row['max_level'] as int;
        final score = await _cacheService.getSubjectiveTrustScore(_n1, holderNpub, skill);
        grouped.putIfAbsent(skill, () => []).add(_SkillHolder(
          npub: holderNpub,
          level: level,
          score: score,
        ));
      }

      // Trier chaque groupe par score décroissant
      for (final holders in grouped.values) {
        holders.sort((a, b) => b.score.compareTo(a.score));
      }

      if (mounted) setState(() => _holdersBySkill = grouped);
    } catch (e) {
      Logger.error('TrustWebScreen', 'Erreur chargement skills', e);
    } finally {
      if (mounted) setState(() => _skillsLoading = false);
    }
  }

  // ----------------------------------------------------------------
  // BUILD
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Toile de Confiance'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFB347),
          labelColor: const Color(0xFFFFB347),
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Liens N1'),
            Tab(text: 'Réseau N2'),
            Tab(text: 'Trouver'),
            Tab(text: 'Progresser'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildN1Tab(),
                _buildN2Tab(),
                _buildFindTab(),
                _buildProgressTab(),
              ],
            ),
    );
  }

  // ----------------------------------------------------------------
  // ONGLET N1
  // ----------------------------------------------------------------

  Widget _buildN1Tab() {
    return RefreshIndicator(
      onRefresh: _loadNetwork,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('🤝 P2P (Mutuel)', 'Vous vous suivez mutuellement.'),
          if (_p2p.isEmpty)
            _buildEmptyState('Aucun lien mutuel')
          else
            ..._p2p.map((npub) => _buildContactRow(npub, type: 'p2p')),
          const SizedBox(height: 24),
          _buildSectionHeader('➡️ Sortant (12P)', 'Vous les suivez — ils ne vous suivent pas.'),
          if (_outgoing.isEmpty)
            _buildEmptyState('Aucun lien sortant')
          else
            ..._outgoing.map((npub) => _buildContactRow(npub, type: '12p')),
          const SizedBox(height: 24),
          _buildSectionHeader('⬅️ Entrant (P21)', 'Ils vous suivent — vous ne les suivez pas.'),
          if (_p21.isEmpty)
            _buildEmptyState('Aucun lien entrant')
          else
            ..._p21.map((npub) => _buildContactRow(npub, type: 'p21')),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // ONGLET N2
  // ----------------------------------------------------------------

  Widget _buildN2Tab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.hub, size: 80, color: Color(0xFFFFB347)),
          const SizedBox(height: 24),
          const Text(
            'Réseau Étendu (N2)',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'Synchronisez les contacts de vos liens P2P pour étendre votre toile hors-ligne.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSyncingN2 ? null : _syncN2,
              icon: _isSyncingN2
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.sync),
              label: Text(_isSyncingN2 ? 'Synchronisation...' : 'Synchroniser mon Réseau'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB347),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // ONGLET "TROUVER" — Skills que je ne possède pas
  // ----------------------------------------------------------------

  Widget _buildFindTab() {
    if (_skillsLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFFFB347)),
            SizedBox(height: 16),
            Text('Chargement des compétences du réseau...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_holdersBySkill.isEmpty) {
      return _buildLoadSkillsButton(
        icon: Icons.search,
        title: 'Découvrir les experts',
        subtitle: 'Trouvez les compétences disponibles dans votre réseau que vous ne possédez pas encore.',
      );
    }

    // Skills présents sur le réseau mais absents de mon profil
    final availableSkills = _holdersBySkill.keys
        .where((skill) => !_mySkillLevels.containsKey(skill))
        .toList()
      ..sort((a, b) {
        // Trier par score moyen décroissant
        final avgA = _avgScore(_holdersBySkill[a]!);
        final avgB = _avgScore(_holdersBySkill[b]!);
        return avgB.compareTo(avgA);
      });

    if (availableSkills.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emoji_events, size: 64, color: Color(0xFFFFB347)),
              const SizedBox(height: 16),
              const Text(
                'Vous maîtrisez déjà tous les skills du réseau !',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _loadSkillsData,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFFB347)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSkillsData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: availableSkills.length,
        itemBuilder: (context, index) {
          final skill = availableSkills[index];
          final holders = _holdersBySkill[skill]!;
          return _buildSkillCard(
            skill: skill,
            holders: holders,
            myLevel: 0,
            mode: 'find',
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------------
  // ONGLET "PROGRESSER" — Skills que je possède, cherche des pairs
  // ----------------------------------------------------------------

  Widget _buildProgressTab() {
    if (_skillsLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFFFB347)),
            SizedBox(height: 16),
            Text('Analyse de vos compétences...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_holdersBySkill.isEmpty && _mySkillLevels.isEmpty) {
      return _buildLoadSkillsButton(
        icon: Icons.trending_up,
        title: 'Progresser dans vos compétences',
        subtitle: 'Trouvez des pairs et des mentors pour monter en niveau.',
      );
    }

    if (_mySkillLevels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_circle_outline, size: 64, color: Colors.white38),
              const SizedBox(height: 16),
              const Text(
                'Vous n\'avez pas encore déclaré de compétences.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Allez dans Échange de Savoir-Faire pour déclarer vos compétences.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final mySkills = _mySkillLevels.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _loadSkillsData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: mySkills.length,
        itemBuilder: (context, index) {
          final entry = mySkills[index];
          final skill = entry.key;
          final myLevel = entry.value;
          final holders = _holdersBySkill[skill] ?? [];
          // Garder uniquement les pairs de niveau >= myLevel (pour apprendre)
          final relevantHolders = holders
              .where((h) => h.level >= myLevel)
              .toList();
          return _buildSkillCard(
            skill: skill,
            holders: relevantHolders,
            myLevel: myLevel,
            mode: 'progress',
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------------
  // WIDGETS PARTAGÉS
  // ----------------------------------------------------------------

  Widget _buildLoadSkillsButton({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: const Color(0xFFFFB347)),
          const SizedBox(height: 24),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loadSkillsData,
              icon: const Icon(Icons.sync),
              label: const Text('Charger les compétences du réseau'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB347),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillCard({
    required String skill,
    required List<_SkillHolder> holders,
    required int myLevel,
    required String mode, // 'find' | 'progress'
  }) {
    final visibleHolders = holders.take(5).toList();
    final hiddenCount = holders.length - visibleHolders.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête du skill
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        skill,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mode == 'find'
                            ? '${holders.length} expert${holders.length > 1 ? 's' : ''} dans le réseau'
                            : (myLevel > 0
                                ? 'Votre niveau : X$myLevel  •  ${holders.length} pair${holders.length > 1 ? 's' : ''} disponible${holders.length > 1 ? 's' : ''}'
                                : 'Aucun pair trouvé pour ce skill'),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (myLevel > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _levelColor(myLevel).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _levelColor(myLevel), width: 1),
                    ),
                    child: Text(
                      'X$myLevel',
                      style: TextStyle(
                        color: _levelColor(myLevel),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Liste des holders
          if (visibleHolders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                mode == 'progress'
                    ? 'Aucun pair de niveau ≥ X$myLevel trouvé. Partagez votre QR pour rencontrer des pairs !'
                    : 'Aucun expert trouvé pour l\'instant.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13, fontStyle: FontStyle.italic),
              ),
            )
          else ...[
            ...visibleHolders.map((h) => _buildHolderRow(h, skill, mode)),
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '+ $hiddenCount autre${hiddenCount > 1 ? 's' : ''}...',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
          ],

          // Bouton d'action principal
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SkillSwapScreen(
                      user: widget.user,
                      skillTag: skill,
                    ),
                  ),
                ),
                icon: Icon(mode == 'find' ? Icons.qr_code_scanner : Icons.trending_up, size: 18),
                label: Text(
                  mode == 'find' ? 'Rencontrer un expert' : 'Scanner un pair',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: mode == 'find' ? Colors.indigo[700] : Colors.teal[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHolderRow(_SkillHolder holder, String skill, String mode) {
    final scoreColor = holder.score > 0
        ? Colors.green[400]!
        : holder.score < 0
            ? Colors.red[400]!
            : Colors.grey[500]!;

    final scoreLabel = holder.score > 3
        ? '+++' : holder.score > 1 ? '++' : holder.score > 0 ? '+'
        : holder.score < -3 ? '---' : holder.score < -1 ? '--' : holder.score < 0 ? '-' : '·';

    final cryptoService = CryptoService();
    String shortNpub = holder.npub;
    try {
      final bech32 = holder.npub.startsWith('npub1')
          ? holder.npub
          : cryptoService.encodeNpub(holder.npub);
      shortNpub = '${bech32.substring(0, 10)}…${bech32.substring(bech32.length - 4)}';
    } catch (_) {}

    final isN1 = _n1.contains(holder.npub);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isN1 ? Colors.green[800] : Colors.grey[800],
            child: Icon(
              isN1 ? Icons.person : Icons.person_outline,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shortNpub,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                if (isN1)
                  Text(
                    'Contact direct',
                    style: TextStyle(color: Colors.green[400], fontSize: 10),
                  ),
              ],
            ),
          ),
          // Niveau
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _levelColor(holder.level).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'X${holder.level}',
              style: TextStyle(
                color: _levelColor(holder.level),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Score subjectif
          SizedBox(
            width: 32,
            child: Text(
              scoreLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: scoreColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: -1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // HELPERS N1
  // ----------------------------------------------------------------

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(message,
          style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic)),
    );
  }

  Widget _buildContactRow(String npub, {required String type}) {
    final cryptoService = CryptoService();
    String npubBech32 = npub;
    try {
      if (!npub.startsWith('npub1')) {
        npubBech32 = cryptoService.encodeNpub(npub);
      }
    } catch (_) {}
    final shortNpub = '${npubBech32.substring(0, 12)}…${npubBech32.substring(npubBech32.length - 4)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: type == 'p2p' ? Colors.green : (type == '12p' ? Colors.orange : Colors.blue),
            child: const Icon(Icons.person, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              shortNpub,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          if (type == '12p')
            IconButton(
              icon: const Icon(Icons.qr_code, color: Color(0xFFFFB347), size: 20),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Demandez-lui de scanner votre QR-ID !')),
                );
              },
            )
          else if (type == 'p21')
            ElevatedButton(
              onPressed: () => _acceptFollower(npub),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Accepter', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // UTILS
  // ----------------------------------------------------------------

  double _avgScore(List<_SkillHolder> holders) {
    if (holders.isEmpty) return 0;
    return holders.fold(0, (sum, h) => sum + h.score) / holders.length;
  }

  Color _levelColor(int level) {
    if (level >= 11) return Colors.purple;
    if (level >= 5) return Colors.blue;
    if (level >= 2) return const Color(0xFFFFB347);
    return Colors.green;
  }
}

// Modèle léger pour un holder de skill avec son score subjectif
class _SkillHolder {
  final String npub;
  final int level;
  final int score;

  const _SkillHolder({required this.npub, required this.level, required this.score});
}
