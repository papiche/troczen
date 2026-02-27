import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'logger_service.dart';

/// Service de cache d'images local pour fonctionnement hors-ligne
/// 
/// Les images téléchargées sont stockées localement avec leurs métadonnées
/// pour permettre l'affichage même sans connexion réseau
class ImageCacheService {
  static const String _cacheDir = 'image_cache';
  static const String _metadataFile = 'cache_metadata.json';
  
  /// Obtenir le répertoire de cache
  Future<Directory> getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/$_cacheDir');
    
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    
    return cacheDir;
  }

  /// Obtenir le répertoire de cache (interne)
  Future<Directory> get _getCacheDirectory async {
    return getCacheDirectory();
  }
  
  /// Obtenir le fichier de métadonnées
  Future<File> get _getMetadataFile async {
    final cacheDir = await _getCacheDirectory;
    return File('${cacheDir.path}/$_metadataFile');
  }
  
  /// Charger les métadonnées du cache
  Future<Map<String, CachedImageMetadata>> _loadMetadata() async {
    try {
      final file = await _getMetadataFile;
      
      if (!await file.exists()) {
        return {};
      }
      
      final content = await file.readAsString();
      final Map<String, dynamic> json = jsonDecode(content);
      
      return json.map(
        (key, value) => MapEntry(
          key,
          CachedImageMetadata.fromJson(value),
        ),
      );
    } catch (e) {
      Logger.error('ImageCache', 'Erreur chargement metadata cache', e);
      return {};
    }
  }
  
  /// Sauvegarder les métadonnées du cache
  Future<void> _saveMetadata(Map<String, CachedImageMetadata> metadata) async {
    try {
      final file = await _getMetadataFile;
      final json = metadata.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      Logger.error('ImageCache', 'Erreur sauvegarde metadata cache', e);
    }
  }
  
  /// Générer un nom de fichier unique basé sur l'URL
  String _generateCacheFilename(String url) {
    final bytes = utf8.encode(url);
    final hash = sha256.convert(bytes);
    final ext = url.split('.').last.split('?').first;
    return '${hash.toString()}.${ext.length <= 4 ? ext : 'jpg'}';
  }
  
  /// Convertit une URL IPFS en URL HTTP via une passerelle
  String _convertIpfsUrl(String url) {
    if (url.startsWith('ipfs://')) {
      // Extraire le CID et le chemin après ipfs://
      final ipfsPath = url.substring(7);
      // Utiliser la passerelle copylaradio ou une passerelle publique
      return 'https://ipfs.copylaradio.com/ipfs/$ipfsPath';
    }
    return url;
  }
  
  /// Télécharger et mettre en cache une image
  ///
  /// [url] : URL de l'image (IPFS ou HTTP)
  /// [npub] : Clé publique Nostr (pour association)
  /// [type] : Type d'image ('avatar', 'logo', 'banner')
  ///
  /// Retourne le chemin local de l'image en cache
  Future<String?> cacheImage({
    required String url,
    required String npub,
    required String type,
  }) async {
    Logger.log('ImageCache', 'Tentative de mise en cache: $url');
    
    try {
      // Gestion des URLs IPFS brutes (si l'API renvoie ipfs://)
      final effectiveUrl = _convertIpfsUrl(url);
      
      if (effectiveUrl != url) {
        Logger.log('ImageCache', 'URL IPFS convertie: $url -> $effectiveUrl');
      }
      
      // Télécharger l'image
      final response = await http.get(Uri.parse(effectiveUrl)).timeout(
        const Duration(seconds: 30),
      );
      
      if (response.statusCode != 200) {
        Logger.error('ImageCache', 'Échec HTTP ${response.statusCode} pour $effectiveUrl');
        return null;
      }
      
      // Obtenir le répertoire de cache
      final cacheDir = await _getCacheDirectory;
      
      // Générer le nom du fichier avec extension correcte
      final filename = _generateCacheFilename(effectiveUrl);
      final file = File('${cacheDir.path}/$filename');
      
      // Sauvegarder l'image
      await file.writeAsBytes(response.bodyBytes);
      
      // Charger les métadonnées existantes
      final metadata = await _loadMetadata();
      
      // Ajouter les nouvelles métadonnées (avec l'URL originale comme clé)
      metadata[url] = CachedImageMetadata(
        url: url,
        localPath: file.path,
        npub: npub,
        type: type,
        cachedAt: DateTime.now(),
        size: response.bodyBytes.length,
      );
      
      // Sauvegarder les métadonnées
      await _saveMetadata(metadata);
      
      Logger.success('ImageCache', 'Succès cache: ${file.path} (${response.bodyBytes.length} bytes)');
      
      return file.path;
      
    } catch (e) {
      Logger.error('ImageCache', 'Exception téléchargement pour $url', e);
      return null;
    }
  }
  
  /// Obtenir une image depuis le cache
  ///
  /// Retourne le chemin local si l'image est en cache, sinon null
  Future<String?> getCachedImage(String url) async {
    try {
      final metadata = await _loadMetadata();
      final cached = metadata[url];
      
      if (cached == null) {
        Logger.log('ImageCache', 'Pas de cache pour: $url');
        return null;
      }
      
      // Vérifier que le fichier existe toujours
      final file = File(cached.localPath);
      if (await file.exists()) {
        Logger.log('ImageCache', 'Image trouvée en cache: ${cached.localPath}');
        return cached.localPath;
      } else {
        // Fichier supprimé, nettoyer les métadonnées
        Logger.warn('ImageCache', 'Fichier cache manquant: ${cached.localPath}');
        metadata.remove(url);
        await _saveMetadata(metadata);
        return null;
      }
      
    } catch (e) {
      Logger.error('ImageCache', 'Erreur récupération cache', e);
      return null;
    }
  }
  
  /// Obtenir ou télécharger une image
  /// 
  /// Essaye d'abord de récupérer depuis le cache,
  /// sinon télécharge et met en cache
  Future<String?> getOrCacheImage({
    required String url,
    required String npub,
    required String type,
  }) async {
    // Essayer le cache d'abord
    final cached = await getCachedImage(url);
    if (cached != null) {
      return cached;
    }
    
    // Sinon, télécharger et mettre en cache
    return await cacheImage(
      url: url,
      npub: npub,
      type: type,
    );
  }
  
  /// Obtenir toutes les images en cache pour un utilisateur
  Future<List<CachedImageMetadata>> getCachedImagesForUser(String npub) async {
    try {
      final metadata = await _loadMetadata();
      return metadata.values
          .where((m) => m.npub == npub)
          .toList();
    } catch (e) {
      Logger.error('ImageCache', 'Erreur récupération images user', e);
      return [];
    }
  }
  
  /// Nettoyer le cache (supprimer les anciennes images)
  /// 
  /// [olderThanDays] : Supprimer les images plus vieilles que X jours
  Future<int> cleanCache({int olderThanDays = 30}) async {
    try {
      final metadata = await _loadMetadata();
      final now = DateTime.now();
      int deletedCount = 0;
      
      final toDelete = <String>[];
      
      for (final entry in metadata.entries) {
        final age = now.difference(entry.value.cachedAt).inDays;
        
        if (age > olderThanDays) {
          toDelete.add(entry.key);
          
          // Supprimer le fichier
          final file = File(entry.value.localPath);
          if (await file.exists()) {
            await file.delete();
            deletedCount++;
          }
        }
      }
      
      // Nettoyer les métadonnées
      for (final url in toDelete) {
        metadata.remove(url);
      }
      
      await _saveMetadata(metadata);
      
      Logger.success('ImageCache', 'Cache nettoyé: $deletedCount images supprimées');
      
      return deletedCount;
      
    } catch (e) {
      Logger.error('ImageCache', 'Erreur nettoyage cache', e);
      return 0;
    }
  }
  
  /// Obtenir les statistiques du cache
  Future<CacheStatistics> getStatistics() async {
    try {
      final metadata = await _loadMetadata();
      final cacheDir = await _getCacheDirectory;
      
      int totalSize = 0;
      for (final cached in metadata.values) {
        totalSize += cached.size;
      }
      
      return CacheStatistics(
        imageCount: metadata.length,
        totalSize: totalSize,
        cacheDirectory: cacheDir.path,
      );
      
    } catch (e) {
      debugPrint('❌ Erreur statistiques cache: $e');
      return CacheStatistics(
        imageCount: 0,
        totalSize: 0,
        cacheDirectory: '',
      );
    }
  }
  
  /// Vider complètement le cache
  Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDirectory;
      
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        await cacheDir.create(recursive: true);
      }
      
      Logger.success('ImageCache', 'Cache complètement vidé');
      
    } catch (e) {
      Logger.error('ImageCache', 'Erreur vidage cache', e);
    }
  }
}

