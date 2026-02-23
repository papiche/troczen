import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import '../models/market.dart';
import 'crypto_service.dart';
import 'storage_service.dart';
import 'image_cache_service.dart';
import 'logger_service.dart';
import 'du_calculation_service.dart';
import 'nostr_connection_service.dart';
import 'api_service.dart';

/// Service de gestion des marchés Nostr (kinds 30303, 30304)
/// Responsabilité unique: Publication et synchronisation des P3 et circuits
class NostrMarketService {
  final NostrConnectionService _connection;
  final CryptoService _cryptoService;
  final StorageService _storageService;
  final ImageCacheService _imageCache = ImageCacheService();
  
  // Sync automatique
  Timer? _backgroundSyncTimer;
  bool _autoSyncEnabled = false;
  Duration _autoSyncInterval = const Duration(minutes: 5);
  Market? _lastSyncedMarket;
  bool _isSyncing = false;
  
  // Getters publics pour compatibilité avec NostrService facade
  bool get autoSyncEnabled => _autoSyncEnabled;
  Market? get lastSyncedMarket => _lastSyncedMarket;
  
  // Enregistrement des pubkeys sur le relai
  bool _pubkeyRegistered = false;
  String? _registeredPubkey;
  String? _apiUrl;
  
  // Callbacks
  Function(String bonId, String p3Hex)? onP3Received;
  Function(String error)? onError;
  
  NostrMarketService({
    required NostrConnectionService connection,
    required CryptoService cryptoService,
    required StorageService storageService,
  })  : _connection = connection,
        _cryptoService = cryptoService,
        _storageService = storageService;
  
  // ============================================================
  // ENREGISTREMENT PUBKEY SUR LE RELAI
  // ============================================================
  
