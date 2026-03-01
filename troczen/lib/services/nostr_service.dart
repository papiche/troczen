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
  late final NostrConnectionService _connection;
  late final NostrMarketService _market;
  late final NostrWoTxService _wotx;
  
  
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
    _connection = NostrConnectionService();
    
    _market = NostrMarketService(
      connection: _connection,
      cryptoService: _cryptoService,
      storageService: _storageService,
    );
    
    _wotx = NostrWoTxService(
      connection: _connection,
      cryptoService: _cryptoService,
    );
    
    // Rediriger les callbacks via les streams
    _connSub = _connection.onConnectionChange.listen((connected) {
      onConnectionChange?.call(connected);
    });
    
    _errSub = _connection.onError.listen((error) {
      onError?.call(error);
    });
    
    _msgSub = _connection.onMessage.listen(_handleMessage);
    
    _market.onP3Received = (bonId, p3Hex) {
      onP3Received?.call(bonId, p3Hex);
    };
    
    _market.onError = (error) {
      onError?.call(error);
    };
    
    _wotx.onError = (error) {
      onError?.call(error);
    };
    
    _wotx.onTagsReceived = (tags) {
      onTagsReceived?.call(tags);
    };
  }
  
  // ============================================================
  // CONNEXION - Déléguer à NostrConnectionService
  // ============================================================
  
  Future<bool> connect(String relayUrl) => _connection.connect(relayUrl);
  
  Future<void> disconnect() => _connection.disconnect();
  
  bool get isConnected => _connection.isConnected;
  
  String? get currentRelay => _connection.currentRelay;
  
  Future<bool> forceReconnect() => _connection.forceReconnect();
  
  bool get autoSyncEnabled => _market.autoSyncEnabled;
  Market? get lastSyncedMarket => _market.lastSyncedMarket;
  bool get isAppInBackground => _connection.isAppInBackground;
  int get reconnectAttempts => _connection.reconnectAttempts;
  
  void onAppPaused() {
    _connection.onAppPaused();
    _market.onAppPaused();
  }
  
  void onAppResumed() {
    _connection.onAppResumed();
    _market.onAppResumed();
  }
  
  void dispose() {
    _connSub?.cancel();
    _errSub?.cancel();
    _msgSub?.cancel();
    _market.dispose();
  }
  
  // ============================================================
  // MARCHÉS - Déléguer à NostrMarketService
  // ============================================================
  
  Future<bool> publishP3({
    required String bonId,
    required String issuerNsecHex,
    required String p3Hex,
    required String seedMarket,
    required String issuerNpub,
    required String marketName,
    required double value,
    String? category,
    String? rarity,
    String? wish,
    int? duIndex,
  }) => _market.publishP3(
    bonId: bonId,
    issuerNsecHex: issuerNsecHex,
    p3Hex: p3Hex,
    seedMarket: seedMarket,
    issuerNpub: issuerNpub,
    marketName: marketName,
    value: value,
    category: category,
    rarity: rarity,
    wish: wish,
    duIndex: duIndex,
  );
  
  Future<bool> publishBonProfileUpdate({
    required String bonId,
    required String issuerNsecHex,
    required String issuerNpub,
    required String marketName,
    required double value,
    required String p3Cipher,
    required String p3Nonce,
    required int expiryTimestamp,
    required Map<String, dynamic> profileData,
    String? category,
    String? rarity,
    String? wish,
  }) => _market.publishBonProfileUpdate(
    bonId: bonId,
    issuerNsecHex: issuerNsecHex,
    issuerNpub: issuerNpub,
    marketName: marketName,
    value: value,
    p3Cipher: p3Cipher,
    p3Nonce: p3Nonce,
    expiryTimestamp: expiryTimestamp,
    profileData: profileData,
    category: category,
    rarity: rarity,
    wish: wish,
  );

  Future<bool> publishBonCircuit({
    required String bonId,
    required double valueZen,
    required int hopCount,
    required int ageDays,
    required String marketName,
    required String issuerNpub,
    required Uint8List nsecBonBytes,
    required String seedMarket,
    String? skillAnnotation,
    String? rarity,
    String? cardType,
  }) => _market.publishBonCircuit(
    bonId: bonId,
    valueZen: valueZen,
    hopCount: hopCount,
    ageDays: ageDays,
    marketName: marketName,
    issuerNpub: issuerNpub,
    nsecBonBytes: nsecBonBytes,
    seedMarket: seedMarket,
    skillAnnotation: skillAnnotation,
    rarity: rarity,
    cardType: cardType,
  );
  
  Future<String?> subscribeToMarket(String marketName, {int? since}) =>
    _market.subscribeToMarket(marketName, since: since);
  
  Future<String?> subscribeToMarkets(List<String> marketNames, {int? since}) =>
    _market.subscribeToMarkets(marketNames, since: since);
  
  Future<int> syncMarketP3s(Market market) async {
    // Synchroniser les followers avant de lancer la sync du marché
    try {
      final user = await _storageService.getUser();
      if (user != null && _connection.isConnected) {
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
    return await _market.syncMarketP3s(market, duService);
  }
  
  Future<int> syncMarketsP3s(List<Market> markets) async {
    // Utiliser le relay du premier marché
    final relayUrl = markets.first.relayUrl ?? AppConfig.defaultRelayUrl;
    
    if (!_connection.isConnected) {
      final connected = await _connection.connect(relayUrl);
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

    final originalCallback = _market.onP3Received;
    _market.onP3Received = (bonId, p3Hex) async {
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
    
    final subscriptionId = await subscribeToMarkets(marketNames, since: since);
    
    if (subscriptionId == null) {
      return 0;
    }

    Timer? fallbackTimer;
    
    void finishSync() async {
      fallbackTimer?.cancel();
      _connection.removeHandler(subscriptionId);
      _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
      
      await flushBatch();
      _market.onP3Received = originalCallback;
      
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

    _connection.registerHandler(subscriptionId, (message) {
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
  
  void enableAutoSync({Duration? interval, Market? initialMarket}) =>
    _market.enableAutoSync(interval: interval, initialMarket: initialMarket);
  
  void disableAutoSync() => _market.disableAutoSync();
  
  void updateAutoSyncMarket(Market market) =>
    _market.updateAutoSyncMarket(market);
  
  Future<int> triggerImmediateSync(Market market) async {
    if (!_connection.isConnected && market.relayUrl != null) {
      await _connection.connect(market.relayUrl!);
    }
    
    if (!_connection.isConnected) {
      onError?.call('Pas de connexion pour synchronisation');
      return 0;
    }
    
    return await syncMarketP3s(market);
  }
  
  // ============================================================
  // WoTx - Déléguer à NostrWoTxService
  // ============================================================
  
  Future<bool> publishSkillPermit({
    required String npub,
    required String nsec,
    required String skillTag,
    required String seedMarket,
  }) => _wotx.publishSkillPermit(
    npub: npub,
    nsec: nsec,
    skillTag: skillTag,
    seedMarket: seedMarket,
  );
  
  Future<List<String>> fetchSkillDefinitions() =>
    _wotx.fetchSkillDefinitions();
  
  Future<bool> publishSkillRequest({
    required String npub,
    required String nsec,
    required String skill,
    required String seedMarket,
    String motivation = "Déclaration initiale lors de l'inscription",
  }) => _wotx.publishSkillRequest(
    npub: npub,
    nsec: nsec,
    skill: skill,
    seedMarket: seedMarket,
    motivation: motivation,
  );
  
  Future<List<Map<String, dynamic>>> fetchPendingSkillRequests({
    required List<String> mySkills,
    required String myNpub,
  }) => _wotx.fetchPendingSkillRequests(
    mySkills: mySkills,
    myNpub: myNpub,
  );
  
  Future<bool> publishSkillAttestation({
    required String myNpub,
    required String myNsec,
    required String requestId,
    required String requesterNpub,
    required String permitId,
    required String seedMarket,
    String? motivation,
  }) => _wotx.publishSkillAttestation(
    myNpub: myNpub,
    myNsec: myNsec,
    requestId: requestId,
    requesterNpub: requesterNpub,
    permitId: permitId,
    seedMarket: seedMarket,
    motivation: motivation,
  );
  
  Future<List<Map<String, dynamic>>> fetchMyAttestations(String myNpub) =>
    _wotx.fetchMyAttestations(myNpub);
  
  Future<bool> publishSkillReview({
    required String myNpub,
    required String myNsec,
    required String targetNpub,
    required String permitEventId,
    required bool isPositive,
  }) => _wotx.publishSkillReview(
    myNpub: myNpub,
    myNsec: myNsec,
    targetNpub: targetNpub,
    permitEventId: permitEventId,
    isPositive: isPositive,
  );

  Future<bool> publishSkillReaction({
    required String myNpub,
    required String myNsec,
    required String artisanNpub,
    required String eventId,
    required bool isPositive,
  }) => _wotx.publishSkillReaction(
    myNpub: myNpub,
    myNsec: myNsec,
    artisanNpub: artisanNpub,
    eventId: eventId,
    isPositive: isPositive,
  );
  
  Future<List<String>> fetchActivityTagsFromProfiles({int limit = 100}) =>
    _wotx.fetchActivityTagsFromProfiles(limit: limit);
  
  // ============================================================
  // DU (Dividende Universel) - Kind 30305
  // ============================================================

  /// Publie un incrément de DU (kind 30305)
  Future<bool> publishDuIncrement(String npub, String nsec, double amount, DateTime date) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

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
      return await _connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur publication DU: $e');
      return false;
    }
  }

  /// Calcule le DU disponible à partir des événements Nostr
  Future<double> computeAvailableDu(String npub) async {
    final cacheDb = CacheDatabaseService();
    
    if (!_connection.isConnected) {
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
    if (!_connection.isConnected) return null;
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
    if (!_connection.isConnected) return [];

    final completer = Completer<List<Map<String, dynamic>>>();
    final events = <Map<String, dynamic>>[];
    final subscriptionId = 'fetch_${kind}_${DateTime.now().millisecondsSinceEpoch}';

    _connection.registerHandler(subscriptionId, (message) {
      try {
        if (message[0] == 'EVENT' && message.length >= 3) {
          final event = message[2] as Map<String, dynamic>;
          events.add(event);
        } else if (message[0] == 'EOSE') {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          _connection.removeHandler(subscriptionId);
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
    _connection.sendMessage(request);

    Timer? fallbackTimer;
    fallbackTimer = Timer(const Duration(seconds: 10), () {
      _connection.removeHandler(subscriptionId);
      if (!completer.isCompleted) {
        _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
        completer.complete(events);
      }
    });

    final result = await completer.future;
    fallbackTimer.cancel();
    return result;
  }

  // ============================================================
  // PROFILS UTILISATEUR & AUTRES (À conserver temporairement)
  // ============================================================
  
  /// Publie un profil utilisateur (kind 0)
  Future<bool> publishUserProfile({
    required String npub,
    required String nsec,
    required String name,
    String? displayName,
    String? about,
    String? picture,
    String? banner,
    String? picture64,
    String? banner64,
    String? website,
    String? g1pub,
    List<String>? tags,
    String? activity,
    String? profession,
    Map<String, dynamic>? economicData,
  }) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    final registered = await _market.ensurePubkeyRegistered(npub);
    if (!registered) {
      Logger.warn('NostrService', 'Pubkey non enregistrée sur l\'API, mais on tente la publication Nostr quand même');
    }

    try {
      final profile = NostrProfile(
        npub: npub,
        name: name,
        displayName: displayName,
        about: about,
        picture: picture,
        banner: banner,
        picture64: picture64,
        banner64: banner64,
        website: website,
        g1pub: g1pub,
        tags: tags,
        activity: activity,
        profession: profession,
        economicData: economicData,
      );

      final nostrTags = <List<String>>[];
      
      if (tags != null && tags.isNotEmpty) {
        for (final tag in tags) {
          final normalizedTag = tag.toLowerCase().trim();
          if (normalizedTag.isNotEmpty) {
            nostrTags.add(['t', normalizedTag]);
          }
        }
      }
      
      if (activity != null && activity.trim().isNotEmpty) {
        nostrTags.add(['t', activity.toLowerCase().trim()]);
      }
      
      if (profession != null && profession.trim().isNotEmpty) {
        nostrTags.add(['t', profession.toLowerCase().trim()]);
      }

      final event = {
        'kind': NostrConstants.kindMetadata,
        'pubkey': npub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': nostrTags,
        'content': jsonEncode(profile.toJson()),
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
      _connection.sendMessage(message);
      
      Logger.log('NostrService', 'Profil publié avec ${nostrTags.length} tags');
      return true;
    } catch (e) {
      onError?.call('Erreur publication profil: $e');
      return false;
    }
  }
  
  /// Récupère l'historique des transferts d'un bon (kind 1)
  Future<List<Map<String, dynamic>>> fetchBonTransfers(String bonId) async {
    return fetchBonsTransfers([bonId]);
  }

  /// Récupère l'historique des transferts pour plusieurs bons (kind 1)
  Future<List<Map<String, dynamic>>> fetchBonsTransfers(List<String> bonIds) async {
    if (!_connection.isConnected || bonIds.isEmpty) {
      if (bonIds.isNotEmpty) Logger.error('NostrService', 'Non connecté');
      return [];
    }

    try {
      final completer = Completer<List<Map<String, dynamic>>>();
      final transfers = <Map<String, dynamic>>[];
      
      final subscriptionId = 'transfers_${DateTime.now().millisecondsSinceEpoch}';
      
      _connection.registerHandler(subscriptionId, (message) {
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
            _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            _connection.removeHandler(subscriptionId);
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
      
      _connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        _connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
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
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    final registered = await _market.ensurePubkeyRegistered(bonId);
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
      return await _connection.sendEventAndWait(eventId, message);
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
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    final registered = await _market.ensurePubkeyRegistered(bonId);
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
      return await _connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur publication burn: $e');
      return false;
    }
  }
  
  /// Récupère un profil utilisateur (kind 0)
  Future<NostrProfile?> fetchUserProfile(String npub) async {
    if (!_connection.isConnected) {
      return null;
    }
    
    try {
      final completer = Completer<NostrProfile?>();
      final subscriptionId = 'profile_${DateTime.now().millisecondsSinceEpoch}';
      
      _connection.registerHandler(subscriptionId, (message) {
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
              if (!completer.isCompleted) {
                completer.complete(profile);
              }
            }
          } else if (message[0] == 'EOSE') {
            _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            _connection.removeHandler(subscriptionId);
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
      
      _connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        _connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
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
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    final registered = await _market.ensurePubkeyRegistered(npub);
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
      return await _connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur publication contacts: $e');
      return false;
    }
  }
  
  /// Récupère les followers (ceux qui m'ont dans leur kind 3)
  Future<List<String>> fetchFollowers(String myNpub) async {
    if (!_connection.isConnected) return [];

    try {
      final completer = Completer<List<String>>();
      final followers = <String>{};
      final subscriptionId = 'followers_${DateTime.now().millisecondsSinceEpoch}';
      
      _connection.registerHandler(subscriptionId, (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
            final event = message[2] as Map<String, dynamic>;
            followers.add(event['pubkey'].toString());
          } else if (message[0] == 'EOSE') {
            _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            _connection.removeHandler(subscriptionId);
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
      
      _connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        _connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
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
    if (!_connection.isConnected || npubs.isEmpty) return {};

    try {
      final completer = Completer<Map<String, List<String>>>();
      final result = <String, List<String>>{};
      final subscriptionId = 'multi_contacts_${DateTime.now().millisecondsSinceEpoch}';
      
      _connection.registerHandler(subscriptionId, (message) {
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
            _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            _connection.removeHandler(subscriptionId);
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
      
      _connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        _connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
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
    if (!_connection.isConnected) {
      return [];
    }

    try {
      final completer = Completer<List<String>>();
      final contacts = <String>[];
      final subscriptionId = 'contacts_${DateTime.now().millisecondsSinceEpoch}';
      
      _connection.registerHandler(subscriptionId, (message) {
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
            _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            _connection.removeHandler(subscriptionId);
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
      
      _connection.sendMessage(request);
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        _connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
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
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    final registered = await _market.ensurePubkeyRegistered(npub);
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
      return await _connection.sendEventAndWait(eventId, message);
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
            _market.handleP3Event(event);
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

