import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:hex/hex.dart';
import '../config/app_config.dart';
import '../models/market.dart';
import '../models/nostr_profile.dart';
import '../utils/nostr_utils.dart';
import 'crypto_service.dart';
import 'storage_service.dart';
import 'logger_service.dart';
import 'du_calculation_service.dart';
import 'nostr_connection_service.dart';
import 'nostr_market_service.dart';
import 'nostr_wotx_service.dart';
import 'cache_database_service.dart';

/// ✅ NostrService REFACTORED - Pattern Facade
/// 
/// Cette version délègue toutes les opérations aux services spécialisés:
/// - NostrConnectionService: Connexion WebSocket
/// - NostrMarketService: P3, Circuits, Marchés  
/// - NostrWoTxService: Compétences, Attestations
///
/// ✅ 100% compatible avec l'ancienne API
/// ✅ Migration transparente sans changement de code
/// ✅ Principe de responsabilité unique (SRP) respecté
class NostrService {
  final CryptoService _cryptoService;
  final StorageService _storageService;
  
  // Services spécialisés
  late final NostrConnectionService connection;
  late final NostrMarketService market;
  late final NostrWoTxService wotx;
  
  
  // Callbacks (redirigés vers les sous-services)
  Function(String bonId, String p3Hex)? onP3Received;
  Function(String error)? onError;
  Function(bool connected)? onConnectionChange;
  Function(List<String> tags)? onTagsReceived;

  // Abonnements aux streams
  StreamSubscription<bool>? _connSub;
  StreamSubscription<String>? _errSub;
  StreamSubscription<dynamic>? _msgSub;
  
  NostrService({
    required CryptoService cryptoService,
    required StorageService storageService,
  })  : _cryptoService = cryptoService,
        _storageService = storageService {
    
    // Initialiser les sous-services
    connection = NostrConnectionService();
    
    market = NostrMarketService(
      connection: connection,
      cryptoService: _cryptoService,
      storageService: _storageService,
    );
    
    wotx = NostrWoTxService(
      connection: connection,
      cryptoService: _cryptoService,
    );
    
    // Rediriger les callbacks via les streams
    _connSub = connection.onConnectionChange.listen((connected) {
      onConnectionChange?.call(connected);
    });
    
    _errSub = connection.onError.listen((error) {
      onError?.call(error);
    });
    
    _msgSub = connection.onMessage.listen(_handleMessage);
    
    market.onP3Received = (bonId, p3Hex) {
      onP3Received?.call(bonId, p3Hex);
    };
    
    market.onError = (error) {
      onError?.call(error);
    };
    
    wotx.onError = (error) {
      onError?.call(error);
    };
    
    wotx.onTagsReceived = (tags) {
      onTagsReceived?.call(tags);
    };
  }
  
  // ============================================================
  // CONNEXION - Déléguer à NostrConnectionService
  // ============================================================
  
  Future<bool> connect(String relayUrl) => connection.connect(relayUrl);
  
  Future<void> disconnect() => connection.disconnect();
  
  bool get isConnected => connection.isConnected;
  
  String? get currentRelay => connection.currentRelay;
  
  Future<bool> forceReconnect() => connection.forceReconnect();
  
  bool get autoSyncEnabled => market.autoSyncEnabled;
  Market? get lastSyncedMarket => market.lastSyncedMarket;
  bool get isAppInBackground => connection.isAppInBackground;
  int get reconnectAttempts => connection.reconnectAttempts;
  
  void onAppPaused() {
    connection.onAppPaused();
    market.onAppPaused();
  }
  
  void onAppResumed() {
    connection.onAppResumed();
    market.onAppResumed();
  }
  
  void dispose() {
    _connSub?.cancel();
    _errSub?.cancel();
    _msgSub?.cancel();
    market.dispose();
  }
  
  // ============================================================
  // MARCHÉS - Déléguer à NostrMarketService
  // ============================================================
  
