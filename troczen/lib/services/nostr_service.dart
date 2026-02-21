import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:flutter/foundation.dart';
import '../models/market.dart';
import '../models/nostr_profile.dart';
import 'crypto_service.dart';
import 'storage_service.dart';
import 'image_cache_service.dart';
import 'logger_service.dart';
import 'du_calculation_service.dart';

/// ✅ NIP-12: Normalise un nom de marché en tag de routage standardisé
/// Cette fonction garantit que tous les marchés sont indexables de la même façon
/// par tous les relais Nostr (Strfry, etc.)
///
/// Exemples:
/// - "Marché de Paris" → "market_marche_de_paris"
/// - "ZEN-Lyon" → "market_zen_lyon"
/// - "Café du Coin" → "market_cafe_du_coin"
String normalizeMarketTag(String marketName) {
  // 1. Normalisation NFKD pour séparer les accents de leurs lettres
  final normalized = marketName.runes.map((r) {
    final char = String.fromCharCode(r);
    // Décomposer les caractères accentués
    if (char.codeUnitAt(0) > 127) {
      // Caractère non-ASCII, on garde seulement la base
      // Ex: 'é' → 'e', 'à' → 'a'
      return _removeDiacritics(char);
    }
    return char;
  }).join();
  
  // 2. Convertir en minuscules
  final lower = normalized.toLowerCase();
  
  // 3. Remplacer tout ce qui n'est pas alphanumérique par underscore
  final sanitized = lower.replaceAll(RegExp(r'[^a-z0-9]'), '_');
  
  // 4. Supprimer les underscores multiples et enlever les extrémités
  final cleaned = sanitized.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  
  // 5. Préfixer avec "market_"
  return 'market_$cleaned';
}

