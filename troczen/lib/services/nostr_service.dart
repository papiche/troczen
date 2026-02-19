import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import '../models/market.dart';
import '../models/nostr_profile.dart';
import 'crypto_service.dart';
import 'storage_service.dart';
import 'image_cache_service.dart';
import 'logger_service.dart';

/// Service de publication et synchronisation via Nostr
/// Gère la publication des P3 (kind 30303) et la synchronisation
class NostrService {
  final CryptoService _cryptoService;
  final StorageService _storageService;
  final ImageCacheService _imageCache = ImageCacheService();
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  String? _currentRelayUrl;
  
  // ✅ Sync automatique en arrière-plan
  Timer? _backgroundSyncTimer;
  bool _autoSyncEnabled = false;
  Duration _autoSyncInterval = const Duration(minutes: 5);
  Market? _lastSyncedMarket;

  // ✅ Getters publics pour les tests
  bool get autoSyncEnabled => _autoSyncEnabled;
  Market? get lastSyncedMarket => _lastSyncedMarket;
  
  // Callbacks
  Function(String bonId, String p3Hex)? onP3Received;
  Function(String error)? onError;
  Function(bool connected)? onConnectionChange;
  Function(List<String> tags)? onTagsReceived;

  NostrService({
    required CryptoService cryptoService,
    required StorageService storageService,
  })  : _cryptoService = cryptoService,
        _storageService = storageService;

  /// Connexion au relais Nostr
  Future<bool> connect(String relayUrl) async {
    try {
      if (_isConnected && _currentRelayUrl == relayUrl) {
        return true;
      }

      await disconnect();

      final uri = Uri.parse(relayUrl);
      _channel = WebSocketChannel.connect(uri);
      _currentRelayUrl = relayUrl;

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          _isConnected = false;
          onError?.call('Erreur WebSocket: $error');
          onConnectionChange?.call(false);
        },
        onDone: () {
          _isConnected = false;
          onConnectionChange?.call(false);
        },
      );

