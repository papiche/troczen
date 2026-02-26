import 'dart:async';
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
  static const String _marketTransfersTable = 'market_transfers';
  static const String _syncMetadataTable = 'sync_metadata';
  static const String _n2CacheTable = 'n2_cache';
  static const String _localWalletBonsTable = 'local_wallet_bons';
  static const String _followersCacheTable = 'followers_cache';

  // Stream pour notifier les insertions (Vigilance Alchimiste)
  final _insertionsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get insertionsStream => _insertionsController.stream;

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
    await db.execute(
      'CREATE INDEX idx_market_bons_created_at ON $_marketBonsTable(created_at)',
    );

    // Table pour les transferts du marché (kind 1)
    await db.execute('''
      CREATE TABLE $_marketTransfersTable (
        event_id TEXT PRIMARY KEY,
        bon_id TEXT NOT NULL,
        from_npub TEXT NOT NULL,
        to_npub TEXT NOT NULL,
        value REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        market_tag TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_mt_bon_id ON $_marketTransfersTable(bon_id)',
    );
    await db.execute(
      'CREATE INDEX idx_mt_timestamp ON $_marketTransfersTable(timestamp)',
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

    // Table pour les bons du portefeuille local
    await db.execute('''
      CREATE TABLE $_localWalletBonsTable (
        bon_id TEXT PRIMARY KEY,
        raw_data TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Table pour les followers (ceux qui suivent l'utilisateur)
    await db.execute('''
      CREATE TABLE $_followersCacheTable (
        npub TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  // ============================================================
  // MÉTHODES LOCAL WALLET BONS
  // ============================================================

  /// Sauvegarder un bon dans le portefeuille local
  Future<void> saveLocalBon(Map<String, dynamic> bonData) async {
    final db = await database;
    final bonId = bonData['bonId'] as String?;
    if (bonId == null) return;

    await db.insert(
      _localWalletBonsTable,
      {
        'bon_id': bonId,
        'raw_data': jsonEncode(bonData),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Sauvegarder une liste de bons dans le portefeuille local
  Future<void> saveLocalBonsBatch(List<Map<String, dynamic>> bons) async {
    if (bons.isEmpty) return;
    
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.transaction((txn) async {
      for (final bonData in bons) {
        final bonId = bonData['bonId'] as String?;
        if (bonId == null) continue;

        await txn.insert(
          _localWalletBonsTable,
          {
            'bon_id': bonId,
            'raw_data': jsonEncode(bonData),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Récupérer tous les bons du portefeuille local
  Future<List<Map<String, dynamic>>> getLocalBons() async {
    final db = await database;
    final results = await db.query(_localWalletBonsTable);
    
    return results.map((row) {
      return jsonDecode(row['raw_data'] as String) as Map<String, dynamic>;
    }).toList();
  }

  /// Supprimer un bon du portefeuille local
  Future<void> deleteLocalBon(String bonId) async {
    final db = await database;
    await db.delete(
      _localWalletBonsTable,
      where: 'bon_id = ?',
      whereArgs: [bonId],
    );
  }

  /// Vider le portefeuille local
  Future<void> clearLocalBons() async {
    final db = await database;
    await db.delete(_localWalletBonsTable);
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
    
    _insertionsController.add({
      'type': 'market_bon',
      'data': bonData,
    });
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

  /// Remplace atomiquement tous les bons du portefeuille local par une nouvelle liste.
  /// Utilise une transaction SQLite pour garantir l'intégrité des données.
  Future<void> replaceAllLocalBons(List<Map<String, dynamic>> bons) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // 1. Supprimer toutes les entrées existantes
      await txn.delete(_localWalletBonsTable);

      // 2. Insérer les nouveaux bons
      for (final bonData in bons) {
        final bonId = bonData['bonId'] as String?;
        if (bonId == null) {
          // Si un bon n'a pas d'ID, on l'ignore (normalement ne devrait pas arriver)
          continue;
        }
        await txn.insert(
          _localWalletBonsTable,
          {
            'bon_id': bonId,
            'raw_data': jsonEncode(bonData),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
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
  // MÉTHODES MARKET TRANSFERS (KIND 1)
  // ============================================================

  /// Sauvegarder un transfert du marché
  Future<void> saveMarketTransfer(Map<String, dynamic> transferData) async {
    final db = await database;
    final eventId = transferData['event_id'] as String?;
    if (eventId == null) return;

    await db.insert(
      _marketTransfersTable,
      {
        'event_id': eventId,
        'bon_id': transferData['bon_id'],
        'from_npub': transferData['from_npub'],
        'to_npub': transferData['to_npub'],
        'value': transferData['value'],
        'timestamp': transferData['timestamp'],
        'market_tag': transferData['market_tag'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    _insertionsController.add({
      'type': 'market_transfer',
      'data': transferData,
    });
  }

  /// Sauvegarder un lot de transferts du marché
  Future<void> saveMarketTransfersBatch(List<Map<String, dynamic>> transfers) async {
    if (transfers.isEmpty) return;
    
    final db = await database;
    await db.transaction((txn) async {
      for (final transferData in transfers) {
        final eventId = transferData['event_id'] as String?;
        if (eventId == null) continue;

        await txn.insert(
          _marketTransfersTable,
          {
            'event_id': eventId,
            'bon_id': transferData['bon_id'],
            'from_npub': transferData['from_npub'],
            'to_npub': transferData['to_npub'],
            'value': transferData['value'],
            'timestamp': transferData['timestamp'],
            'market_tag': transferData['market_tag'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ============================================================
  // MÉTHODES D'AGRÉGATION (ALCHIMISTE)
  // ============================================================

  /// Récupère les métriques agrégées pour une période donnée
  Future<AggregatedMetrics> getAggregatedMetrics(DateTime start, DateTime end, {String? groupBy}) async {
    final db = await database;
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();
    
    // 1. Calcul des totaux (Volume, Nombre de bons, Émetteurs uniques)
    final summaryResult = await db.rawQuery('''
      SELECT
        SUM(value) as total_volume,
        COUNT(*) as total_count,
        COUNT(DISTINCT issuer_npub) as unique_issuers
      FROM $_marketBonsTable
      WHERE created_at BETWEEN ? AND ?
      AND (status = 'active' OR status IS NULL)
    ''', [startStr, endStr]);

    final summary = summaryResult.first;

    // 2. Calcul de la série temporelle (pour les graphiques)
    // groupBy peut être '%Y-%m-%d' (jour), '%Y-%W' (semaine) ou '%Y-%m' (mois)
    final groupFormat = groupBy ?? '%Y-%m-%d';
    
    final seriesResult = await db.rawQuery('''
      SELECT
        strftime('$groupFormat', created_at) as period,
        SUM(value) as volume
      FROM $_marketBonsTable
      WHERE created_at BETWEEN ? AND ?
      AND (status = 'active' OR status IS NULL)
      GROUP BY period
      ORDER BY period ASC
    ''', [startStr, endStr]);

    final series = seriesResult.map((row) {
      final periodStr = row['period'] as String?;
      DateTime date = DateTime.now();
      if (periodStr != null) {
        try {
          if (groupFormat == '%Y-%m-%d') {
            date = DateTime.parse(periodStr);
          } else if (groupFormat == '%Y-%m') {
            date = DateTime.parse('$periodStr-01');
          } else {
            // Fallback pour semaine ou autre
            date = DateTime.parse(periodStr);
          }
        } catch (e) {
          // Ignorer l'erreur de parsing
        }
      }
      return TimeSeriesPoint(
        date,
        (row['volume'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    // 3. Calcul des transferts (kind 1)
    final transfersResult = await db.rawQuery('''
      SELECT
        SUM(value) as total_transfers_volume,
        COUNT(*) as total_transfers_count
      FROM $_marketTransfersTable
      WHERE timestamp BETWEEN ? AND ?
    ''', [start.millisecondsSinceEpoch ~/ 1000, end.millisecondsSinceEpoch ~/ 1000]);
    
    final transfersSummary = transfersResult.first;

    return AggregatedMetrics(
      totalVolume: (summary['total_volume'] as num?)?.toDouble() ?? 0.0,
      count: (summary['total_count'] as int?) ?? 0,
      uniqueIssuers: (summary['unique_issuers'] as int?) ?? 0,
      transfersVolume: (transfersSummary['total_transfers_volume'] as num?)?.toDouble() ?? 0.0,
      transfersCount: (transfersSummary['total_transfers_count'] as int?) ?? 0,
      series: series,
    );
  }

  /// Récupère un résumé des transferts pour le graphe de circulation
  Future<List<TransferEdge>> getTransferSummary({int? limitDays}) async {
    final db = await database;
    
    String timeFilter = '';
    List<dynamic> args = [];
    
    if (limitDays != null) {
      final cutoff = DateTime.now().subtract(Duration(days: limitDays)).millisecondsSinceEpoch ~/ 1000;
      timeFilter = 'WHERE t.timestamp >= ?';
      args.add(cutoff);
    }

    // On joint avec market_bons pour connaître l'émetteur original
    final result = await db.rawQuery('''
      SELECT
        t.from_npub,
        t.to_npub,
        SUM(t.value) as total_value,
        COUNT(*) as transfer_count,
        MAX(CASE WHEN t.to_npub = b.issuer_npub THEN 1 ELSE 0 END) as is_loop
      FROM $_marketTransfersTable t
      LEFT JOIN $_marketBonsTable b ON t.bon_id = b.bon_id
      $timeFilter
      GROUP BY t.from_npub, t.to_npub
    ''', args);

    return result.map((row) {
      return TransferEdge(
        fromNpub: row['from_npub'] as String,
        toNpub: row['to_npub'] as String,
        totalValue: (row['total_value'] as num).toDouble(),
        transferCount: row['transfer_count'] as int,
        isLoop: (row['is_loop'] as int) == 1,
      );
    }).toList();
  }

  /// Récupère les statistiques par émetteur
  Future<List<IssuerStats>> getTopIssuers(DateTime start, DateTime end) async {
    final db = await database;
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();

    final result = await db.rawQuery('''
      SELECT
        b.issuer_npub,
        b.issuer_name,
        SUM(b.value) as total_emitted,
        COUNT(b.bon_id) as bons_count,
        (
          SELECT COUNT(*)
          FROM $_marketTransfersTable t
          WHERE t.bon_id = b.bon_id
          AND t.timestamp BETWEEN ? AND ?
        ) as transfers_count
      FROM $_marketBonsTable b
      WHERE b.created_at BETWEEN ? AND ?
      AND b.issuer_npub IS NOT NULL
      GROUP BY b.issuer_npub, b.issuer_name
      ORDER BY total_emitted DESC
      LIMIT 50
    ''', [start.millisecondsSinceEpoch ~/ 1000, end.millisecondsSinceEpoch ~/ 1000, startStr, endStr]);

    final issuers = result.map((row) {
      final bonsCount = (row['bons_count'] as int?) ?? 1;
      final transfersCount = (row['transfers_count'] as int?) ?? 0;
      return IssuerStats(
        npub: row['issuer_npub'] as String? ?? 'Inconnu',
        name: row['issuer_name'] as String? ?? 'Anonyme',
        totalEmitted: (row['total_emitted'] as num?)?.toDouble() ?? 0.0,
        avgTransfers: bonsCount > 0 ? transfersCount / bonsCount : 0.0,
      );
    }).toList();

    // Fetch activity series for each issuer
    for (int i = 0; i < issuers.length; i++) {
      final issuer = issuers[i];
      final seriesResult = await db.rawQuery('''
        SELECT
          strftime('%Y-%m-%d', created_at) as period,
          SUM(value) as volume
        FROM $_marketBonsTable
        WHERE issuer_npub = ?
        AND created_at BETWEEN ? AND ?
        GROUP BY period
        ORDER BY period ASC
      ''', [issuer.npub, startStr, endStr]);

      final series = seriesResult.map((row) => (row['volume'] as num?)?.toDouble() ?? 0.0).toList();
      issuers[i] = IssuerStats(
        npub: issuer.npub,
        name: issuer.name,
        totalEmitted: issuer.totalEmitted,
        avgTransfers: issuer.avgTransfers,
        activitySeries: series.isEmpty ? [0.0] : series,
      );
    }

    return issuers;
  }

  /// Récupère la liste des utilisateurs en phase de Bootstrap (ayant émis un Bon Zéro)
  Future<List<String>> getBootstrapUsers() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT DISTINCT issuer_npub
      FROM $_marketBonsTable
      WHERE value = 0 OR rarity = 'bootstrap'
      AND issuer_npub IS NOT NULL
    ''');
    return result.map((row) => row['issuer_npub'] as String).toList();
  }

  /// Calcule les métriques du tableau de bord pour une période donnée via SQL
  Future<Map<String, dynamic>> getDashboardMetricsForPeriod(DateTime start, DateTime end) async {
    final db = await database;
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();

    // Total Volume (active or null status)
    final volumeResult = await db.rawQuery('''
      SELECT SUM(value) as total
      FROM $_marketBonsTable
      WHERE (status = 'active' OR status IS NULL)
      AND created_at >= ? AND created_at <= ?
    ''', [startStr, endStr]);
    final totalVolume = (volumeResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Active Merchants
    final merchantsResult = await db.rawQuery('''
      SELECT COUNT(DISTINCT issuer_npub) as count
      FROM $_marketBonsTable
      WHERE issuer_npub IS NOT NULL AND issuer_npub != ''
      AND created_at >= ? AND created_at <= ?
    ''', [startStr, endStr]);
    final activeMerchants = (merchantsResult.first['count'] as int?) ?? 0;

    // Spent Volume
    final spentResult = await db.rawQuery('''
      SELECT SUM(value) as total
      FROM $_marketBonsTable
      WHERE (status = 'spent' OR status = 'burned')
      AND created_at >= ? AND created_at <= ?
    ''', [startStr, endStr]);
    final spentVolume = (spentResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // New Bons Count
    final countResult = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM $_marketBonsTable
      WHERE created_at >= ? AND created_at <= ?
    ''', [startStr, endStr]);
    final newBonsCount = (countResult.first['count'] as int?) ?? 0;

    return {
      'totalVolume': totalVolume,
      'activeMerchants': activeMerchants,
      'spentVolume': spentVolume,
      'newBonsCount': newBonsCount,
    };
  }

  /// Calculer la masse monétaire d'un groupe d'utilisateurs (M_n1)
  Future<double> calculateMonetaryMass(List<String> npubs) async {
    if (npubs.isEmpty) return 0.0;
    
    final db = await database;
    final placeholders = List.filled(npubs.length, '?').join(',');
    
    final result = await db.rawQuery(
      '''
      SELECT SUM(value) as total
      FROM $_marketBonsTable
      WHERE status = 'active'
      AND issuer_npub IN ($placeholders)
      ''',
      npubs,
    );
    
    final total = result.first['total'];
    return total != null ? (total as num).toDouble() : 0.0;
  }

  /// Calculer la masse monétaire des autres utilisateurs (M_n2)
  /// Retourne un tuple (masse, nombre_utilisateurs)
  Future<Map<String, dynamic>> calculateOtherMonetaryMass(List<String> excludedNpubs) async {
    final db = await database;
    
    String query;
    List<dynamic> args;
    
    if (excludedNpubs.isEmpty) {
      query = '''
        SELECT SUM(value) as total, COUNT(DISTINCT issuer_npub) as count
        FROM $_marketBonsTable
        WHERE status = 'active'
      ''';
      args = [];
    } else {
      final placeholders = List.filled(excludedNpubs.length, '?').join(',');
      query = '''
        SELECT SUM(value) as total, COUNT(DISTINCT issuer_npub) as count
        FROM $_marketBonsTable
        WHERE status = 'active'
        AND issuer_npub NOT IN ($placeholders)
      ''';
      args = excludedNpubs;
    }
    
    final result = await db.rawQuery(query, args);
    
    final total = result.first['total'];
    final count = result.first['count'];
    
    return {
      'mass': total != null ? (total as num).toDouble() : 0.0,
      'count': count != null ? (count as int) : 0,
    };
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
    
    _insertionsController.add({
      'type': 'n2_contact',
      'data': {'npub': npub, 'via_n1_npub': viaN1Npub},
    });
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

  /// Récupérer tous les contacts N2
  Future<List<Map<String, String>>> getN2Contacts() async {
    final db = await database;
    final results = await db.query(_n2CacheTable);
    return results.map((row) => {
      'npub': row['npub'] as String,
      'via_n1_npub': row['via_n1_npub'] as String,
    }).toList();
  }

  /// Vider le cache N2
  Future<void> clearN2Cache() async {
    final db = await database;
    await db.delete(_n2CacheTable);
  }

  // ============================================================
  // MÉTHODES FOLLOWERS CACHE
  // ============================================================

  /// Sauvegarder un follower
  Future<void> saveFollower(String npub) async {
    final db = await database;
    await db.insert(
      _followersCacheTable,
      {
        'npub': npub,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Sauvegarder un lot de followers
  Future<void> saveFollowersBatch(List<String> npubs) async {
    if (npubs.isEmpty) return;
    
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.transaction((txn) async {
      for (final npub in npubs) {
        await txn.insert(
          _followersCacheTable,
          {
            'npub': npub,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Récupérer tous les followers
  Future<List<String>> getFollowers() async {
    final db = await database;
    final results = await db.query(_followersCacheTable);
    return results.map((row) => row['npub'] as String).toList();
  }

  /// Vider le cache des followers
  Future<void> clearFollowersCache() async {
    final db = await database;
    await db.delete(_followersCacheTable);
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
    await db.delete(_marketTransfersTable);
    await db.delete(_syncMetadataTable);
    await db.delete(_n2CacheTable);
    await db.delete(_localWalletBonsTable);
    await db.delete(_followersCacheTable);
  }

  /// Exécute la maintenance automatique de la base de données
  /// Supprime les données anciennes et défragmente la base
  Future<void> runMaintenance({int daysOld = 30}) async {
    try {
      final db = await database;
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      
      // Supprimer les P3 expirés
      await db.delete(
        _p3CacheTable,
        where: 'updated_at < ?',
        whereArgs: [cutoffDate.millisecondsSinceEpoch],
      );
      
      // Supprimer les bons du marché expirés
      await db.delete(
        _marketBonsTable,
        where: 'updated_at < ?',
        whereArgs: [cutoffDate.millisecondsSinceEpoch],
      );
      
      // Supprimer les transferts expirés
      await db.delete(
        _marketTransfersTable,
        where: 'timestamp < ?',
        whereArgs: [cutoffDate.millisecondsSinceEpoch ~/ 1000],
      );
      
      await db.execute('VACUUM');
    } catch (e) {
      // Ignorer les erreurs de maintenance
    }
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

// ============================================================
// MODÈLES DE DONNÉES POUR L'AGRÉGATION
// ============================================================

class AggregatedMetrics {
  final double totalVolume;
  final int count;
  final int uniqueIssuers;
  final double transfersVolume;
  final int transfersCount;
  final List<TimeSeriesPoint> series;

  AggregatedMetrics({
    required this.totalVolume,
    required this.count,
    required this.uniqueIssuers,
    required this.transfersVolume,
    required this.transfersCount,
    this.series = const [],
  });
}

class TimeSeriesPoint {
  final DateTime date;
  final double value;
  TimeSeriesPoint(this.date, this.value);
}

class IssuerStats {
  final String npub;
  final String name;
  final double totalEmitted;
  final double avgTransfers;
  final List<double> activitySeries;

  IssuerStats({
    required this.npub,
    required this.name,
    required this.totalEmitted,
    required this.avgTransfers,
    this.activitySeries = const [],
  });
}

class TransferEdge {
  final String fromNpub;
  final String toNpub;
  final double totalValue;
  final int transferCount;
  final bool isLoop;

  TransferEdge({
    required this.fromNpub,
    required this.toNpub,
    required this.totalValue,
    required this.transferCount,
    required this.isLoop,
  });
}
