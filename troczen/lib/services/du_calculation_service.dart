import 'dart:math';
import 'dart:typed_data';
import 'package:hex/hex.dart';
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
  factory DuParams.fallback({
    double cSquared = 0.01,
    double duBase = 10.0,
    int n1 = 0,
    int n2 = 0,
  }) {
    return DuParams(
      cSquared: cSquared,
      alpha: 0.0,
      duBase: duBase,
      duSkill: 0.0,
      duTotal: duBase,
      n1: n1,
      n2: n2,
      computedAt: DateTime.now(),
      fromBox: false,
    );
  }
}

/// Service expérimental pour le calcul du Dividende Universel (DU)
/// basé sur le graphe social Nostr (P2P)
///
/// ✅ PROTOCOLE V6 - HYPERRELATIVISTE:
/// Calcul 100% local du DU basé sur le graphe social Nostr (P2P).
/// Plus de dépendance à la TrocZen Box pour le calcul.
class DuCalculationService {
  final StorageService _storageService;
  final NostrService _nostrService;
  final CryptoService _cryptoService;

  // Constantes de la TRM (Théorie Relative de la Monnaie)
  // C = ln(ev/2)/(ev/2) où ev = espérance de vie (ex: 80 ans)
  // Pour simplifier, on utilise une constante C d'environ 10% par an
  static const double _cSquared = 0.01; // 10% au carré
  
  // Seuil minimum de liens réciproques pour déclencher le DU
  static const int _minMutualFollows = 5;
  
  // Durée de vie d'un bon DU (Monnaie fondante)
  static const int _duExpirationDays = 28;
  
  // DU initial au lancement du marché (100 ẐEN/jour)
  static const double _initialDuValue = 100.0;

  DuCalculationService({
    required StorageService storageService,
    required NostrService nostrService,
    required CryptoService cryptoService,
  })  : _storageService = storageService,
        _nostrService = nostrService,
        _cryptoService = cryptoService;

  /// ✅ PROTOCOLE V6: Calcul local 100%
  Future<DuParams> _calculateLocalDu({
    required List<String> mutuals,
    required double currentDu,
    required bool isFirstTime,
  }) async {
    if (isFirstTime) {
      double initialDu = _initialDuValue;
      
      // Tenter de récupérer la moyenne des DU actuels sur le réseau (kind 30305)
      // pour fixer un DU(0) actualisé par rapport au temps passé des actuels participants
      try {
        final avgDu = await _nostrService.fetchAverageRecentDu();
        if (avgDu != null && avgDu > 0) {
          initialDu = avgDu;
          Logger.log('DuCalculationService', 'Premier DU: valeur actualisée depuis le réseau (${initialDu.toStringAsFixed(2)} ẐEN)');
        } else {
          Logger.log('DuCalculationService', 'Premier DU: émission de la valeur par défaut ($_initialDuValue ẐEN)');
        }
      } catch (e) {
        Logger.log('DuCalculationService', 'Premier DU: émission de la valeur par défaut ($_initialDuValue ẐEN)');
      }

      return DuParams.fallback(
        cSquared: _cSquared,
        duBase: initialDu,
        n1: mutuals.length,
        n2: 0,
      );
    }

    // 1. Calculer M_n1 (masse monétaire des N1 mutuels) via SQL
    final mn1 = await _storageService.calculateMonetaryMass(mutuals);

    // 2. Calculer M_n2 (masse monétaire des N2) via SQL
    // On exclut les N1 mutuels pour obtenir les autres utilisateurs
    final n2Data = await _storageService.calculateOtherMonetaryMass(mutuals);
    double mn2 = n2Data['mass'] as double;
    int n2Count = n2Data['count'] as int;
    
    // Si on n'a pas de N2, on utilise une estimation basée sur N1
    if (n2Count == 0) {
      n2Count = max(1, mutuals.length * 3);
      // Estimation de la masse N2
      final marketData = await _storageService.getMarketEconomicData();
      final totalVolume = marketData['totalVolume'] as double? ?? 1000.0;
      mn2 = totalVolume * 0.5;
    }

    final sqrtN2 = sqrt(n2Count);
    final effectiveMass = mn1 + (mn2 / sqrtN2);
    final effectivePopulation = mutuals.length + sqrtN2;
    
    // Utiliser le C²
    final duIncrement = _cSquared * effectiveMass / effectivePopulation;
    
    // Plafond de sécurité pour l'incrément (+5% max de la masse cumulée)
    final maxIncrement = currentDu * 0.05;
    final cappedIncrement = min(duIncrement, maxIncrement);

    Logger.log('DuCalculationService',
      'Calcul local: Incrément=${cappedIncrement.toStringAsFixed(2)} ẐEN (C²=$_cSquared, N1=${mutuals.length}, N2=$n2Count, Mn1=$mn1, Mn2=$mn2)');

    return DuParams.fallback(
      cSquared: _cSquared,
      duBase: cappedIncrement,
      n1: mutuals.length,
      n2: n2Count,
    );
  }

