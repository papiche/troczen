import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/market.dart';
import '../utils/nostr_utils.dart';
import 'crypto_service.dart';
import 'storage_service.dart';
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
        return true; 
      }
    } catch (e) {
      Logger.error('NostrMarket', 'Erreur appel /api/nostr/register', e);
      return true; 
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
    required String issuerNsecHex,
    required String p3Hex,
    required String seedMarket,
    required String issuerNpub,
    required String marketName,
    required double value,
    String? category,
    String? rarity,
    String? wish,
    int? duIndex, // ✅ AJOUT : Paramètre pour gérer de multiples DUs émis le même jour
  }) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    try {
      // 1. Chiffrer P3 avec K_day
      final now = DateTime.now();
      final p3Encrypted = await _cryptoService.encryptP3WithSeed(p3Hex, seedMarket, now);

      // 2. Enregistrer la pubkey de l'émetteur (si nécessaire)
      final registered = await ensurePubkeyRegistered(issuerNpub);
      if (!registered) {
        Logger.warn('NostrMarket', 'Pubkey non enregistrée sur l\'API, mais on tente la publication Nostr quand même');
      }

      // 3. Créer l'event Nostr
      final expiry = now.add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000;
      String dTag = 'zen-$bonId'; // Défaut (bons artisans normaux)

      // ✅ CORRECTION : Rendre le tag `d` prédictible pour écraser les clones (NIP-33)
      if (category == 'DU') {
        final today = DateTime.now().toIso8601String().substring(0, 10);
        final idx = duIndex ?? 0;
        dTag = 'zen-du-$today-part$idx'; 
      } else if (category == 'bootstrap') {
        // Un seul bon bootstrap par utilisateur !
        dTag = 'zen-bootstrap-${issuerNpub.substring(0, 16)}';
      }

      final event = {
        'kind': 30303,
        'pubkey': issuerNpub,
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'tags':[
          ['d', dTag],
          ['bon_id', bonId],
          ['t', NostrUtils.normalizeMarketTag(marketName)],
          ['market', marketName],['currency', 'ZEN'],
          ['value', value.toString()],
          ['issuer', issuerNpub],
          ['category', category ?? 'generic'],
          ['expiration', expiry.toString()],['rarity', rarity ?? 'common'],
          ['p3_cipher', p3Encrypted['ciphertext']],['p3_nonce', p3Encrypted['nonce']],
          ['version', '1'],['policy', '2of3-ssss'],
          if (wish != null && wish.isNotEmpty) ['wish', wish],
        ],
        'content': jsonEncode({
          'display_name': 'Bon ${value.toStringAsFixed(0)} ẐEN',
          'design': 'panini-standard',
        }),
      };

      // 4. Calculer l'ID et signer avec la clé de l'émetteur
      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      Uint8List issuerNsecBytes;
      try {
        issuerNsecBytes = Uint8List.fromList(HEX.decode(issuerNsecHex));
      } catch (e) {
        throw Exception('Clé privée émetteur invalide (non hexadécimale)');
      }
      final signature = _cryptoService.signMessageBytes(eventId, issuerNsecBytes);
      event['sig'] = signature;
      
      // 5. Nettoyage sécurité
      _cryptoService.secureZeroiseBytes(issuerNsecBytes);

      // 6. Envoyer au relais
      final message = jsonEncode(['EVENT', event]);
      return await _connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur publication P3: $e');
      return false;
    }
  }
  
  // ============================================================
  // MISE À JOUR PROFIL BON (Kind 30303)
  // ============================================================

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
  }) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    try {
      final now = DateTime.now();
      
      final event = {
        'kind': 30303,
        'pubkey': issuerNpub,
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'tags':[
          ['d', 'zen-$bonId'],
          ['t', NostrUtils.normalizeMarketTag(marketName)],
          ['market', marketName],
          ['currency', 'ZEN'],
          ['value', value.toString()],
          ['issuer', issuerNpub],
          ['category', category ?? 'generic'],['expiration', expiryTimestamp.toString()],
          ['rarity', rarity ?? 'common'],['p3_cipher', p3Cipher],
          ['p3_nonce', p3Nonce],
          ['version', '1'],
          ['policy', '2of3-ssss'],
          if (wish != null && wish.isNotEmpty)['wish', wish],
        ],
        'content': jsonEncode(profileData),
      };

      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      
      // Signer avec la clé de l'émetteur
      Uint8List issuerNsecBytes;
      try {
        issuerNsecBytes = Uint8List.fromList(HEX.decode(issuerNsecHex));
      } catch (e) {
        throw Exception('Clé privée émetteur invalide (non hexadécimale)');
      }
      final signature = _cryptoService.signMessageBytes(eventId, issuerNsecBytes);
      event['sig'] = signature;
      
      _cryptoService.secureZeroiseBytes(issuerNsecBytes);

      final message = jsonEncode(['EVENT', event]);
      return await _connection.sendEventAndWait(eventId, message);
    } catch (e) {
      onError?.call('Erreur mise à jour profil bon: $e');
      return false;
    }
  }

  // ============================================================
  // PUBLICATION CIRCUIT (Kind 30304)
  // ============================================================
  
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
      Logger.warn('NostrMarket', 'Pubkey non enregistrée sur l\'API, mais on tente la publication Nostr quand même');
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
        if (cardType != null) 'cardType': cardType,
      };
      
      // Chiffrer le contenu
      final plaintextContent = jsonEncode(circuitContent);
      final encrypted = _cryptoService.encryptWoTxContent(plaintextContent, seedMarket);
      
      // Tags publics
      final tags = <List<String>>[
        ['d', 'circuit_$bonId'],['t', NostrUtils.normalizeMarketTag(marketName)],
        ['market', marketName],
        ['issuer', issuerNpub],['value', valueZen.toString()],
        ['hops', hopCount.toString()],['age_days', ageDays.toString()],
        if (skillAnnotation != null && skillAnnotation.isNotEmpty)['skill', skillAnnotation],
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

      final eventId = NostrUtils.calculateEventId(event);
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
  
  Future<String?> subscribeToMarket(String marketName, {int? since}) async {
    return await subscribeToMarkets([marketName], since: since);
  }

  Future<String?> subscribeToMarkets(List<String> marketNames, {int? since}) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return null;
    }

    if (marketNames.isEmpty) {
      Logger.warn('NostrMarket', 'Aucun marché à surveiller');
      return null;
    }

    final subscriptionId = 'zen-multi-${marketNames.length}-${DateTime.now().millisecondsSinceEpoch}';
    final marketTags = marketNames.map((m) => NostrUtils.normalizeMarketTag(m)).toList();
    
    final filters = <String, dynamic>{
      'kinds': [1, 30303],
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
    return subscriptionId;
  }
  
  Future<int> syncMarketP3s(Market market, DuCalculationService duService) async {
    if (_isSyncing) {
      Logger.info('NostrMarket', 'Sync déjà en cours');
      return 0;
    }
    
    _isSyncing = true;
    
    try {
      if (!_connection.isConnected) {
        final connected = await _connection.connect(market.relayUrl ?? AppConfig.defaultRelayUrl);
        if (!connected) {
          _isSyncing = false;
          return 0;
        }
      }

      // Synchroniser les followers
      try {
        final user = await _storageService.getUser();
        if (user != null) {
          final subscriptionId = 'followers_sync_${DateTime.now().millisecondsSinceEpoch}';
          final followers = <String>{};
          
          _connection.registerHandler(subscriptionId, (message) {
            if (message[0] == 'EVENT' && message.length >= 3) {
              final event = message[2] as Map<String, dynamic>;
              followers.add(event['pubkey'].toString());
            }
          });

          final request = jsonEncode([
            'REQ',
            subscriptionId,
            {
              'kinds': [3],
              '#p': [user.npub],
            }
          ]);
          
          _connection.sendMessage(request);
          
          await Future.delayed(const Duration(seconds: 3));
          _connection.removeHandler(subscriptionId);
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          
          await _storageService.saveFollowersBatch(followers.toList());
          Logger.info('NostrMarket', '${followers.length} followers synchronisés');
        }
      } catch (e) {
        Logger.error('NostrMarket', 'Erreur sync followers', e);
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

      final lastSyncDate = await _storageService.getLastP3Sync();
      final since = lastSyncDate != null ? lastSyncDate.millisecondsSinceEpoch ~/ 1000 : null;
      
      final subscriptionId = await subscribeToMarket(market.name, since: since);
      
      if (subscriptionId == null) {
        _isSyncing = false;
        return 0;
      }

      final estimatedSize = market.merchantCount ?? 100;
      final timeoutSeconds = (15 + (estimatedSize ~/ 10)).clamp(15, 60);
      final timeout = Duration(seconds: timeoutSeconds);
      
      Logger.info('NostrMarket',
          'Sync démarrée avec timeout de secours de ${timeout.inSeconds}s');

      Timer? fallbackTimer;
      
      void finishSync() async {
        fallbackTimer?.cancel();
        _connection.removeHandler(subscriptionId);
        _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
        
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
        
        if (!completer.isCompleted) {
          completer.complete(syncedCount);
        }
      }

      _connection.registerHandler(subscriptionId, (message) {
        if (message[0] == 'EOSE') {
          Logger.info('NostrMarket', 'EOSE reçu pour la sync');
          finishSync();
        }
      });

      fallbackTimer = Timer(timeout, () {
        Logger.warn('NostrMarket', 'Timeout de secours atteint pour la sync');
        finishSync();
      });

      final result = await completer.future;
      fallbackTimer?.cancel();
      return result;
    } finally {
      _isSyncing = false;
    }
  }
  
  Future<void> handleP3Event(Map<String, dynamic> event) async {
    try {
      if (event['kind'] == 1) {
        await _handleKind1Event(event);
        return;
      }

      if (event['kind'] != 30303) return;

      final calculatedId = NostrUtils.calculateEventId(event);
      if (event['id'] != calculatedId) {
        Logger.error('NostrMarket', 'Event ID falsifié rejeté');
        return;
      }

      if (!_cryptoService.verifySignature(calculatedId, event['sig'], event['pubkey'])) {
        Logger.error('NostrMarket', 'Signature invalide détectée et rejetée');
        return;
      }

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
              // Rétrocompatibilité pour les anciens bons qui n'ont pas le tag 'bon_id'
              if (bonId == null && tag[1].toString().startsWith('zen-')) {
                final dTagValue = tag[1].toString().substring(4);
                // On s'assure qu'on ne prend pas les nouveaux tags anti-clonage
                if (!dTagValue.startsWith('du-') && !dTagValue.startsWith('bootstrap-')) {
                  bonId = dTagValue;
                }
              }
              break;
            case 'bon_id':
              bonId = tag[1].toString(); // ✅ Source de vérité pour l'ID du bon
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
            case 'expiration':
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

      String? pictureUrl;
      String? bannerUrl;
      String? picture64;
      String? banner64;
      try {
        final content = event['content'];
        if (content != null && content is String) {
          final contentJson = jsonDecode(content);
          
          pictureUrl = contentJson['picture'] as String?;
          
          bannerUrl = contentJson['banner'] as String?;
          
          picture64 = contentJson['picture64'] as String?;
          banner64 = contentJson['banner64'] as String?;
        }
      } catch (e) {
        Logger.error('NostrMarket', 'Erreur parsing content bon', e);
      }

      final bonData = {
        'bonId': bonId, // Note: attention si le D tag a changé.
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
        'picture64': picture64,
        'banner64': banner64,
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
  
  Future<void> _handleKind1Event(Map<String, dynamic> event) async {
    try {
      final tags = event['tags'] as List;
      String? bonId;
      String? toNpub;
      String? fromNpub;
      String? marketTag;
      double value = 0.0;

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          if (tag[0] == 'bon' && tag.length > 1) {
            bonId = tag[1].toString();
          } else if (tag[0] == 'p' && tag.length > 1) {
            toNpub = tag[1].toString();
          } else if (tag[0] == 'from_npub' && tag.length > 1) {
            fromNpub = tag[1].toString();
          } else if (tag[0] == 't' && tag.length > 1) {
            marketTag = tag[1].toString();
          } else if (tag[0] == 'value' && tag.length > 1) {
            value = double.tryParse(tag[1].toString()) ?? 0.0;
          }
        }
      }

      if (bonId == null || toNpub == null || fromNpub == null) return;

      final transferData = {
        'event_id': event['id'],
        'bon_id': bonId,
        'from_npub': fromNpub,
        'to_npub': toNpub,
        'value': value,
        'timestamp': event['created_at'],
        'market_tag': marketTag,
      };

      await _storageService.saveMarketTransfer(transferData);
    } catch (e) {
      Logger.error('NostrMarket', 'Erreur traitement kind 1', e);
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
        // Logique laissée vide dans l'original
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
          // Logique laissée vide dans l'original
        }
      });
    }
  }
  
  void dispose() {
    disableAutoSync();
  }
  
}