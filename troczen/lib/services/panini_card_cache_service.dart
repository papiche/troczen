import 'dart:io';
import 'package:flutter/material.dart';
import '../models/bon.dart';
import 'image_cache_service.dart';
import 'logger_service.dart';
import 'image_memory_cache.dart';

/// Résultat du cache pour une carte Panini
class PaniniCacheResult {
  /// Chemin local de l'image mise en cache (picture selon NIP nostr)
  final String? localPicturePath;
  final bool isChecking;

  const PaniniCacheResult({
    this.localPicturePath,
    this.isChecking = true,
  });

  PaniniCacheResult copyWith({
    String? localPicturePath,
    bool? isChecking,
  }) {
    return PaniniCacheResult(
      localPicturePath: localPicturePath ?? this.localPicturePath,
      isChecking: isChecking ?? this.isChecking,
    );
  }
}

/// Service responsable de la gestion du cache des images pour les cartes Panini.
/// 
/// Ce service gère:
/// - La vérification du cache local pour les images (picture selon NIP nostr)
/// - Le chargement offline-first des images
/// - La coordination avec [ImageCacheService]
/// 
/// Note: Selon les standards NIP nostr, le champ `picture` est utilisé
/// pour l'image du profil. Il n'y a pas de distinction entre logo et avatar.
class PaniniCardCacheService extends ChangeNotifier {
  final ImageCacheService _imageCacheService;
  
  // Cache des résultats par ID de bon
  final Map<String, PaniniCacheResult> _cacheResults = {};
  
  // Set des IDs en cours de vérification
  final Set<String> _checkingIds = {};
  
  // Set des chemins de fichiers locaux existants (cache mémoire partagé)
  static final Set<String> _existingLocalFiles = {};
  static bool _isInitialized = false;
  static bool _isInitializing = false;

  PaniniCardCacheService({
    ImageCacheService? imageCacheService,
  }) : _imageCacheService = imageCacheService ?? ImageCacheService() {
    _initCache();
  }

  /// Initialise le cache en scannant le dossier image_cache
  Future<void> _initCache() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    
    try {
      final cacheDir = await _imageCacheService.getCacheDirectory();
      if (await cacheDir.exists()) {
        final files = cacheDir.listSync();
        for (var file in files) {
          if (file is File) {
            _existingLocalFiles.add(file.path);
          }
        }
      }
      _isInitialized = true;
      _isInitializing = false;
      Logger.log('PaniniCardCache', 'Cache initialisé avec ${_existingLocalFiles.length} fichiers');
      notifyListeners();
    } catch (e) {
      _isInitializing = false;
      Logger.error('PaniniCardCache', 'Erreur initialisation cache', e);
    }
  }

  /// Récupère le résultat du cache pour un bon donné.
  /// 
  /// Si le cache n'a pas encore été vérifié, déclenche la vérification
  /// en arrière-plan et retourne un résultat avec [isChecking] à true.
  PaniniCacheResult getCacheResult(Bon bon) {
    final bonId = bon.bonId;
    
    // Si déjà en cache, le retourner
    if (_cacheResults.containsKey(bonId)) {
      return _cacheResults[bonId]!;
    }
    
    // Si déjà en cours de vérification, retourner l'état checking
    if (_checkingIds.contains(bonId)) {
      return const PaniniCacheResult(isChecking: true);
    }
    
    // Déclencher la vérification
    _checkCacheForBon(bon);
    
    return const PaniniCacheResult(isChecking: true);
  }

  /// Vérifie le cache pour un bon spécifique
  Future<void> _checkCacheForBon(Bon bon) async {
    final bonId = bon.bonId;
    _checkingIds.add(bonId);
    
    Logger.log('PaniniCardCache', 'Vérification cache pour ${bon.issuerName}');
    
    // Vérifier l'image du profil (picture selon NIP nostr)
    // Note: logoUrl et picture sont la même image selon les standards NIP
    final pictureUrl = bon.picture ?? bon.logoUrl;
    String? localPath;
    
    if (pictureUrl != null && pictureUrl.isNotEmpty) {
      Logger.log('PaniniCardCache', 'Picture URL: $pictureUrl');
      localPath = await _imageCacheService.getCachedImage(pictureUrl);
      if (localPath != null) {
        addLocalFileToCache(localPath);
      }
    }
    
    Logger.log('PaniniCardCache', 'Cache trouvé: $localPath');
    
    final cacheResult = PaniniCacheResult(
      localPicturePath: localPath,
      isChecking: false,
    );
    
    _cacheResults[bonId] = cacheResult;
    _checkingIds.remove(bonId);
    
    notifyListeners();
  }

  /// Précharge les images pour un bon (appel optionnel pour optimiser)
  Future<void> precacheBon(Bon bon) async {
    await _checkCacheForBon(bon);
  }

  /// Invalide le cache pour un bon spécifique
  void invalidateCache(String bonId) {
    _cacheResults.remove(bonId);
    notifyListeners();
  }

  /// Invalide tout le cache
  void invalidateAllCache() {
    _cacheResults.clear();
    _checkingIds.clear();
    notifyListeners();
  }

  /// Vérifie si un fichier local existe physiquement (utilise le cache mémoire si possible)
  bool localFileExists(String? path) {
    if (path == null) return false;
    if (_isInitialized) {
      return _existingLocalFiles.contains(path);
    }
    return File(path).existsSync();
  }
  
  /// Ajoute un fichier au cache mémoire
  void addLocalFileToCache(String path) {
    _existingLocalFiles.add(path);
  }

  /// Construit une image offline-first avec fallback réseau
  Widget buildOfflineFirstImage({
    required String? url,
    required String? localPath,
    required double width,
    required double height,
    required Color color,
    required String rarity,
    required bool isPending,
    required IconData defaultIcon,
    BoxFit fit = BoxFit.cover,
    bool isChecking = false,
  }) {
    // Si on est encore en train de vérifier le cache, afficher le loader
    if (isChecking) {
      return _buildLoadingPlaceholder(width, height, color);
    }
    
    // OFFLINE-FIRST: Si l'image est disponible localement, l'utiliser directement
    if (localPath != null && localFileExists(localPath)) {
      Logger.log('PaniniCardCache', 'Utilisation fichier local: $localPath');
      
      // Utiliser le cache mémoire pour éviter le flicker
      final cachedImage = ImageMemoryCache.getLocal(localPath);
      if (cachedImage != null) {
        return Image(
          image: cachedImage,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            Logger.error('PaniniCardCache',
              'Erreur lecture fichier local (cache): $localPath', error);
            return _buildDefaultIcon(width, color, isPending, defaultIcon);
          },
        );
      }
      
      return Image.file(
        File(localPath),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          Logger.error('PaniniCardCache',
            'Erreur lecture fichier local: $localPath', error);
          return _buildDefaultIcon(width, color, isPending, defaultIcon);
        },
      );
    }
    
    if (localPath != null) {
      Logger.warn('PaniniCardCache', 
        'Fichier cache manquant malgré path: $localPath');
    }
    
    // Retourner l'icône par défaut
    // Le widget appelant gérera le CachedNetworkImage
    return _buildDefaultIcon(width, color, isPending, defaultIcon);
  }

  Widget _buildLoadingPlaceholder(double width, double height, Color color) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[800],
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: color.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultIcon(double width, Color color, bool isPending, IconData icon) {
    return Icon(
      icon,
      size: width * 0.8,
      color: color.withValues(alpha: isPending ? 0.3 : 1.0),
    );
  }
}
