import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import '../models/market.dart';
import '../models/nostr_profile.dart';
import 'crypto_service.dart';
import 'storage_service.dart';
import 'image_cache_service.dart';
import 'logger_service.dart';
import 'du_calculation_service.dart';
import 'nostr_connection_service.dart';
import 'nostr_market_service.dart';
import 'nostr_wotx_service.dart';

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
  
  // Garder pour compatibilité
  final ImageCacheService _imageCache = ImageCacheService();
  
  // Callbacks (redirigés vers les sous-services)
  Function(String bonId, String p3Hex)? onP3Received;
  Function(String error)? onError;
  Function(bool connected)? onConnectionChange;
  Function(List<String> tags)? onTagsReceived;

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
    
    // Rediriger les callbacks
    _connection.onConnectionChange = (connected) {
      onConnectionChange?.call(connected);
    };
    
    _connection.onError = (error) {
      onError?.call(error);
    };
    
    _connection.onMessage = _handleMessage;
    
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
    _connection.dispose();
    _market.dispose();
  }
  
  // ============================================================
  // MARCHÉS - Déléguer à NostrMarketService
  // ============================================================
  
  Future<bool> publishP3({
    required String bonId,
    required String p2Hex,
    required String p3Hex,
    required String seedMarket,
    required String issuerNpub,
    required String marketName,
    required double value,
    String? category,
    String? rarity,
    String? wish,
  }) => _market.publishP3(
    bonId: bonId,
    p2Hex: p2Hex,
    p3Hex: p3Hex,
    seedMarket: seedMarket,
    issuerNpub: issuerNpub,
    marketName: marketName,
    value: value,
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
  
  Future<void> subscribeToMarket(String marketName, {int? since}) =>
    _market.subscribeToMarket(marketName, since: since);
  
  Future<void> subscribeToMarkets(List<String> marketNames, {int? since}) =>
    _market.subscribeToMarkets(marketNames, since: since);
  
  Future<int> syncMarketP3s(Market market) async {
    final duService = DuCalculationService(
      storageService: _storageService,
      nostrService: this,
      cryptoService: _cryptoService,
    );
    return await _market.syncMarketP3s(market, duService);
  }
  
  Future<int> syncMarketsP3s(List<Market> markets) async {
    // Utiliser le relay du premier marché
    final relayUrl = markets.first.relayUrl ?? 'wss://relay.copylaradio.com';
    
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
    await subscribeToMarkets(marketNames);

    Timer(const Duration(seconds: 8), () async {
      await flushBatch();
      _market.onP3Received = originalCallback;
      
      try {
        final duService = DuCalculationService(
          storageService: _storageService,
          nostrService: this,
          cryptoService: _cryptoService,
        );
        await duService.checkAndGenerateDU();
      } catch (e) {
        Logger.error('NostrService', 'Erreur vérification DU', e);
      }
      
      completer.complete(syncedCount);
    });

    return completer.future;
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
  
  Future<List<String>> fetchActivityTagsFromProfiles({int limit = 100}) =>
    _wotx.fetchActivityTagsFromProfiles(limit: limit);
  
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
    String? website,
    String? g1pub,
    List<String>? tags,
    String? activity,
    String? profession,
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
        website: website,
        g1pub: g1pub,
        tags: tags,
        activity: activity,
        profession: profession,
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

      final eventId = _calculateEventId(event);
      event['id'] = eventId;
      final signature = _cryptoService.signMessage(eventId, nsec);
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
    if (!_connection.isConnected) {
      Logger.error('NostrService', 'Non connecté');
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
            transfers.add(event);
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
          '#bon': [bonId],
        }
      ]);
      
      _connection.sendMessage(request);
      
      Timer(const Duration(seconds: 5), () {
        _connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(transfers);
        }
      });
      
      return await completer.future;
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
      final p2Bytes = Uint8List.fromList(HEX.decode(bonP2));
      final p3Bytes = Uint8List.fromList(HEX.decode(bonP3));
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);

      final content = {
        'type': 'transfer',
        'bon_id': bonId,
        'value': value,
        'unit': 'ZEN',
        'market': marketName,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final event = {
        'kind': NostrConstants.kindText,
        'pubkey': bonId,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['p', receiverNpub],
          ['t', 'troczen-transfer'],
          ['t', _normalizeMarketTag(marketName)],
          ['market', marketName],
          ['bon', bonId],
          ['value', value.toString()],
        ],
        'content': jsonEncode(content),
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;
      final signature = _cryptoService.signMessageBytes(eventId, nsecBonBytes);
      event['sig'] = signature;
      
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

      final message = jsonEncode(['EVENT', event]);
      _connection.sendMessage(message);

      return true;
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
          ['e', bonId],
          ['t', _normalizeMarketTag(marketName)],
          ['market', marketName],
          ['reason', reason],
        ],
        'content': 'BURN | $reason',
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;
      final signature = _cryptoService.signMessageBytes(eventId, nsecBonBytes);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      _connection.sendMessage(message);

      return true;
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
      
      Timer(const Duration(seconds: 5), () {
        _connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(null);
        }
      });
      
      return await completer.future;
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

      final eventId = _calculateEventId(event);
      event['id'] = eventId;
      final signature = _cryptoService.signMessage(eventId, nsec);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      _connection.sendMessage(message);

      return true;
    } catch (e) {
      onError?.call('Erreur publication contacts: $e');
      return false;
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
      
      Timer(const Duration(seconds: 5), () {
        _connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(contacts);
        }
      });
      
      return await completer.future;
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

      final eventId = _calculateEventId(event);
      event['id'] = eventId;
      final signature = _cryptoService.signMessage(eventId, nsec);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      _connection.sendMessage(message);

      return true;
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
          } else if (kind == 30303) {
            _market.handleP3Event(event);
          }
        }
        break;
    }
  }
  
  void _handleMetadataEvent(Map<String, dynamic> event) {
    try {
      final npub = event['pubkey'] as String?;
      final content = event['content'] as String?;
      
      if (npub == null || content == null) return;
      
      final contentJson = jsonDecode(content);
      final picture = contentJson['picture'] as String?;
      final banner = contentJson['banner'] as String?;

      if (picture != null && picture.isNotEmpty) {
        _imageCache.getOrCacheImage(
          url: picture,
          npub: npub,
          type: 'avatar'
        );
      }
      
      if (banner != null && banner.isNotEmpty) {
        _imageCache.getOrCacheImage(
          url: banner,
          npub: npub,
          type: 'banner'
        );
      }
    } catch (e) {
      Logger.error('NostrService', 'Erreur traitement metadata', e);
    }
  }
  
  // ============================================================
  // UTILITAIRES
  // ============================================================
  
  String _normalizeMarketTag(String marketName) {
    final normalized = marketName.runes.map((r) {
      final char = String.fromCharCode(r);
      if (char.codeUnitAt(0) > 127) {
        return _removeDiacritics(char);
      }
      return char;
    }).join();
    
    final lower = normalized.toLowerCase();
    final sanitized = lower.replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final cleaned = sanitized.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    
    return 'market_$cleaned';
  }
  
  String _removeDiacritics(String char) {
    const diacriticsMap = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
      'œ': 'oe', 'æ': 'ae',
      'À': 'a', 'Â': 'a', 'Ä': 'a', 'Á': 'a', 'Ã': 'a', 'Å': 'a',
      'È': 'e', 'É': 'e', 'Ê': 'e', 'Ë': 'e',
      'Ì': 'i', 'Í': 'i', 'Î': 'i', 'Ï': 'i',
      'Ò': 'o', 'Ó': 'o', 'Ô': 'o', 'Ö': 'o', 'Õ': 'o',
      'Ù': 'u', 'Ú': 'u', 'Û': 'u', 'Ü': 'u',
      'Ç': 'c', 'Ñ': 'n',
      'Œ': 'oe', 'Æ': 'ae',
    };
    
    return diacriticsMap[char] ?? char.toLowerCase();
  }
  
  String _calculateEventId(Map<String, dynamic> event) {
    final serialized = jsonEncode([
      0,
      event['pubkey'],
      event['created_at'],
      event['kind'],
      event['tags'],
      event['content'],
    ]);

    final hash = sha256.convert(utf8.encode(serialized));
    return HEX.encode(hash.bytes);
  }
}

/// Normalise un nom de marché en tag de routage standardisé (NIP-12)
String normalizeMarketTag(String marketName) {
  final normalized = marketName.runes.map((r) {
    final char = String.fromCharCode(r);
    if (char.codeUnitAt(0) > 127) {
      return _removeDiacriticsGlobal(char);
    }
    return char;
  }).join();
  
  final lower = normalized.toLowerCase();
  final sanitized = lower.replaceAll(RegExp(r'[^a-z0-9]'), '_');
  final cleaned = sanitized.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  
  return 'market_$cleaned';
}

String _removeDiacriticsGlobal(String char) {
  const diacriticsMap = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
    'œ': 'oe', 'æ': 'ae',
  };
  
  return diacriticsMap[char] ?? char.toLowerCase();
}
