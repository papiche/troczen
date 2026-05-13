import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bs58/bs58.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../services/storage_service.dart';
import '../../services/crypto_service.dart';
import '../../services/api_service.dart';
import '../../services/logger_service.dart';
import 'onboarding_flow.dart';

// Même isolate que onboarding_account_screen.dart
Future<Uint8List> _deriveSeedInIsolateImport(Map<String, String> args) async {
  final crypto = CryptoService();
  return await crypto.deriveSeed(args['salt']!, args['pepper']!);
}

/// Import d'un compte MULTIPASS existant (Astroport/Ẑelkova) via QR SSSS.
///
/// Le QR SSSS du MULTIPASS (affiché dans Ẑelkova → page contact → mode expert)
/// a le format :  M-<base58(SSSS_PART1:/ipns/k51...)>
///
/// Deux modes de récupération :
///   - Avec station : GET {apiUrl}/g1nostr?nostrns=... → nsec/npub/g1pub directs
///   - Autonome     : formulaire salt+pepper avec dérivation Scrypt locale
///     (mêmes paramètres N=4096,r=16,p=1 → mêmes clés que le MULTIPASS)
class OnboardingMultipassImportScreen extends StatefulWidget {
  final VoidCallback onImported;

  const OnboardingMultipassImportScreen({super.key, required this.onImported});

  @override
  State<OnboardingMultipassImportScreen> createState() =>
      _OnboardingMultipassImportScreenState();
}

enum _Phase { scan, confirm, loading, fallback }

