import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'logger_service.dart';

/// Service API TrocZen pour upload logos uniquement
/// Toutes les opérations Nostr se font directement via le relais
class ApiService {
  // Utiliser les constantes de AppConfig
  String _currentApiUrl = AppConfig.defaultApiUrl;
  String _currentRelayUrl = AppConfig.defaultRelayUrl;
  bool _isLocal = false;

  /// Détecte automatiquement si connecté à une borne locale
  Future<bool> detectLocalNetwork() async {
    // Tester chaque URL locale
    for (final url in AppConfig.localHosts) {
      try {
        final response = await http.get(
          Uri.parse('$url/health'),
        ).timeout(AppConfig.localDetectionTimeout);

        if (response.statusCode == 200) {
          // Borne locale détectée !
          _currentApiUrl = url;
          _isLocal = true;
          
          // Extraire l'IP/host pour le relay WebSocket
          final host = Uri.parse(url).host;
          _currentRelayUrl = 'ws://$host:7777';  // Port relay local

          Logger.success('ApiService', 'Borne locale détectée: $_currentApiUrl');
          return true;
        }
      } catch (e) {
        // Timeout ou erreur - pas cette URL
        continue;
      }
    }

    // Aucune borne locale - utiliser l'API publique
    _currentApiUrl = AppConfig.defaultApiUrl;
    _currentRelayUrl = AppConfig.defaultRelayUrl;
    _isLocal = false;
    
    Logger.info('ApiService', 'Utilisation API publique: $_currentApiUrl');
    return false;
  }

  /// Vérifie le statut de l'upload IPFS pour un fichier
  ///
  /// Retourne les informations IPFS si l'upload est terminé,
  /// ou null si encore en cours ou en erreur
  Future<Map<String, dynamic>?> checkIpfsStatus(String filename) async {
    try {
      final baseUrl = _currentApiUrl.endsWith('/')
          ? _currentApiUrl.substring(0, _currentApiUrl.length - 1)
          : _currentApiUrl;
      final uri = Uri.parse('$baseUrl/api/upload/status/$filename');
      
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      Logger.error('ApiService', 'Erreur vérification statut IPFS', e);
      return null;
    }
  }

  /// Attend que l'upload IPFS soit terminé avec polling
  ///
  /// [filename] : Nom du fichier à vérifier
  /// [maxAttempts] : Nombre maximum de tentatives (défaut: 30)
  /// [delay] : Délai entre chaque tentative (défaut: 1 seconde)
  ///
  /// Retourne l'URL IPFS si disponible, sinon l'URL locale
  Future<String> waitForIpfsUrl({
    required String filename,
    required String localUrl,
    int maxAttempts = 30,
    Duration delay = const Duration(seconds: 1),
  }) async {
    for (int i = 0; i < maxAttempts; i++) {
      final status = await checkIpfsStatus(filename);
      
      if (status != null && status['ipfs_status'] == 'completed') {
        final ipfsUrl = status['ipfs_url'] as String?;
        if (ipfsUrl != null && ipfsUrl.isNotEmpty) {
          Logger.success('ApiService', 'URL IPFS obtenue: $ipfsUrl');
          return ipfsUrl;
        }
      }
      
      // Attendre avant la prochaine vérification
      await Future.delayed(delay);
    }
    
    // Timeout - retourner l'URL locale
    Logger.warn('ApiService', 'Timeout attente IPFS, utilisation URL locale');
    return localUrl;
  }

  /// Upload image (logo, bandeau, avatar) pour profils Nostr
  ///
  /// L'upload IPFS est asynchrone côté serveur. Cette méthode:
  /// 1. Uploade le fichier et obtient l'URL locale immédiatement
  /// 2. Attend l'URL IPFS avec un polling (max 30 secondes)
  /// 3. Retourne l'URL IPFS si disponible, sinon l'URL locale
  ///
  /// Préfère toujours l'URL IPFS car elle est décentralisée et permanente.
  Future<Map<String, dynamic>?> uploadImage({
    required String npub,
    required File imageFile,
    required String type,  // 'logo', 'banner', ou 'avatar'
    bool waitForIpfs = true,  // Attendre l'URL IPFS
  }) async {
    try {
      // ✅ SÉCURITÉ: Normaliser l'URL pour éviter les doubles slash
      // si _currentApiUrl se termine par '/'
      final baseUrl = _currentApiUrl.endsWith('/')
          ? _currentApiUrl.substring(0, _currentApiUrl.length - 1)
          : _currentApiUrl;
      final uri = Uri.parse('$baseUrl/api/upload/image');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['npub'] = npub;
      request.fields['type'] = type;
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        imageFile.path,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        
        // Si l'upload IPFS est en cours et qu'on doit attendre
        if (waitForIpfs && result['ipfs_status'] == 'pending') {
          final filename = result['filename'] as String?;
          final localUrl = result['local_url'] as String?;
          
          if (filename != null && localUrl != null) {
            // Attendre l'URL IPFS
            final ipfsUrl = await waitForIpfsUrl(
              filename: filename,
              localUrl: localUrl,
            );
            
            // Mettre à jour le résultat avec l'URL IPFS
            result['url'] = ipfsUrl;
            result['ipfs_url'] = ipfsUrl;
            result['storage'] = ipfsUrl.contains('ipfs') ? 'ipfs' : 'local';
            
            Logger.success('ApiService', 'Upload terminé - URL finale: $ipfsUrl');
          }
        }
        
        return result;
      } else {
        Logger.error('ApiService', 'Erreur upload: ${response.body}');
        return null;
      }
    } catch (e) {
      Logger.error('ApiService', 'Erreur upload image ($type)', e);
      return null;
    }
  }

  /// Méthode alias pour compatibilité avec l'ancien nom
  Future<Map<String, dynamic>?> uploadLogo({
    required String npub,
    required File imageFile,
  }) async {
    return uploadImage(npub: npub, imageFile: imageFile, type: 'logo');
  }

  // Getters
  String get apiUrl => _currentApiUrl;
  String get relayUrl => _currentRelayUrl;
  bool get isLocal => _isLocal;

  /// Force l'utilisation de l'API publique
  void usePublicApi() {
    _currentApiUrl = AppConfig.defaultApiUrl;
    _currentRelayUrl = AppConfig.defaultRelayUrl;
    _isLocal = false;
  }

  /// Force l'utilisation d'une URL personnalisée
  void setCustomApi(String apiUrl, String relayUrl) {
    _currentApiUrl = apiUrl;
    _currentRelayUrl = relayUrl;
    _isLocal = false;
  }

  /// Vérifie la dernière version APK disponible
  /// Retourne les informations de version ou null en cas d'erreur
  Future<Map<String, dynamic>?> checkLatestVersion() async {
    try {
      final baseUrl = _currentApiUrl.endsWith('/')
          ? _currentApiUrl.substring(0, _currentApiUrl.length - 1)
          : _currentApiUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/apk/latest'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      Logger.error('ApiService', 'Erreur vérification maj APK', e);
      return null;
    }
  }
}
