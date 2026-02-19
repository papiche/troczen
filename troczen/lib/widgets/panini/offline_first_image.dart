import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/bon_extensions.dart';

/// Widget d'image avec support offline-first.
/// 
/// Priorise l'utilisation d'images locales en cache,
/// avec fallback sur CachedNetworkImage pour le réseau.
/// 
/// Exemple d'utilisation:
/// ```dart
/// OfflineFirstImage(
///   url: bon.logoUrl,
///   localPath: localLogoPath,
///   width: 60,
///   height: 60,
///   color: color,
///   rarity: bon.rarity,
///   isPending: bon.status == BonStatus.pending,
/// )
/// ```
class OfflineFirstImage extends StatelessWidget {
  final String? url;
  final String? localPath;
  final double width;
  final double height;
  final Color color;
  final String? rarity;
  final bool isPending;
  final BoxFit fit;
  final bool isChecking;

  const OfflineFirstImage({
    super.key,
    required this.url,
    required this.localPath,
    required this.width,
    required this.height,
    required this.color,
    required this.rarity,
    required this.isPending,
    this.fit = BoxFit.cover,
    this.isChecking = false,
  });

  @override
  Widget build(BuildContext context) {
    // Si on est encore en train de vérifier le cache, afficher le loader
    if (isChecking) {
      return _buildLoadingPlaceholder();
    }
    
    // OFFLINE-FIRST: Si l'image est disponible localement, l'utiliser directement
    if (localPath != null && _localFileExists(localPath)) {
      return Image.file(
        File(localPath!),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          // En cas d'erreur de lecture locale, fallback sur le réseau
          return _buildNetworkImage();
        },
      );
    }
    
    // Sinon, utiliser CachedNetworkImage (avec son propre cache)
    return _buildNetworkImage();
  }

  bool _localFileExists(String? path) {
    if (path == null) return false;
    return File(path).existsSync();
  }

  Widget _buildLoadingPlaceholder() {
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

  Widget _buildNetworkImage() {
    if (url == null || url!.isEmpty) {
      return _buildDefaultIcon();
    }
    
    return CachedNetworkImage(
      imageUrl: url!,
      width: width,
      height: height,
      fit: fit,
      memCacheHeight: (height * 2).toInt(),
      memCacheWidth: (width * 2).toInt(),
      maxHeightDiskCache: (height * 4).toInt(),
      maxWidthDiskCache: (width * 4).toInt(),
      placeholder: (context, url) => _buildLoadingPlaceholder(),
      errorWidget: (context, url, error) => _buildDefaultIcon(),
    );
  }

  Widget _buildDefaultIcon() {
    return Icon(
      RarityHelper.getDefaultIcon(rarity),
      size: width * 0.8,
      color: color.withValues(alpha: isPending ? 0.3 : 1.0),
    );
  }
}