  Future<int> syncMarketP3s(Market targetMarket) async {
    // Synchroniser les followers avant de lancer la sync du marché
    try {
      final user = await _storageService.getUser();
      if (user != null && connection.isConnected) {
        final followers = await fetchFollowers(user.npub);
        await _storageService.saveFollowersBatch(followers);
        Logger.info('NostrService', '${followers.length} followers synchronisés');
      }
    } catch (e) {
      Logger.error('NostrService', 'Erreur sync followers', e);
    }

    final duService = DuCalculationService(
      storageService: _storageService,
      nostrService: this,
      cryptoService: _cryptoService,
    );
    return await market.syncMarketP3s(targetMarket, duService);
  }
  
  Future<int> syncMarketsP3s(List<Market> markets) async {
    // Utiliser le relay du premier marché
    final relayUrl = markets.first.relayUrl ?? AppConfig.defaultRelayUrl;
    
    if (!connection.isConnected) {
      final connected = await connection.connect(relayUrl);
      if (!connected) return 0;
    }

    int syncedCount = 0;
    final completer = Completer<int>();
    
    final Map<String, String> p3Batch = {};
    const int batchSize = 50;
    
    Future<void> flushBatch() async {
      if (p3Batch.isNotEmpty) {
        final batchToWrite = Map<String, String>.from(p3Batch);
        p3Batch.clear();
        await _storageService.saveP3BatchToCache(batchToWrite);
      }
    }

    final originalCallback = market.onP3Received;
    market.onP3Received = (bonId, p3Hex) async {
      p3Batch[bonId] = p3Hex;
      syncedCount++;
      originalCallback?.call(bonId, p3Hex);
      
      if (p3Batch.length >= batchSize) {
        await flushBatch();
      }
    };

    final marketNames = markets.map((m) => m.name).toList();
    final lastSyncDate = await _storageService.getLastP3Sync();
    final since = lastSyncDate != null ? lastSyncDate.millisecondsSinceEpoch ~/ 1000 : null;
    
    final subscriptionId = await market.subscribeToMarkets(marketNames, since: since);
    
    if (subscriptionId == null) {
      return 0;
    }

    Timer? fallbackTimer;
    
    void finishSync() async {
      fallbackTimer?.cancel();
      connection.removeHandler(subscriptionId);
      connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
      
      await flushBatch();
      market.onP3Received = originalCallback;
      
      try {
        // Synchroniser les followers avant de vérifier le DU
        final user = await _storageService.getUser();
        if (user != null) {
          final followers = await fetchFollowers(user.npub);
          await _storageService.saveFollowersBatch(followers);
          Logger.info('NostrService', '${followers.length} followers synchronisés');
        }

        final duService = DuCalculationService(
          storageService: _storageService,
          nostrService: this,
          cryptoService: _cryptoService,
        );
        await duService.checkAndGenerateDU();
      } catch (e) {
        Logger.error('NostrService', 'Erreur vérification DU', e);
      }
      
      if (!completer.isCompleted) {
        completer.complete(syncedCount);
      }
    }

    connection.registerHandler(subscriptionId, (message) {
      if (message[0] == 'EOSE') {
        Logger.info('NostrService', 'EOSE reçu pour la sync multi-marchés');
        finishSync();
      }
    });

    fallbackTimer = Timer(const Duration(seconds: 15), () {
      Logger.warn('NostrService', 'Timeout de secours atteint pour la sync multi-marchés');
      finishSync();
    });

    final result = await completer.future;
    fallbackTimer.cancel();
    return result;
  }
  
  Future<int> triggerImmediateSync(Market targetMarket) async {
    if (!connection.isConnected && targetMarket.relayUrl != null) {
      await connection.connect(targetMarket.relayUrl!);
    }
    
    if (!connection.isConnected) {
      onError?.call('Pas de connexion pour synchronisation');
      return 0;
    }
    
    return await syncMarketP3s(targetMarket);
  }

