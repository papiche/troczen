import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/nostr_profile.dart';
import '../services/qr_service.dart';
import '../services/nostr_service.dart';
import '../services/cache_database_service.dart';
import '../utils/nostr_utils.dart';
import '../widgets/circuit_revelation_widget.dart'; // Pour l'animation de célébration

class SkillSwapScreen extends StatefulWidget {
  final User user;
  final String skillTag;

  const SkillSwapScreen({
    super.key,
    required this.user,
    required this.skillTag,
  });

  @override
  State<SkillSwapScreen> createState() => _SkillSwapScreenState();
}

class _SkillSwapScreenState extends State<SkillSwapScreen> {
  final _qrService = QRService();
  final _cacheService = CacheDatabaseService();

  MobileScannerController? _scannerController;
  bool _isScanning = false;
  bool _isProcessing = false;
  bool _showCelebration = false;
  String _celebrationMessage = '';

  int _myLevel = 0;
  bool _levelLoading = true;

  @override
  void initState() {
    super.initState();
    _initScanner();
    _syncAndLoadLevel();
  }

  Future<void> _syncAndLoadLevel() async {
    setState(() => _levelLoading = true);
    final nostrService = context.read<NostrService>();
    final normalizedSkill = NostrUtils.normalizeSkillTag(widget.skillTag);

    // Synchronise les achievements depuis le relay puis charge le niveau local
    final events = await nostrService.wotx.fetchMyAchievements(widget.user.npub);
    for (final event in events) {
      await _cacheService.saveSkillAchievement(event);
    }

    final level = await _cacheService.getMySkillLevel(widget.user.npub, normalizedSkill);
    if (mounted) setState(() { _myLevel = level; _levelLoading = false; });
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  String get _qrPayload {
    final payload = {
      'type': 'skill_swap',
      'npub': widget.user.npub,
      'name': widget.user.displayName,
      'skill': widget.skillTag,
    };
    return jsonEncode(payload);
  }

  void _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null) return;

