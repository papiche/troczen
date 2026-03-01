import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'logger_service.dart';

/// Service de gestion de la connexion WebSocket Nostr
/// Responsabilité unique: Connexion, reconnexion, cycle de vie
class NostrConnectionService {
  static final NostrConnectionService _instance = NostrConnectionService._internal();
  
  factory NostrConnectionService() {
    return _instance;
  }
  
  NostrConnectionService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _currentRelayUrl;
  
  // Gestion de la reconnexion avec backoff exponentiel
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  
  // Gestion du cycle de vie de l'application
  bool _isAppInBackground = false;
  
  // Routage interne des handlers temporaires
  // Évite l'erreur "Stream has already been listened to"
  final Map<String, Function(List<dynamic>)> _subscriptionHandlers = {};
  
  // Attente des acquittements (OK)
  final Map<String, Completer<bool>> _publishCompleters = {};
  
  // Streams pour remplacer les listes de callbacks manuelles (évite les fuites de mémoire)
  final _connectionChangeController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _messageController = StreamController<dynamic>.broadcast();
  
  Stream<bool> get onConnectionChange => _connectionChangeController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<dynamic> get onMessage => _messageController.stream;
  
  // Getters publics
  bool get isConnected => _isConnected;
  String? get currentRelay => _currentRelayUrl;
  bool get isAppInBackground => _isAppInBackground;
  int get reconnectAttempts => _reconnectAttempts;
  Map<String, Function(List<dynamic>)> get subscriptionHandlers => _subscriptionHandlers;
  
  /// Connexion au relais Nostr
  Future<bool> connect(String relayUrl) async {
    if (_isConnecting) {
      Logger.log('NostrConnection', 'Connexion déjà en cours vers $relayUrl');
      // Attendre que la connexion en cours se termine
      int retries = 0;
      while (_isConnecting && retries < 50) { // Max 5 secondes d'attente
        await Future.delayed(const Duration(milliseconds: 100));
        retries++;
      }
      return _isConnected && _currentRelayUrl == relayUrl;
    }

    try {
      if (_isConnected && _currentRelayUrl == relayUrl) {
        return true;
      }

      _isConnecting = true;
      await disconnect();

      final uri = Uri.parse(relayUrl);
      
      // Utiliser dart:io WebSocket pour configurer le pingInterval
      final ws = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 10));
      ws.pingInterval = const Duration(seconds: 30);
      
