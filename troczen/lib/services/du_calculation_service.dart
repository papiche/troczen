import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/bon.dart';
import '../models/market.dart';
import 'storage_service.dart';
import 'nostr_service.dart';
import 'crypto_service.dart';
import 'logger_service.dart';

/// Modèle pour les paramètres DU reçus de la TrocZen Box
class DuParams {
  final double cSquared;
  final double alpha;
  final double duBase;
  final double duSkill;
  final double duTotal;
  final int n1;
  final int n2;
  final DateTime computedAt;
  final bool fromBox;

  DuParams({
    required this.cSquared,
    required this.alpha,
    required this.duBase,
    required this.duSkill,
    required this.duTotal,
    required this.n1,
    required this.n2,
    required this.computedAt,
    required this.fromBox,
  });

  factory DuParams.fromJson(Map<String, dynamic> json, {bool fromBox = true}) {
    return DuParams(
      cSquared: (json['c2'] ?? json['cSquared'] ?? 0.01).toDouble(),
      alpha: (json['alpha'] ?? 0.0).toDouble(),
      duBase: (json['du_base'] ?? json['duBase'] ?? 10.0).toDouble(),
      duSkill: (json['du_skill'] ?? json['duSkill'] ?? 0.0).toDouble(),
      duTotal: (json['du'] ?? json['duTotal'] ?? 10.0).toDouble(),
      n1: json['n1'] ?? 0,
      n2: json['n2'] ?? 0,
      computedAt: json['computedAt'] != null
          ? DateTime.parse(json['computedAt'])
          : DateTime.now(),
      fromBox: fromBox,
    );
  }

  /// Crée des paramètres de fallback (mode hors-ligne)
  factory DuParams.fallback({double cSquared = 0.01, double duBase = 10.0}) {
    return DuParams(
      cSquared: cSquared,
      alpha: 0.0,
      duBase: duBase,
      duSkill: 0.0,
      duTotal: duBase,
      n1: 0,
      n2: 0,
      computedAt: DateTime.now(),
      fromBox: false,
    );
  }
}

/// Service expérimental pour le calcul du Dividende Universel (DU)
/// basé sur le graphe social Nostr (P2P)
///
/// ✅ PROTOCOLE V6 - HYPERRELATIVISTE:
/// L'app DOIT faire une requête HTTP GET /api/dashboard/<npub>?market=<market_id>
/// à la TrocZen Box (si connectée) pour récupérer les paramètres C², α, et DUbase
/// calculés par le moteur Python.
/// Le calcul local statique (avec _cSquared = 0.01) est utilisé uniquement comme
/// FALLBACK si la box est injoignable (vrai mode hors-ligne).
class DuCalculationService {
  final StorageService _storageService;
  final NostrService _nostrService;
  final CryptoService _cryptoService;
  
  /// URL de la TrocZen Box (mise à jour dynamiquement)
  String _boxApiUrl = '';
  // ignore: unused_field
  bool _boxConnected = false;

  // Constantes de la TRM (Théorie Relative de la Monnaie)
  // C = ln(ev/2)/(ev/2) où ev = espérance de vie (ex: 80 ans)
  // Pour simplifier, on utilise une constante C d'environ 10% par an
  // C_SQUARED est utilisé dans la formule simplifiée (FALLBACK uniquement)
  static const double _cSquaredFallback = 0.01; // 10% au carré - FALLBACK
  
  // Seuil minimum de liens réciproques pour déclencher le DU
  static const int _minMutualFollows = 5;
  
  // Durée de vie d'un bon DU (Monnaie fondante)
  static const int _duExpirationDays = 28;
  
  // DU initial au lancement du marché (100 ẐEN/jour)
  static const double _initialDuValue = 100.0;
  
  // Timeout pour les requêtes à la Box
  static const Duration _boxTimeout = Duration(seconds: 5);

  DuCalculationService({
    required StorageService storageService,
    required NostrService nostrService,
    required CryptoService cryptoService,
    String? boxApiUrl,
  })  : _storageService = storageService,
        _nostrService = nostrService,
        _cryptoService = cryptoService,
        _boxApiUrl = boxApiUrl ?? '';

  /// Configure l'URL de la TrocZen Box
  void setBoxApiUrl(String url) {
    _boxApiUrl = url;
    _boxConnected = false;
    Logger.log('DuCalculationService', 'URL Box configurée: $url');
  }

