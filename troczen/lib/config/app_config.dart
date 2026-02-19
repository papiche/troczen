/// Configuration centrale de l'application TrocZen
/// Contient toutes les constantes et paramètres globaux
class AppConfig {
  // ==================== VERSION ====================
  /// Version de l'application (doit correspondre à pubspec.yaml)
  static const String appVersion = '1.0.9';
  
  /// Nom de l'application
  static const String appName = 'TrocZen';
  
  // ==================== FEATURE FLAGS ====================
  /// Active/désactive les fonctionnalités NFC expérimentales
  /// NFC est encore en phase de développement/test
  static const bool nfcEnabled = false;
  
  /// Message affiché quand NFC n'est pas disponible
  static const String nfcUnavailableMessage = 'NFC bientôt disponible';
  
  // ==================== API & RELAY ====================
  /// URL de l'API de production
  static const String defaultApiUrl = 'https://zen.copylaradio.com';
  
  /// URL du relais Nostr de production
  static const String defaultRelayUrl = 'wss://relay.copylaradio.com';
  
  /// URLs locales (borne wifi/portail captif)
  static const String localApiUrl = 'http://zen.local:5000';
  static const String localRelayUrl = 'ws://zen.local:7777';
  static const String localIPFSgw = 'ws://zen.local:8080';
  
  static const List<String> localHosts = [
    'http://192.168.101.1:5000',  // AP direct
    'http://10.0.0.1:5000',       // Routeur standard
    'http://zen.local:5000',      // mDNS
  ];
  
  // ==================== DÉLAIS & TIMEOUTS ====================
  /// Timeout par défaut pour les opérations réseau
  static const Duration networkTimeout = Duration(seconds: 30);
  
  /// Timeout pour la détection réseau local
  static const Duration localDetectionTimeout = Duration(seconds: 2);
  
  /// Durée d'expiration d'un échange (swap)
  static const Duration swapTimeout = Duration(minutes: 2);
  
  /// Intervalle de synchronisation automatique Nostr
  static const Duration autoSyncInterval = Duration(minutes: 5);
  
  // ==================== USER AGENT ====================
  /// User Agent pour les requêtes API
  static String get userAgent => 'TrocZen/$appVersion (Flutter)';
  
  // ==================== LIENS ====================
  /// URL du dépôt GitHub
  static const String githubUrl = 'https://github.com/papiche/troczen';
  
  // ==================== EMPREINTES DIGITALES ====================
  /// Empreinte du keystore de signature APK
  static const String apkSignatureFingerprint = '';
  
  // Constructeur privé pour empêcher l'instanciation
  AppConfig._();
}
