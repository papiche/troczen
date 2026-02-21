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

/// Service expérimental pour le calcul du Dividende Universel (DU)
/// basé sur le graphe social Nostr (P2P)
class DuCalculationService {
  final StorageService _storageService;
  final NostrService _nostrService;
  final CryptoService _cryptoService;

  // Constantes de la TRM (Théorie Relative de la Monnaie)
  // C = ln(ev/2)/(ev/2) où ev = espérance de vie (ex: 80 ans)
  // Pour simplifier, on utilise une constante C d'environ 10% par an
  // C_SQUARED est utilisé dans la formule simplifiée
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

  /// Vérifie si le DU peut être généré aujourd'hui et le génère si oui
  Future<bool> checkAndGenerateDU() async {
    try {
      final user = await _storageService.getUser();
      final market = await _storageService.getActiveMarket();
      
      if (user == null || market == null) {
        Logger.warn('DuCalculationService', 'Utilisateur ou marché non configuré');
        return false;
      }

      // 1. Vérifier si le DU a déjà été généré aujourd'hui
      final lastDuDateStr = await _storageService.getLastP3Sync(); // On pourrait utiliser une clé dédiée
      // Pour l'instant, on simule la vérification
      // if (hasGeneratedToday) return false;

      // 2. Récupérer les contacts locaux (N1)
      final myContacts = await _storageService.getContacts();
      if (myContacts.length < _minMutualFollows) {
        Logger.log('DuCalculationService', 'Pas assez de contacts (${myContacts.length}/$_minMutualFollows)');
        return false;
      }

      // 3. Récupérer les follows réciproques via Nostr
      // Dans une vraie implémentation, on vérifierait que chaque contact nous suit en retour
      // Pour cette démo, on suppose que les contacts locaux sont réciproques
      final mutuals = myContacts;

      if (mutuals.length < _minMutualFollows) {
        Logger.log('DuCalculationService', 'Pas assez de liens réciproques (${mutuals.length}/$_minMutualFollows)');
        return false;
      }

      // 4. Calculer la masse monétaire (M_n1 et M_n2)
      // Pour l'instant, on utilise des valeurs simulées basées sur les données du marché
      final marketData = await _storageService.getMarketEconomicData();
      final totalVolume = marketData['totalVolume'] as double? ?? 1000.0;
      
      // Simulation: M_n1 = part proportionnelle du volume total
      final mn1 = totalVolume * (mutuals.length / max(1, marketData['uniqueIssuers'] as int? ?? 10));
      // Simulation: M_n2 = masse étendue
      final mn2 = totalVolume * 0.5;

      // 5. Calculer le nouveau DU
      // Formule corrigée pour l'invariance d'échelle :
      // DU_new = DU_current + C² * (M_n1 + M_n2 / sqrt(N2)) / (N1 + sqrt(N2))
      final currentDu = await getCurrentGlobalDu();
      final n1 = mutuals.length;
      final n2 = max(1, n1 * 3); // Estimation des amis d'amis (évite div par 0)
      
      final sqrtN2 = sqrt(n2);
      final effectiveMass = mn1 + (mn2 / sqrtN2);
      final effectivePopulation = n1 + sqrtN2;
      
      final newDuValue = currentDu + (_cSquared * effectiveMass / effectivePopulation);
      
      // Plafond de sécurité (ex: max +5% par jour)
      final cappedDuValue = min(newDuValue, currentDu * 1.05);

      Logger.success('DuCalculationService', 'Nouveau DU calculé: $cappedDuValue ẐEN');

      // 6. Générer les bons quantitatifs
      await _generateQuantitativeBons(user, market, cappedDuValue);

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
