import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Service de traçabilité des échanges pour conformité fiscale et RGPD
/// Journal local SQLite des transferts avec anonymisation optionnelle
///
/// ✅ OPTIMISÉ: Contient aussi le cache P3 pour éviter les OOM sur iOS/Android
/// FlutterSecureStorage (Keychain/Keystore) n'est pas fait pour stocker des MB de données
class AuditTrailService {
  static Database? _database;
  static const String _tableName = 'transfer_log';
  static const String _p3CacheTable = 'p3_cache';
  static const String _marketBonsTable = 'market_bons';

  /// Initialiser la base de données
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'troczen_audit.db');

    return await openDatabase(
      path,
      version: 2, // ✅ Increment pour migration P3 cache
      onCreate: (db, version) async {
        await _createAllTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Migration vers version 2: ajout tables P3 cache
          await _createP3Tables(db);
        }
      },
    );
  }

  /// Créer toutes les tables (nouvelle installation)
  Future<void> _createAllTables(Database db) async {
    await _createTransferLogTable(db);
    await _createP3Tables(db);
  }

  /// Créer la table de log des transferts
  Future<void> _createTransferLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        sender_name TEXT,
        sender_npub TEXT,
        receiver_name TEXT,
        receiver_npub TEXT,
        amount REAL NOT NULL,
        bon_id TEXT NOT NULL,
        method TEXT NOT NULL,
        status TEXT NOT NULL,
        market_name TEXT,
        rarity TEXT,
        transfer_count INTEGER,
        challenge TEXT,
        signature TEXT,
        device_id TEXT,
        app_version TEXT,
        anonymized INTEGER DEFAULT 0
      )
    ''');

    // Index pour requêtes fréquentes
    await db.execute(
      'CREATE INDEX idx_timestamp ON $_tableName(timestamp)',
    );
    await db.execute(
      'CREATE INDEX idx_bon_id ON $_tableName(bon_id)',
    );
    await db.execute(
      'CREATE INDEX idx_sender ON $_tableName(sender_npub)',
    );
  }

  /// Créer les tables P3 cache (migration v2)
  Future<void> _createP3Tables(Database db) async {
    // Table pour le cache P3 individuel (bonId -> p3Hex)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_p3CacheTable (
        bon_id TEXT PRIMARY KEY,
        p3_hex TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_p3_updated ON $_p3CacheTable(updated_at)',
    );

    // Table pour les données du marché (kind 30303)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_marketBonsTable (
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
      'CREATE INDEX IF NOT EXISTS idx_market_issuer ON $_marketBonsTable(issuer_npub)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_market_status ON $_marketBonsTable(status)',
    );

    // Table pour les métadonnées de synchronisation
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// Enregistrer un transfert
  Future<void> logTransfer({
    required String id,
    required DateTime timestamp,
    String? senderName,
    required String senderNpub,
    String? receiverName,
    required String receiverNpub,
    required double amount,
    required String bonId,
    required String method, // 'NFC' ou 'QR'
    required String status, // 'completed', 'failed', 'timeout'
    String? marketName,
    String? rarity,
    int? transferCount,
    String? challenge,
    String? signature,
    String? deviceId,
    String? appVersion,
  }) async {
    final db = await database;

    final transfer = {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'sender_name': senderName,
      'sender_npub': senderNpub,
      'receiver_name': receiverName,
      'receiver_npub': receiverNpub,
      'amount': amount,
      'bon_id': bonId,
      'method': method,
      'status': status,
      'market_name': marketName,
      'rarity': rarity,
      'transfer_count': transferCount,
      'challenge': challenge,
      'signature': signature,
      'device_id': deviceId,
      'app_version': appVersion,
      'anonymized': 0,
    };

    await db.insert(
      _tableName,
      transfer,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Récupérer tous les transferts
  Future<List<Map<String, dynamic>>> getAllTransfers() async {
    final db = await database;
    return await db.query(
      _tableName,
      orderBy: 'timestamp DESC',
    );
  }

  /// Récupérer transferts par période
  Future<List<Map<String, dynamic>>> getTransfersByPeriod({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await database;
    return await db.query(
      _tableName,
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
      orderBy: 'timestamp DESC',
    );
  }

  /// Récupérer transferts d'un bon spécifique
  Future<List<Map<String, dynamic>>> getTransfersByBonId(String bonId) async {
    final db = await database;
    return await db.query(
      _tableName,
      where: 'bon_id = ?',
      whereArgs: [bonId],
      orderBy: 'timestamp ASC',
    );
  }

  /// Statistiques globales
  Future<Map<String, dynamic>> getStatistics() async {
    final db = await database;

    // Total transfers
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName',
    );
    final total = totalResult.first['count'] as int;

    // Total volume
    final volumeResult = await db.rawQuery(
      'SELECT SUM(amount) as volume FROM $_tableName WHERE status = ?',
      ['completed'],
    );
    final volume = volumeResult.first['volume'] ?? 0.0;

    // Par méthode
    final methodResult = await db.rawQuery(
      'SELECT method, COUNT(*) as count FROM $_tableName GROUP BY method',
    );

    // Par statut
    final statusResult = await db.rawQuery(
      'SELECT status, COUNT(*) as count FROM $_tableName GROUP BY status',
    );

    // Dernière activité
    final lastResult = await db.query(
      _tableName,
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    return {
      'total_transfers': total,
      'total_volume': volume,
      'by_method': Map.fromEntries(
        methodResult.map((r) => MapEntry(r['method'] as String, r['count'])),
      ),
      'by_status': Map.fromEntries(
        statusResult.map((r) => MapEntry(r['status'] as String, r['count'])),
      ),
      'last_activity': lastResult.isNotEmpty
          ? DateTime.fromMillisecondsSinceEpoch(
              lastResult.first['timestamp'] as int,
            )
          : null,
    };
  }

  /// Exporter en CSV pour audit fiscal
  Future<File> exportToCsv({
    DateTime? start,
    DateTime? end,
  }) async {
    List<Map<String, dynamic>> transfers;

    if (start != null && end != null) {
      transfers = await getTransfersByPeriod(start: start, end: end);
    } else {
      transfers = await getAllTransfers();
    }

    final buffer = StringBuffer();

    // En-têtes CSV
    buffer.writeln(
      'ID,Date,Heure,Émetteur,Receveur,Montant (ẐEN),Bon ID,Méthode,Statut,Marché,Rareté',
    );

    // Données
    for (final transfer in transfers) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        transfer['timestamp'] as int,
      );

      buffer.writeln([
        transfer['id'],
        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}',
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}',
        transfer['sender_name'] ?? 'Anonyme',
        transfer['receiver_name'] ?? 'Anonyme',
        transfer['amount'],
        transfer['bon_id'],
        transfer['method'],
        transfer['status'],
        transfer['market_name'] ?? '',
        transfer['rarity'] ?? '',
      ].map((e) => '"${e.toString().replaceAll('"', '""')}"').join(','));
    }

    // Sauvegarder fichier
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/troczen_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());

    return file;
  }

  /// Exporter en JSON
  Future<File> exportToJson({
    DateTime? start,
    DateTime? end,
  }) async {
    List<Map<String, dynamic>> transfers;

    if (start != null && end != null) {
      transfers = await getTransfersByPeriod(start: start, end: end);
    } else {
      transfers = await getAllTransfers();
    }

    final data = {
      'exported_at': DateTime.now().toIso8601String(),
      'period': {
        'start': start?.toIso8601String(),
        'end': end?.toIso8601String(),
      },
      'count': transfers.length,
      'transfers': transfers.map((t) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(t['timestamp'] as int);
        return {
          ...t,
          'timestamp_iso': timestamp.toIso8601String(),
        };
      }).toList(),
    };

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/troczen_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonEncode(data));

    return file;
  }

  /// Anonymiser les données (RGPD)
  Future<void> anonymizeAll() async {
    final db = await database;

    await db.update(
      _tableName,
      {
        'sender_name': 'Anonyme',
        'sender_npub': 'anonymized',
        'receiver_name': 'Anonyme',
        'receiver_npub': 'anonymized',
        'challenge': null,
        'signature': null,
        'device_id': null,
        'anonymized': 1,
      },
    );
  }

  /// Anonymiser données anciennes (> 90 jours)
  Future<void> anonymizeOldData({int daysOld = 90}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));

    await db.update(
      _tableName,
      {
        'sender_name': 'Anonyme',
        'sender_npub': 'anonymized',
        'receiver_name': 'Anonyme',
        'receiver_npub': 'anonymized',
        'challenge': null,
        'signature': null,
        'device_id': null,
        'anonymized': 1,
      },
      where: 'timestamp < ? AND anonymized = 0',
      whereArgs: [cutoffDate.millisecondsSinceEpoch],
    );
  }

  /// Supprimer toutes les données (RGPD - droit à l'oubli)
  Future<void> deleteAllData() async {
    final db = await database;
    await db.delete(_tableName);
  }

  /// Supprimer données anciennes (> 1 an)
  Future<void> deleteOldData({int daysOld = 365}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));

    await db.delete(
      _tableName,
      where: 'timestamp < ?',
      whereArgs: [cutoffDate.millisecondsSinceEpoch],
    );
  }

  /// Obtenir taille de la base de données
  Future<int> getDatabaseSize() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(join(directory.path, 'troczen_audit.db'));

    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  /// Vider le cache
  Future<void> vacuum() async {
    final db = await database;
    await db.execute('VACUUM');
  }

  /// Générer rapport mensuel
  Future<Map<String, dynamic>> getMonthlyReport(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);

    final transfers = await getTransfersByPeriod(start: start, end: end);

    final completed = transfers.where((t) => t['status'] == 'completed').length;
    final failed = transfers.where((t) => t['status'] == 'failed').length;

    final totalVolume = transfers
        .where((t) => t['status'] == 'completed')
        .fold<double>(0, (sum, t) => sum + (t['amount'] as double));

    final nfcCount = transfers.where((t) => t['method'] == 'NFC').length;
    final qrCount = transfers.where((t) => t['method'] == 'QR').length;

    return {
      'period': {
        'year': year,
        'month': month,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      },
      'total_transfers': transfers.length,
      'completed': completed,
      'failed': failed,
      'success_rate': transfers.isNotEmpty ? (completed / transfers.length) : 0.0,
      'total_volume': totalVolume,
      'average_amount': completed > 0 ? (totalVolume / completed) : 0.0,
      'by_method': {
        'NFC': nfcCount,
        'QR': qrCount,
      },
      'nfc_adoption_rate': transfers.isNotEmpty ? (nfcCount / transfers.length) : 0.0,
    };
  }

  /// Fermer la base de données
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // ============================================================
  // ✅ MÉTHODES P3 CACHE - Stockage optimisé dans SQLite
  // FlutterSecureStorage n'est pas fait pour des MB de données
  // ============================================================

  /// Sauvegarder une P3 dans le cache SQLite
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
  /// ✅ OPTIMISÉ: Évite les OOM et le Jank UI
  Future<void> saveP3BatchToCache(Map<String, String> p3Batch) async {
    if (p3Batch.isEmpty) return;
    
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Utiliser une transaction pour performance optimale
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
  // ✅ MÉTHODES MARKET BONS - Données du marché (kind 30303)
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
  /// ✅ OPTIMISÉ: Transaction unique pour performance
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
      // Fallback si pas de raw_data
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

  /// Sauvegarder le timestamp de dernière sync
  Future<void> saveLastP3Sync() async {
    final db = await database;
    await db.execute(
      'INSERT OR REPLACE INTO sync_metadata (key, value) VALUES (?, ?)',
      ['last_p3_sync', DateTime.now().millisecondsSinceEpoch.toString()],
    );
  }

  /// Récupérer le timestamp de dernière sync
  Future<DateTime?> getLastP3Sync() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT value FROM sync_metadata WHERE key = ?',
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
}
