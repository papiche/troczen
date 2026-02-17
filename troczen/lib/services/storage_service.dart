import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
}