  /// Synchronisation "Light Node" pour les Alchimistes (Gossip)
  Future<int> syncGossipData() async {
    if (!connection.isConnected) return 0;

    final cacheDb = CacheDatabaseService();
    final lastSyncDate = await _storageService.getLastP3Sync();
    final since = lastSyncDate != null ? lastSyncDate.millisecondsSinceEpoch ~/ 1000 : null;

    final completer = Completer<int>();
    int syncedCount = 0;
    final subscriptionId = 'gossip_${DateTime.now().millisecondsSinceEpoch}';
    final eventsBatch = <Map<String, dynamic>>[];
    const int batchSize = 100;

    Future<void> flushBatch() async {
      if (eventsBatch.isNotEmpty) {
        final batchToWrite = List<Map<String, dynamic>>.from(eventsBatch);
        eventsBatch.clear();
        await cacheDb.saveGossipEventsBatch(batchToWrite);
      }
    }

    connection.registerHandler(subscriptionId, (message) async {
      try {
        if (message[0] == 'EVENT' && message.length >= 3) {
          final event = message[2] as Map<String, dynamic>;
          eventsBatch.add(event);
          syncedCount++;
          
          if (eventsBatch.length >= batchSize) {
            await flushBatch();
          }
        } else if (message[0] == 'EOSE') {
          connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          connection.removeHandler(subscriptionId);
          await flushBatch();
          if (!completer.isCompleted) {
            completer.complete(syncedCount);
          }
        }
      } catch (e) {
        Logger.error('NostrService', 'Erreur parsing gossip event', e);
      }
    });

    final filter = <String, dynamic>{
      'kinds': [0, 1, 3, 5, 7, 30303, 30304, 30305, 30502, 30503],
    };
    if (since != null) {
      filter['since'] = since;
    }

    final request = jsonEncode(['REQ', subscriptionId, filter]);
    connection.sendMessage(request);

    Timer? fallbackTimer;
    fallbackTimer = Timer(const Duration(seconds: 30), () async {
      connection.removeHandler(subscriptionId);
      await flushBatch();
      if (!completer.isCompleted) {
        connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
        completer.complete(syncedCount);
      }
    });

    final result = await completer.future;
    fallbackTimer.cancel();
    return result;
  }
  
  // ============================================================
  // DU (Dividende Universel) - Kind 30305
  // ============================================================