  /// Marque la Box comme connectée/déconnectée
  void setBoxConnected(bool connected) {
    _boxConnected = connected;
    Logger.log('DuCalculationService', 'Box connectée: $connected');
  }

  /// ✅ PROTOCOLE V6: Récupère les paramètres DU depuis la TrocZen Box
  /// Fait une requête HTTP GET /api/dashboard/<npub>?market=<market_id>
  /// Retourne null si la Box est injoignable (mode hors-ligne)
  Future<DuParams?> _fetchDuParamsFromBox(String npub, String marketId) async {
    if (_boxApiUrl.isEmpty) {
      Logger.log('DuCalculationService', 'Pas d\'URL Box configurée - mode hors-ligne');
      return null;
    }

    try {
      final uri = Uri.parse('$_boxApiUrl/api/dashboard/$npub?market=$marketId');
      Logger.log('DuCalculationService', 'Requête Box: $uri');

      final response = await http.get(uri).timeout(_boxTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        // Extraire les paramètres DU depuis la réponse du dashboard
        // Structure attendue: { markets: [{ du: {...}, params: {...} }] }
        final markets = data['markets'] as List<dynamic>?;
        if (markets != null && markets.isNotEmpty) {
          final marketData = markets[0] as Map<String, dynamic>;
          final duData = marketData['du'] as Map<String, dynamic>? ?? {};
          final paramsData = marketData['params'] as Map<String, dynamic>? ?? {};
          
          // Fusionner du et params pour DuParams
          final mergedData = {
            ...duData,
            ...paramsData,
            'n1': data['network']?['n1'] ?? 0,
            'n2': data['network']?['n2'] ?? 0,
          };
          
          final duParams = DuParams.fromJson(mergedData, fromBox: true);
          Logger.success('DuCalculationService',
            'Paramètres DU reçus de la Box: C²=${duParams.cSquared.toStringAsFixed(4)}, '
            'α=${duParams.alpha.toStringAsFixed(2)}, DU=${duParams.duTotal.toStringAsFixed(2)} ẐEN');
          
          return duParams;
        }
      } else {
        Logger.warn('DuCalculationService', 'Box répond ${response.statusCode}');
      }
    } catch (e) {
      Logger.warn('DuCalculationService', 'Box injoignable: $e');
    }

    return null;
  }

  /// ✅ PROTOCOLE V6: Calcul local de fallback (mode hors-ligne)
  /// Utilisé uniquement si la TrocZen Box est injoignable
  Future<DuParams> _calculateLocalFallback({
    required int n1Count,
    required double currentDu,
    required double mn1,
    required double mn2,
  }) async {
    final n2 = max(1, n1Count * 3);
    final sqrtN2 = sqrt(n2);
    final effectiveMass = mn1 + (mn2 / sqrtN2);
    final effectivePopulation = n1Count + sqrtN2;
    
    // Utiliser le C² de fallback (0.01)
    final duIncrement = _cSquaredFallback * effectiveMass / effectivePopulation;
    final newDu = currentDu + duIncrement;
    
    // Plafond de sécurité (+5% max)
    final cappedDu = min(newDu, currentDu * 1.05);

    Logger.log('DuCalculationService',
      'Calcul local fallback: DU=${cappedDu.toStringAsFixed(2)} ẐEN (C²=$_cSquaredFallback)');

    return DuParams.fallback(
      cSquared: _cSquaredFallback,
      duBase: cappedDu,
    );
  }