  /// ✅ PROTOCOLE V6: Vérifie si le DU peut être généré aujourd'hui et le génère si oui
  ///
  /// ALGORITHME:
  /// 1. Vérifier si le DU a déjà été généré aujourd'hui
  /// 2. Récupérer les contacts locaux (N1) et les followers
  /// 3. Calculer les liens réciproques (N1 mutuels)
  /// 4. Calculer le DU localement
  /// 5. Générer les bons quantitatifs
  Future<bool> checkAndGenerateDU() async {
    try {
      final user = await _storageService.getUser();
      final market = await _storageService.getActiveMarket();
      
      if (user == null || market == null) {
        Logger.warn('DuCalculationService', 'Utilisateur ou marché non configuré');
        return false;
      }

      // 1. Calculer le nombre de jours écoulés depuis la dernière génération
      final lastDuDate = await _storageService.getLastDuGenerationDate();
      int missedDays = 1;
      
      if (lastDuDate != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final lastDate = DateTime(lastDuDate.year, lastDuDate.month, lastDuDate.day);
        
        missedDays = today.difference(lastDate).inDays;
        
        if (missedDays <= 0) {
          Logger.log('DuCalculationService', 'DU déjà généré aujourd\'hui');
          return false;
        }
        
        // Limite de rattrapage : on ne peut rattraper qu'un certain nombre de jours d'inactivité
        // Cela évite une création monétaire massive si l'app est rouverte après 2 ans
        // et incite à une participation régulière au réseau.
        const int maxCatchupDays = 30; // Limite fixée à 30 jours
        if (missedDays > maxCatchupDays) {
          Logger.warn('DuCalculationService', 'Plafond de rattrapage atteint: $missedDays jours réduits à $maxCatchupDays');
          missedDays = maxCatchupDays;
        }
      }

      // 2. Récupérer les contacts locaux (N1)
      final myContacts = await _storageService.getContacts();
      if (myContacts.length < _minMutualFollows) {
        Logger.log('DuCalculationService', 'Pas assez de contacts (${myContacts.length}/$_minMutualFollows)');
        return false;
      }

      // 3. Récupérer les follows réciproques (N1 mutuels)
      // On utilise le cache local des followers
      final followers = await _storageService.getFollowers();
      List<String> mutuals = myContacts.where((npub) => followers.contains(npub)).toList();
      
      // Si on n'a pas de followers en cache, on essaie de les récupérer via Nostr
      if (followers.isEmpty && market.relayUrl != null && await _nostrService.connect(market.relayUrl!)) {
        final fetchedFollowers = await _nostrService.fetchFollowers(user.npub);
        await _storageService.saveFollowersBatch(fetchedFollowers);
        mutuals = myContacts.where((npub) => fetchedFollowers.contains(npub)).toList();
        await _nostrService.disconnect();
      }
      
      if (mutuals.length < _minMutualFollows) {
        Logger.log('DuCalculationService', 'Pas assez de liens réciproques (${mutuals.length}/$_minMutualFollows)');
        return false;
      }

      // 4. ✅ PROTOCOLE V6: Calcul local 100%
      final lastDu = await _storageService.getLastDuValue();
      final isFirstTime = lastDu == null;
      final currentDu = lastDu ?? 0.0;
      
      final duParams = await _calculateLocalDu(
        mutuals: mutuals,
        currentDu: currentDu,
        isFirstTime: isFirstTime,
      );

      // 5. Vérifier que le DU est positif
      if (duParams.duTotal <= 0) {
        Logger.warn('DuCalculationService', 'DU nul ou négatif - pas de génération');
        return false;
      }

      // Multiplier l'incrément par le nombre de jours manqués
      final totalIncrement = duParams.duTotal * missedDays;

      Logger.success('DuCalculationService',
        'Incrément DU: ${totalIncrement.toStringAsFixed(2)} ẐEN '
        '(${duParams.duTotal.toStringAsFixed(2)} ẐEN/jour × $missedDays jours)');

      // 6. Ajouter l'incrément total au DU disponible à émettre (cache local)
      await _storageService.addAvailableDuToEmit(totalIncrement);

      // 7. Enregistrer la date de génération et la nouvelle valeur cumulée
      await _storageService.setLastDuGenerationDate(DateTime.now());
      await _storageService.setLastDuValue(currentDu + totalIncrement);

      // 8. Publier l'incrément DU sur Nostr (kind 30305)
      try {
        await _nostrService.publishDuIncrement(
          user.npub,
          user.nsec,
          totalIncrement,
          DateTime.now(),
        );
        Logger.success('DuCalculationService', 'Incrément DU publié sur Nostr (kind 30305)');
      } catch (e) {
        Logger.warn('DuCalculationService', 'Erreur publication incrément DU: $e');
      }

      // 9. Publier les données économiques sur le profil Nostr
      try {
        final availableDu = await _storageService.getAvailableDuToEmit();
        final economicData = {
          'cumulative_du': currentDu + duParams.duTotal,
          'available_du': availableDu,
          'daily_increment': duParams.duTotal,
          'missed_days_caught_up': missedDays,
          'n1_count': mutuals.length,
          'n2_count': duParams.n2,
          'last_update': DateTime.now().toIso8601String(),
        };

        // On récupère le profil actuel pour ne pas écraser les autres champs
        final currentProfile = await _nostrService.fetchUserProfile(user.npub);
        
        await _nostrService.publishUserProfile(
          npub: user.npub,
          nsec: user.nsec,
          name: currentProfile?.name ?? user.displayName,
          displayName: currentProfile?.displayName ?? user.displayName,
          about: currentProfile?.about,
          picture: currentProfile?.picture,
          banner: currentProfile?.banner,
          website: currentProfile?.website,
          g1pub: currentProfile?.g1pub ?? user.g1pub,
          tags: currentProfile?.tags,
          activity: currentProfile?.activity,
          profession: currentProfile?.profession,
          economicData: economicData,
        );
        Logger.success('DuCalculationService', 'Données économiques publiées sur le profil');
      } catch (e) {
        Logger.warn('DuCalculationService', 'Erreur publication données économiques: $e');
      }

      return true;
    } catch (e) {
      Logger.error('DuCalculationService', 'Erreur calcul DU', e);
      return false;
    }
  }

