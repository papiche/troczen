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

class StorageService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Clés de stockage
  static const String _userKey = 'user';
  static const String _bonsKey = 'bons';
  static const String _marketKey = 'market';
  static const String _p3CacheKey = 'p3_cache';
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

  /// Sauvegarde une P3 dans le cache
  /// Le cache P3 est une Map<bonId, p3Hex>
  Future<void> saveP3ToCache(String bonId, String p3Hex) async {
    final cache = await getP3Cache();
    cache[bonId] = p3Hex;
    await _secureStorage.write(
      key: _p3CacheKey,
      value: jsonEncode(cache),
    );
  }

  /// Récupère le cache P3 complet
  Future<Map<String, String>> getP3Cache() async {
    final data = await _secureStorage.read(key: _p3CacheKey);
    if (data == null) return {};
    
    final Map<String, dynamic> jsonMap = jsonDecode(data);
    return jsonMap.map((key, value) => MapEntry(key, value.toString()));
  }

  /// Récupère une P3 depuis le cache
  Future<String?> getP3FromCache(String bonId) async {
    final cache = await getP3Cache();
    return cache[bonId];
  }

  /// Récupère la liste des P3 du marché depuis le cache
  /// Retourne une liste de Map avec les métadonnées des P3
  Future<List<Map<String, dynamic>>> getP3List() async {
    try {
      final data = await _secureStorage.read(key: 'market_p3_list');
      if (data == null) return [];
      
      final List<dynamic> p3Data = jsonDecode(data);
      return p3Data.cast<Map<String, dynamic>>();
    } catch (e) {
      Logger.error('StorageService', 'Erreur getP3List', e);
      return [];
    }
  }

  /// Sauvegarde la liste des P3 du marché
  Future<void> saveP3List(List<Map<String, dynamic>> p3List) async {
    try {
      await _secureStorage.write(
        key: 'market_p3_list',
        value: jsonEncode(p3List),
      );
      // Enregistrer le timestamp de la dernière sync
      await _secureStorage.write(
        key: 'market_p3_last_sync',
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      Logger.success('StorageService', '${p3List.length} P3 sauvegardées');
    } catch (e) {
      Logger.error('StorageService', 'Erreur saveP3List', e);
      rethrow;
    }
  }

  /// Vide le cache local des P3 du marché
  Future<void> clearP3Cache() async {
    try {
      await _secureStorage.delete(key: 'market_p3_list');
      await _secureStorage.delete(key: 'market_p3_last_sync');
      // Vider aussi le cache P3 des bons individuels
      await _secureStorage.delete(key: _p3CacheKey);
      Logger.success('StorageService', 'Cache P3 vidé');
    } catch (e) {
      Logger.error('StorageService', 'Erreur clearP3Cache', e);
      rethrow;
    }
  }

  /// Récupère le timestamp de la dernière synchronisation P3
  Future<DateTime?> getLastP3Sync() async {
    try {
      final timestamp = await _secureStorage.read(key: 'market_p3_last_sync');
      if (timestamp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    } catch (e) {
      return null;
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