  /// ✅ PROTOCOLE V6: Vérifie si le DU peut être généré aujourd'hui et le génère si oui
  ///
  /// ALGORITHME:
  /// 1. Tenter de récupérer les paramètres depuis la TrocZen Box (HTTP GET)
  /// 2. Si Box joignable → utiliser C², α, DUbase calculés par le moteur Python
  /// 3. Si Box injoignable → fallback au calcul local statique (C² = 0.01)
  Future<bool> checkAndGenerateDU() async {
    try {
      final user = await _storageService.getUser();
      final market = await _storageService.getActiveMarket();
      
      if (user == null || market == null) {
        Logger.warn('DuCalculationService', 'Utilisateur ou marché non configuré');
        return false;
      }

      // 1. Vérifier si le DU a déjà été généré aujourd'hui
      final lastDuDate = await _storageService.getLastDuGenerationDate();
      if (lastDuDate != null) {
        final now = DateTime.now();
        final hasGeneratedToday = lastDuDate.year == now.year &&
            lastDuDate.month == now.month &&
            lastDuDate.day == now.day;
        
        if (hasGeneratedToday) {
          Logger.log('DuCalculationService', 'DU déjà généré aujourd\'hui');
          return false;
        }
      }

      // 2. Récupérer les contacts locaux (N1)
      final myContacts = await _storageService.getContacts();
      if (myContacts.length < _minMutualFollows) {
        Logger.log('DuCalculationService', 'Pas assez de contacts (${myContacts.length}/$_minMutualFollows)');
        return false;
      }

      // 3. Récupérer les follows réciproques via Nostr
      final mutuals = myContacts;
      if (mutuals.length < _minMutualFollows) {
        Logger.log('DuCalculationService', 'Pas assez de liens réciproques (${mutuals.length}/$_minMutualFollows)');
        return false;
      }

      // 4. ✅ PROTOCOLE V6: Tenter de récupérer les paramètres depuis la Box
      DuParams duParams;
      final boxParams = await _fetchDuParamsFromBox(user.npub, market.name);
      
      if (boxParams != null) {
        // Box joignable → utiliser les paramètres calculés par le moteur Python
        duParams = boxParams;
        Logger.success('DuCalculationService',
          '🟢 Mode connecté - Paramètres Box: C²=${duParams.cSquared.toStringAsFixed(4)}, '
          'α=${duParams.alpha.toStringAsFixed(2)}, DU=${duParams.duTotal.toStringAsFixed(2)} ẐEN');
      } else {
        // Box injoignable → fallback calcul local
        Logger.warn('DuCalculationService', '🟠 Mode hors-ligne - Utilisation du calcul local fallback');
        
        final currentDu = await getCurrentGlobalDu();
        final marketData = await _storageService.getMarketEconomicData();
        final totalVolume = marketData['totalVolume'] as double? ?? 1000.0;
        
        final mn1 = totalVolume * (mutuals.length / max(1, marketData['uniqueIssuers'] as int? ?? 10));
        final mn2 = totalVolume * 0.5;
        
        duParams = await _calculateLocalFallback(
          n1Count: mutuals.length,
          currentDu: currentDu,
          mn1: mn1,
          mn2: mn2,
        );
      }

      // 5. Vérifier que le DU est positif
      if (duParams.duTotal <= 0) {
        Logger.warn('DuCalculationService', 'DU nul ou négatif - pas de génération');
        return false;
      }

      Logger.success('DuCalculationService',
        'Nouveau DU: ${duParams.duTotal.toStringAsFixed(2)} ẐEN '
        '(base: ${duParams.duBase.toStringAsFixed(2)} + skill: ${duParams.duSkill.toStringAsFixed(2)})');

      // 6. Générer les bons quantitatifs
      await _generateQuantitativeBons(user, market, duParams.duTotal);

      // 7. Enregistrer la date de génération
      await _storageService.setLastDuGenerationDate(DateTime.now());

      return true;
    } catch (e) {
      Logger.error('DuCalculationService', 'Erreur calcul DU', e);
      return false;
    }
  }

  /// Récupère la valeur actuelle du DU global
  /// Au lancement du marché, DU(0) = 100 ẐEN/jour
  Future<double> getCurrentGlobalDu() async {
    // Dans une vraie implémentation, cette valeur serait calculée par consensus
    // ou récupérée depuis un oracle Nostr
    // Pour l'instant, on retourne la valeur initiale
    return _initialDuValue; // 100 ẐEN au lancement
  }

  /// Génère un bon de bootstrap pour un nouvel utilisateur
  /// Bon à 0 ẐEN avec TTL de 28 jours (évite l'asymétrie monétaire)
  /// Ce bon sert de "ticket d'entrée" sur le marché
  Future<bool> generateBootstrapAllocation(User user, Market market) async {
    try {
      Logger.log('DuCalculationService', 'Génération bon bootstrap (0 ẐEN, 28j) pour ${user.displayName}');
      
      final now = DateTime.now();
      final expirationDate = now.add(const Duration(days: _duExpirationDays));
      
      // Créer un bon à 0 ẐEN avec validité 28 jours
      await _createBootstrapBon(user, market, expirationDate);
      
      // Marquer l'utilisateur comme ayant reçu son bootstrap et enregistrer l'expiration
      await _storageService.setBootstrapReceived(true, expirationDate: expirationDate);
      
      Logger.success('DuCalculationService', 'Bon bootstrap créé avec succès');
      return true;
    } catch (e) {
      Logger.error('DuCalculationService', 'Erreur génération bootstrap', e);
      return false;
    }
  }