/// Métadonnées d'une image en cache
class CachedImageMetadata {
  final String url;          // URL originale
  final String localPath;    // Chemin local
  final String npub;         // Clé publique Nostr
  final String type;         // Type d'image
  final DateTime cachedAt;   // Date de mise en cache
  final int size;            // Taille en octets
  
  CachedImageMetadata({
    required this.url,
    required this.localPath,
    required this.npub,
    required this.type,
    required this.cachedAt,
    required this.size,
  });
  
  Map<String, dynamic> toJson() => {
    'url': url,
    'localPath': localPath,
    'npub': npub,
    'type': type,
    'cachedAt': cachedAt.toIso8601String(),
    'size': size,
  };
  
  factory CachedImageMetadata.fromJson(Map<String, dynamic> json) {
    return CachedImageMetadata(
      url: json['url'],
      localPath: json['localPath'],
      npub: json['npub'],
      type: json['type'],
      cachedAt: DateTime.parse(json['cachedAt']),
      size: json['size'],
    );
  }
}

/// Statistiques du cache
class CacheStatistics {
  final int imageCount;      // Nombre d'images en cache
  final int totalSize;       // Taille totale en octets
  final String cacheDirectory; // Répertoire du cache
  
  CacheStatistics({
    required this.imageCount,
    required this.totalSize,
    required this.cacheDirectory,
  });
  
  /// Taille formatée en Mo
  String get formattedSize {
    final mb = totalSize / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB';
  }
  
  @override
  String toString() {
    return 'CacheStatistics(images: $imageCount, size: $formattedSize)';
  }
}