class _OnboardingMultipassImportScreenState
    extends State<OnboardingMultipassImportScreen> {
  _Phase _phase = _Phase.scan;

  // Résultats du scan
  String _ssssHead = '';
  String _nostrns = '';

  // Formulaire fallback
  final _saltController = TextEditingController();
  final _pepperController = TextEditingController();
  bool _obscurePepper = true;
  String? _saltError;
  String? _pepperError;

  bool _isProcessing = false;
  String _statusMessage = '';

  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _saltController.dispose();
    _pepperController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // DÉCODAGE QR SSSS
  // ----------------------------------------------------------------

  /// Decode QR : M-<base58(SSSS_PART1:/ipns/k51...)>
  /// Retourne null si format non reconnu.
  ({String ssssHead, String nostrns})? _decodeMultipassQr(String raw) {
    if (!raw.startsWith('M-')) return null;
    try {
      final encoded = raw.substring(2);
      final decoded = utf8.decode(base58.decode(encoded));
      // Format : "1-<hex>:/ipns/k51..." — séparer sur le premier ':'
      final idx = decoded.indexOf(':');
      if (idx <= 0) return null;
      final ssssHead = decoded.substring(0, idx);
      final nostrns = decoded.substring(idx + 1);
      if (!ssssHead.startsWith('1-') || nostrns.isEmpty) return null;
      return (ssssHead: ssssHead, nostrns: nostrns);
    } catch (_) {
      return null;
    }
  }

  void _onQrDetected(BarcodeCapture capture) {
    if (_phase != _Phase.scan) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    final decoded = _decodeMultipassQr(raw);
    if (decoded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR non reconnu — attendu : QR SSSS du MULTIPASS (M-...)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _ssssHead = decoded.ssssHead;
      _nostrns = decoded.nostrns;
      _phase = _Phase.confirm;
    });
  }

  // ----------------------------------------------------------------
  // MODE 1 : IMPORT VIA API UPASSPORT
  // ----------------------------------------------------------------

  Future<void> _tryApiImport() async {
    setState(() {
      _phase = _Phase.loading;
      _statusMessage = 'Connexion à la station…';
    });

    try {
      final apiService = context.read<ApiService>();
      final apiUrl = apiService.apiUrl;

      setState(() => _statusMessage = 'Récupération du MULTIPASS…');

      final uri = Uri.parse('$apiUrl/g1nostr').replace(
        queryParameters: {'nostrns': _nostrns},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final nsec = data['nsec'] as String?;
        final npub = data['npub'] as String? ?? data['hex'] as String?;
        final g1pub = data['g1pub'] as String?;
        final email = data['email'] as String?;

        if (nsec != null && npub != null) {
          await _createAndSaveUser(
            nsec: nsec,
            npub: npub,
            g1pub: g1pub,
            displayName: email ?? 'MULTIPASS',
          );
          return;
        }
      }

      // API inaccessible ou réponse incomplète → fallback
      Logger.warn('MultipassImport', 'API non disponible (${response.statusCode}), bascule mode autonome');
      _goToFallback();
    } catch (e) {
      Logger.warn('MultipassImport', 'Erreur API, bascule mode autonome : $e');
      _goToFallback();
    }
  }

  void _goToFallback() {
    if (mounted) {
      setState(() {
        _phase = _Phase.fallback;
        _statusMessage = '';
      });
    }
  }

  // ----------------------------------------------------------------
  // MODE 2 : DÉRIVATION SCRYPT LOCALE (sans tiers de confiance)
  // ----------------------------------------------------------------

  Future<void> _importFromScrypt() async {
    final salt = _saltController.text.trim();
    final pepper = _pepperController.text;

    if (salt.isEmpty || salt.length < 3) {
      setState(() => _saltError = 'Minimum 3 caractères (ex : votre email)');
      return;
    }
    if (pepper.isEmpty || pepper.length < 8) {
      setState(() => _pepperError = 'Minimum 8 caractères');
      return;
    }

    setState(() {
      _isProcessing = true;
      _saltError = null;
      _pepperError = null;
    });

    try {
      final seedBytes = await compute(_deriveSeedInIsolateImport, {
        'salt': salt,
        'pepper': pepper,
      });

      final cryptoService = CryptoService();
      final privateKeyBytes = await cryptoService.deriveNostrPrivateKey(seedBytes);
      cryptoService.secureZeroiseBytes(seedBytes);

      final nsec = privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final npub = cryptoService.derivePublicKey(privateKeyBytes);
      final g1pub = cryptoService.generateG1Pub(privateKeyBytes);

      await _createAndSaveUser(nsec: nsec, npub: npub, g1pub: g1pub, displayName: salt);
    } catch (e) {
      setState(() => _isProcessing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ----------------------------------------------------------------
  // CRÉATION ET SAUVEGARDE DU USER
  // ----------------------------------------------------------------

  Future<void> _createAndSaveUser({
    required String nsec,
    required String npub,
    String? g1pub,
    String displayName = 'MULTIPASS',
  }) async {
    final storageService = StorageService();

    // Normaliser nsec/npub : supprimer préfixes bech32 si présents
    final nsecHex = _stripBech32(nsec, 'nsec1');
    final npubHex = _stripBech32(npub, 'npub1');

    final user = User(
      npub: npubHex,
      nsec: nsecHex,
      displayName: displayName,
      createdAt: DateTime.now(),
      g1pub: g1pub,
      activityTags: [],
    );

    await storageService.saveUser(user);
    final market = await storageService.initializeDefaultMarket(name: 'Marché Libre');

    if (mounted) {
      final notifier = context.read<OnboardingNotifier>();
      notifier.setSeedMarket(market.seedMarket, 'mode000');
      notifier.updateState(notifier.state.copyWith(marketName: market.name));
    }

    setState(() => _isProcessing = false);
    if (mounted) widget.onImported();
  }

  /// Supprime le préfixe bech32 (ex: "nsec1...") et renvoie le hex pur.
  /// Si la valeur est déjà en hex, la retourne telle quelle.
  String _stripBech32(String value, String prefix) {
    if (!value.startsWith(prefix)) return value;
    try {
      final cryptoService = CryptoService();
      if (prefix == 'nsec1') return cryptoService.decodeNsec(value);
      if (prefix == 'npub1') return cryptoService.decodeNpub(value);
    } catch (_) {}
    return value;
  }

  // ----------------------------------------------------------------
  // BUILD
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importer un MULTIPASS'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.scan => _buildScanPhase(),
          _Phase.confirm => _buildConfirmPhase(),
          _Phase.loading => _buildLoadingPhase(),
          _Phase.fallback => _buildFallbackPhase(),
        },
      ),
    );
  }

  // ---- Phase SCAN ----

  Widget _buildScanPhase() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                'Scannez le QR SSSS',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Dans Ẑelkova → votre profil → mode expert → QR SSSS',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                controller: _scannerController!,
                onDetect: _onQrDetected,
              ),
              Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFFB347), width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Text(
                  'Centrez le QR SSSS dans le cadre',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextButton.icon(
            onPressed: _goToFallback,
            icon: const Icon(Icons.keyboard, color: Colors.white54),
            label: const Text(
              'Saisir manuellement mes identifiants',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Phase CONFIRM ----

  Widget _buildConfirmPhase() {
    final shortNs = _nostrns.length > 30
        ? '${_nostrns.substring(0, 14)}…${_nostrns.substring(_nostrns.length - 12)}'
        : _nostrns;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user, size: 72, color: Color(0xFFFFB347)),
          const SizedBox(height: 24),
          const Text(
            'MULTIPASS détecté',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NOSTR NS', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                const SizedBox(height: 4),
                Text(shortNs, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 12),
                Text('Part SSSS', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  '${_ssssHead.substring(0, 10)}…',
                  style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'TrocZen va tenter de récupérer votre identité\nvia votre station UPlanet, ou dériver\nvos clés localement si elle est inaccessible.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _tryApiImport,
              icon: const Icon(Icons.download_done),
              label: const Text('Importer ce MULTIPASS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB347),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _phase = _Phase.scan),
            child: const Text('Rescanner', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  // ---- Phase LOADING ----

  Widget _buildLoadingPhase() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFFFFB347)),
          const SizedBox(height: 24),
          Text(
            _statusMessage,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ---- Phase FALLBACK (Scrypt autonome) ----

  Widget _buildFallbackPhase() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.lock_outline, size: 48, color: Color(0xFFFFB347)),
          const SizedBox(height: 16),
          const Text(
            'Mode autonome',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Station inaccessible — saisissez vos identifiants UPlanet.\nLes clés seront dérivées localement, sans aucun tiers.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5),
          ),
          if (_nostrns.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, color: Colors.indigoAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nostrns.length > 38
                          ? '${_nostrns.substring(0, 20)}…${_nostrns.substring(_nostrns.length - 16)}'
                          : _nostrns,
                      style: const TextStyle(
                        color: Colors.indigoAccent,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Login (salt = email UPlanet)
                Text('Login (votre email UPlanet)',
                    style: TextStyle(color: Colors.grey[300], fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: _saltController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'vous@domaine.com',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF0D0D1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    errorText: _saltError,
                    prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFFFFB347)),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => setState(() => _saltError = null),
                ),
                const SizedBox(height: 16),
                // Mot de passe (pepper)
                Text('Mot de passe',
                    style: TextStyle(color: Colors.grey[300], fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: _pepperController,
                  obscureText: _obscurePepper,
                  decoration: InputDecoration(
                    hintText: 'Votre mot de passe UPlanet',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF0D0D1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    errorText: _pepperError,
                    prefixIcon: const Icon(Icons.lock, color: Color(0xFFFFB347)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePepper ? Icons.visibility : Icons.visibility_off,
                        color: Colors.grey[500],
                      ),
                      onPressed: () => setState(() => _obscurePepper = !_obscurePepper),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => setState(() => _pepperError = null),
                ),
                const SizedBox(height: 16),
                // Note de compatibilité
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Les mêmes identifiants que votre MULTIPASS UPlanet génèrent les mêmes clés cryptographiques (Scrypt N=4096). Aucune donnée n\'est transmise.',
                          style: TextStyle(color: Colors.green[300], fontSize: 11, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _importFromScrypt,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB347),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Importer mes clés', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          if (_nostrns.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _phase = _Phase.scan),
              icon: const Icon(Icons.qr_code_scanner, size: 16),
              label: const Text('Rescanner le QR'),
              style: TextButton.styleFrom(foregroundColor: Colors.white54),
            ),
        ],
      ),
    );
  }
}