  /// Régénère un Bon Zéro si l'utilisateur a transféré le précédent
  /// et n'a pas encore atteint N1 ≥ 5 (DU non actif)
  /// La date d'expiration reste celle du Bon Zéro initial
  Future<bool> regenerateBootstrapIfNeeded(User user, Market market) async {
    try {
      // Vérifier si le DU est déjà actif (N1 ≥ 5)
      final contacts = await _storageService.getContacts();
      if (contacts.length >= _minMutualFollows) {
        Logger.log('DuCalculationService', 'DU déjà actif (N1=${contacts.length}), pas de régénération');
        return false;
      }

      // Vérifier si le Bon Zéro initial a expiré
      final isExpired = await _storageService.isBootstrapExpired();
      if (isExpired) {
        Logger.log('DuCalculationService', 'Bon Zéro initial expiré, pas de régénération');
        return false;
      }

      // Récupérer la date d'expiration initiale
      final initialExpiration = await _storageService.getBootstrapExpiration();
      if (initialExpiration == null) {
        Logger.warn('DuCalculationService', 'Pas de date d\'expiration initiale trouvée');
        return false;
      }

      // Vérifier si l'utilisateur a encore un Bon Zéro actif dans son portefeuille
      final bons = await _storageService.getBons();
      final hasActiveBootstrap = bons.any((b) =>
        b.cardType == 'bootstrap' &&
        b.value == 0.0 &&
        b.status == BonStatus.active &&
        !b.isExpired
      );

      if (hasActiveBootstrap) {
        Logger.log('DuCalculationService', 'Un Bon Zéro actif existe déjà');
        return false;
      }

      // Créer un nouveau Bon Zéro avec la même expiration que l'initial
      Logger.log('DuCalculationService', 'Régénération Bon Zéro pour ${user.displayName}');
      await _createBootstrapBon(user, market, initialExpiration);
      
      Logger.success('DuCalculationService', 'Bon Zéro régénéré avec succès');
      return true;
    } catch (e) {
      Logger.error('DuCalculationService', 'Erreur régénération bootstrap', e);
      return false;
    }
  }

  /// Crée un bon de bootstrap à 0 ẐEN avec une date d'expiration spécifiée
  Future<void> _createBootstrapBon(User user, Market market, DateTime expirationDate) async {
    final keys = _cryptoService.generateNostrKeyPair();
    final bonId = keys['publicKeyHex']!;
    final nsecHex = keys['privateKeyHex']!;
    
    // Convertir en Uint8List et utiliser shamirSplitBytes
    final nsecBytes = Uint8List.fromList(HEX.decode(nsecHex));
    final parts = _cryptoService.shamirSplitBytes(nsecBytes);
    
    // Nettoyer la clé privée originale immédiatement
    _cryptoService.secureZeroiseBytes(nsecBytes);
    
    // Convertir en hex uniquement pour la sauvegarde
    final p1Hex = HEX.encode(parts[0]);
    final p2Hex = HEX.encode(parts[1]);
    final p3Hex = HEX.encode(parts[2]);
    
    final now = DateTime.now();
    final bon = Bon(
      bonId: bonId,
      value: 0.0, // 0 ẐEN - pas d'asymétrie monétaire
      issuerName: user.displayName,
      issuerNpub: user.npub,
      createdAt: now,
      expiresAt: expirationDate, // Utilise l'expiration passée en paramètre
      status: BonStatus.active,
      p1: p1Hex,
      p2: p2Hex,
      p3: p3Hex,
      marketName: market.name,
      rarity: 'bootstrap', // Rareté spéciale pour le bon de bootstrap
      cardType: 'bootstrap',
      duAtCreation: 0.0, // Pas de DU à la création
      picture: user.picture,
      logoUrl: user.picture,
      picture64: user.picture64,
    );

    // Sauvegarder localement
    await _storageService.saveBon(bon);
    await _storageService.saveP3ToCache(bonId, p3Hex);

    // Publier le profil du bon (Kind 0)
    try {
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(
        null,
        Uint8List.fromList(HEX.decode(p2Hex)),
        Uint8List.fromList(HEX.decode(p3Hex))
      );
      final nsecBonHex = HEX.encode(nsecBonBytes);
      
      await _nostrService.publishUserProfile(
        npub: bonId,
        nsec: nsecBonHex,
        name: user.displayName,
        displayName: user.displayName,
        about: 'Bon Zéro - ${market.name}',
        picture: user.picture,
        banner: user.banner,
        picture64: user.picture64,
        banner64: user.banner64,
        website: user.website,
        g1pub: user.g1pub,
      );
      
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
    } catch (e) {
      Logger.warn('DuCalculationService', 'Erreur publication profil Bon Zéro: $e');
    }

    // Publier sur Nostr
    await _nostrService.publishP3(
      bonId: bonId,
      p2Hex: p2Hex,
      p3Hex: p3Hex,
      seedMarket: market.seedMarket,
      issuerNpub: user.npub,
      marketName: market.name,
      value: 0.0,
      category: 'bootstrap',
    );
    
    // Nettoyer les parts de la RAM après sauvegarde
    for (final part in parts) {
      _cryptoService.secureZeroiseBytes(part);
    }
  }

