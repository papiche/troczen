import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'logger_service.dart';

/// Service de gestion de la connexion WebSocket Nostr
/// Responsabilité unique: Connexion, reconnexion, cycle de vie
class NostrConnectionService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
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
  
  // Callbacks
  Function(bool connected)? onConnectionChange;
  Function(String error)? onError;
  Function(dynamic message)? onMessage;
  
  // Getters publics
  bool get isConnected => _isConnected;
  String? get currentRelay => _currentRelayUrl;
  bool get isAppInBackground => _isAppInBackground;
  int get reconnectAttempts => _reconnectAttempts;
  Map<String, Function(List<dynamic>)> get subscriptionHandlers => _subscriptionHandlers;
  
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
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          onConnectionChange?.call(false);
          if (!_isAppInBackground) {
            _scheduleReconnect();
          }
        },
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      onConnectionChange?.call(true);
      Logger.log('NostrConnection', 'Connecté à $relayUrl');
      return true;
    } catch (e) {
      _isConnected = false;
      onError?.call('Connexion impossible: $e');
      onConnectionChange?.call(false);
      _scheduleReconnect();
      return false;
    }
  }

  /// Déconnexion du relais
  Future<void> disconnect() async {
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
    Logger.log('NostrConnection', 'Déconnecté');
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
      
      // Notifier le callback global
      onMessage?.call(message);
      
      // Gestion spéciale des messages système
      switch (messageType) {
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
      }
    } catch (e) {
      onError?.call('Erreur parsing message: $e');
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
    disconnect();
  }
  
  // ============================================================
  // RECONNEXION AUTOMATIQUE AVEC BACKOFF EXPONENTIEL
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