  /// Enregistre la pubkey sur le relai Nostr (policy amisOfAmis)
  Future<bool> ensurePubkeyRegistered(String pubkeyHex) async {
    if (_pubkeyRegistered && _registeredPubkey == pubkeyHex) {
      return true;
    }
    
    _apiUrl ??= await _getApiUrl();
    
    if (_apiUrl == null) {
      Logger.warn('NostrMarket', 'API URL non configurée - skip pubkey registration');
      return true;
    }
    
    try {
      final url = Uri.parse('$_apiUrl/api/nostr/register');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pubkey': pubkeyHex}),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _pubkeyRegistered = true;
        _registeredPubkey = pubkeyHex;
        
        if (data['already_registered'] == true) {
          Logger.log('NostrMarket', 'Pubkey déjà enregistrée');
        } else {
          Logger.success('NostrMarket', 'Pubkey enregistrée avec succès');
        }
        
        return true;
      } else {
        Logger.error('NostrMarket', 'Erreur enregistrement pubkey: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      Logger.error('NostrMarket', 'Erreur appel /api/nostr/register', e);
      return false;
    }
  }
  
  Future<String?> _getApiUrl() async {
    try {
      final apiService = ApiService();
      return apiService.apiUrl;
    } catch (e) {
      Logger.error('NostrMarket', 'Erreur récupération API URL', e);
      return null;
    }
  }
  
  // ============================================================
  // PUBLICATION P3 (Kind 30303)
  // ============================================================
  
  /// Publie une P3 chiffrée sur Nostr (kind 30303)
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
  }) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    try {
      // 1. Chiffrer P3 avec K_day
      final now = DateTime.now();
      final p3Encrypted = await _cryptoService.encryptP3WithSeed(p3Hex, seedMarket, now);

      // 2. Reconstruire sk_B ÉPHÉMÈRE
      final p2Bytes = Uint8List.fromList(HEX.decode(p2Hex));
      final p3Bytes = Uint8List.fromList(HEX.decode(p3Hex));
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);
      
      // 3. Enregistrer la pubkey du bon
      final registered = await ensurePubkeyRegistered(bonId);
      if (!registered) {
        Logger.error('NostrMarket', 'Publication P3 annulée: pubkey non enregistrée');
        _cryptoService.secureZeroiseBytes(nsecBonBytes);
        _cryptoService.secureZeroiseBytes(p2Bytes);
        _cryptoService.secureZeroiseBytes(p3Bytes);
        return false;
      }

      // 4. Créer l'event Nostr
      final expiry = now.add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000;
      
      final event = {
        'kind': 30303,
        'pubkey': bonId,
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['d', 'zen-$bonId'],
          ['t', _normalizeMarketTag(marketName)],
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
          if (wish != null && wish.isNotEmpty) ['wish', wish],
        ],
        'content': jsonEncode({
          'display_name': 'Bon ${value.toStringAsFixed(0)} ẐEN',
          'design': 'panini-standard',
        }),
      };

      // 5. Calculer l'ID et signer
      final eventId = _calculateEventId(event);
      event['id'] = eventId;
      final signature = _cryptoService.signMessageBytes(eventId, nsecBonBytes);
      event['sig'] = signature;
      
      // 6. Nettoyage sécurité
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

      // 7. Envoyer au relais
      final message = jsonEncode(['EVENT', event]);
      _connection.sendMessage(message);

      return true;
    } catch (e) {
      onError?.call('Erreur publication P3: $e');
      return false;
    }
  }
  
  // ============================================================
  // PUBLICATION CIRCUIT (Kind 30304)
  // ============================================================
  
  /// Publie un event circuit/révélation (kind 30304)
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
  }) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    final registered = await ensurePubkeyRegistered(bonId);
    if (!registered) {
      Logger.error('NostrMarket', 'Publication circuit annulée: pubkey non enregistrée');
      return false;
    }

    try {
      // Créer le contenu JSON
      final circuitContent = {
        'type': 'circuit_revelation',
        'bon_id': bonId,
        'value_zen': valueZen,
        'hop_count': hopCount,
        'age_days': ageDays,
        'market': marketName,
        'timestamp': DateTime.now().toIso8601String(),
        if (skillAnnotation != null && skillAnnotation.isNotEmpty)
          'skill_annotation': skillAnnotation,
        if (rarity != null) 'rarity': rarity,
        if (cardType != null) 'card_type': cardType,
      };
      
      // Chiffrer le contenu
      final plaintextContent = jsonEncode(circuitContent);
      final encrypted = _cryptoService.encryptWoTxContent(plaintextContent, seedMarket);
      
      // Tags publics
      final tags = <List<String>>[
        ['d', 'circuit_$bonId'],
        ['t', _normalizeMarketTag(marketName)],
        ['market', marketName],
        ['issuer', issuerNpub],
        ['value', valueZen.toString()],
        ['hops', hopCount.toString()],
        ['age_days', ageDays.toString()],
        if (skillAnnotation != null && skillAnnotation.isNotEmpty)
          ['skill', skillAnnotation],
      ];
      
      if (encrypted['nonce']!.isNotEmpty) {
        tags.add(['encryption', 'aes-gcm', encrypted['nonce']!]);
      }

      final event = {
        'kind': 30304,
        'pubkey': bonId,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': tags,
        'content': encrypted['ciphertext']!,
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;
      final signature = _cryptoService.signMessageBytes(eventId, nsecBonBytes);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      _connection.sendMessage(message);
      
      Logger.log('NostrMarket',
          'Circuit révélé: $bonId | $valueZenẐEN | $hopCount hops | $ageDays jours');

      return true;
    } catch (e) {
      onError?.call('Erreur publication circuit: $e');
      return false;
    }
  }
  
  // ============================================================
  // SYNCHRONISATION P3
  // ============================================================
  
  /// S'abonne aux events kind 30303 d'un marché
  Future<void> subscribeToMarket(String marketName, {int? since}) async {
    await subscribeToMarkets([marketName], since: since);
  }

  /// S'abonne aux events kind 30303 de plusieurs marchés
  Future<void> subscribeToMarkets(List<String> marketNames, {int? since}) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return;
    }

    if (marketNames.isEmpty) {
      Logger.warn('NostrMarket', 'Aucun marché à surveiller');
      return;
    }

    final subscriptionId = 'zen-multi-${marketNames.length}';
    final marketTags = marketNames.map((m) => _normalizeMarketTag(m)).toList();
    
    final filters = <String, dynamic>{
      'kinds': [30303],
      '#t': marketTags,
    };

    if (since != null) {
      filters['since'] = since;
    }

    final request = jsonEncode([
      'REQ',
      subscriptionId,
      filters,
    ]);

    _connection.sendMessage(request);
    Logger.log('NostrMarket', 'Abonné à ${marketNames.length} marché(s): ${marketNames.join(", ")}');
  }
  
  /// Synchronise tous les P3 d'un marché avec insertion en lot
  Future<int> syncMarketP3s(Market market, DuCalculationService duService) async {
    if (_isSyncing) {
      Logger.info('NostrMarket', 'Sync déjà en cours');
      return 0;
    }
    
    _isSyncing = true;
    
    try {
      if (!_connection.isConnected) {
        final connected = await _connection.connect(market.relayUrl ?? 'wss://relay.troczen.com');
        if (!connected) {
          _isSyncing = false;
          return 0;
        }
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
          Logger.log('NostrMarket', 'Batch de ${batchToWrite.length} P3 sauvegardé');
        }
      }

      final originalCallback = onP3Received;
      onP3Received = (bonId, p3Hex) async {
        p3Batch[bonId] = p3Hex;
        syncedCount++;
        originalCallback?.call(bonId, p3Hex);
        
        if (p3Batch.length >= batchSize) {
          await flushBatch();
        }
      };

      await subscribeToMarket(market.name);

      final estimatedSize = market.merchantCount ?? 100;
      final timeoutSeconds = (5 + (estimatedSize ~/ 20)).clamp(5, 30);
      final timeout = Duration(seconds: timeoutSeconds);
      
      Logger.info('NostrMarket',
          'Sync démarrée avec timeout de ${timeout.inSeconds}s');

      Timer(timeout, () async {
        await flushBatch();
        
        onP3Received = originalCallback;
        
        try {
          await duService.checkAndGenerateDU();
        } catch (e) {
          Logger.error('NostrMarket', 'Erreur vérification DU', e);
        }
        
        try {
          final marketBons = await _storageService.getMarketBonsData();
          Logger.success('NostrMarket',
              'Sync terminée: $syncedCount P3 reçus, ${marketBons.length} en cache');
        } catch (e) {
          Logger.info('NostrMarket', 'Impossible de vérifier la cohérence: $e');
        }
        
        completer.complete(syncedCount);
      });

      return completer.future;
    } finally {
      _isSyncing = false;
    }
  }
  
  /// Traite un event Nostr reçu (Kind 30303 - Bons)
  Future<void> handleP3Event(Map<String, dynamic> event) async {
    try {
      if (event['kind'] != 30303) return;

      final tags = event['tags'] as List;
      String? bonId;
      String? p3Cipher;
      String? p3Nonce;
      String? marketName;
      String? issuerNpub;
      String? issuerName;
      double? value;
      String? category;
      String? rarity;
      int? expiryTimestamp;
      String? wish;

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
            case 'issuer':
              issuerNpub = tag[1].toString();
              break;
            case 'value':
              value = double.tryParse(tag[1].toString());
              break;
            case 'category':
              category = tag[1].toString();
              break;
            case 'rarity':
              rarity = tag[1].toString();
              break;
            case 'expiry':
              expiryTimestamp = int.tryParse(tag[1].toString());
              break;
            case 'wish':
              wish = tag[1].toString();
              break;
          }
        }
      }

      if (bonId == null || p3Cipher == null || p3Nonce == null) {
        Logger.warn('NostrMarket', 'Event kind 30303 rejeté: tag obligatoire manquant');
        return;
      }

      final markets = await _storageService.getMarkets();
      
      Market? targetMarket;
      for (final m in markets) {
        if (m.name == marketName) {
          targetMarket = m;
          break;
        }
      }
      
      if (targetMarket == null) {
        Logger.debug('NostrMarket', 'Event ignoré: marché "$marketName" non configuré');
        return;
      }

      final eventTimestamp = event['created_at'] as int;
      final eventDate = DateTime.fromMillisecondsSinceEpoch(eventTimestamp * 1000);
      final p3Hex = await _cryptoService.decryptP3WithSeed(
        p3Cipher,
        p3Nonce,
        targetMarket.seedMarket,
        eventDate,
      );

      Logger.log('NostrMarket', 'Bon reçu/déchiffré: $bonId');

      String? pictureUrl;
      String? bannerUrl;
      try {
        final content = event['content'];
        if (content != null && content is String) {
          final contentJson = jsonDecode(content);
          
          pictureUrl = contentJson['picture'] as String?;
          if (pictureUrl != null && pictureUrl.isNotEmpty) {
            _imageCache.getOrCacheImage(
              url: pictureUrl,
              npub: bonId,
              type: 'logo'
            );
          }
          
          bannerUrl = contentJson['banner'] as String?;
          if (bannerUrl != null && bannerUrl.isNotEmpty) {
            _imageCache.getOrCacheImage(
              url: bannerUrl,
              npub: bonId,
              type: 'banner'
            );
          }
        }
      } catch (e) {
        Logger.error('NostrMarket', 'Erreur parsing content bon', e);
      }

      final bonData = {
        'bonId': bonId,
        'issuerNpub': issuerNpub,
        'issuerName': issuerName ?? 'Commerçant',
        'value': value ?? 0.0,
        'category': category ?? 'generic',
        'rarity': rarity ?? 'common',
        'marketName': marketName,
        'createdAt': eventDate.toIso8601String(),
        'expiresAt': expiryTimestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(expiryTimestamp * 1000).toIso8601String()
            : null,
        'status': 'active',
        'picture': pictureUrl,
        'banner': bannerUrl,
        'p3Hex': p3Hex,
        'eventTimestamp': eventTimestamp,
        'wish': wish,
      };
      
      await _storageService.saveMarketBonData(bonData);

      onP3Received?.call(bonId, p3Hex);
    } catch (e) {
      Logger.error('NostrMarket', 'Erreur traitement event', e);
      onError?.call('Erreur traitement event: $e');
    }
  }
  
  // ============================================================
  // SYNC AUTOMATIQUE
  // ============================================================
  
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
    
    _backgroundSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
      if (_connection.isConnected && _lastSyncedMarket != null) {
        // Note: besoin du DuService pour la sync complète
      }
    });
  }

  void disableAutoSync() {
    _autoSyncEnabled = false;
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
  }

  void updateAutoSyncMarket(Market market) {
    _lastSyncedMarket = market;
  }
  
  void onAppPaused() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
  }
  
  void onAppResumed() {
    if (_autoSyncEnabled && _backgroundSyncTimer == null) {
      _backgroundSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
        if (_connection.isConnected && _lastSyncedMarket != null && !_connection.isAppInBackground) {
          // Sync automatique
        }
      });
    }
  }
  
  void dispose() {
    disableAutoSync();
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