  /// Vérifie si l'utilisateur a déjà reçu son allocation de bootstrap
  Future<bool> hasReceivedBootstrap() async {
    return await _storageService.hasReceivedBootstrap();
  }

  /// Génère des bons en coupures standards (1, 2, 5, 10, 20, 50)
  Future<void> _generateQuantitativeBons(User user, Market market, double totalValue) async {
    final denominations = [50.0, 20.0, 10.0, 5.0, 2.0, 1.0];
    double remaining = totalValue;
    
    for (final denom in denominations) {
      while (remaining >= denom) {
        await _createAndPublishBon(user, market, denom, totalValue);
        remaining -= denom;
      }
    }
    
    // S'il reste une fraction, on crée un dernier bon
    if (remaining > 0.1) {
      await _createAndPublishBon(user, market, double.parse(remaining.toStringAsFixed(2)), totalValue);
    }
  }

  /// Crée un bon individuel et le publie sur Nostr
  /// ✅ SÉCURITÉ: Utilise shamirSplitBytes() pour éviter les String en RAM
  Future<void> _createAndPublishBon(User user, Market market, double value, double currentDu) async {
    final keys = _cryptoService.generateNostrKeyPair();
    final bonId = keys['publicKeyHex']!;
    final nsecHex = keys['privateKeyHex']!;
    
    // ✅ SÉCURITÉ: Convertir en Uint8List et utiliser shamirSplitBytes
    final nsecBytes = Uint8List.fromList(HEX.decode(nsecHex));
    final parts = _cryptoService.shamirSplitBytes(nsecBytes);
    
    // Nettoyer la clé privée originale immédiatement
    _cryptoService.secureZeroiseBytes(nsecBytes);
    
    // Convertir en hex uniquement pour la sauvegarde
    final p1Hex = HEX.encode(parts[0]);
    final p2Hex = HEX.encode(parts[1]);
    final p3Hex = HEX.encode(parts[2]);
    
    final now = DateTime.now();
    final bon = Bon(
      bonId: bonId,
      value: value,
      issuerName: user.displayName,
      issuerNpub: user.npub,
      createdAt: now,
      expiresAt: now.add(const Duration(days: _duExpirationDays)), // Monnaie fondante
      status: BonStatus.active,
      p1: p1Hex,
      p2: p2Hex,
      p3: p3Hex,
      marketName: market.name,
      rarity: 'common',
      cardType: 'DU',
      duAtCreation: currentDu, // Stocker la valeur du DU à la création
    );

    // Sauvegarder localement
    await _storageService.saveBon(bon);
    await _storageService.saveP3ToCache(bonId, p3Hex);

    // Publier sur Nostr
    await _nostrService.publishP3(
      bonId: bonId,
      p2Hex: p2Hex,
      p3Hex: p3Hex,
      seedMarket: market.seedMarket,
      issuerNpub: user.npub,
      marketName: market.name,
      value: value,
      category: 'DU',
    );
    
    // ✅ SÉCURITÉ: Nettoyer les parts de la RAM après sauvegarde
    for (final part in parts) {
      _cryptoService.secureZeroiseBytes(part);
    }
  }
}
