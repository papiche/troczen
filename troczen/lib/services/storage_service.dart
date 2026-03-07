import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hex/hex.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../models/market.dart';
import 'logger_service.dart';
import 'cache_database_service.dart';

/// Service de stockage principal de l'application
///
/// ✅ SÉPARÉ: Le cache P3 utilise maintenant une base SQLite dédiée (CacheDatabaseService)
/// - AuditTrailService: journal d'audit pour conformité RGPD/fiscale
/// - CacheDatabaseService: données éphémères du réseau (P3, marché)
///
/// Cette séparation évite la suppression accidentelle du cache lors d'une
/// demande RGPD (droit à l'oubli) qui ne doit effacer que les données personnelles
class StorageService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Instance du service SQLite pour le cache réseau (P3, marché)
  // ✅ SÉPARÉ de l'audit trail pour indépendance du cycle de vie
  final CacheDatabaseService _cacheService = CacheDatabaseService();

  Stream<Map<String, dynamic>> get cacheInsertionsStream => _cacheService.insertionsStream;

  // Clés de stockage (uniquement pour les petites données sensibles)
  static const String _userKey = 'user';
  static const String _bonsKey = 'bons';
  static const String _marketsKey = 'markets';         // Liste des marchés
  static const String _onboardingCompleteKey = 'onboarding_complete';
  static const String _contactsKey = 'contacts'; // Liste des contacts (npubs)
  static const String _bootstrapReceivedKey = 'bootstrap_received'; // Bon Zéro reçu
  static const String _bootstrapExpirationKey = 'bootstrap_expiration'; // Date expiration Bon Zéro initial
  static const String _appModeKey = 'app_mode'; // Mode d'utilisation (0=Flâneur, 1=Artisan, 2=Alchimiste)
  static const String _lastDuGenerationKey = 'last_du_generation'; // Date de dernière génération du DU
  static const String _lastDuValueKey = 'last_du_value'; // Dernière valeur du DU générée
  static const String _availableDuToEmitKey = 'available_du_to_emit'; // DU disponible à émettre

  /// Sauvegarde l'utilisateur
  Future<void> saveUser(User user) async {
    await _secureStorage.write(
      key: _userKey,
      value: jsonEncode(user.toJson()),
    );
  }

  /// Récupère l'utilisateur
  Future<User?> getUser() async {
    final data = await _secureStorage.read(key: _userKey);
    if (data == null) return null;
    return User.fromJson(jsonDecode(data));
  }

  /// Supprime l'utilisateur
  Future<void> deleteUser() async {
    await _secureStorage.delete(key: _userKey);
  }

  /// Sauvegarde un bon
  /// ✅ SÉCURITÉ: Utilise SQLite qui gère ses propres transactions
  Future<void> saveBon(Bon bon) async {
    await _cacheService.saveLocalBon(bon.toJson());
  }

  /// Récupère tous les bons
  Future<List<Bon>> getBons() async {
    return await _getBonsInternal();
  }

  /// Récupère un bon par son ID
  Future<Bon?> getBonById(String bonId) async {
    final bons = await getBons();
    try {
      return bons.firstWhere((b) => b.bonId == bonId);
    } catch (e) {
      return null;
    }
  }

  /// Supprime un bon
  Future<void> deleteBon(String bonId) async {
    await _cacheService.deleteLocalBon(bonId);
  }

  // ============================================================
  // ✅ WAL (Write-Ahead Log) - Protection contre double-dépense
  // Implémente un verrouillage atomique pour les transferts
  // ============================================================
  /// Cette opération DOIT être effectuée AVANT de générer l'offre
  /// Retourne le bon verrouillé ou null si le bon n'existe pas/déjà verrouillé
  Future<Bon?> lockBonForTransfer(
    String bonId, {
    String? challenge,
    int ttlSeconds = 300, // 5 minutes par défaut
  }) async {
    final bon = await getBonById(bonId);
    
    if (bon == null) {
      Logger.warn('StorageService', 'Bon $bonId non trouvé pour verrouillage');
      return null;
    }
    
    // Vérifier si le bon est déjà verrouillé
    if (bon.isTransferLocked) {
      Logger.warn('StorageService', 'Bon $bonId déjà verrouillé pour transfert');
      return null;
    }
    
    // Vérifier que le bon est actif
    if (bon.status != BonStatus.active) {
      Logger.warn('StorageService', 'Bon $bonId non actif (status: ${bon.status})');
      return null;
    }
    
    // Créer le bon verrouillé
    final lockedBon = bon.copyWith(
      status: BonStatus.lockedForTransfer,
      transferLockTimestamp: DateTime.now(),
      transferLockChallenge: challenge ?? DateTime.now().millisecondsSinceEpoch.toRadixString(16),
      transferLockTtlSeconds: ttlSeconds,
    );
    
    await _cacheService.saveLocalBon(lockedBon.toJson());
    
    Logger.success('StorageService', 'Bon $bonId verrouillé pour transfert (TTL: ${ttlSeconds}s)');
    return lockedBon;
  }

  /// ✅ WAL: Confirme le transfert et supprime définitivement P2
  /// Cette opération DOIT être appelée APRÈS réception de l'ACK validé
  /// Retourne true si succès, false si le bon n'était pas verrouillé
  Future<bool> confirmTransferAndRemoveP2(String bonId, String challenge) async {
    final bon = await getBonById(bonId);
    
    if (bon == null) {
      Logger.error('StorageService', 'Bon $bonId non trouvé pour confirmation');
      return false;
    }
    
    // Vérifier que le bon était verrouillé
    if (bon.status != BonStatus.lockedForTransfer) {
      Logger.error('StorageService', 'Bon $bonId n\'était pas verrouillé (status: ${bon.status})');
      return false;
    }
    
    // Vérifier le challenge (protection contre replay)
    if (bon.transferLockChallenge != challenge) {
      Logger.error('StorageService', 'Challenge mismatch pour bon $bonId');
      return false;
    }
    
    // Marquer comme dépensé et supprimer P2
    final spentBon = bon.copyWith(
      status: BonStatus.spent,
      p2: null, // CRITIQUE: Suppression de P2
      transferLockTimestamp: null,
      transferLockChallenge: null,
      transferLockTtlSeconds: null,
      transferCount: (bon.transferCount ?? 0) + 1,
    );
    
    await _cacheService.saveLocalBon(spentBon.toJson());
    
    Logger.success('StorageService', 'Transfert confirmé pour bon $bonId - P2 supprimé');
    return true;
  }

  /// ✅ WAL: Annule un verrou de transfert (timeout, erreur, annulation utilisateur)
  /// Remet le bon en état actif
  Future<bool> cancelTransferLock(String bonId) async {
    final bon = await getBonById(bonId);
    
    if (bon == null) {
      Logger.warn('StorageService', 'Bon $bonId non trouvé pour annulation verrou');
      return false;
    }
    
    if (bon.status != BonStatus.lockedForTransfer) {
      // Ce n'est pas une erreur si le bon n'est pas verrouillé
      return true;
    }
    
    // Remettre le bon en état actif
    final activeBon = bon.copyWith(
      status: BonStatus.active,
      transferLockTimestamp: null,
      transferLockChallenge: null,
      transferLockTtlSeconds: null,
    );
    
    await _cacheService.saveLocalBon(activeBon.toJson());
    
    Logger.success('StorageService', 'Verrou annulé pour bon $bonId');
    return true;
  }

  /// ✅ WAL: Réconciliation des états via Kind 1 au démarrage
  /// À appeler au démarrage de l'application
  /// Vérifie la vérité du réseau pour les bons actifs ou verrouillés
  /// Retourne le nombre de bons mis à jour
  Future<int> reconcileBonsState(dynamic nostrService, {Function(Bon)? onGhostTransferDetected}) async {
    // 1. Récupérer les bons sans verrouiller pour l'analyse
    final bonsToAnalyze = await _getBonsInternal();
    final bonsToCheck = bonsToAnalyze.where((b) =>
      b.status == BonStatus.active || b.status == BonStatus.lockedForTransfer
    ).toList();
    
    if (bonsToCheck.isEmpty) return 0;

    // 1.5. Récupérer les événements en attente (Outbox)
    final pendingEvents = await _cacheService.getPendingEvents();
    final pendingBonIds = <String>{};
    for (final event in pendingEvents) {
      if (event['kind'] == 1) {
        final tags = event['tags'] as List?;
        if (tags != null) {
          for (final tag in tags) {
            if (tag is List && tag.isNotEmpty && tag[0] == 'bon' && tag.length > 1) {
              pendingBonIds.add(tag[1].toString());
            }
          }
        }
      }
    }

    // 2. Requêter les Kind 1 pour tous ces bons
    final bonIds = bonsToCheck.map((b) => b.bonId).toList();
    final transfers = await nostrService.fetchBonsTransfers(bonIds);
    
    // Grouper les transferts par bonId
    final transfersByBonId = <String, List<Map<String, dynamic>>>{};
    for (final t in transfers) {
      final tags = t['tags'] as List?;
      if (tags != null) {
        for (final tag in tags) {
          if (tag is List && tag.isNotEmpty && tag[0] == 'bon' && tag.length > 1) {
            final bonId = tag[1].toString();
            transfersByBonId.putIfAbsent(bonId, () => []).add(t);
          }
        }
      }
    }

    // 3. Appliquer les modifications
    int recoveredCount = 0;
    final updatedBons = <Bon>[];
    
    for (final bon in bonsToCheck) {
      if (bon.status == BonStatus.active || bon.status == BonStatus.lockedForTransfer) {
        final bonTransfers = transfersByBonId[bon.bonId] ?? [];
        
        if (bonTransfers.isNotEmpty) {
          // Cas A et B : Un transfert a eu lieu sur le réseau !
          final updatedBon = bon.copyWith(
            status: BonStatus.spent,
            p2: null,
            transferLockTimestamp: null,
            transferLockChallenge: null,
            transferLockTtlSeconds: null,
          );
          updatedBons.add(updatedBon);
          recoveredCount++;
          Logger.info('StorageService', 'Réconciliation: bon ${bon.bonId} marqué comme dépensé (Kind 1 trouvé)');
        } else if (bon.status == BonStatus.lockedForTransfer && bon.isTransferLockExpired) {
          // Vérifier si un événement est en attente dans l'Outbox
          if (pendingBonIds.contains(bon.bonId)) {
            Logger.info('StorageService', 'Réconciliation: bon ${bon.bonId} maintenu verrouillé (transfert en attente dans l\'Outbox)');
            continue;
          }

          // Cas C : Le Fantôme Hors-Ligne
          if (onGhostTransferDetected != null) {
            // On délègue la décision à l'UI
            onGhostTransferDetected(bon);
          } else {
            // Par défaut, on le remet actif si pas de callback
            final updatedBon = bon.copyWith(
              status: BonStatus.active,
              transferLockTimestamp: null,
              transferLockChallenge: null,
              transferLockTtlSeconds: null,
            );
            updatedBons.add(updatedBon);
            recoveredCount++;
            Logger.info('StorageService', 'Réconciliation: bon ${bon.bonId} remis en état actif (verrou expiré, pas de Kind 1)');
          }
        }
      }
    }
    
    if (updatedBons.isNotEmpty) {
      await _cacheService.saveLocalBonsBatch(updatedBons.map((b) => b.toJson()).toList());
      Logger.success('StorageService', 'Réconciliation: $recoveredCount bon(s) mis à jour');
    }
    
    return recoveredCount;
  }

  /// ✅ WAL: Récupère les bons verrouillés (pour affichage UI)
  Future<List<Bon>> getLockedBons() async {
    final bons = await getBons();
    return bons.where((b) => b.isTransferLocked).toList();
  }

  /// ✅ WAL: Vérifie si un bon est verrouillé pour transfert
  Future<bool> isBonLocked(String bonId) async {
    final bon = await getBonById(bonId);
    return bon?.isTransferLocked ?? false;
  }

  /// Récupère tous les bons (version interne sans verrou)
  /// ✅ MIGRATION: Utilise SQLite au lieu de FlutterSecureStorage
  Future<List<Bon>> _getBonsInternal() async {
    try {
      final localBonsData = await _cacheService.getLocalBons();
      if (localBonsData.isEmpty) {
        // Migration depuis l'ancien stockage si nécessaire
        final oldData = await _secureStorage.read(key: _bonsKey);
        if (oldData != null) {
          final List<dynamic> jsonList = jsonDecode(oldData);
          final oldBons = jsonList.map((json) => Bon.fromJson(json)).toList();
          if (oldBons.isNotEmpty) {
            await _cacheService.saveLocalBonsBatch(oldBons.map((b) => b.toJson()).toList());
            await _secureStorage.delete(key: _bonsKey); // Nettoyer l'ancien stockage
            return oldBons;
          }
        }
        return [];
      }
      return localBonsData.map((json) => Bon.fromJson(json)).toList();
    } catch (e) {
      Logger.error('StorageService', 'Erreur _getBonsInternal', e);
      return [];
    }
  }

  // ============================================================
  // ✅ GESTION MULTI-MARCHÉS
  // Permet à un utilisateur d'être membre de plusieurs marchés
  // ============================================================

  /// Récupère le marché actif (alias pour getActiveMarket)
  /// Utilisé pour la compatibilité avec le code existant
  Future<Market?> getMarket() async {
    return await getActiveMarket();
  }

  /// Sauvegarde un marché (ajoute ou met à jour)
  /// Si c'est le premier marché, il devient actif par défaut
  Future<void> saveMarket(Market market) async {
    final markets = await getMarkets();
    final existingIndex = markets.indexWhere((m) => m.name == market.name);
    
    if (existingIndex != -1) {
      // Mettre à jour le marché existant
      markets[existingIndex] = market;
    } else {
      // Ajouter nouveau marché (actif si premier)
      final newMarket = markets.isEmpty ? market.copyWith(isActive: true) : market;
      markets.add(newMarket);
    }
    
    await _saveMarkets(markets);
  }

  /// Supprime tous les marchés (reset complet)
  Future<void> deleteMarket() async {
    await _secureStorage.delete(key: _marketsKey);
  }

  /// Récupère la liste de tous les marchés configurés
  Future<List<Market>> getMarkets() async {
    try {
      final data = await _secureStorage.read(key: _marketsKey);
      if (data == null) return [];
      
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList.map((json) => Market.fromJson(json)).toList();
    } catch (e) {
      Logger.error('StorageService', 'Erreur getMarkets', e);
      return [];
    }
  }

  /// Sauvegarde la liste complète des marchés
  Future<void> _saveMarkets(List<Market> markets) async {
    await _secureStorage.write(
      key: _marketsKey,
      value: jsonEncode(markets.map((m) => m.toJson()).toList()),
    );
  }

  /// Ajoute un nouveau marché à la liste
  /// ✅ AMÉLIORÉ: Utilise marketId (checksum de la seed) comme identifiant unique
  /// Retourne true si ajouté, false si déjà existant (même marketId)
  Future<bool> addMarket(Market market) async {
    try {
      final markets = await getMarkets();
      
      // ✅ MODIFIÉ: Vérifier si le marché existe déjà par marketId (unique)
      final existingIndex = markets.indexWhere((m) => m.marketId == market.marketId);
      if (existingIndex != -1) {
        Logger.warn('StorageService', 'Marché "${market.fullName}" déjà existant (ID: ${market.marketId})');
        return false;
      }
      
      // Si c'est le premier marché, le marquer comme actif
      final newMarket = markets.isEmpty
          ? market.copyWith(isActive: true)
          : market;
      
      markets.add(newMarket);
      await _saveMarkets(markets);
      
      Logger.success('StorageService', 'Marché "${market.fullName}" ajouté (ID: ${market.marketId})');
      return true;
    } catch (e) {
      Logger.error('StorageService', 'Erreur addMarket', e);
      return false;
    }
  }

  /// Supprime un marché de la liste par son marketId
  /// ✅ AMÉLIORÉ: Utilise marketId au lieu du nom
  /// Retourne true si supprimé, false si non trouvé
  Future<bool> removeMarket(String marketId) async {
    try {
      final markets = await getMarkets();
      final initialLength = markets.length;
      
      // ✅ MODIFIÉ: Supprimer le marché par marketId
      markets.removeWhere((m) => m.marketId == marketId);
      
      if (markets.length == initialLength) {
        Logger.warn('StorageService', 'Marché avec ID "$marketId" non trouvé');
        return false;
      }
      
      // Si le marché supprimé était actif, activer le premier restant
      if (markets.isNotEmpty && !markets.any((m) => m.isActive)) {
        markets[0] = markets[0].copyWith(isActive: true);
      }
      
      await _saveMarkets(markets);
      Logger.success('StorageService', 'Marché avec ID "$marketId" supprimé');
      return true;
    } catch (e) {
      Logger.error('StorageService', 'Erreur removeMarket', e);
      return false;
    }
  }

  /// Récupère le marché actuellement actif
  /// Si aucun marché n'est actif, retourne le premier de la liste
  Future<Market?> getActiveMarket() async {
    try {
      final markets = await getMarkets();
      if (markets.isEmpty) return null;
      
      // Chercher le marché actif
      final activeMarket = markets.firstWhere(
        (m) => m.isActive,
        orElse: () => markets.first,
      );
      
      return activeMarket;
    } catch (e) {
      Logger.error('StorageService', 'Erreur getActiveMarket', e);
      return null;
    }
  }

  /// Définit le marché actif par son marketId
  /// ✅ AMÉLIORÉ: Utilise marketId au lieu du nom
  /// Retourne true si succès, false si marché non trouvé
  Future<bool> setActiveMarket(String marketId) async {
    try {
      final markets = await getMarkets();
      final marketIndex = markets.indexWhere((m) => m.marketId == marketId);
      
      if (marketIndex == -1) {
        Logger.warn('StorageService', 'Marché avec ID "$marketId" non trouvé');
        return false;
      }
      
      // Désactiver tous les marchés et activer le sélectionné
      for (int i = 0; i < markets.length; i++) {
        markets[i] = markets[i].copyWith(isActive: i == marketIndex);
      }
      
      await _saveMarkets(markets);
      Logger.success('StorageService', 'Marché "${markets[marketIndex].fullName}" défini comme actif');
      return true;
    } catch (e) {
      Logger.error('StorageService', 'Erreur setActiveMarket', e);
      return false;
    }
  }

  /// Met à jour un marché existant
  /// ✅ AMÉLIORÉ: Utilise marketId pour la recherche
  /// Retourne true si mis à jour, false si non trouvé
  Future<bool> updateMarket(Market market) async {
    try {
      final markets = await getMarkets();
      final index = markets.indexWhere((m) => m.marketId == market.marketId);
      
      if (index == -1) {
        Logger.warn('StorageService', 'Marché "${market.fullName}" non trouvé');
        return false;
      }
      
      markets[index] = market;
      await _saveMarkets(markets);
      Logger.success('StorageService', 'Marché "${market.fullName}" mis à jour');
      return true;
    } catch (e) {
      Logger.error('StorageService', 'Erreur updateMarket', e);
      return false;
    }
  }

  /// Récupère un marché par son marketId
  /// ✅ AMÉLIORÉ: Utilise marketId au lieu du nom
  Future<Market?> getMarketById(String marketId) async {
    final markets = await getMarkets();
    try {
      return markets.firstWhere((m) => m.marketId == marketId);
    } catch (e) {
      return null;
    }
  }
  

  /// Vérifie si un marché existe par son marketId
  /// ✅ AMÉLIORÉ: Utilise marketId au lieu du nom
  Future<bool> hasMarket(String marketId) async {
    final markets = await getMarkets();
    return markets.any((m) => m.marketId == marketId);
  }

  /// Retourne le nombre de marchés configurés
  Future<int> getMarketsCount() async {
    final markets = await getMarkets();
    return markets.length;
  }

  // ============================================================
  // ✅ MÉTHODES P3 CACHE - dans SQLite
  // ============================================================

  /// Sauvegarde une P3 dans le cache SQLite
  /// ✅ SÉPARÉ: Utilise CacheDatabaseService (base dédiée au cache réseau)
  Future<void> saveP3ToCache(String bonId, String p3Hex) async {
    await _cacheService.saveP3ToCache(bonId, p3Hex);
  }

  /// ✅ OPTIMISÉ: Insertion en lot (batch) pour le cache P3
  /// Utilise une transaction SQLite pour performance optimale
  Future<void> saveP3BatchToCache(Map<String, String> p3Batch) async {
    if (p3Batch.isEmpty) return;
    
    try {
      await _cacheService.saveP3BatchToCache(p3Batch);
      Logger.success('StorageService', '${p3Batch.length} P3 sauvegardées en lot (SQLite)');
    } catch (e) {
      Logger.error('StorageService', 'Erreur saveP3BatchToCache', e);
      rethrow;
    }
  }

  /// Récupère le cache P3 complet depuis SQLite
  Future<Map<String, String>> getP3Cache() async {
    return await _cacheService.getP3Cache();
  }

  /// Récupère une P3 depuis le cache SQLite
  Future<String?> getP3FromCache(String bonId) async {
    return await _cacheService.getP3FromCache(bonId);
  }

  /// ✅ SÉCURITÉ: Récupère une P3 en Uint8List directement (évite les String en RAM)
  /// L'appelant DOIT appeler secureZeroiseBytes() après usage
  /// Retourne null si la P3 n'existe pas ou si le décodage échoue
  Future<Uint8List?> getP3FromCacheBytes(String bonId) async {
    final p3Hex = await _cacheService.getP3FromCache(bonId);
    if (p3Hex == null || p3Hex.isEmpty) return null;
    try {
      return Uint8List.fromList(HEX.decode(p3Hex));
    } catch (e) {
      Logger.error('StorageService', 'Erreur décodage P3 bytes pour $bonId', e);
      return null;
    }
  }

  /// Récupère la liste des P3 du marché depuis SQLite
  /// ✅ SÉPARÉ: Utilise CacheDatabaseService (base dédiée au cache réseau)
  Future<List<Map<String, dynamic>>> getP3List() async {
    try {
      return await _cacheService.getMarketBonsData();
    } catch (e) {
      Logger.error('StorageService', 'Erreur getP3List', e);
      return [];
    }
  }

  /// Sauvegarde la liste des P3 du marché dans SQLite
  /// ✅ SÉPARÉ: Utilise CacheDatabaseService (base dédiée au cache réseau)
  Future<void> saveP3List(List<Map<String, dynamic>> p3List) async {
    try {
      await _cacheService.saveMarketBonDataBatch(p3List);
      await _cacheService.saveLastP3Sync();
      Logger.success('StorageService', '${p3List.length} P3 sauvegardées (SQLite)');
    } catch (e) {
      Logger.error('StorageService', 'Erreur saveP3List', e);
      rethrow;
    }
  }

  /// ✅ SÉPARÉ: Sauvegarde un P3 du marché avec ses métadonnées complètes
  /// Utilise CacheDatabaseService (base dédiée au cache réseau)
  Future<void> saveMarketBonData(Map<String, dynamic> bonData) async {
    try {
      await _cacheService.saveMarketBonData(bonData);
    } catch (e) {
      Logger.error('StorageService', 'Erreur saveMarketBonData', e);
    }
  }

  /// ✅ SÉPARÉ: Sauvegarde en lot des données du marché (batch)
  /// Transaction SQLite unique pour performance optimale
  Future<void> saveMarketBonDataBatch(List<Map<String, dynamic>> bonDataList) async {
    if (bonDataList.isEmpty) return;
    
    try {
      await _cacheService.saveMarketBonDataBatch(bonDataList);
      Logger.success('StorageService', '${bonDataList.length} bons marché sauvegardés en lot (SQLite)');
    } catch (e) {
      Logger.error('StorageService', 'Erreur saveMarketBonDataBatch', e);
      rethrow;
    }
  }

  /// Sauvegarde un transfert du marché (kind 1)
  Future<void> saveMarketTransfer(Map<String, dynamic> transferData) async {
    try {
      await _cacheService.saveMarketTransfer(transferData);
    } catch (e) {
      Logger.error('StorageService', 'Erreur saveMarketTransfer', e);
    }
  }

  /// Sauvegarde un lot de transferts du marché (kind 1)
  Future<void> saveMarketTransfersBatch(List<Map<String, dynamic>> transfers) async {
    if (transfers.isEmpty) return;
    try {
      await _cacheService.saveMarketTransfersBatch(transfers);
      Logger.success('StorageService', '${transfers.length} transferts marché sauvegardés en lot (SQLite)');
    } catch (e) {
      Logger.error('StorageService', 'Erreur saveMarketTransfersBatch', e);
      rethrow;
    }
  }

  /// ✅ CORRECTION: Récupère les données économiques du marché global
  /// Retourne les métadonnées de tous les bons publiés sur le marché (kind 30303)
  /// Utilisé par le Dashboard pour afficher la santé économique du marché
  Future<List<Map<String, dynamic>>> getMarketBonsData() async {
    return await getP3List();
  }

  /// ✅ CORRECTION EXPIRATION: Récupère les métadonnées d'un bon depuis le cache du marché
  /// Permet de récupérer l'expiration (expiresAt) depuis l'événement kind 30303
  /// Utilisé lors de la réception d'un bon pour préserver l'expiration (monnaie fondante)
  Future<Map<String, dynamic>?> getMarketBonById(String bonId) async {
    return await _cacheService.getMarketBonById(bonId);
  }

  /// Récupère les bons créés à une date précise (Y-M-D)
  Future<List<Map<String, dynamic>>> getBonsForDate(String dateStr) async {
    return await _cacheService.getBonsForDate(dateStr);
  }

  /// Calcule les métriques du tableau de bord pour une période donnée via SQL
  Future<Map<String, dynamic>> getDashboardMetricsForPeriod(DateTime start, DateTime end) async {
    return await _cacheService.getDashboardMetricsForPeriod(start, end);
  }

  /// Récupère les métriques agrégées pour une période donnée (Alchimiste)
  Future<AggregatedMetrics> getAggregatedMetrics(DateTime start, DateTime end, {String? groupBy}) async {
    return await _cacheService.getAggregatedMetrics(start, end, groupBy: groupBy);
  }

  /// Récupère les statistiques par émetteur (Alchimiste)
  Future<List<IssuerStats>> getTopIssuers(DateTime start, DateTime end) async {
    return await _cacheService.getTopIssuers(start, end);
  }

  /// Récupère le résumé des transferts pour le graphe de circulation
  Future<List<TransferEdge>> getTransferSummary({int? limitDays}) async {
    return await _cacheService.getTransferSummary(limitDays: limitDays);
  }

  /// Récupère la liste des utilisateurs en phase de Bootstrap
  Future<List<String>> getBootstrapUsers() async {
    return await _cacheService.getBootstrapUsers();
  }

  /// Obtenir le nombre total de bons sur le marché
  Future<int> getMarketBonsCount() async {
    return await _cacheService.getMarketBonsCount();
  }

  /// Calculer la masse monétaire d'un groupe d'utilisateurs (M_n1)
  Future<double> calculateMonetaryMass(List<String> npubs) async {
    return await _cacheService.calculateMonetaryMass(npubs);
  }

  /// Calculer la masse monétaire des autres utilisateurs (M_n2)
  /// Retourne un tuple (masse, nombre_utilisateurs)
  Future<Map<String, dynamic>> calculateOtherMonetaryMass(List<String> excludedNpubs) async {
    return await _cacheService.calculateOtherMonetaryMass(excludedNpubs);
  }

  /// ✅ Récupère les données économiques agrégées pour le dashboard
  /// Combine les données du marché global avec le wallet local
  Future<Map<String, dynamic>> getMarketEconomicData() async {
    try {
      final marketBons = await getMarketBonsData();
      final localBons = await getBons();
      
      final now = DateTime.now();
      
      // Volume total en circulation (bons actifs sur le marché)
      final totalVolume = marketBons
          .where((b) => b['status'] == 'active' || b['status'] == null)
          .fold<double>(0.0, (sum, b) => sum + ((b['value'] as num?)?.toDouble() ?? 0));
      
      // Nombre de commerçants uniques
      final uniqueIssuers = marketBons
          .map((b) => b['issuerNpub'] as String?)
          .where((npub) => npub != null)
          .toSet()
          .length;
      
      // Nombre total de bons sur le marché
      final totalMarketBons = marketBons.length;
      
      // Bons créés cette semaine
      final last7Days = now.subtract(const Duration(days: 7));
      final weeklyBons = marketBons.where((b) {
        final createdAt = b['createdAt'] as String?;
        if (createdAt == null) return false;
        return DateTime.tryParse(createdAt)?.isAfter(last7Days) ?? false;
      }).length;
      
      // Distribution par valeur
      final valueDistribution = <double, int>{};
      for (final bon in marketBons) {
        final value = (bon['value'] as num?)?.toDouble() ?? 0;
        valueDistribution[value] = (valueDistribution[value] ?? 0) + 1;
      }
      
      // Distribution par rareté
      final rarityDistribution = <String, int>{};
      for (final bon in marketBons) {
        final rarity = (bon['rarity'] as String?) ?? 'common';
        rarityDistribution[rarity] = (rarityDistribution[rarity] ?? 0) + 1;
      }
      
      // Top émetteurs
      final issuerTotals = <String, double>{};
      for (final bon in marketBons) {
        final issuerName = (bon['issuerName'] as String?) ?? 'Inconnu';
        final value = (bon['value'] as num?)?.toDouble() ?? 0;
        issuerTotals[issuerName] = (issuerTotals[issuerName] ?? 0) + value;
      }
      final topIssuers = issuerTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      return {
        'totalVolume': totalVolume,
        'uniqueIssuers': uniqueIssuers,
        'totalMarketBons': totalMarketBons,
        'weeklyBons': weeklyBons,
        'valueDistribution': valueDistribution,
        'rarityDistribution': rarityDistribution,
        'topIssuers': topIssuers.take(5).toList(),
        'localBonsCount': localBons.length,
        'lastUpdate': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      Logger.error('StorageService', 'Erreur getMarketEconomicData', e);
      return {};
    }
  }

  /// Vide le cache local des P3 du marché
  /// ✅ SÉPARÉ: Utilise CacheDatabaseService (base dédiée au cache réseau)
  Future<void> clearP3Cache() async {
    try {
      await _cacheService.clearP3Cache();
      await _cacheService.clearMarketBons();
      Logger.success('StorageService', 'Cache P3 vidé (SQLite)');
    } catch (e) {
      Logger.error('StorageService', 'Erreur clearP3Cache', e);
      rethrow;
    }
  }

  /// Récupère le timestamp de la dernière synchronisation P3
  /// ✅ SÉPARÉ: Utilise CacheDatabaseService (base dédiée au cache réseau)
  Future<DateTime?> getLastP3Sync() async {
    return await _cacheService.getLastP3Sync();
  }

  /// Efface tout le stockage (pour reset complet)
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
  }

  /// Nettoie les bons expirés du wallet local
  /// Marque les bons expirés avec le statut BonStatus.expired au lieu de les supprimer
  Future<int> cleanupExpiredBons() async {
    final bons = await _getBonsInternal();
    int expiredCount = 0;
    final updatedBons = <Bon>[];
    
    for (final bon in bons) {
      if (bon.isExpired && bon.status != BonStatus.expired) {
        updatedBons.add(bon.copyWith(status: BonStatus.expired));
        expiredCount++;
      }
    }
    
    if (updatedBons.isNotEmpty) {
      await _cacheService.saveLocalBonsBatch(updatedBons.map((b) => b.toJson()).toList());
      Logger.log('StorageService', 'Nettoyage: $expiredCount bons marqués comme expirés');
    }
    
    return expiredCount;
  }

  /// Récupère les bons actifs (non dépensés, non expirés)
  Future<List<Bon>> getActiveBons() async {
    final bons = await getBons();
    return bons.where((b) => b.isValid).toList();
  }

  /// Récupère les bons par statut
  Future<List<Bon>> getBonsByStatus(BonStatus status) async {
    final bons = await getBons();
    return bons.where((b) => b.status == status).toList();
  }

  /// Initialise un marché par défaut si aucun n'existe
  ///
  /// Deux types de marchés :
  /// - **MARCHÉ LIBRE** : Seed à zéro = Transparence publique et auditabilité totale
  ///   (équivalence 1 ẐEN = 0.1 Ğ1 pour ancrage cognitif)
  /// - **MARCHÉ LOCAL** : Seed aléatoire sécurisée pour écosystème privé/fermé
  Future<Market> initializeDefaultMarket({String? name}) async {
    final existing = await getMarket();
    if (existing != null) return existing;

    // Déterminer le nom du marché
    final marketName = name ?? 'Marché Libre';
    final isGlobalMarket = marketName.toUpperCase() == 'HACKATHON';

    String seedHex;
    
    if (isGlobalMarket) {
      // ✅ MARCHÉ GLOBAL : Seed à zéro = Transparence publique et auditabilité totale
      // Ce n'est PAS une faille de sécurité, c'est une FEATURE !
      // Tout le monde peut auditer le graphe des transactions (comme une blockchain publique)
      // Ancrage cognitif : 1 ẐEN ≈ 0.1 Ğ1 sur ce marché
      seedHex = '0' * 64; // 32 octets à zéro
      Logger.info('StorageService', '🌐 Marché Libre activé (Transparence publique)');
    } else {
      // ✅ MARCHÉ LOCAL : Graine aléatoire sécurisée pour écosystème privé
      // Idéal pour un village, une communauté, un réseau de confiance fermé
      final secureRandom = Random.secure();
      final seedBytes = Uint8List.fromList(
        List.generate(32, (_) => secureRandom.nextInt(256))
      );
      seedHex = HEX.encode(seedBytes);
    }

    final defaultMarket = Market(
      name: marketName,
      seedMarket: seedHex, // Graine (zéro pour marché global, aléatoire pour marché local)
      validUntil: DateTime.now().add(const Duration(days: 365)),
      relayUrl: AppConfig.defaultRelayUrl,
    );

    await saveMarket(defaultMarket);
    
    if (isGlobalMarket) {
      Logger.success('StorageService', '🌐 Marché Libre créé (Transparence publique, 1 ẐEN ≈ 0.1 Ğ1)');
    } else {
      Logger.success('StorageService', '🏘️ Marché local "$marketName" créé avec seed sécurisée');
    }
    
    return defaultMarket;
  }

  /// Vérifie si c'est le premier lancement (onboarding non complété)
  Future<bool> isFirstLaunch() async {
    final market = await getMarket();
    final user = await getUser();
    final onboardingComplete = await _secureStorage.read(key: _onboardingCompleteKey);
    
    // Premier lancement si pas de marché OU pas d'utilisateur OU onboarding non marqué comme complété
    return market == null || user == null || onboardingComplete != 'true';
  }

  /// Marque l'onboarding comme complété
  Future<void> markOnboardingComplete() async {
    await _secureStorage.write(key: _onboardingCompleteKey, value: 'true');
  }

  /// Récupère la graine du marché (seedMarket)
  Future<String?> getSeedMarket() async {
    final market = await getMarket();
    return market?.seedMarket;
  }

  /// Vérifie si un profil Nostr existe
  Future<bool> hasNostrProfile() async {
    final user = await getUser();
    return user != null && user.npub.isNotEmpty;
  }

  // ============================================================
  // ✅ GESTION DES FOLLOWERS (Ceux qui suivent l'utilisateur)
  // ============================================================

  /// Sauvegarde un follower
  Future<void> saveFollower(String npub) async {
    await _cacheService.saveFollower(npub);
  }

  /// Sauvegarde un lot de followers
  Future<void> saveFollowersBatch(List<String> npubs) async {
    await _cacheService.saveFollowersBatch(npubs);
  }

  /// Récupère tous les followers
  Future<List<String>> getFollowers() async {
    return await _cacheService.getFollowers();
  }

  /// Vide le cache des followers
  Future<void> clearFollowersCache() async {
    await _cacheService.clearFollowersCache();
  }

  // ============================================================
  // ✅ GESTION DES CONTACTS (Réseau de confiance)
  // ============================================================

  /// Récupère la liste des contacts (npubs)
  Future<List<String>> getContacts() async {
    try {
      final data = await _secureStorage.read(key: _contactsKey);
      if (data == null) return [];
      
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList.map((e) => e.toString()).toList();
    } catch (e) {
      Logger.error('StorageService', 'Erreur getContacts', e);
      return [];
    }
  }

  /// Sauvegarde la liste complète des contacts
  Future<void> saveContacts(List<String> contacts) async {
    try {
      // S'assurer qu'il n'y a pas de doublons
      final uniqueContacts = contacts.toSet().toList();
      await _secureStorage.write(
        key: _contactsKey,
        value: jsonEncode(uniqueContacts),
      );
    } catch (e) {
      Logger.error('StorageService', 'Erreur saveContacts', e);
    }
  }

  /// Ajoute un contact à la liste
  Future<bool> addContact(String npub) async {
    try {
      final contacts = await getContacts();
      if (!contacts.contains(npub)) {
        contacts.add(npub);
        await saveContacts(contacts);
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('StorageService', 'Erreur addContact', e);
      return false;
    }
  }

  /// Supprime un contact de la liste
  Future<bool> removeContact(String npub) async {
    try {
      final contacts = await getContacts();
      if (contacts.contains(npub)) {
        contacts.remove(npub);
        await saveContacts(contacts);
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('StorageService', 'Erreur removeContact', e);
      return false;
    }
  }

  // ============================================================
  // ✅ GESTION DU CACHE N2 (Amis d'amis)
  // ============================================================

  /// Sauvegarde un contact N2
  Future<void> saveN2Contact(String npub, String viaN1Npub) async {
    await _cacheService.saveN2Contact(npub, viaN1Npub);
  }

  /// Sauvegarde un lot de contacts N2
  Future<void> saveN2ContactsBatch(List<Map<String, String>> contacts) async {
    await _cacheService.saveN2ContactsBatch(contacts);
  }

  /// Vérifie si un npub est dans le réseau N2
  Future<bool> isN2Contact(String npub) async {
    return await _cacheService.isN2Contact(npub);
  }

  /// Récupère tous les contacts N2
  Future<List<Map<String, String>>> getN2Contacts() async {
    return await _cacheService.getN2Contacts();
  }

  /// Vide le cache N2
  Future<void> clearN2Cache() async {
    await _cacheService.clearN2Cache();
  }

  // ============================================================
  // GESTION DU BON ZÉRO (Bootstrap pour nouveaux utilisateurs)
  // ============================================================

  /// Vérifie si l'utilisateur a déjà reçu son Bon Zéro initial
  Future<bool> hasReceivedBootstrap() async {
    try {
      final value = await _secureStorage.read(key: _bootstrapReceivedKey);
      return value == 'true';
    } catch (e) {
      Logger.error('StorageService', 'Erreur hasReceivedBootstrap', e);
      return false;
    }
  }

  /// Marque l'utilisateur comme ayant reçu son Bon Zéro
  /// et enregistre la date d'expiration initiale (28 jours)
  Future<void> setBootstrapReceived(bool received, {DateTime? expirationDate}) async {
    try {
      await _secureStorage.write(
        key: _bootstrapReceivedKey,
        value: received.toString(),
      );
      
      // Enregistrer la date d'expiration initiale
      if (expirationDate != null) {
        await _secureStorage.write(
          key: _bootstrapExpirationKey,
          value: expirationDate.toIso8601String(),
        );
      }
      
      Logger.log('StorageService', 'Bon Zéro marqué comme reçu: $received');
    } catch (e) {
      Logger.error('StorageService', 'Erreur setBootstrapReceived', e);
    }
  }

  /// Récupère la date d'expiration du Bon Zéro initial
  /// Retourne null si non défini
  Future<DateTime?> getBootstrapExpiration() async {
    try {
      final value = await _secureStorage.read(key: _bootstrapExpirationKey);
      if (value == null) return null;
      return DateTime.parse(value);
    } catch (e) {
      Logger.error('StorageService', 'Erreur getBootstrapExpiration', e);
      return null;
    }
  }

  /// Vérifie si le Bon Zéro initial a expiré
  Future<bool> isBootstrapExpired() async {
    final expiration = await getBootstrapExpiration();
    if (expiration == null) return true;
    return DateTime.now().isAfter(expiration);
  }

  /// Vérifie si le bootstrap a expiré ET que le DU n'est pas activé (N1 < 5)
  /// C'est la condition pour l'auto-destruction de l'application
  Future<bool> isBootstrapExpiredAndDuNotActive() async {
    // Vérifier si l'utilisateur a reçu un bootstrap
    final hasBootstrap = await hasReceivedBootstrap();
    if (!hasBootstrap) return false; // Pas de bootstrap = pas d'expiration
    
    // Vérifier si le bootstrap a expiré
    final isExpired = await isBootstrapExpired();
    if (!isExpired) return false; // Pas encore expiré
    
    // Vérifier si le DU est activé (N1 ≥ 5)
    final contacts = await getContacts();
    final hasEnoughContacts = contacts.length >= 5; // _minMutualFollows = 5
    
    // Si le bootstrap est expiré ET qu'on n'a pas assez de contacts = auto-destruction
    return !hasEnoughContacts;
  }

  /// Supprime toutes les données de l'application (réinitialisation complète)
  /// Inclut le stockage sécurisé ET le cache SQLite
  Future<void> clearAllData() async {
    try {
      // Supprimer toutes les données du stockage sécurisé
      await _secureStorage.deleteAll();
      
      // Vider le cache SQLite
      await _cacheService.clearAllCache();
      
      Logger.info('StorageService', 'Toutes les données ont été supprimées');
    } catch (e) {
      Logger.error('StorageService', 'Erreur lors de la suppression des données', e);
      rethrow;
    }
  }

  // ============================================================
  // ✅ GESTION DU MODE D'UTILISATION (Progressive Disclosure)
  // 3 modes : Flâneur (0), Artisan (1), Alchimiste (2)
  // ============================================================

  /// Sauvegarde le mode d'utilisation de l'application
  /// 0 = Flâneur (Client/Acheteur), 1 = Artisan (Commerçant), 2 = Alchimiste (Expert)
  Future<void> setAppMode(int modeIndex) async {
    try {
      await _secureStorage.write(key: _appModeKey, value: modeIndex.toString());
      Logger.log('StorageService', 'Mode d\'application défini: $modeIndex');
    } catch (e) {
      Logger.error('StorageService', 'Erreur setAppMode', e);
    }
  }

  /// Récupère le mode d'utilisation de l'application
  /// Retourne 0 (Flâneur) par défaut si non défini
  Future<int> getAppMode() async {
    try {
      final mode = await _secureStorage.read(key: _appModeKey);
      return mode != null ? int.parse(mode) : 0; // Défaut : Flâneur
    } catch (e) {
      Logger.error('StorageService', 'Erreur getAppMode', e);
      return 0; // Défaut : Flâneur en cas d'erreur
    }
  }

  // ============================================================
  // ✅ GESTION DU DIVIDENDE UNIVERSEL (DU)
  // ============================================================

  /// Sauvegarde la date de la dernière génération de DU
  Future<void> setLastDuGenerationDate(DateTime date) async {
    try {
      await _secureStorage.write(
        key: _lastDuGenerationKey,
        value: date.toIso8601String(),
      );
    } catch (e) {
      Logger.error('StorageService', 'Erreur setLastDuGenerationDate', e);
    }
  }

  /// Récupère la date de la dernière génération de DU
  Future<DateTime?> getLastDuGenerationDate() async {
    try {
      final value = await _secureStorage.read(key: _lastDuGenerationKey);
      if (value == null) return null;
      return DateTime.parse(value);
    } catch (e) {
      Logger.error('StorageService', 'Erreur getLastDuGenerationDate', e);
      return null;
    }
  }

  /// Sauvegarde la dernière valeur du DU générée
  Future<void> setLastDuValue(double value) async {
    try {
      await _secureStorage.write(
        key: _lastDuValueKey,
        value: value.toString(),
      );
    } catch (e) {
      Logger.error('StorageService', 'Erreur setLastDuValue', e);
    }
  }

  /// Récupère la dernière valeur du DU générée
  Future<double?> getLastDuValue() async {
    try {
      final value = await _secureStorage.read(key: _lastDuValueKey);
      if (value == null) return null;
      return double.parse(value);
    } catch (e) {
      Logger.error('StorageService', 'Erreur getLastDuValue', e);
      return null;
    }
  }

  /// Sauvegarde le DU disponible à émettre
  Future<void> setAvailableDuToEmit(double value) async {
    try {
      await _secureStorage.write(
        key: _availableDuToEmitKey,
        value: value.toString(),
      );
    } catch (e) {
      Logger.error('StorageService', 'Erreur setAvailableDuToEmit', e);
    }
  }

  /// Récupère le DU disponible à émettre
  Future<double> getAvailableDuToEmit() async {
    try {
      final value = await _secureStorage.read(key: _availableDuToEmitKey);
      if (value == null) return 0.0;
      return double.parse(value);
    } catch (e) {
      Logger.error('StorageService', 'Erreur getAvailableDuToEmit', e);
      return 0.0;
    }
  }

  /// Ajoute au DU disponible à émettre
  Future<void> addAvailableDuToEmit(double amount) async {
    final current = await getAvailableDuToEmit();
    await setAvailableDuToEmit(current + amount);
  }

  /// Déduit du DU disponible à émettre
  Future<bool> deductAvailableDuToEmit(double amount) async {
    final current = await getAvailableDuToEmit();
    if (current >= amount) {
      await setAvailableDuToEmit(current - amount);
      return true;
    }
    return false;
  }
}