      _isConnected = true;
      onConnectionChange?.call(true);
      return true;
    } catch (e) {
      _isConnected = false;
      onError?.call('Connexion impossible: $e');
      onConnectionChange?.call(false);
      return false;
    }
  }

  /// Déconnexion du relais
  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
    _isConnected = false;
    _currentRelayUrl = null;
    onConnectionChange?.call(false);
  }

  // ============================================================
  // ✅ SYNC AUTOMATIQUE EN ARRIÈRE-PLAN
  // ============================================================

  /// Active la synchronisation automatique en arrière-plan
  void enableAutoSync({
    Duration? interval,
    Market? initialMarket,
  }) {
    if (_autoSyncEnabled) return;
    
    _autoSyncEnabled = true;
    if (interval != null) {
      _autoSyncInterval = interval;
    }
    _lastSyncedMarket = initialMarket;
    
    // Démarrer le timer de sync
    _backgroundSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
      if (_isConnected && _lastSyncedMarket != null) {
        _doBackgroundSync();
      }
    });
  }

  /// Désactive la synchronisation automatique
  void disableAutoSync() {
    _autoSyncEnabled = false;
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
  }

  /// Met à jour le marché à synchroniser automatiquement
  void updateAutoSyncMarket(Market market) {
    _lastSyncedMarket = market;
  }

  /// Effectue une synchronisation en arrière-plan silencieuse
  Future<void> _doBackgroundSync() async {
    if (!_isConnected || _lastSyncedMarket == null) return;
    
    try {
      await syncMarketP3s(_lastSyncedMarket!);
      // Sync silencieuse - pas de notification si succès
    } catch (e) {
      // Erreur ignorée en arrière-plan
    }
  }

  /// Force une synchronisation immédiate (pour appel manuel)
  Future<int> triggerImmediateSync(Market market) async {
    // Utiliser le relay du marché s'il n'est pas connecté
    if (!_isConnected && market.relayUrl != null) {
      await connect(market.relayUrl!);
    }
    
    if (!_isConnected) {
      onError?.call('Pas de connexion pour synchronisation');
      return 0;
    }
    
    return await syncMarketP3s(market);
  }

  /// ✅ Publie une P3 chiffrée sur Nostr (kind 30303)
  /// SIGNÉ PAR LE BON LUI-MÊME pour analytics économiques
  Future<bool> publishP3({
    required String bonId,
    required String p2Hex,  // ✅ Passer P2 pour reconstruction
    required String p3Hex,
    required String seedMarket,  // ✅ Graine du marché (remplace kmarketHex)
    required String issuerNpub,
    required String marketName,
    required double value,
    String? category,
    String? rarity,
  }) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    try {
      // 1. Chiffrer P3 avec K_day (clé du jour dérivée de la graine)
      final now = DateTime.now();
      final p3Encrypted = await _cryptoService.encryptP3WithSeed(p3Hex, seedMarket, now);

      // 2. ✅ Reconstruire sk_B ÉPHÉMÈRE (P2+P3) pour signature
      final nsecBon = _cryptoService.shamirCombine(null, p2Hex, p3Hex);

      // 3. Créer l'event Nostr avec tags optimisés pour dashboard
      final expiry = now.add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000;
      
      final event = {
        'kind': 30303,
        'pubkey': bonId,  // ✅ Clé publique du BON (pas l'émetteur)
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['d', 'zen-$bonId'],
          ['market', marketName],
          ['currency', 'ZEN'],
          ['value', value.toString()],
          ['issuer', issuerNpub],
          ['category', category ?? 'generic'],
          ['expiry', expiry.toString()],
          ['rarity', rarity ?? 'common'],
          ['p3_cipher', p3Encrypted['ciphertext']],
          ['p3_nonce', p3Encrypted['nonce']],
          ['version', '1'],
          ['policy', '2of3-ssss'],
        ],
        'content': jsonEncode({
          'display_name': 'Bon ${value.toStringAsFixed(0)} ẐEN',
          'design': 'panini-standard',
        }),
      };

      // 4. Calculer l'ID de l'event
      final eventId = _calculateEventId(event);
      event['id'] = eventId;

      // 5. ✅ Signer avec la clé privée du bon (reconstruction éphémère)
      final signature = _cryptoService.signMessage(eventId, nsecBon);
      event['sig'] = signature;
      // nsecBon disparaît de la RAM ici ✅

      // 6. Envoyer au relais
      final message = jsonEncode(['EVENT', event]);
      _channel!.sink.add(message);

      return true;
    } catch (e) {
      onError?.call('Erreur publication P3: $e');
      return false;
    }
  }

  /// ✅ PUBLIER PROFIL UTILISATEUR (kind 0 metadata)
  /// Les tags sont ajoutés comme tags 't' dans l'event Nostr (ex: centres d'intérêt)
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
    List<String>? tags,  // ✅ Tags d'activité/centres d'intérêt
  }) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return false;
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
      );

      // ✅ Construire les tags Nostr à partir de la liste
      final nostrTags = <List<String>>[];
      if (tags != null && tags.isNotEmpty) {
        for (final tag in tags) {
          nostrTags.add(['t', tag]);
        }
      }

      final event = {
        'kind': NostrConstants.kindMetadata,
        'pubkey': npub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': nostrTags,  // ✅ Tags intégrés dans l'event
        'content': jsonEncode(profile.toJson()),
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;

      final signature = _cryptoService.signMessage(eventId, nsec);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      _channel!.sink.add(message);

      return true;
    } catch (e) {
      onError?.call('Erreur publication profil: $e');
      return false;
    }
  }

  /// ✅ PUBLIER EVENT DE TRANSFERT (kind 1)
  /// Enregistre un transfert de bon pour le dashboard économique
  Future<bool> publishTransfer({
    required String bonId,
    required String bonP2,  // ✅ Pour reconstruction sk_B
    required String bonP3,
    required String receiverNpub,
    required double value,
    required String marketName,
  }) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    try {
      // ✅ Reconst<br/>ruire sk_B ÉPHÉMÈRE pour que le BON signe son transfert
      final nsecBon = _cryptoService.shamirCombine(null, bonP2, bonP3);

      // Contenu du transfert
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
        'pubkey': bonId,  // ✅ Le BON signe (pas l'émetteur)
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['p', receiverNpub],
          ['t', 'troczen-transfer'],
          ['market', marketName],
          ['bon', bonId],
          ['value', value.toString()],
        ],
        'content': jsonEncode(content),
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;

      // ✅ Signature par le bon
      final signature = _cryptoService.signMessage(eventId, nsecBon);
      event['sig'] = signature;
      // nsecBon disparaît ici

      final message = jsonEncode(['EVENT', event]);
      _channel!.sink.add(message);

      return true;
    } catch (e) {
      onError?.call('Erreur publication transfert: $e');
      return false;
    }
  }

  /// ✅ PUBLIER EVENT BURN (kind 5)
  /// Pour révoquer un bon (émetteur avec P1+P3)
  Future<bool> publishBurn({
    required String bonId,
    required String nsecBon,  // sk_B reconstruit temporairement avec P1+P3
    required String reason,
    required String marketName,
  }) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    try {
      final event = {
        'kind': 5,
        'pubkey': bonId,  // ✅ Clé publique du bon
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['e', bonId],
          ['market', marketName],
          ['reason', reason],
        ],
        'content': 'BURN | $reason',
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;

      // ✅ Signer avec la clé privée du bon (reconstruit éphémère)
      final signature = _cryptoService.signMessage(eventId, nsecBon);
      event['sig'] = signature;
      // nsecBon disparaît ici

      final message = jsonEncode(['EVENT', event]);
      _channel!.sink.add(message);

      return true;
    } catch (e) {
      onError?.call('Erreur publication burn: $e');
      return false;
    }
  }

  /// S'abonne aux events kind 30303 d'un marché
  Future<void> subscribeToMarket(String marketName, {int? since}) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return;
    }

    final subscriptionId = 'zen-market-$marketName';
    final filters = <String, dynamic>{
      'kinds': [30303],
      '#market': [marketName],
    };

    if (since != null) {
      filters['since'] = since;
    }

    final request = jsonEncode([
      'REQ',
      subscriptionId,
      filters,
    ]);

    _channel!.sink.add(request);
  }

  /// Synchronise tous les P3 d'un marché
  Future<int> syncMarketP3s(Market market) async {
    if (!_isConnected) {
      final connected = await connect(market.relayUrl ?? NostrConstants.defaultRelay);
      if (!connected) return 0;
    }

    int syncedCount = 0;
    final completer = Completer<int>();

    final originalCallback = onP3Received;
    onP3Received = (bonId, p3Hex) async {
      await _storageService.saveP3ToCache(bonId, p3Hex);
      syncedCount++;
      originalCallback?.call(bonId, p3Hex);
    };

    await subscribeToMarket(market.name);

    Timer(const Duration(seconds: 5), () {
      onP3Received = originalCallback;
      completer.complete(syncedCount);
    });

    return completer.future;
  }

  /// Gère les messages reçus du relais
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data);
      
      if (message is! List || message.isEmpty) return;

      final messageType = message[0];

      switch (messageType) {
        case 'EVENT':
          // Vérifier le kind pour router vers le bon handler
          if (message.length > 2 && message[2] is Map) {
            final event = message[2] as Map<String, dynamic>;
            final kind = event['kind'];
            
            if (kind == 0) {
              // Kind 0 = Metadata utilisateur
              _handleMetadataEvent(event);
            } else {
              // Autres kinds (30303, etc.)
              _handleEvent(event);
            }
          }
          break;
        case 'OK':
          final eventId = message[1];
          final success = message[2];
          if (!success) {
            final errorMsg = message.length > 3 ? message[3] : 'Erreur inconnue';
            onError?.call('Event $eventId rejeté: $errorMsg');
          }
          break;
        case 'NOTICE':
          final notice = message[1];
          onError?.call('Notice: $notice');
          break;
        case 'EOSE':
          break;
      }
    } catch (e) {
      onError?.call('Erreur parsing message: $e');
    }
  }

  /// Traite un event Nostr reçu (Kind 30303 - Bons)
  void _handleEvent(Map<String, dynamic> event) async {
    try {
      if (event['kind'] != 30303) return;

      final tags = event['tags'] as List;
      String? bonId;
      String? p3Cipher;
      String? p3Nonce;
      String? marketName;

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          switch (tag[0]) {
            case 'd':
              if (tag[1].toString().startsWith('zen-')) {
                bonId = tag[1].toString().substring(4);
              }
              break;
            case 'market':
              marketName = tag[1].toString();
              break;
            case 'p3_cipher':
              p3Cipher = tag[1].toString();
              break;
            case 'p3_nonce':
              p3Nonce = tag[1].toString();
              break;
          }
        }
      }

      if (bonId == null || p3Cipher == null || p3Nonce == null) {
        Logger.warn('NostrService', 'Event kind 30303 rejeté: tag obligatoire manquant (bonId=$bonId)');
        return;
      }

      final market = await _storageService.getMarket();
      if (market == null || market.name != marketName) {
        Logger.warn('NostrService', 'Event rejeté: marché incompatible ($marketName vs ${market?.name})');
        return;
      }

      // Calculer la clé du jour à partir de la graine du marché
      // On utilise la date de l'event (timestamp) pour déchiffrer
      final eventTimestamp = event['created_at'] as int;
      final eventDate = DateTime.fromMillisecondsSinceEpoch(eventTimestamp * 1000);
      final p3Hex = await _cryptoService.decryptP3WithSeed(
        p3Cipher,
        p3Nonce,
        market.seedMarket,
        eventDate,
      );

      Logger.log('NostrService', 'Bon reçu/déchiffré: $bonId');

      // EXTRACTION ET MISE EN CACHE DES IMAGES DU BON
      try {
        final content = event['content'];
        if (content != null && content is String) {
          final contentJson = jsonDecode(content);
          
          // Image principale du bon (picture)
          final picture = contentJson['picture'] as String?;
          if (picture != null && picture.isNotEmpty) {
            Logger.log('NostrService', 'Mise en cache image bon: $picture');
            _imageCache.getOrCacheImage(
              url: picture,
              npub: bonId,
              type: 'logo'
            );
          }
          
          // Bannière du bon
          final banner = contentJson['banner'] as String?;
          if (banner != null && banner.isNotEmpty) {
            Logger.log('NostrService', 'Mise en cache bannière bon: $banner');
            _imageCache.getOrCacheImage(
              url: banner,
              npub: bonId,
              type: 'banner'
            );
          }
        }
      } catch (e) {
        Logger.error('NostrService', 'Erreur parsing content bon pour images', e);
      }

      onP3Received?.call(bonId, p3Hex);
    } catch (e) {
      Logger.error('NostrService', 'Erreur traitement event Nostr', e);
      onError?.call('Erreur traitement event: $e');
    }
  }

  /// Traite un event de métadonnées utilisateur (Kind 0)
  void _handleMetadataEvent(Map<String, dynamic> event) {
    try {
      final npub = event['pubkey'] as String?;
      final content = event['content'] as String?;
      
      if (npub == null || content == null) return;
      
      final contentJson = jsonDecode(content);
      final picture = contentJson['picture'] as String?;
      final banner = contentJson['banner'] as String?;

      // Mise en cache de l'avatar
      if (picture != null && picture.isNotEmpty) {
        Logger.log('NostrService', 'Mise en cache avatar pour $npub: $picture');
        _imageCache.getOrCacheImage(
          url: picture,
          npub: npub,
          type: 'avatar'
        );
      }
      
      // Mise en cache de la bannière
      if (banner != null && banner.isNotEmpty) {
        Logger.log('NostrService', 'Mise en cache banner pour $npub: $banner');
        _imageCache.getOrCacheImage(
          url: banner,
          npub: npub,
          type: 'banner'
        );
      }
      
      Logger.log('NostrService', 'Métadonnées mises à jour pour $npub');
    } catch (e) {
      Logger.error('NostrService', 'Erreur traitement metadata', e);
    }
  }

  /// Calcule l'ID d'un event Nostr (hash SHA256 de la sérialisation)
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

  /// ✅ PUBLIER LISTE DES RELAIS (kind 10002)
  Future<bool> publishRelayList({
    required String npub,
    required String nsec,
    required List<String> relays,
  }) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    try {
      // Créer le relay list
      final relayList = <String, dynamic>{};
      for (final relay in relays) {
        relayList[relay] = {
          'read': true,
          'write': true,
        };
      }

      // Créer les tags
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
      _channel!.sink.add(message);

      return true;
    } catch (e) {
      onError?.call('Erreur publication relay list: $e');
      return false;
    }
  }

  /// Récupère les tags d'activité depuis les profils existants (kind 0) sur le relais
  /// Retourne une liste de tags uniques extraits des métadonnées des profils
  Future<List<String>> fetchActivityTagsFromProfiles({int limit = 100}) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return [];
    }

    try {
      final completer = Completer<List<String>>();
      final Set<String> extractedTags = {};
      final subscriptionId = 'zen-tags-${DateTime.now().millisecondsSinceEpoch}';
      
      // Sauvegarder le callback original
      final originalOnTagsReceived = onTagsReceived;
      
      // Timer pour fermer l'abonnement après un délai
      final timer = Timer(const Duration(seconds: 5), () {
        _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
        if (!completer.isCompleted) {
          completer.complete(extractedTags.toList()..sort());
        }
      });

      // Créer un abonnement pour les events kind 0 (métadonnées)
      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'kinds': [0],
          'limit': limit,
        },
      ]);
      
      _channel!.sink.add(request);
      
      // Écouter les réponses
      final subscription = _channel!.stream.listen((data) {
        try {
          final message = jsonDecode(data);
          
          if (message is List && message.isNotEmpty) {
            if (message[0] == 'EVENT' && message[1] == subscriptionId) {
              final event = message[2] as Map<String, dynamic>?;
              if (event != null) {
                final content = event['content'] as String?;
                if (content != null) {
                  final contentJson = jsonDecode(content);
                  
                  // Extraire les tags du profil
                  // Les tags peuvent être dans différents champs selon le format NIP-24
                  
                  // 1. Tags explicites dans le champ 'tags' (NIP-24)
                  final tags = contentJson['tags'] as List?;
                  if (tags != null) {
                    for (final tag in tags) {
                      if (tag is List && tag.isNotEmpty && tag[0] == 't') {
                        final tagValue = tag.length > 1 ? tag[1]?.toString() : null;
                        if (tagValue != null && tagValue.isNotEmpty) {
                          extractedTags.add(tagValue);
                        }
                      }
                    }
                  }
                  
                  // 2. Champ 'activity' ou 'profession' personnalisé
                  final activity = contentJson['activity'] as String?;
                  if (activity != null && activity.isNotEmpty) {
                    extractedTags.add(activity);
                  }
                  
                  final profession = contentJson['profession'] as String?;
                  if (profession != null && profession.isNotEmpty) {
                    extractedTags.add(profession);
                  }
                  
                  // 3. Extraire du champ 'about' si contient des hashtags
                  final about = contentJson['about'] as String?;
                  if (about != null) {
                    // Rechercher des hashtags dans le texte
                    final hashtagRegex = RegExp(r'#(\w+)');
                    final matches = hashtagRegex.allMatches(about);
                    for (final match in matches) {
                      final hashtag = match.group(1);
                      if (hashtag != null && hashtag.isNotEmpty) {
                        extractedTags.add(hashtag);
                      }
                    }
                  }
                }
              }
            } else if (message[0] == 'EOSE' && message[1] == subscriptionId) {
              // End of Stored Events
              timer.cancel();
              _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
              if (!completer.isCompleted) {
                completer.complete(extractedTags.toList()..sort());
              }
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing tags response', e);
        }
      });
      
      // Attendre le résultat
      final result = await completer.future;
      
      // Nettoyer
      await subscription.cancel();
      timer.cancel();
      onTagsReceived = originalOnTagsReceived;
      
      Logger.log('NostrService', 'Tags extraits: ${result.length} tags uniques');
      onTagsReceived?.call(result);
      
      return result;
    } catch (e) {
      onError?.call('Erreur récupération tags: $e');
      Logger.error('NostrService', 'Erreur fetchActivityTagsFromProfiles', e);
      return [];
    }
  }

  bool get isConnected => _isConnected;
  String? get currentRelay => _currentRelayUrl;
}