    try {
      final data = jsonDecode(rawValue) as Map<String, dynamic>;
      if (data['type'] != 'skill_swap') return;

      final targetNpub = data['npub'] as String;
      final targetName = data['name'] as String;
      final targetSkill = data['skill'] as String;

      if (targetNpub == widget.user.npub) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vous ne pouvez pas vous certifier vous-même.')),
        );
        return;
      }

      if (NostrUtils.normalizeSkillTag(targetSkill) != NostrUtils.normalizeSkillTag(widget.skillTag)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Compétence différente: $targetSkill')),
        );
        return;
      }

      setState(() {
        _isProcessing = true;
        _isScanning = false;
      });

      _showValidationDialog(targetNpub, targetName, targetSkill);

    } catch (e) {
      // Not a valid skill swap QR
    }
  }

  Future<void> _showValidationDialog(String targetNpub, String targetName, String targetSkill) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          'Évaluer $targetName en $targetSkill ?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          _myLevel > 0
              ? 'Votre niveau : X$_myLevel. Choisissez votre type de validation.'
              : 'Choisissez votre type de validation.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'kind7_negative'),
            icon: const Icon(Icons.thumb_down),
            label: const Text('Dislike'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[900],
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'kind7'),
            icon: const Icon(Icons.thumb_up),
            label: const Text('Like'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
          if (_myLevel > 0) // Règle B : Adoubement si l'utilisateur a lui-même un niveau
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'kind30502'),
              icon: const Icon(Icons.workspace_premium),
              label: const Text('Adoubement'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
            ),
        ],
      ),
    );

    if (result == 'cancel' || result == null) {
      setState(() {
        _isProcessing = false;
        _isScanning = true;
      });
      return;
    }

    // On a besoin de l'ID du permit de la cible.
    // Pour simplifier, on le reconstruit (PERMIT_SKILL_X1)
    final normalizedSkill = NostrUtils.normalizeSkillTag(targetSkill);
    final permitId = 'PERMIT_${normalizedSkill.toUpperCase()}_X1';
    
    // On génère un faux eventId pour le permit si on ne l'a pas
    // Dans une vraie app, on devrait le chercher dans le cache
    final permitEventId = '0000000000000000000000000000000000000000000000000000000000000000';

    bool success = false;

    if (!mounted) return;
    final nostrService = context.read<NostrService>();

    if (result == 'kind7' || result == 'kind7_negative') {
      success = await nostrService.wotx.publishSkillReaction(
        myNpub: widget.user.npub,
        myNsec: widget.user.nsec,
        artisanNpub: targetNpub,
        eventId: permitEventId,
        skillTag: targetSkill,
        isPositive: result == 'kind7',
      );
    } else if (result == 'kind30502') {
      success = await nostrService.wotx.publishSkillAttestation(
        myNpub: widget.user.npub,
        myNsec: widget.user.nsec,
        requestId: permitEventId,
        requesterNpub: targetNpub,
        permitId: permitId,
        seedMarket: NostrConstants.globalMarketKey,
        motivation: 'Adoubement par un pair de niveau X$_myLevel',
      );
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Validation envoyée à $targetName !'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de l\'envoi de la validation.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isProcessing = false;
          _isScanning = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showCelebration) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: CircuitRevelationWidget(
          customMessage: _celebrationMessage,
          onClose: () {
            if (mounted) Navigator.pop(context);
          },
        ),
      );
    }

    return Scaffold(
      
      appBar: AppBar(
        title: const Text('Échange de Savoir-Faire'),
        backgroundColor: Colors.indigo,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Toggle Scan / Show
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _isScanning = false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_isScanning ? Colors.indigo : Colors.grey[800],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Mon QR'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _isScanning = true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isScanning ? Colors.indigo : Colors.grey[800],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Scanner'),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isScanning ? _buildScanner() : _buildMyQr(),
          ),
        ],
      ),
    );
  }

  Widget _buildMyQr() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Faites scanner ce QR par un pair',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            widget.skillTag,
            style: const TextStyle(
              color: Colors.indigoAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _levelLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
                )
              : Text(
                  _myLevel > 0 ? 'Niveau X$_myLevel' : 'Niveau X0 (en cours)',
                  style: TextStyle(
                    color: _myLevel > 0 ? Colors.amber : Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _qrService.buildQrWidget(
              Uint8List.fromList(utf8.encode(_qrPayload)),
              size: 250
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _checkMyUpgrades,
            icon: const Icon(Icons.refresh),
            label: const Text('Vérifier mes montées de niveau'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        if (_scannerController != null)
          MobileScanner(
            controller: _scannerController!,
            onDetect: _handleScan,
          ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.indigo, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Text(
            'Scannez le QR d\'un pair',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _checkMyUpgrades() async {
    final normalizedSkill = NostrUtils.normalizeSkillTag(widget.skillTag);

    final upgradeInfo = await _cacheService.checkLevelUpgrade(
      widget.user.npub,
      normalizedSkill,
      _myLevel,
    );

    if (upgradeInfo['canUpgrade'] == true) {
      final newLevel = upgradeInfo['newLevel'] as int;
      final justifications = (upgradeInfo['justificationEvents'] as List).cast<String>();
      final rule = upgradeInfo['rule'] as String? ?? 'A';

      if (!mounted) return;
      final nostrService = context.read<NostrService>();
      final success = await nostrService.wotx.publishSkillAchievement(
        myNpub: widget.user.npub,
        myNsec: widget.user.nsec,
        skillTag: normalizedSkill,
        newLevel: newLevel,
        justificationEventIds: justifications,
      );

      if (success && mounted) {
        // Persister localement le nouvel achievement
        await _cacheService.saveSkillAchievement({
          'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
          'pubkey': widget.user.npub,
          'kind': 30503,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'tags': [
            ['t', normalizedSkill],
            ['level', newLevel.toString()],
            for (final j in justifications) ['e', j],
          ],
          'content': '{"type":"skill_achievement","skill":"$normalizedSkill","level":$newLevel}',
        });

        final ruleLabel = rule == 'B' ? 'adoubement' : 'consensus de vos pairs';
        setState(() {
          _myLevel = newLevel;
          _celebrationMessage =
              'Bravo ! Vous atteignez le niveau X$newLevel en ${widget.skillTag} par $ruleLabel !';
          _showCelebration = true;
        });

        // Vérifier si un fork de confiance est détecté
        final fork = await _cacheService.checkDislikeFork(widget.user.npub, normalizedSkill);
        if (fork['hasFork'] == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Bifurcation détectée sur "$normalizedSkill" : ${(fork['campB'] as List).length} pairs alternatifs.',
              ),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } else {
      final reactions = await _cacheService.getSkillReactionsForSubject(widget.user.npub, normalizedSkill);
      final positives = reactions.where((r) => r['content'] == '+').length;
      final needed = 3 - positives;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            needed > 0
                ? 'Encore $needed like(s) de pairs distincts pour monter de niveau.'
                : 'Pas encore assez de validations pour monter de niveau.',
          ),
        ),
      );
    }
  }
}
