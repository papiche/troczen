import 'dart:math';
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
      // Formule: DU_new = DU_current + C² * (M_n1 + sqrt(M_n2)) / (N1 + N2)
      final currentDu = await getCurrentGlobalDu();
      final n1 = mutuals.length;
      final n2 = n1 * 3; // Estimation des amis d'amis
      
      final newDuValue = currentDu + (_cSquared * (mn1 + sqrt(mn2)) / (n1 + n2));
      
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

  /// Récupère la valeur actuelle du DU global (simulé pour l'instant)
  Future<double> getCurrentGlobalDu() async {
    // Dans une vraie implémentation, cette valeur serait calculée par consensus
    // ou récupérée depuis un oracle Nostr
    return 10.0; // Valeur de base
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
  Future<void> _createAndPublishBon(User user, Market market, double value, double currentDu) async {
    final keys = _cryptoService.generateNostrKeyPair();
    final bonId = keys['publicKeyHex']!;
    final nsec = keys['privateKeyHex']!;
    
    final parts = _cryptoService.shamirSplit(nsec);
    
    final bon = Bon(
      bonId: bonId,
      value: value,
      issuerName: user.displayName,
      issuerNpub: user.npub,
      createdAt: DateTime.now(),
      status: BonStatus.active,
      p1: parts[0],
      p2: parts[1],
      p3: parts[2],
      marketName: market.name,
      rarity: 'common',
      cardType: 'DU',
      duAtCreation: currentDu, // Stocker la valeur du DU à la création
    );

    // Sauvegarder localement
    await _storageService.saveBon(bon);
    await _storageService.saveP3ToCache(bonId, parts[2]);

    // Publier sur Nostr
    await _nostrService.publishP3(
      bonId: bonId,
      p2Hex: parts[1],
      p3Hex: parts[2],
      seedMarket: market.seedMarket,
      issuerNpub: user.npub,
      marketName: market.name,
      value: value,
      category: 'DU',
    );
  }
}