/// Retire les diacritiques d'un caractère (accents, etc.)
String _removeDiacritics(String char) {
  // Mapping manuel des caractères accentués courants vers leur base
  const diacriticsMap = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
    'œ': 'oe', 'æ': 'ae',
    // Majuscules
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

/// Service de publication et synchronisation via Nostr
/// Gère la publication des P3 (kind 30303) et la synchronisation
///
/// ✅ CORRECTIONS:
/// - Gestion du cycle de vie du Timer (arrêt en arrière-plan)
/// - Reconnexion automatique WebSocket avec backoff exponentiel
/// - Conformité NIP-24 pour les tags d'activité
class NostrService {
  final CryptoService _cryptoService;
  final StorageService _storageService;
  final ImageCacheService _imageCache = ImageCacheService();
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  String? _currentRelayUrl;
  
  // ✅ CORRECTION: Map pour routage interne des handlers temporaires
  // Évite l'erreur "Stream has already been listened to" en utilisant un seul listen()
  final Map<String, Function(List<dynamic>)> _subscriptionHandlers = {};
  
  // ✅ Sync automatique en arrière-plan
  Timer? _backgroundSyncTimer;
  bool _autoSyncEnabled = false;
  Duration _autoSyncInterval = const Duration(minutes: 5);
  Market? _lastSyncedMarket;
  
  // ✅ NOUVEAU: Gestion de l'état de l'application (arrière-plan/ premier plan)
  bool _isAppInBackground = false;
  
  // ✅ NOUVEAU: Reconnexion automatique
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);

  // ✅ Getters publics pour les tests
  bool get autoSyncEnabled => _autoSyncEnabled;
  Market? get lastSyncedMarket => _lastSyncedMarket;
  bool get isAppInBackground => _isAppInBackground;
  int get reconnectAttempts => _reconnectAttempts;
  
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
          // ✅ NOUVEAU: Tenter reconnexion automatique
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          onConnectionChange?.call(false);
          // ✅ NOUVEAU: Tenter reconnexion automatique si pas en arrière-plan
          if (!_isAppInBackground) {
            _scheduleReconnect();
          }
        },
      );

      _isConnected = true;
      _reconnectAttempts = 0; // ✅ Reset du compteur de reconnexion
      onConnectionChange?.call(true);
      return true;
    } catch (e) {
      _isConnected = false;
      onError?.call('Connexion impossible: $e');
      onConnectionChange?.call(false);
      // ✅ NOUVEAU: Tenter reconnexion automatique
      _scheduleReconnect();
      return false;
    }
  }

  /// Déconnexion du relais
  Future<void> disconnect() async {
    // ✅ NOUVEAU: Annuler le timer de reconnexion
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
    _isConnected = false;
    _currentRelayUrl = null;
    onConnectionChange?.call(false);
  }
  
  // ============================================================
  // ✅ NOUVEAU: GESTION DU CYCLE DE VIE DE L'APPLICATION
  // ============================================================
  
  /// Appelé quand l'application passe en arrière-plan
  /// Arrête le timer de sync pour éviter les fuites mémoire
  void onAppPaused() {
    _isAppInBackground = true;
    Logger.log('NostrService', 'Application en arrière-plan - pause sync');
    
    // Suspendre le timer de sync automatique
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
    
    // Annuler les tentatives de reconnexion en arrière-plan
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
  
  /// Appelé quand l'application revient au premier plan
  /// Redémarre le timer de sync si nécessaire
  void onAppResumed() {
    _isAppInBackground = false;
    Logger.log('NostrService', 'Application au premier plan - reprise sync');
    
    // Redémarrer le timer de sync si auto-sync était activé
    if (_autoSyncEnabled && _backgroundSyncTimer == null) {
      _backgroundSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
        if (_isConnected && _lastSyncedMarket != null && !_isAppInBackground) {
          _doBackgroundSync();
        }
      });
    }
    
    // Tenter de se reconnecter si on était connecté
    if (_currentRelayUrl != null && !_isConnected) {
      connect(_currentRelayUrl!);
    }
  }
  
  /// Appelé quand l'application est détruite
  /// Nettoie toutes les ressources
  void dispose() {
    disableAutoSync();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    disconnect();
  }
  
  // ============================================================
  // ✅ NOUVEAU: RECONNEXION AUTOMATIQUE AVEC BACKOFF EXPONENTIEL
  // ============================================================
  
  /// Planifie une tentative de reconnexion avec backoff exponentiel
  void _scheduleReconnect() {
    // Ne pas reconnecter si en arrière-plan ou max tentatives atteint
    if (_isAppInBackground || _reconnectAttempts >= _maxReconnectAttempts) {
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        onError?.call('Max tentatives de reconnexion atteint');
      }
      return;
    }
    
    _reconnectTimer?.cancel();
    
    // Calcul du délai avec backoff exponentiel
    final delay = Duration(
      milliseconds: (_baseReconnectDelay.inMilliseconds *
          (1 << _reconnectAttempts)).clamp(
        _baseReconnectDelay.inMilliseconds,
        _maxReconnectDelay.inMilliseconds,
      ),
    );
    
    _reconnectAttempts++;
    Logger.log('NostrService',
        'Reconnexion planifiée dans ${delay.inSeconds}s (tentative $_reconnectAttempts/$_maxReconnectAttempts)');
    
    _reconnectTimer = Timer(delay, () async {
      if (_currentRelayUrl != null && !_isAppInBackground) {
        Logger.log('NostrService', 'Tentative de reconnexion...');
        final success = await connect(_currentRelayUrl!);
        if (success) {
          Logger.log('NostrService', 'Reconnexion réussie');
          // Relancer la sync si un marché était en cours
          if (_lastSyncedMarket != null) {
            syncMarketP3s(_lastSyncedMarket!);
          }
        }
      }
    });
  }
  
  /// Force une reconnexion immédiate (reset le compteur de backoff)
  Future<bool> forceReconnect() async {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    if (_currentRelayUrl != null) {
      return await connect(_currentRelayUrl!);
    }
    return false;
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
    String? wish,
  }) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    try {
      // 1. Chiffrer P3 avec K_day (clé du jour dérivée de la graine)
      final now = DateTime.now();
      final p3Encrypted = await _cryptoService.encryptP3WithSeed(p3Hex, seedMarket, now);

      // 2. ✅ SÉCURITÉ: Reconstruire sk_B ÉPHÉMÈRE (P2+P3) directement en Uint8List
      // Convertir les String en Uint8List pour éviter les String en RAM
      final p2Bytes = Uint8List.fromList(HEX.decode(p2Hex));
      final p3Bytes = Uint8List.fromList(HEX.decode(p3Hex));
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);

      // 3. Créer l'event Nostr avec tags optimisés pour dashboard
      final expiry = now.add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000;
      
      final event = {
        'kind': 30303,
        'pubkey': bonId,  // ✅ Clé publique du BON (pas l'émetteur)
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['d', 'zen-$bonId'],
          ['t', normalizeMarketTag(marketName)],  // ✅ NIP-12: Tag 't' normalisé pour indexation
          ['market', marketName],  // Gardé pour affichage UI (joli nom)
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

      // 4. Calculer l'ID de l'event
      final eventId = _calculateEventId(event);
      event['id'] = eventId;

      // 5. ✅ SÉCURITÉ: Signer avec la clé privée du bon (Uint8List)
      final signature = _cryptoService.signMessageBytes(eventId, nsecBonBytes);
      event['sig'] = signature;
      
      // ✅ SÉCURITÉ: Nettoyage explicite RAM avec Uint8List
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

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
  ///
  /// NIP-24 Compliant: Les tags d'activité sont ajoutés de deux façons:
  /// 1. Dans le contenu JSON (pour les clients NIP-24)
  /// 2. Comme tags 't' de l'event (pour la recherche/filtrage NIP-12)
  ///
  /// Cela assure une interopérabilité maximale avec l'écosystème Nostr.
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
    List<String>? tags,  // ✅ Tags d'activité/centres d'intérêt (NIP-24)
    String? activity,    // ✅ Activité professionnelle (NIP-24 extended)
    String? profession,  // ✅ Métier (NIP-24 extended)
  }) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    try {
      // ✅ Créer le profil avec tous les champs NIP-24
      final profile = NostrProfile(
        npub: npub,
        name: name,
        displayName: displayName,
        about: about,
        picture: picture,
        banner: banner,
        website: website,
        g1pub: g1pub,
        tags: tags,           // ✅ Tags dans le contenu JSON
        activity: activity,   // ✅ NIP-24 extended
        profession: profession,
      );

      // ✅ NIP-12/NIP-24: Construire les tags 't' pour l'event
      // Les tags 't' permettent la recherche et le filtrage par les clients
      final nostrTags = <List<String>>[];
      
      // Ajouter les tags d'activité/centres d'intérêt
      if (tags != null && tags.isNotEmpty) {
        for (final tag in tags) {
          // ✅ NIP-12: Les tags 't' doivent être en minuscules pour la recherche
          final normalizedTag = tag.toLowerCase().trim();
          if (normalizedTag.isNotEmpty) {
            nostrTags.add(['t', normalizedTag]);
          }
        }
      }
      
      // ✅ Ajouter l'activité comme tag si présente
      if (activity != null && activity.trim().isNotEmpty) {
        nostrTags.add(['t', activity.toLowerCase().trim()]);
      }
      
      // ✅ Ajouter la profession comme tag si présente
      if (profession != null && profession.trim().isNotEmpty) {
        nostrTags.add(['t', profession.toLowerCase().trim()]);
      }

      final event = {
        'kind': NostrConstants.kindMetadata,
        'pubkey': npub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': nostrTags,  // ✅ NIP-12: Tags pour recherche/filtrage
        'content': jsonEncode(profile.toJson()),  // ✅ NIP-24: Contenu JSON complet
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;

      final signature = _cryptoService.signMessage(eventId, nsec);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      _channel!.sink.add(message);
      
      Logger.log('NostrService',
          'Profil publié avec ${nostrTags.length} tags (NIP-24 compliant)');

      return true;
    } catch (e) {
      onError?.call('Erreur publication profil: $e');
      return false;
    }
  }

  /// ✅ RÉCUPÉRER HISTORIQUE DES TRANSFERTS D'UN BON (kind 1)
  /// ✅ CORRECTION: Utilise le système de routage interne au lieu de stream.listen()
  Future<List<Map<String, dynamic>>> fetchBonTransfers(String bonId) async {
    if (!_isConnected) {
      Logger.error('NostrService', 'Non connecté au relais');
      return [];
    }

    try {
      final completer = Completer<List<Map<String, dynamic>>>();
      final transfers = <Map<String, dynamic>>[];
      
      final subscriptionId = 'transfers_${DateTime.now().millisecondsSinceEpoch}';
      
      // ✅ CORRECTION: Enregistrer le handler temporaire dans la map
      _subscriptionHandlers[subscriptionId] = (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
            final event = message[2] as Map<String, dynamic>;
            transfers.add(event);
          } else if (message[0] == 'EOSE') {
            _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
            _subscriptionHandlers.remove(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(transfers);
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing transfers response', e);
        }
      };

      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'kinds': [NostrConstants.kindText],
          '#bon': [bonId],
        }
      ]);
      
      _channel?.sink.add(request);
      
      Timer(const Duration(seconds: 5), () {
        _subscriptionHandlers.remove(subscriptionId);
        if (!completer.isCompleted) {
          _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(transfers);
        }
      });
      
      return await completer.future;
    } catch (e) {
      Logger.error('NostrService', 'Erreur récupération transferts', e);
      return [];
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
      // ✅ SÉCURITÉ: Reconstruire sk_B ÉPHÉMÈRE directement en Uint8List
      // Convertir les String en Uint8List pour éviter les String en RAM
      final p2Bytes = Uint8List.fromList(HEX.decode(bonP2));
      final p3Bytes = Uint8List.fromList(HEX.decode(bonP3));
      final nsecBonBytes = _cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);

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
          ['t', normalizeMarketTag(marketName)],  // ✅ NIP-12: Tag 't' normalisé pour indexation
          ['market', marketName],  // Gardé pour affichage UI (joli nom)
          ['bon', bonId],
          ['value', value.toString()],
        ],
        'content': jsonEncode(content),
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;

      // ✅ SÉCURITÉ: Signature avec Uint8List
      final signature = _cryptoService.signMessageBytes(eventId, nsecBonBytes);
      event['sig'] = signature;
      
      // ✅ SÉCURITÉ: Nettoyage explicite RAM avec Uint8List
      _cryptoService.secureZeroiseBytes(nsecBonBytes);
      _cryptoService.secureZeroiseBytes(p2Bytes);
      _cryptoService.secureZeroiseBytes(p3Bytes);

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
  /// ⚠️ NOTE: Utilise une String immuable qui reste en mémoire.
  /// Préférez publishBurnBytes() pour une meilleure sécurité mémoire.
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
          ['t', normalizeMarketTag(marketName)],  // ✅ NIP-12: Tag 't' normalisé pour indexation
          ['market', marketName],  // Gardé pour affichage UI (joli nom)
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

  /// ✅ SÉCURITÉ: Publie un event BURN (kind 5) avec Uint8List
  /// Version sécurisée qui permet le nettoyage mémoire de la clé privée.
  Future<bool> publishBurnBytes({
    required String bonId,
    required Uint8List nsecBonBytes,  // sk_B reconstruit temporairement avec P1+P3
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
          ['t', normalizeMarketTag(marketName)],  // ✅ NIP-12: Tag 't' normalisé pour indexation
          ['market', marketName],  // Gardé pour affichage UI (joli nom)
          ['reason', reason],
        ],
        'content': 'BURN | $reason',
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;

      // ✅ SÉCURITÉ: Signer avec Uint8List
      final signature = _cryptoService.signMessageBytes(eventId, nsecBonBytes);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      _channel!.sink.add(message);

      return true;
    } catch (e) {
      onError?.call('Erreur publication burn: $e');
      return false;
    }
  }

  /// S'abonne aux events kind 30303 d'un marché unique
  Future<void> subscribeToMarket(String marketName, {int? since}) async {
    await subscribeToMarkets([marketName], since: since);
  }

  /// ✅ NOUVEAU: S'abonne aux events kind 30303 de plusieurs marchés
  /// Nostr supporte les tableaux pour les requêtes de tags
  Future<void> subscribeToMarkets(List<String> marketNames, {int? since}) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
      return;
    }

    if (marketNames.isEmpty) {
      Logger.warn('NostrService', 'Aucun marché à surveiller');
      return;
    }

    // Créer un ID d'abonnement unique basé sur les marchés
    final subscriptionId = 'zen-multi-${marketNames.length}';
    
    // ✅ NIP-12: Utiliser le tag 't' pour le filtrage (les relais n'indexent pas les tags personnalisés)
    final marketTags = marketNames.map((m) => normalizeMarketTag(m)).toList();
    
    final filters = <String, dynamic>{
      'kinds': [30303],
      '#t': marketTags,  // ✅ NIP-12: Tag 't' indexé par tous les relais
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
    Logger.log('NostrService', 'Abonné à ${marketNames.length} marché(s): ${marketNames.join(", ")}');
  }

  /// ✅ UI/UX: Synchronise tous les P3 d'un marché avec insertion en lot
  /// Utilise un batch pour éviter les freezes de l'UI lors de la synchronisation massive
  /// Au lieu de N écritures I/O individuelles, on fait une seule écriture à la fin
  Future<int> syncMarketP3s(Market market) async {
    if (!_isConnected) {
      final connected = await connect(market.relayUrl ?? NostrConstants.defaultRelay);
      if (!connected) return 0;
    }

    int syncedCount = 0;
    final completer = Completer<int>();
    
    // ✅ UI/UX: Buffer pour accumulation des P3 avant insertion en lot
    final Map<String, String> p3Batch = {};
    const int batchSize = 50; // Écrire toutes les 50 P3 ou à la fin
    
    // ✅ UI/UX: Fonction pour écrire le batch de P3
    Future<void> flushBatch() async {
      if (p3Batch.isNotEmpty) {
        final batchToWrite = Map<String, String>.from(p3Batch);
        p3Batch.clear();
        await _storageService.saveP3BatchToCache(batchToWrite);
        Logger.log('NostrService', 'Batch de ${batchToWrite.length} P3 sauvegardé');
      }
    }

    final originalCallback = onP3Received;
    onP3Received = (bonId, p3Hex) async {
      // ✅ UI/UX: Accumuler dans le batch au lieu d'écrire immédiatement
      p3Batch[bonId] = p3Hex;
      syncedCount++;
      originalCallback?.call(bonId, p3Hex);
      
      // Écrire le batch si taille atteinte
      if (p3Batch.length >= batchSize) {
        await flushBatch();
      }
    };

    await subscribeToMarket(market.name);

    // ✅ UI/UX: Timer avec flush final du batch
    Timer(const Duration(seconds: 5), () async {
      // Flush final des P3 restants
      await flushBatch();
      
      onP3Received = originalCallback;
      
      // ✅ NOUVEAU: Vérifier et générer le DU après la synchronisation
      try {
        final duService = DuCalculationService(
          storageService: _storageService,
          nostrService: this,
          cryptoService: _cryptoService,
        );
        await duService.checkAndGenerateDU();
      } catch (e) {
        Logger.error('NostrService', 'Erreur lors de la vérification du DU', e);
      }
      
      completer.complete(syncedCount);
    });

    return completer.future;
  }

  /// ✅ NOUVEAU: Synchronise les P3 de plusieurs marchés en parallèle
  /// Utilise un abonnement unique avec filtre multi-marchés
  Future<int> syncMarketsP3s(List<Market> markets) async {
    if (markets.isEmpty) return 0;
    
    // Utiliser le relay du premier marché (ou défaut)
    final relayUrl = markets.first.relayUrl ?? NostrConstants.defaultRelay;
    
    if (!_isConnected) {
      final connected = await connect(relayUrl);
      if (!connected) return 0;
    }

    int syncedCount = 0;
    final completer = Completer<int>();
    
    // Buffer pour accumulation des P3
    final Map<String, String> p3Batch = {};
    const int batchSize = 50;
    
    Future<void> flushBatch() async {
      if (p3Batch.isNotEmpty) {
        final batchToWrite = Map<String, String>.from(p3Batch);
        p3Batch.clear();
        await _storageService.saveP3BatchToCache(batchToWrite);
        Logger.log('NostrService', 'Batch de ${batchToWrite.length} P3 sauvegardé');
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

    // ✅ S'abonner à tous les marchés en une seule requête
    final marketNames = markets.map((m) => m.name).toList();
    await subscribeToMarkets(marketNames);

    // Timer avec flush final
    Timer(const Duration(seconds: 8), () async {
      await flushBatch();
      
      onP3Received = originalCallback;
      
      // ✅ NOUVEAU: Vérifier et générer le DU après la synchronisation
      try {
        final duService = DuCalculationService(
          storageService: _storageService,
          nostrService: this,
          cryptoService: _cryptoService,
        );
        await duService.checkAndGenerateDU();
      } catch (e) {
        Logger.error('NostrService', 'Erreur lors de la vérification du DU', e);
      }
      
      completer.complete(syncedCount);
    });

    return completer.future;
  }

  /// Gère les messages reçus du relais
  /// ✅ CORRECTION: Route les messages vers les handlers temporaires enregistrés
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data);
      
      if (message is! List || message.isEmpty) return;

      final messageType = message[0];
      final subscriptionId = message.length > 1 ? message[1] as String? : null;

      // ✅ CORRECTION: D'abord router vers les handlers temporaires si présents
      if (subscriptionId != null && _subscriptionHandlers.containsKey(subscriptionId)) {
        _subscriptionHandlers[subscriptionId]!(message);
        // Ne pas return ici car on veut aussi traiter les events globaux
      }

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
          // ✅ CORRECTION: Nettoyer le handler temporaire si présent
          if (subscriptionId != null && _subscriptionHandlers.containsKey(subscriptionId)) {
            // Le handler temporaire a déjà été appelé ci-dessus
            // On peut optionnellement le supprimer ici si nécessaire
          }
          break;
      }
    } catch (e) {
      onError?.call('Erreur parsing message: $e');
    }
  }

  /// Traite un event Nostr reçu (Kind 30303 - Bons)
  /// ✅ CORRECTION: Extrait et stocke les métadonnées complètes pour le Dashboard économique
  void _handleEvent(Map<String, dynamic> event) async {
    try {
      if (event['kind'] != 30303) return;

      final tags = event['tags'] as List;
      String? bonId;
      String? p3Cipher;
      String? p3Nonce;
      String? marketName;
      // ✅ NOUVEAU: Extraire toutes les métadonnées économiques
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
        Logger.warn('NostrService', 'Event kind 30303 rejeté: tag obligatoire manquant (bonId=$bonId)');
        return;
      }

      // ✅ MULTI-MARCHÉS: Chercher le marché correspondant dans la liste configurée
      final markets = await _storageService.getMarkets();
      
      // ✅ ANTI-SPAM: Ignorer silencieusement les événements des marchés inconnus
      // Ne PAS lancer d'exception pour éviter un déluge de Snackbars d'erreur
      Market? targetMarket;
      for (final m in markets) {
        if (m.name == marketName) {
          targetMarket = m;
          break;
        }
      }
      
      if (targetMarket == null) {
        // Marché non configuré en local -> on ignore silencieusement
        // C'est normal: l'utilisateur peut être sur un relais global avec d'autres marchés
        Logger.debug('NostrService', 'Event ignoré: marché "$marketName" non configuré en local');
        return;
      }

      // Calculer la clé du jour à partir de la graine du marché
      // On utilise la date de l'event (timestamp) pour déchiffrer
      final eventTimestamp = event['created_at'] as int;
      final eventDate = DateTime.fromMillisecondsSinceEpoch(eventTimestamp * 1000);
      final p3Hex = await _cryptoService.decryptP3WithSeed(
        p3Cipher,
        p3Nonce,
        targetMarket.seedMarket,
        eventDate,
      );

      Logger.log('NostrService', 'Bon reçu/déchiffré: $bonId');

      // EXTRACTION ET MISE EN CACHE DES IMAGES DU BON
      String? pictureUrl;
      String? bannerUrl;
      try {
        final content = event['content'];
        if (content != null && content is String) {
          final contentJson = jsonDecode(content);
          
          // Image principale du bon (picture)
          pictureUrl = contentJson['picture'] as String?;
          if (pictureUrl != null && pictureUrl.isNotEmpty) {
            Logger.log('NostrService', 'Mise en cache image bon: $pictureUrl');
            _imageCache.getOrCacheImage(
              url: pictureUrl,
              npub: bonId,
              type: 'logo'
            );
          }
          
          // Bannière du bon
          bannerUrl = contentJson['banner'] as String?;
          if (bannerUrl != null && bannerUrl.isNotEmpty) {
            Logger.log('NostrService', 'Mise en cache bannière bon: $bannerUrl');
            _imageCache.getOrCacheImage(
              url: bannerUrl,
              npub: bonId,
              type: 'banner'
            );
          }
          
          // ✅ NOUVEAU: Extraire le nom de l'émetteur depuis le contenu
          final displayName = contentJson['display_name'] as String?;
          if (displayName != null && issuerName == null) {
            // Extraire le nom de l'émetteur du display_name (ex: "Bon 50 ẐEN" -> pas utile)
            // On garde issuerName tel quel s'il n'est pas dans le content
          }
        }
      } catch (e) {
        Logger.error('NostrService', 'Erreur parsing content bon pour images', e);
      }

      // ✅ CORRECTION: Stocker les métadonnées complètes du bon pour le Dashboard économique
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
        'status': 'active', // Par défaut, un bon nouvellement publié est actif
        'picture': pictureUrl,
        'banner': bannerUrl,
        'p3Hex': p3Hex,
        'eventTimestamp': eventTimestamp,
        'wish': wish,
      };
      
      await _storageService.saveMarketBonData(bonData);
      Logger.log('NostrService', 'Métadonnées bon stockées pour dashboard: $bonId (valeur: $value ẐEN)');

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
  
  /// ✅ v2.0.1: Récupère le profil utilisateur (Kind 0) depuis le relais
  /// Utilisé pour afficher la carte d'invitation d'un marché
  /// ✅ CORRECTION: Utilise le système de routage interne au lieu de stream.listen()
  Future<NostrProfile?> fetchUserProfile(String npub) async {
    if (!_isConnected) {
      Logger.error('NostrService', 'Non connecté au relais');
      return null;
    }
    
    try {
      final completer = Completer<NostrProfile?>();
      
      // Envoyer une requête REQ pour le Kind 0 de ce npub
      final subscriptionId = 'profile_${DateTime.now().millisecondsSinceEpoch}';
      
      // ✅ CORRECTION: Enregistrer le handler temporaire dans la map
      _subscriptionHandlers[subscriptionId] = (message) {
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
            // End of stored events - fermer le subscription
            _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
            _subscriptionHandlers.remove(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing profile response', e);
        }
      };
      
      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'authors': [npub],
          'kinds': [0],
          'limit': 1,
        }
      ]);
      
      // Envoyer la requête
      _channel?.sink.add(request);
      
      // Timeout après 5 secondes
      Timer(const Duration(seconds: 5), () {
        _subscriptionHandlers.remove(subscriptionId);
        if (!completer.isCompleted) {
          _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(null);
        }
      });
      
      return await completer.future;
    } catch (e) {
      Logger.error('NostrService', 'Erreur récupération profil', e);
      return null;
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

  /// ✅ PUBLIER LISTE DE CONTACTS (kind 3) - Follow
  Future<bool> publishContactList({
    required String npub,
    required String nsec,
    required List<String> contactsNpubs,
  }) async {
    if (!_isConnected) {
      onError?.call('Non connecté au relais');
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
      _channel!.sink.add(message);

      Logger.log('NostrService', 'Liste de contacts publiée avec ${contactsNpubs.length} contacts');
      return true;
    } catch (e) {
      onError?.call('Erreur publication contacts: $e');
      return false;
    }
  }

  /// ✅ RÉCUPÉRER LISTE DE CONTACTS (kind 3)
  /// ✅ CORRECTION: Utilise le système de routage interne au lieu de stream.listen()
  Future<List<String>> fetchContactList(String npub) async {
    if (!_isConnected) {
      Logger.error('NostrService', 'Non connecté au relais');
      return [];
    }

    try {
      final completer = Completer<List<String>>();
      final contacts = <String>[];
      
      final subscriptionId = 'contacts_${DateTime.now().millisecondsSinceEpoch}';
      
      // ✅ CORRECTION: Enregistrer le handler temporaire dans la map
      _subscriptionHandlers[subscriptionId] = (message) {
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
            _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
            _subscriptionHandlers.remove(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(contacts);
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing contacts response', e);
        }
      };

      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'authors': [npub],
          'kinds': [3],
          'limit': 1,
        }
      ]);
      
      _channel?.sink.add(request);
      
      Timer(const Duration(seconds: 5), () {
        _subscriptionHandlers.remove(subscriptionId);
        if (!completer.isCompleted) {
          _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(contacts);
        }
      });
      
      return await completer.future;
    } catch (e) {
      Logger.error('NostrService', 'Erreur récupération contacts', e);
      return [];
    }
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
      
      // ✅ CORRECTION: Enregistrer le handler temporaire dans la map
      _subscriptionHandlers[subscriptionId] = (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
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
          } else if (message[0] == 'EOSE') {
            // End of Stored Events
            _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
            _subscriptionHandlers.remove(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(extractedTags.toList()..sort());
            }
          }
        } catch (e) {
          Logger.error('NostrService', 'Erreur parsing tags response', e);
        }
      };

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
      
      // Timer pour fermer l'abonnement après un délai
      Timer(const Duration(seconds: 5), () {
        _subscriptionHandlers.remove(subscriptionId);
        if (!completer.isCompleted) {
          _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(extractedTags.toList()..sort());
        }
      });
      
      // Attendre le résultat
      final result = await completer.future;
      
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