      _channel = IOWebSocketChannel(ws);
      _currentRelayUrl = relayUrl;

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          _isConnected = false;
          _errorController.add('Erreur WebSocket: $error');
          _connectionChangeController.add(false);
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          _connectionChangeController.add(false);
          if (!_isAppInBackground) {
            _scheduleReconnect();
          }
        },
      );

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionChangeController.add(true);
      Logger.log('NostrConnection', 'Connecté à $relayUrl');
      return true;
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      _errorController.add('Connexion impossible: $e');
      _connectionChangeController.add(false);
      _scheduleReconnect();
      return false;
    }
  }

  /// Déconnexion du relais
  Future<void> disconnect() async {
    // En mode singleton, on ne déconnecte pas vraiment sauf si forcé
    // pour éviter les connexions/déconnexions intempestives
    Logger.log('NostrConnection', 'Demande de déconnexion ignorée (mode persistant)');
  }
  
  /// Force la déconnexion réelle (utilisé lors de la fermeture de l'app)
  Future<void> forceDisconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
    _isConnected = false;
    _currentRelayUrl = null;
    if (!_connectionChangeController.isClosed) {
      _connectionChangeController.add(false);
    }
    Logger.log('NostrConnection', 'Déconnecté (forcé)');
  }
  
  /// Envoie un message au relais
  void send(String message) {
    if (!_isConnected) {
      Logger.warn('NostrConnection', 'Tentative d\'envoi sans connexion');
      return;
    }
    _channel?.sink.add(message);
  }
  
  /// Alias pour compatibilité avec les services existants
  void sendMessage(String message) => send(message);
  
  /// Envoie un événement et attend l'acquittement (OK) du relais
  Future<bool> sendEventAndWait(String eventId, String message, {Duration timeout = const Duration(seconds: 5)}) async {
    if (!_isConnected) {
      Logger.warn('NostrConnection', 'Tentative d\'envoi sans connexion');
      return false;
    }
    
    final completer = Completer<bool>();
    _publishCompleters[eventId] = completer;
    
    send(message);
    
    try {
      return await completer.future.timeout(timeout);
    } catch (e) {
      _publishCompleters.remove(eventId);
      Logger.warn('NostrConnection', 'Timeout attente OK pour event $eventId');
      return false;
    }
  }
  
  /// Gère les messages reçus du relais
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data);
      
      if (message is! List || message.isEmpty) return;

      final messageType = message[0];
      final subscriptionId = message.length > 1 ? message[1] as String? : null;

      // Router vers les handlers temporaires si présents
      if (subscriptionId != null && _subscriptionHandlers.containsKey(subscriptionId)) {
        _subscriptionHandlers[subscriptionId]!(message);
      }
      
      // Notifier les callbacks globaux
      _messageController.add(message);
      
      // Gestion spéciale des messages système
      switch (messageType) {
        case 'OK':
          final eventId = message[1];
          final success = message[2];
          
          if (_publishCompleters.containsKey(eventId)) {
            _publishCompleters[eventId]!.complete(success);
            _publishCompleters.remove(eventId);
          }
          
          if (!success) {
            final errorMsg = message.length > 3 ? message[3] : 'Erreur inconnue';
            _errorController.add('Event $eventId rejeté: $errorMsg');
          }
          break;
        case 'NOTICE':
          final notice = message[1];
          _errorController.add('Notice: $notice');
          break;
      }
    } catch (e) {
      _errorController.add('Erreur parsing message: $e');
    }
  }
  
  /// Enregistre un handler temporaire pour un subscriptionId
  void registerHandler(String subscriptionId, Function(List<dynamic>) handler) {
    _subscriptionHandlers[subscriptionId] = handler;
  }
  
  /// Supprime un handler temporaire
  void removeHandler(String subscriptionId) {
    _subscriptionHandlers.remove(subscriptionId);
  }
  
  // ============================================================
  // GESTION DU CYCLE DE VIE DE L'APPLICATION
  // ============================================================
  
  /// Appelé quand l'application passe en arrière-plan
  void onAppPaused() {
    _isAppInBackground = true;
    Logger.log('NostrConnection', 'Application en arrière-plan');
    
    // Annuler les tentatives de reconnexion en arrière-plan
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
  
  /// Appelé quand l'application revient au premier plan
  void onAppResumed() {
    _isAppInBackground = false;
    Logger.log('NostrConnection', 'Application au premier plan');
    
    // Tenter de se reconnecter si on était connecté
    if (_currentRelayUrl != null && !_isConnected) {
      connect(_currentRelayUrl!);
    }
  }
  
  /// Appelé quand l'application est détruite
  void dispose() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    forceDisconnect();
    _connectionChangeController.close();
    _errorController.close();
    _messageController.close();
  }
  
  // ============================================================
  // RECONNEXION AUTOMATIQUE AVEC BACKOFF EXPONENTIEL
  // ============================================================
  
  /// Planifie une tentative de reconnexion avec backoff exponentiel
  void _scheduleReconnect() {
    // Ne pas reconnecter si en arrière-plan ou max tentatives atteint
    if (_isAppInBackground || _reconnectAttempts >= _maxReconnectAttempts) {
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        _errorController.add('Max tentatives de reconnexion atteint');
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
    Logger.log('NostrConnection',
        'Reconnexion planifiée dans ${delay.inSeconds}s (tentative $_reconnectAttempts/$_maxReconnectAttempts)');
    
    _reconnectTimer = Timer(delay, () async {
      if (_currentRelayUrl != null && !_isAppInBackground) {
        Logger.log('NostrConnection', 'Tentative de reconnexion...');
        final success = await connect(_currentRelayUrl!);
        if (success) {
          Logger.success('NostrConnection', 'Reconnexion réussie');
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
}
