import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hex/hex.dart';
import '../models/user.dart';
import '../models/bon.dart';
import '../models/market.dart';

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
  Future<void> saveBon(Bon bon) async {
    final bons = await getBons();
    
    // Remplacer ou ajouter le bon
    final index = bons.indexWhere((b) => b.bonId == bon.bonId);
    if (index != -1) {
      bons[index] = bon;
    } else {
      bons.add(bon);
    }
    
    await _saveBons(bons);
  }

  /// Récupère tous les bons
  Future<List<Bon>> getBons() async {
    final data = await _secureStorage.read(key: _bonsKey);
    if (data == null) return [];
    
    final List<dynamic> jsonList = jsonDecode(data);
    return jsonList.map((json) => Bon.fromJson(json)).toList();
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
    final bons = await getBons();
    bons.removeWhere((b) => b.bonId == bonId);
    await _saveBons(bons);
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
      print('❌ Erreur getP3List: $e');
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
      print('✅ ${p3List.length} P3 sauvegardées');
    } catch (e) {
      print('❌ Erreur saveP3List: $e');
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
      print('✅ Cache P3 vidé');
    } catch (e) {
      print('❌ Erreur clearP3Cache: $e');
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
  Future<Market> initializeDefaultMarket() async {
    final existing = await getMarket();
    if (existing != null) return existing;

    // ✅ CORRECTION BUG P0 CRITIQUE: Générer une graine ALÉATOIRE SÉCURISÉE
    // La graine de marché par défaut était 64 zéros, ce qui rend K_day dérivée nulle
    // et ne chiffre rien en pratique (vulnérabilité critique)
    final secureRandom = Random.secure();
    final seedBytes = Uint8List.fromList(
      List.generate(32, (_) => secureRandom.nextInt(256))
    );
    final seedHex = HEX.encode(seedBytes);

    final defaultMarket = Market(
      name: 'Marché Local',
      seedMarket: seedHex, // Graine aléatoire sécurisée de 32 octets (64 caractères hex)
      validUntil: DateTime.now().add(const Duration(days: 365)),
      relayUrl: 'wss://relay.copylaradio.com',
    );

    await saveMarket(defaultMarket);
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