  /// Récupère la valeur actuelle du DU global
  /// Au lancement du marché, DU(0) = 100 ẐEN/jour
  Future<double> getCurrentGlobalDu() async {
    // Récupérer la dernière valeur générée
    final lastDu = await _storageService.getLastDuValue();
    if (lastDu != null) {
      return lastDu;
    }
    
    // Si c'est la première fois, on retourne la valeur initiale
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
    Uint8List nsecBytes;
    try {
      nsecBytes = Uint8List.fromList(HEX.decode(nsecHex));
    } catch (e) {
      throw Exception('Clé privée invalide (non hexadécimale)');
    }
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
      banner: user.banner,
      banner64: user.banner64,
    );

    // Sauvegarder localement
    await _storageService.saveBon(bon);
    await _storageService.saveP3ToCache(bonId, p3Hex);

    // Publier le profil du bon (Kind 0)
    try {
      Uint8List p2Bytes, p3Bytes;
      try {
        p2Bytes = Uint8List.fromList(HEX.decode(p2Hex));
        p3Bytes = Uint8List.fromList(HEX.decode(p3Hex));
      } catch (e) {
        throw Exception('Parts P2 ou P3 invalides (non hexadécimales)');
      }
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(
        null,
        p2Bytes,
        p3Bytes
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
      issuerNsecHex: user.nsec,
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

}

