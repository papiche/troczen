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
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Instance du service SQLite pour le cache réseau (P3, marché)
  // ✅ SÉPARÉ de l'audit trail pour indépendance du cycle de vie
  final CacheDatabaseService _cacheService = CacheDatabaseService();

  // Clés de stockage (uniquement pour les petites données sensibles)
  static const String _userKey = 'user';
  static const String _bonsKey = 'bons';
  static const String _marketKey = 'market';
  static const String _p3CacheKey = 'p3_cache'; // ⚠️ Conservé pour migration
  static const String _onboardingCompleteKey = 'onboarding_complete';

  // ✅ SÉCURITÉ: Mutex pour éviter les race conditions
  // FlutterSecureStorage n'a pas de système de transaction
  // Ce verrou garantit qu'une seule opération d'écriture à la fois
  Completer<void>? _bonsLock;
  
  /// Acquiert le verrou sur les bons
  Future<void> _acquireBonsLock() async {
    while (_bonsLock != null) {
      await _bonsLock!.future;
    }
    _bonsLock = Completer<void>();
  }
  
  /// Libère le verrou sur les bons
  void _releaseBonsLock() {
    final lock = _bonsLock;
    _bonsLock = null;
    lock?.complete();
  }

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
  /// ✅ SÉCURITÉ: Utilise un verrou pour éviter les race conditions
  Future<void> saveBon(Bon bon) async {
    await _acquireBonsLock();
    try {
      final bons = await getBons();
      
      // Remplacer ou ajouter le bon
      final index = bons.indexWhere((b) => b.bonId == bon.bonId);
      if (index != -1) {
        bons[index] = bon;
      } else {
        bons.add(bon);
      }
      
      await _saveBons(bons);
    } finally {
      _releaseBonsLock();
    }
  }

  /// Récupère tous les bons
  /// ✅ SÉCURITÉ: Utilise un verrou pour éviter les race conditions lors de la lecture
  Future<List<Bon>> getBons() async {
    await _acquireBonsLock();
    try {
      final data = await _secureStorage.read(key: _bonsKey);
      if (data == null) return [];
      
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList.map((json) => Bon.fromJson(json)).toList();
    } finally {
      _releaseBonsLock();
    }
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
  /// ✅ SÉCURITÉ: Utilise un verrou pour éviter les race conditions
  Future<void> deleteBon(String bonId) async {
    await _acquireBonsLock();
    try {
      final bons = await _getBonsInternal();
      bons.removeWhere((b) => b.bonId == bonId);
      await _saveBons(bons);
    } finally {
      _releaseBonsLock();
    }
  }

  /// Récupère tous les bons (version interne sans verrou)
  Future<List<Bon>> _getBonsInternal() async {
    final data = await _secureStorage.read(key: _bonsKey);
    if (data == null) return [];
    
    final List<dynamic> jsonList = jsonDecode(data);
    return jsonList.map((json) => Bon.fromJson(json)).toList();
  }

  /// Sauvegarde la liste complète des bons
  Future<void> _saveBons(List<Bon> bons) async {
    await _secureStorage.write(
      key: _bonsKey,
      value: jsonEncode(bons.map((b) => b.toJson()).toList()),
    );
  }

  /// Sauvegarde les informations du marché
  Future<void> saveMarket(Market market) async {
    await _secureStorage.write(
      key: _marketKey,
      value: jsonEncode(market.toJson()),
    );
  }

  /// Récupère les informations du marché
  Future<Market?> getMarket() async {
    final data = await _secureStorage.read(key: _marketKey);
    if (data == null) return null;
    return Market.fromJson(jsonDecode(data));
  }

  /// Supprime les informations du marché
  Future<void> deleteMarket() async {
    await _secureStorage.delete(key: _marketKey);
  }

  // ============================================================
  // ✅ MÉTHODES P3 CACHE - Maintenant dans SQLite
  // FlutterSecureStorage causait des OOM sur iOS/Android
  // ============================================================

  /// Sauvegarde une P3 dans le cache SQLite
  /// ✅ SÉPARÉ: Utilise CacheDatabaseService (base dédiée au cache réseau)
  Future<void> saveP3ToCache(String bonId, String p3Hex) async {
    await _cacheService.saveP3ToCache(bonId, p3Hex);
  }

  /// ✅ OPTIMISÉ: Insertion en lot (batch) pour le cache P3
  /// Utilise une transaction SQLite pour performance optimale
  /// Évite les OOM et le Jank UI lors de la synchronisation massive
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

  /// ✅ CORRECTION: Récupère les données économiques du marché global
  /// Retourne les métadonnées de tous les bons publiés sur le marché (kind 30303)
  /// Utilisé par le Dashboard pour afficher la santé économique du marché
  Future<List<Map<String, dynamic>>> getMarketBonsData() async {
    return await getP3List();
  }

  /// ✅ CORRECTION: Récupère les données économiques agrégées pour le dashboard
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

  /// ✅ MIGRATION: Migre les données P3 de FlutterSecureStorage vers SQLite
  /// À appeler au démarrage de l'application pour les utilisateurs existants
  Future<void> migrateP3CacheToSQLite() async {
    try {
      // Vérifier si des données existent dans l'ancien stockage
      final oldP3CacheData = await _secureStorage.read(key: _p3CacheKey);
      final oldMarketP3ListData = await _secureStorage.read(key: 'market_p3_list');
      
      bool migrated = false;
      
      // Migrer le cache P3 individuel
      if (oldP3CacheData != null && oldP3CacheData.isNotEmpty) {
        try {
          final Map<String, dynamic> jsonMap = jsonDecode(oldP3CacheData);
          final p3Cache = jsonMap.map((key, value) => MapEntry(key, value.toString()));
          
          if (p3Cache.isNotEmpty) {
            await _cacheService.saveP3BatchToCache(p3Cache);
            await _secureStorage.delete(key: _p3CacheKey);
            Logger.success('StorageService', 'Migration P3 cache: ${p3Cache.length} entrées migrées vers SQLite');
            migrated = true;
          }
        } catch (e) {
          Logger.error('StorageService', 'Erreur migration P3 cache', e);
        }
      }
      
      // Migrer les données du marché
      if (oldMarketP3ListData != null && oldMarketP3ListData.isNotEmpty) {
        try {
          final List<dynamic> p3Data = jsonDecode(oldMarketP3ListData);
          final marketBons = p3Data.cast<Map<String, dynamic>>();
          
          if (marketBons.isNotEmpty) {
            await _cacheService.saveMarketBonDataBatch(marketBons);
            await _secureStorage.delete(key: 'market_p3_list');
            Logger.success('StorageService', 'Migration marché: ${marketBons.length} bons migrés vers SQLite');
            migrated = true;
          }
        } catch (e) {
          Logger.error('StorageService', 'Erreur migration marché', e);
        }
      }
      
      // Migrer le timestamp de dernière sync
      final oldSyncTimestamp = await _secureStorage.read(key: 'market_p3_last_sync');
      if (oldSyncTimestamp != null) {
        await _secureStorage.delete(key: 'market_p3_last_sync');
      }
      
      if (migrated) {
        Logger.success('StorageService', '✅ Migration P3 vers SQLite terminée avec succès');
      }
    } catch (e) {
      Logger.error('StorageService', 'Erreur migration P3 vers SQLite', e);
    }
  }

  /// Efface tout le stockage (pour reset complet)
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
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
  /// En mode HACKATHON (name = 'HACKATHON'), utilise une seed à zéro pour faciliter les tests
  /// ⚠️ MODE HACKATHON: Sécurité réduite - chiffrement P3 avec clé prévisible
  Future<Market> initializeDefaultMarket({String? name}) async {
    final existing = await getMarket();
    if (existing != null) return existing;

    // Déterminer le nom du marché
    final marketName = name ?? 'Marché Local';
    final isHackathonMode = marketName.toUpperCase() == 'HACKATHON';

    String seedHex;
    
    if (isHackathonMode) {
      // ✅ MODE HACKATHON: Seed à zéro pour faciliter les tests et le cassage du chiffrement P3
      // Cela permet aux participants du hackathon de comprendre et débugger l'application
      // ⚠️ NE PAS UTILISER EN PRODUCTION - Sécurité réduite
      seedHex = '0' * 64; // 32 octets à zéro
      Logger.warn('StorageService', '⚠️ MODE HACKATHON ACTIVÉ - Seed à zéro utilisée (sécurité réduite)');
    } else {
      // ✅ PRODUCTION: Générer une graine ALÉATOIRE SÉCURISÉE
      // La graine de marché par défaut était 64 zéros, ce qui rend K_day dérivée nulle
      // et ne chiffre rien en pratique (vulnérabilité critique)
      final secureRandom = Random.secure();
      final seedBytes = Uint8List.fromList(
        List.generate(32, (_) => secureRandom.nextInt(256))
      );
      seedHex = HEX.encode(seedBytes);
    }

    final defaultMarket = Market(
      name: marketName,
      seedMarket: seedHex, // Graine (zéro en mode HACKATHON, aléatoire sinon)
      validUntil: DateTime.now().add(const Duration(days: 365)),
      relayUrl: AppConfig.defaultRelayUrl,
    );

    await saveMarket(defaultMarket);
    
    if (isHackathonMode) {
      Logger.success('StorageService', '🎉 Marché HACKATHON créé avec seed à zéro');
    } else {
      Logger.success('StorageService', 'Marché "$marketName" créé avec seed sécurisée');
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
}
