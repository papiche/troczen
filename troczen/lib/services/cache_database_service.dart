import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Service de cache pour les données éphémères du réseau
/// Base de données SÉPARÉE de l'audit trail pour:
/// - Éviter la suppression accidentelle du cache lors d'une demande RGPD
/// - Permettre une gestion indépendante du cycle de vie des données
/// - Optimiser les performances avec une base dédiée au cache
class CacheDatabaseService {
  static Database? _database;
  
  // Tables du cache
  static const String _p3CacheTable = 'p3_cache';
  static const String _marketBonsTable = 'market_bons';
  static const String _syncMetadataTable = 'sync_metadata';
  static const String _n2CacheTable = 'n2_cache';

  /// Initialiser la base de données de cache
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    // ✅ Base SÉPARÉE pour le cache réseau
    final path = join(documentsDirectory.path, 'troczen_cache.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await _createAllTables(db);
      },
    );
  }

  /// Créer toutes les tables du cache
  Future<void> _createAllTables(Database db) async {
    // Table pour le cache P3 individuel (bonId -> p3Hex)
    await db.execute('''
      CREATE TABLE $_p3CacheTable (
        bon_id TEXT PRIMARY KEY,
        p3_hex TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_p3_updated ON $_p3CacheTable(updated_at)',
    );

    // Table pour les données du marché (kind 30303)
    await db.execute('''
      CREATE TABLE $_marketBonsTable (
        bon_id TEXT PRIMARY KEY,
        issuer_npub TEXT,
        issuer_name TEXT,
        value REAL,
        rarity TEXT,
        status TEXT,
        created_at TEXT,
        expires_at TEXT,
        description TEXT,
        image_url TEXT,
        tags TEXT,
        raw_data TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_market_issuer ON $_marketBonsTable(issuer_npub)',
    );
    await db.execute(
      'CREATE INDEX idx_market_status ON $_marketBonsTable(status)',
    );

    // Table pour les métadonnées de synchronisation
    await db.execute('''
      CREATE TABLE $_syncMetadataTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Table pour le cache N2 (Amis d'Amis)
    await db.execute('''
      CREATE TABLE $_n2CacheTable (
        npub TEXT NOT NULL,
        via_n1_npub TEXT NOT NULL,
        PRIMARY KEY (npub, via_n1_npub)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_n2_npub ON $_n2CacheTable(npub)',
    );
  }

  // ============================================================
  // MÉTHODES P3 CACHE
  // ============================================================

  /// Sauvegarder une P3 dans le cache
  Future<void> saveP3ToCache(String bonId, String p3Hex) async {
    final db = await database;
    await db.insert(
      _p3CacheTable,
      {
        'bon_id': bonId,
        'p3_hex': p3Hex,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Sauvegarder un lot de P3 en une seule transaction (batch)
  Future<void> saveP3BatchToCache(Map<String, String> p3Batch) async {
    if (p3Batch.isEmpty) return;
    
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.transaction((txn) async {
      for (final entry in p3Batch.entries) {
        await txn.insert(
          _p3CacheTable,
          {
            'bon_id': entry.key,
            'p3_hex': entry.value,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Récupérer le cache P3 complet
  Future<Map<String, String>> getP3Cache() async {
    final db = await database;
    final results = await db.query(_p3CacheTable);
    
    return Map.fromEntries(
      results.map((row) => MapEntry(
        row['bon_id'] as String,
        row['p3_hex'] as String,
      )),
    );
  }

  /// Récupérer une P3 depuis le cache
  Future<String?> getP3FromCache(String bonId) async {
    final db = await database;
    final results = await db.query(
      _p3CacheTable,
      where: 'bon_id = ?',
      whereArgs: [bonId],
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return results.first['p3_hex'] as String;
  }

  /// Vider le cache P3
  Future<void> clearP3Cache() async {
    final db = await database;
    await db.delete(_p3CacheTable);
  }

  /// Obtenir le nombre de P3 en cache
  Future<int> getP3CacheCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_p3CacheTable',
    );
    return result.first['count'] as int;
  }

  // ============================================================
  // MÉTHODES MARKET BONS
  // ============================================================

  /// Sauvegarder les données d'un bon du marché
  Future<void> saveMarketBonData(Map<String, dynamic> bonData) async {
    final db = await database;
    final bonId = bonData['bonId'] as String?;
    if (bonId == null) return;

    await db.insert(
      _marketBonsTable,
      {
        'bon_id': bonId,
        'issuer_npub': bonData['issuerNpub'],
        'issuer_name': bonData['issuerName'],
        'value': bonData['value'],
        'rarity': bonData['rarity'],
        'status': bonData['status'],
        'created_at': bonData['createdAt'],
        'expires_at': bonData['expiresAt'],
        'description': bonData['description'],
        'image_url': bonData['imageUrl'],
        'tags': bonData['tags'] != null ? jsonEncode(bonData['tags']) : null,
        'raw_data': jsonEncode(bonData),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Sauvegarder un lot de données du marché (batch)
  Future<void> saveMarketBonDataBatch(List<Map<String, dynamic>> bonDataList) async {
    if (bonDataList.isEmpty) return;
    
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.transaction((txn) async {
      for (final bonData in bonDataList) {
        final bonId = bonData['bonId'] as String?;
        if (bonId == null) continue;

        await txn.insert(
          _marketBonsTable,
          {
            'bon_id': bonId,
            'issuer_npub': bonData['issuerNpub'],
            'issuer_name': bonData['issuerName'],
            'value': bonData['value'],
            'rarity': bonData['rarity'],
            'status': bonData['status'],
            'created_at': bonData['createdAt'],
            'expires_at': bonData['expiresAt'],
            'description': bonData['description'],
            'image_url': bonData['imageUrl'],
            'tags': bonData['tags'] != null ? jsonEncode(bonData['tags']) : null,
            'raw_data': jsonEncode(bonData),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Récupérer tous les bons du marché
  Future<List<Map<String, dynamic>>> getMarketBonsData() async {
    final db = await database;
    final results = await db.query(
      _marketBonsTable,
      orderBy: 'updated_at DESC',
    );
    
    return results.map((row) {
      final rawData = row['raw_data'] as String?;
      if (rawData != null) {
        return jsonDecode(rawData) as Map<String, dynamic>;
      }
      return {
        'bonId': row['bon_id'],
        'issuerNpub': row['issuer_npub'],
        'issuerName': row['issuer_name'],
        'value': row['value'],
        'rarity': row['rarity'],
        'status': row['status'],
        'createdAt': row['created_at'],
        'expiresAt': row['expires_at'],
        'description': row['description'],
        'imageUrl': row['image_url'],
        'tags': row['tags'] != null ? jsonDecode(row['tags'] as String) : null,
      };
    }).toList();
  }

  /// Récupérer un bon du marché par ID
  Future<Map<String, dynamic>?> getMarketBonById(String bonId) async {
    final db = await database;
    final results = await db.query(
      _marketBonsTable,
      where: 'bon_id = ?',
      whereArgs: [bonId],
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    
    final rawData = results.first['raw_data'] as String?;
    if (rawData != null) {
      return jsonDecode(rawData) as Map<String, dynamic>;
    }
    return null;
  }

  /// Vider les données du marché
  Future<void> clearMarketBons() async {
    final db = await database;
    await db.delete(_marketBonsTable);
  }

  /// Obtenir le nombre de bons sur le marché
  Future<int> getMarketBonsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_marketBonsTable',
    );
    return result.first['count'] as int;
  }

  // ============================================================
  // MÉTHODES SYNC METADATA
  // ============================================================

  /// Sauvegarder le timestamp de dernière sync P3
  Future<void> saveLastP3Sync() async {
    final db = await database;
    await db.execute(
      'INSERT OR REPLACE INTO $_syncMetadataTable (key, value) VALUES (?, ?)',
      ['last_p3_sync', DateTime.now().millisecondsSinceEpoch.toString()],
    );
  }

  /// Récupérer le timestamp de dernière sync P3
  Future<DateTime?> getLastP3Sync() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT value FROM $_syncMetadataTable WHERE key = ?',
        ['last_p3_sync'],
      );
      if (result.isEmpty) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        int.parse(result.first['value'] as String),
      );
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // MÉTHODES N2 CACHE
  // ============================================================

  /// Sauvegarder un contact N2
  Future<void> saveN2Contact(String npub, String viaN1Npub) async {
    final db = await database;
    await db.insert(
      _n2CacheTable,
      {
        'npub': npub,
        'via_n1_npub': viaN1Npub,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Sauvegarder un lot de contacts N2
  Future<void> saveN2ContactsBatch(List<Map<String, String>> contacts) async {
    if (contacts.isEmpty) return;
    
    final db = await database;
    await db.transaction((txn) async {
      for (final contact in contacts) {
        await txn.insert(
          _n2CacheTable,
          contact,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Vérifier si un npub est dans le réseau N2
  Future<bool> isN2Contact(String npub) async {
    final db = await database;
    final results = await db.query(
      _n2CacheTable,
      where: 'npub = ?',
      whereArgs: [npub],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  /// Vider le cache N2
  Future<void> clearN2Cache() async {
    final db = await database;
    await db.delete(_n2CacheTable);
  }

  // ============================================================
  // MÉTHODES DE GESTION
  // ============================================================

  /// Vider tout le cache (P3 + Market + Sync)
  /// ⚠️ À utiliser avec précaution - efface toutes les données éphémères
  Future<void> clearAllCache() async {
    final db = await database;
    await db.delete(_p3CacheTable);
    await db.delete(_marketBonsTable);
    await db.delete(_syncMetadataTable);
    await db.delete(_n2CacheTable);
  }

  /// Obtenir la taille de la base de cache
  Future<int> getDatabaseSize() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final file = File(join(documentsDirectory.path, 'troczen_cache.db'));

    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  /// Fermer la base de données
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