  /// Publie un incrément de DU (kind 30305)
  Future<bool> publishDuIncrement(String npub, String nsec, double amount, DateTime date) async {
    try {
      final dTag = 'du-${date.toIso8601String().substring(0, 10)}';

      final event = {
        'kind': NostrConstants.kindDuIncrement,
        'pubkey': npub,
        'created_at': date.millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['d', dTag],
          ['amount', amount.toStringAsFixed(2)],
        ],
        'content': '',
      };

      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      
      Uint8List nsecBytes;
      try {
        nsecBytes = Uint8List.fromList(HEX.decode(nsec));
      } catch (e) {
        throw Exception('Clé privée invalide (non hexadécimale)');
      }
      
      final signature = _cryptoService.signMessageBytes(eventId, nsecBytes);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      return await connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur publication DU: $e');
      return false;
    }
  }

  /// Calcule le DU disponible à partir des événements Nostr
  Future<double> computeAvailableDu(String npub) async {
    final cacheDb = CacheDatabaseService();
    
    if (!connection.isConnected) {
      // En offline, retourner la dernière valeur en cache
      return await cacheDb.getTotalDuIncrements(npub);
    }

    try {
      // 1. Récupérer tous les incréments (kind 30305) de l'utilisateur
      final increments = await _fetchEvents(kind: NostrConstants.kindDuIncrement, authors: [npub]);
      double totalIncrements = 0;
      
      for (final e in increments) {
        final tags = e['tags'] as List?;
        if (tags != null) {
          final amountTag = tags.firstWhere(
            (t) => t is List && t.isNotEmpty && t[0] == 'amount',
            orElse: () => null,
          );
          if (amountTag != null && amountTag.length > 1) {
            totalIncrements += double.tryParse(amountTag[1].toString()) ?? 0.0;
          }
        }
      }

      // 2. Récupérer tous les bons émis (kind 30303) de l'utilisateur
      final bons = await _fetchEvents(kind: NostrConstants.kindP3Publication, authors: [npub]);
      double totalEmitted = 0;
      
      for (final bon in bons) {
        final tags = bon['tags'] as List?;
        if (tags != null) {
          final valueTag = tags.firstWhere(
            (t) => t is List && t.isNotEmpty && t[0] == 'value',
            orElse: () => null,
          );
          if (valueTag != null && valueTag.length > 1) {
            totalEmitted += double.tryParse(valueTag[1].toString()) ?? 0.0;
          }
        }
      }

      return totalIncrements - totalEmitted;
    } catch (e) {
      Logger.error('NostrService', 'Erreur calcul DU', e);
      // Fallback sur le cache en cas d'erreur
      return await cacheDb.getTotalDuIncrements(npub);
    }
  }

  /// Récupère la moyenne des incréments DU récents sur le réseau
  Future<double?> fetchAverageRecentDu() async {
    if (!connection.isConnected) return null;
    try {
      final events = await _fetchEvents(kind: NostrConstants.kindDuIncrement, limit: 50);
      if (events.isEmpty) return null;
      
      double total = 0;
      int count = 0;
      for (final e in events) {
        final tags = e['tags'] as List?;
        if (tags != null) {
          final amountTag = tags.firstWhere(
            (t) => t is List && t.isNotEmpty && t[0] == 'amount',
            orElse: () => null,
          );
          if (amountTag != null && amountTag.length > 1) {
            final amount = double.tryParse(amountTag[1].toString());
            if (amount != null && amount > 0) {
              total += amount;
              count++;
            }
          }
        }
      }
      return count > 0 ? total / count : null;
    } catch (e) {
      Logger.error('NostrService', 'Erreur calcul moyenne DU récent', e);
      return null;
    }
  }

  /// Méthode générique pour récupérer des événements
  Future<List<Map<String, dynamic>>> _fetchEvents({
    required int kind,
    List<String>? authors,
    int limit = 1000,
  }) async {
    if (!connection.isConnected) return [];

    final completer = Completer<List<Map<String, dynamic>>>();
    final events = <Map<String, dynamic>>[];
    final subscriptionId = 'fetch_${kind}_${DateTime.now().millisecondsSinceEpoch}';

    connection.registerHandler(subscriptionId, (message) {
      try {
        if (message[0] == 'EVENT' && message.length >= 3) {
          final event = message[2] as Map<String, dynamic>;
          events.add(event);
        } else if (message[0] == 'EOSE') {
          connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          connection.removeHandler(subscriptionId);
          if (!completer.isCompleted) {
            completer.complete(events);
          }
        }
      } catch (e) {
        Logger.error('NostrService', 'Erreur parsing event kind $kind', e);
      }
    });

    final filter = <String, dynamic>{
      'kinds': [kind],
      'limit': limit,
    };
    if (authors != null && authors.isNotEmpty) {
      filter['authors'] = authors;
    }

    final request = jsonEncode(['REQ', subscriptionId, filter]);
    connection.sendMessage(request);

    Timer? fallbackTimer;
    fallbackTimer = Timer(const Duration(seconds: 10), () {
      connection.removeHandler(subscriptionId);
      if (!completer.isCompleted) {
        connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
        completer.complete(events);
      }
    });

    final result = await completer.future;
    fallbackTimer.cancel();
    return result;
  }

  
  /// Récupère l'historique des transferts d'un bon (kind 1)
  Future<List<Map<String, dynamic>>> fetchBonTransfers(String bonId) async {
    return fetchBonsTransfers([bonId]);
  }

  /// Récupère l'historique des transferts pour plusieurs bons (kind 1)
  Future<List<Map<String, dynamic>>> fetchBonsTransfers(List<String> bonIds) async {
    if (!connection.isConnected || bonIds.isEmpty) {
      if (bonIds.isNotEmpty) Logger.error('NostrService', 'Non connecté');
      return [];
    }

    try {
      final completer = Completer<List<Map<String, dynamic>>>();
      final transfers = <Map<String, dynamic>>[];
      
      final subscriptionId = 'transfers_${DateTime.now().millisecondsSinceEpoch}';
      
      connection.registerHandler(subscriptionId, (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
            final event = message[2] as Map<String, dynamic>;
            
            // Vérifier cryptographiquement l'événement
            final calculatedId = NostrUtils.calculateEventId(event);
            if (event['id'] == calculatedId && _cryptoService.verifySignature(calculatedId, event['sig'], event['pubkey'])) {
              transfers.add(event);
            } else {
              Logger.error('NostrService', 'Transfert invalide ignoré');
            }
          } else if (message[0] == 'EOSE') {
            connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            connection.removeHandler(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(transfers);
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing transfers', e);
        }
      });

      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'kinds': [NostrConstants.kindText],
          '#bon': bonIds,
        }
      ]);
      
      connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(transfers);
        }
      });
      
      final result = await completer.future;
      fallbackTimer.cancel();
      return result;
    } catch (e) {
      Logger.error('NostrService', 'Erreur récupération transferts', e);
      return [];
    }
  }
  
  /// Publie un event de transfert (kind 1)
  Future<bool> publishTransfer({
    required String bonId,
    required String bonP2,
    required String bonP3,
    required String senderNpub,
    required String receiverNpub,
    required double value,
    required String marketName,
  }) async {
    final registered = await market.ensurePubkeyRegistered(bonId);
    if (!registered) {
      Logger.error('NostrService', 'Publication transfert annulée');
      return false;
    }

    try {
      Uint8List p2Bytes, p3Bytes;
      try {
        p2Bytes = Uint8List.fromList(HEX.decode(bonP2));
        p3Bytes = Uint8List.fromList(HEX.decode(bonP3));
      } catch (e) {
        throw Exception('Parts P2 ou P3 invalides (non hexadécimales)');
      }
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);
      
      // (Bitcoin Cypher Punk Guerilla)
      final humanReadableContent = "💸 Un transfert de ${value.toString()} ẐEN "
          "vient d'avoir lieu sur '$marketName' !\n\n"
          "TrocZen 🌻 : La monnaie locale, P2P et 100% offline.\n"
          "Rejoignez le mouvement : https://github.com/papiche/troczen";

      final event = {
        'kind': 1,
        'pubkey': bonId,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['p', receiverNpub],
          ['from_npub', senderNpub],
          ['t', 'troczen-transfer'],
          ['t', NostrUtils.normalizeMarketTag(marketName)],
          ['market', marketName],
          ['bon', bonId],
          ['value', value.toString()],
        ],
        'content': humanReadableContent,
      };

      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      final signature = _cryptoService.signMessageBytes(eventId, nsecBonBytes);
      event['sig'] = signature;
      
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

      final message = jsonEncode(['EVENT', event]);
      return await connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur publication transfert: $e');
      return false;
    }
  }
  
  /// Publie un event BURN (kind 5) avec Uint8List
  Future<bool> publishBurnBytes({
    required String bonId,
    required Uint8List nsecBonBytes,
    required String reason,
    required String marketName,
  }) async {
    final registered = await market.ensurePubkeyRegistered(bonId);
    if (!registered) {
      Logger.error('NostrService', 'Publication burn annulée');
      return false;
    }

    try {
      final event = {
        'kind': 5,
        'pubkey': bonId,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['a', '30303:$bonId:zen-$bonId'],
          ['t', NostrUtils.normalizeMarketTag(marketName)],
          ['market', marketName],
          ['reason', reason],
        ],
        'content': 'BURN | $reason',
      };

      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      final signature = _cryptoService.signMessageBytes(eventId, nsecBonBytes);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      return await connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur publication burn: $e');
      return false;
    }
  }
  
  /// Récupère plusieurs profils utilisateurs (kind 0) en une seule requête
  Future<List<NostrProfile>> fetchUserProfilesBatch(List<String> npubs) async {
    if (npubs.isEmpty) return [];
    
    final cacheDb = CacheDatabaseService();
    final profiles = <NostrProfile>[];
    final npubsToFetch = <String>[];
    
    // 1. Vérifier le cache d'abord
    for (final npub in npubs) {
      final cachedData = await cacheDb.getUserProfileCache(npub);
      if (cachedData != null) {
        profiles.add(NostrProfile(
          npub: npub,
          name: (cachedData['name'] as String?) ?? npub.substring(0, 8),
          displayName: cachedData['display_name'] as String?,
          about: cachedData['about'] as String?,
          picture: cachedData['picture'] as String?,
          banner: cachedData['banner'] as String?,
          picture64: cachedData['picture64'] as String?,
          banner64: cachedData['banner64'] as String?,
          website: cachedData['website'] as String?,
        ));
      } else {
        npubsToFetch.add(npub);
      }
    }
    
    if (npubsToFetch.isEmpty || !connection.isConnected) {
      return profiles;
    }
    
    try {
      final completer = Completer<List<NostrProfile>>();
      final fetchedProfiles = <NostrProfile>[];
      final subscriptionId = 'profiles_batch_${DateTime.now().millisecondsSinceEpoch}';
      
      connection.registerHandler(subscriptionId, (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
            final event = message[2] as Map<String, dynamic>;
            final content = event['content'] as String?;
            final pubkey = event['pubkey'] as String?;
            if (content != null && pubkey != null) {
              final contentJson = jsonDecode(content);
              final profile = NostrProfile(
                npub: pubkey,
                name: (contentJson['name'] as String?) ?? pubkey.substring(0, 8),
                displayName: contentJson['display_name'] as String?,
                about: contentJson['about'] as String?,
                picture: contentJson['picture'] as String?,
                banner: contentJson['banner'] as String?,
                picture64: contentJson['picture64'] as String?,
                banner64: contentJson['banner64'] as String?,
                website: contentJson['website'] as String?,
              );
              fetchedProfiles.add(profile);
              
              // Sauvegarder en cache
              cacheDb.saveUserProfileCache(pubkey, contentJson);
            }
          } else if (message[0] == 'EOSE') {
            connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            connection.removeHandler(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(fetchedProfiles);
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing profile batch', e);
        }
      });
      
      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'authors': npubsToFetch,
          'kinds': [0],
        }
      ]);
      
      connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(fetchedProfiles);
        }
      });
      
      final result = await completer.future;
      fallbackTimer.cancel();
      
      profiles.addAll(result);
      return profiles;
    } catch (e) {
      Logger.error('NostrService', 'Erreur récupération profils batch', e);
      return [];
    }
  }

  /// Récupère un profil utilisateur (kind 0)
  Future<NostrProfile?> fetchUserProfile(String npub) async {
    final cacheDb = CacheDatabaseService();
    final cachedData = await cacheDb.getUserProfileCache(npub);
    if (cachedData != null) {
      return NostrProfile(
        npub: npub,
        name: (cachedData['name'] as String?) ?? npub.substring(0, 8),
        displayName: cachedData['display_name'] as String?,
        about: cachedData['about'] as String?,
        picture: cachedData['picture'] as String?,
        banner: cachedData['banner'] as String?,
        picture64: cachedData['picture64'] as String?,
        banner64: cachedData['banner64'] as String?,
        website: cachedData['website'] as String?,
      );
    }

    if (!connection.isConnected) {
      return null;
    }
    
    try {
      final completer = Completer<NostrProfile?>();
      final subscriptionId = 'profile_${DateTime.now().millisecondsSinceEpoch}';
      
      connection.registerHandler(subscriptionId, (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
            final event = message[2] as Map<String, dynamic>;
            final content = event['content'] as String?;
            if (content != null) {
              final contentJson = jsonDecode(content);
              final profile = NostrProfile(
                npub: npub,
                name: (contentJson['name'] as String?) ?? npub.substring(0, 8),
                displayName: contentJson['display_name'] as String?,
                about: contentJson['about'] as String?,
                picture: contentJson['picture'] as String?,
                banner: contentJson['banner'] as String?,
                picture64: contentJson['picture64'] as String?,
                banner64: contentJson['banner64'] as String?,
                website: contentJson['website'] as String?,
              );
              
              // Sauvegarder en cache
              cacheDb.saveUserProfileCache(npub, contentJson);
              
              if (!completer.isCompleted) {
                completer.complete(profile);
              }
            }
          } else if (message[0] == 'EOSE') {
            connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            connection.removeHandler(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing profile', e);
        }
      });
      
      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'authors': [npub],
          'kinds': [0],
          'limit': 1,
        }
      ]);
      
      connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(null);
        }
      });
      
      final result = await completer.future;
      fallbackTimer.cancel();
      return result;
    } catch (e) {
      Logger.error('NostrService', 'Erreur récupération profil', e);
      return null;
    }
  }
  
  /// Publie une liste de contacts (kind 3)
  Future<bool> publishContactList({
    required String npub,
    required String nsec,
    required List<String> contactsNpubs,
  }) async {
    final registered = await market.ensurePubkeyRegistered(npub);
    if (!registered) {
      return false;
    }

    try {
      final tags = contactsNpubs.map((contact) => ['p', contact]).toList();

      final event = {
        'kind': 3,
        'pubkey': npub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': tags,
        'content': '',
      };

      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      Uint8List nsecBytes;
      try {
        nsecBytes = Uint8List.fromList(HEX.decode(nsec));
      } catch (e) {
        throw Exception('Clé privée invalide (non hexadécimale)');
      }
      final signature = _cryptoService.signMessageBytes(eventId, nsecBytes);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      return await connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur publication contacts: $e');
      return false;
    }
  }
  
  /// Récupère les followers (ceux qui m'ont dans leur kind 3)
  Future<List<String>> fetchFollowers(String myNpub) async {
    if (!connection.isConnected) return [];

    try {
      final completer = Completer<List<String>>();
      final followers = <String>{};
      final subscriptionId = 'followers_${DateTime.now().millisecondsSinceEpoch}';
      
      connection.registerHandler(subscriptionId, (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
            final event = message[2] as Map<String, dynamic>;
            followers.add(event['pubkey'].toString());
          } else if (message[0] == 'EOSE') {
            connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            connection.removeHandler(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(followers.toList());
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing followers', e);
        }
      });

      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'kinds': [3],
          '#p': [myNpub],
        }
      ]);
      
      connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(followers.toList());
        }
      });
      
      final result = await completer.future;
      fallbackTimer.cancel();
      return result;
    } catch (e) {
      Logger.error('NostrService', 'Erreur récupération followers', e);
      return [];
    }
  }

  /// Récupère les listes de contacts de plusieurs npubs
  Future<Map<String, List<String>>> fetchMultipleContactLists(List<String> npubs) async {
    if (!connection.isConnected || npubs.isEmpty) return {};

    try {
      final completer = Completer<Map<String, List<String>>>();
      final result = <String, List<String>>{};
      final subscriptionId = 'multi_contacts_${DateTime.now().millisecondsSinceEpoch}';
      
      connection.registerHandler(subscriptionId, (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
            final event = message[2] as Map<String, dynamic>;
            final pubkey = event['pubkey'].toString();
            final tags = event['tags'] as List?;
            
            if (tags != null) {
              final contacts = <String>[];
              for (final tag in tags) {
                if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
                  contacts.add(tag[1].toString());
                }
              }
              result[pubkey] = contacts;
            }
          } else if (message[0] == 'EOSE') {
            connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            connection.removeHandler(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(result);
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing multi contacts', e);
        }
      });

      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'authors': npubs,
          'kinds': [3],
        }
      ]);
      
      connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(result);
        }
      });
      
      final finalResult = await completer.future;
      fallbackTimer.cancel();
      return finalResult;
    } catch (e) {
      Logger.error('NostrService', 'Erreur récupération multi contacts', e);
      return {};
    }
  }

  /// Récupère une liste de contacts (kind 3)
  Future<List<String>> fetchContactList(String npub) async {
    if (!connection.isConnected) {
      return [];
    }

    try {
      final completer = Completer<List<String>>();
      final contacts = <String>[];
      final subscriptionId = 'contacts_${DateTime.now().millisecondsSinceEpoch}';
      
      connection.registerHandler(subscriptionId, (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
            final event = message[2] as Map<String, dynamic>;
            final tags = event['tags'] as List?;
            if (tags != null) {
              for (final tag in tags) {
                if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
                  contacts.add(tag[1].toString());
                }
              }
            }
          } else if (message[0] == 'EOSE') {
            connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            connection.removeHandler(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(contacts);
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing contacts', e);
        }
      });

      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'authors': [npub],
          'kinds': [3],
          'limit': 1,
        }
      ]);
      
      connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(contacts);
        }
      });
      
      final result = await completer.future;
      fallbackTimer.cancel();
      return result;
    } catch (e) {
      Logger.error('NostrService', 'Erreur récupération contacts', e);
      return [];
    }
  }
  
  /// Publie une liste de relais (kind 10002)
  Future<bool> publishRelayList({
    required String npub,
    required String nsec,
    required List<String> relays,
  }) async {
    final registered = await market.ensurePubkeyRegistered(npub);
    if (!registered) {
      return false;
    }

    try {
      final relayList = <String, dynamic>{};
      for (final relay in relays) {
        relayList[relay] = {
          'read': true,
          'write': true,
        };
      }

      final relayTags = relays.map((relay) => ['r', relay]).toList();

      final event = {
        'kind': 10002,
        'pubkey': npub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': relayTags,
        'content': jsonEncode(relayList),
      };

      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      Uint8List nsecBytes;
      try {
        nsecBytes = Uint8List.fromList(HEX.decode(nsec));
      } catch (e) {
        throw Exception('Clé privée invalide (non hexadécimale)');
      }
      final signature = _cryptoService.signMessageBytes(eventId, nsecBytes);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      return await connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur publication relay list: $e');
      return false;
    }
  }
  
  // ============================================================
  // GESTION DES MESSAGES
  // ============================================================
  
  void _handleMessage(dynamic message) {
    if (message is! List || message.isEmpty) return;

    final messageType = message[0];

    // Les handlers temporaires sont déjà gérés par NostrConnectionService
    // Ici on traite les messages globaux
    switch (messageType) {
      case 'EVENT':
        if (message.length > 2 && message[2] is Map) {
          final event = message[2] as Map<String, dynamic>;
          final kind = event['kind'];
          if (kind == 0) {
            _handleMetadataEvent(event);
          } else if (kind == 30303 || kind == 1) {
            market.handleP3Event(event);
          } else if (kind == NostrConstants.kindDuIncrement) {
            _handleDuIncrementEvent(event);
          }
        }
        break;
    }
  }
  
  void _handleDuIncrementEvent(Map<String, dynamic> event) async {
    try {
      final npub = event['pubkey'] as String?;
      final tags = event['tags'] as List?;
      if (npub == null || tags == null) return;

      final dateTag = tags.firstWhere(
        (t) => t is List && t.isNotEmpty && t[0] == 'd',
        orElse: () => null,
      );
      final amountTag = tags.firstWhere(
        (t) => t is List && t.isNotEmpty && t[0] == 'amount',
        orElse: () => null,
      );

      if (dateTag != null && amountTag != null && dateTag.length > 1 && amountTag.length > 1) {
        final dateStr = dateTag[1].toString().replaceFirst('du-', '');
        final amount = double.tryParse(amountTag[1].toString());
        if (amount != null) {
          final cacheDb = CacheDatabaseService();
          await cacheDb.saveDuIncrement(npub, dateStr, amount);
          Logger.log('NostrService', 'Incrément DU mis en cache pour $npub: $amount ẐEN ($dateStr)');
        }
      }
    } catch (e) {
      Logger.error('NostrService', 'Erreur traitement incrément DU', e);
    }
  }

  void _handleMetadataEvent(Map<String, dynamic> event) {
    try {
      final npub = event['pubkey'] as String?;
      final content = event['content'] as String?;
      
      if (npub == null || content == null) return;
      
      // Les images sont maintenant gérées par OfflineFirstImage
      // et cached_network_image
    } catch (e) {
      Logger.error('NostrService', 'Erreur traitement metadata', e);
    }
  }
}

