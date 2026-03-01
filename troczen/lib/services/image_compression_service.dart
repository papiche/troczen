import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'logger_service.dart';

class ImageResult {
  final String originalPath;
  final String base64DataUri;
  
  ImageResult({required this.originalPath, required this.base64DataUri});
}

/// ✅ v2.0.2: Service de compression d'images pour Nostr
/// 
/// Compresse les images en JPEG ultra-léger (< 4 Ko) pour les
/// encoder en Base64 directement dans les événements Nostr (Kind 0).
/// 
/// Cela permet un fonctionnement 100% offline sans API Flask.
/// 
/// Spécifications:
/// - Format: JPEG (compression efficace)
/// - Taille max: 80x80 pixels pour avatar/logo
/// - Taille max: 200x100 pixels pour bannière
/// - Poids max: 4 Ko (4096 bytes) encodé Base64
class ImageCompressionService {
  static const int maxAvatarSize = 80;        // Carré: 80x80 pixels
  static const int maxBannerWidth = 400;      // 400 pixels de large
  static const int maxBannerHeight = 200;     // 200 pixels de haut (Ratio 2:1)
  static const int maxEncodedSize = 4096;     // 4 Ko max en Base64
  
  final ImagePicker _picker = ImagePicker();
  
  /// Sélectionne une image, garde l'original et génère une miniature Base64
  Future<ImageResult?> pickAvatarWithOriginal() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image == null) return null;
      
      final originalBytes = await image.readAsBytes();
      final decodedImage = img.decodeImage(originalBytes);
      
      if (decodedImage == null) return null;
      
      // 1. Calculer les dimensions pour forcer un crop au ratio 2:1 (Paysage)
      int targetWidth = decodedImage.width;
      int targetHeight = decodedImage.height;
      
      if (targetWidth < targetHeight * 2) {
        // L'image est trop verticale (portrait ou carrée) -> on coupe en haut et en bas
        targetHeight = targetWidth ~/ 2;
      } else {
        // L'image est trop panoramique -> on coupe sur les côtés
        targetWidth = targetHeight * 2;
      }
      
      int offsetX = (decodedImage.width - targetWidth) ~/ 2;
      int offsetY = (decodedImage.height - targetHeight) ~/ 2;
      
      // 2. Recadrer l'image originale au centre
      img.Image croppedImage = img.copyCrop(
        decodedImage,
        x: offsetX,
        y: offsetY,
        width: targetWidth,
        height: targetHeight,
      );
      
      // 3. Redimensionner à la taille max de la bannière (400x200)
      img.Image resizedImage = img.copyResize(
        croppedImage,
        width: maxBannerWidth,
        height: maxBannerHeight,
        // Plus besoin de maintainAspect car on a déjà le ratio parfait
      );
      
      final compressedBytes = await _compressToTargetSize(resizedImage, maxEncodedSize);
      final base64Uri = _encodeAsDataUri(compressedBytes);
      
      return ImageResult(
        originalPath: image.path,
        base64DataUri: base64Uri,
      );
    } catch (e) {
      Logger.error('ImageCompressionService', 'Erreur sélection avatar avec original', e);
      return null;
    }
  }

  /// Sélectionne une bannière, garde l'original et génère une miniature Base64
  Future<ImageResult?> pickBannerWithOriginal() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image == null) return null;
      
      final originalBytes = await image.readAsBytes();
      final decodedImage = img.decodeImage(originalBytes);
      
      if (decodedImage == null) return null;
      
      img.Image resizedImage = img.copyResize(
        decodedImage,
        width: maxBannerWidth,
        height: maxBannerHeight,
        maintainAspect: true,
      );
      
      final compressedBytes = await _compressToTargetSize(resizedImage, maxEncodedSize);
      final base64Uri = _encodeAsDataUri(compressedBytes);
      
      return ImageResult(
        originalPath: image.path,
        base64DataUri: base64Uri,
      );
    } catch (e) {
      Logger.error('ImageCompressionService', 'Erreur sélection bannière avec original', e);
      return null;
    }
  }

  /// Sélectionne et compresse une image depuis la galerie
  /// Retourne une chaîne data URI (data:image/jpeg;base64,...)
  Future<String?> pickAndCompressAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxAvatarSize.toDouble(),
        maxHeight: maxAvatarSize.toDouble(),
      );
      
      if (image == null) return null;
      
      var bytes = await image.readAsBytes();
      
      if (bytes.length > maxEncodedSize) {
        final decodedImage = img.decodeImage(bytes);
        if (decodedImage == null) return null;

        bytes = await _compressToTargetSize(decodedImage, maxEncodedSize);
      }
      
      return _encodeAsDataUri(bytes);
    } catch (e) {
      Logger.error('ImageCompressionService', 'Erreur sélection avatar', e);
      return null;
    }
  }
  
  /// Sélectionne et compresse une bannière depuis la galerie
  /// Retourne une chaîne data URI (data:image/jpeg;base64,...)
  Future<String?> pickAndCompressBanner() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        // On demande une haute résolution initiale pour avoir de la matière à recadrer
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image == null) return null;
      
      final originalBytes = await image.readAsBytes();
      final decodedImage = img.decodeImage(originalBytes);
      
      if (decodedImage == null) return null;

      // 1. Calculer les dimensions pour forcer un crop au ratio 2:1 (Paysage)
      int targetWidth = decodedImage.width;
      int targetHeight = decodedImage.height;
      
      if (targetWidth < targetHeight * 2) {
        // L'image est trop verticale (portrait ou carrée) -> on coupe en haut et en bas
        targetHeight = targetWidth ~/ 2;
      } else {
        // L'image est trop panoramique -> on coupe sur les côtés
        targetWidth = targetHeight * 2;
      }
      
      int offsetX = (decodedImage.width - targetWidth) ~/ 2;
      int offsetY = (decodedImage.height - targetHeight) ~/ 2;
      
      // 2. Recadrer l'image originale au centre
      img.Image croppedImage = img.copyCrop(
        decodedImage,
        x: offsetX,
        y: offsetY,
        width: targetWidth,
        height: targetHeight,
      );
      
      // 3. Redimensionner à la taille max de la bannière (400x200)
      img.Image resizedImage = img.copyResize(
        croppedImage,
        width: maxBannerWidth,
        height: maxBannerHeight,
        // Plus besoin de maintainAspect car on a déjà le ratio parfait
      );
      
      // 4. Compresser pour s'assurer qu'on reste sous la limite des 4 Ko
      final compressedBytes = await _compressToTargetSize(resizedImage, maxEncodedSize);
      
      return _encodeAsDataUri(compressedBytes);
    } catch (e) {
      Logger.error('ImageCompressionService', 'Erreur sélection bannière', e);
      return null;
    }
  }
  
  Future<Uint8List> _compressToTargetSize(img.Image image, int maxBytes) async {
    int currentQuality = 80;
    List<int> compressedBytes = img.encodeJpg(image, quality: currentQuality);

    // 1. Boucle de compression dynamique (baisse de qualité)
    while (compressedBytes.length > maxBytes && currentQuality > 10) {
      currentQuality -= 10;
      compressedBytes = img.encodeJpg(image, quality: currentQuality);
    }

    // 2. Sécurité finale si c'est toujours trop lourd (baisse de résolution)
    if (compressedBytes.length > maxBytes) {
      Logger.log('ImageCompressionService', 'Image toujours > ${maxBytes ~/ 1024}Ko. Réduction des dimensions.');
      final smallerImage = img.copyResize(
        image, 
        width: image.width ~/ 2, 
        height: image.height ~/ 2,
        maintainAspect: true,
      );
      compressedBytes = img.encodeJpg(smallerImage, quality: 30);
    }

    return Uint8List.fromList(compressedBytes);
  }

  /// Encode les bytes en data URI Base64
  String _encodeAsDataUri(Uint8List bytes) {
    final base64 = base64Encode(bytes);
    return 'data:image/jpeg;base64,$base64';
  }
  
  /// Vérifie si une chaîne est un data URI Base64
  static bool isBase64DataUri(String? uri) {
    if (uri == null || uri.isEmpty) return false;
    // Permet d'accepter potentiellement du webp si jamais ça évolue un jour
    return uri.startsWith('data:image/');
  }
  
  /// Extrait les bytes d'un data URI Base64
  static Uint8List? extractBytesFromDataUri(String dataUri) {
    try {
      if (!isBase64DataUri(dataUri)) return null;
      
      // Format: data:image/jpeg;base64,xxxxx
      final base64Start = dataUri.indexOf(',') + 1;
      if (base64Start == 0) return null;
      
      final base64String = dataUri.substring(base64Start);
      return base64Decode(base64String);
    } catch (e) {
      Logger.error('ImageCompressionService', 'Erreur extraction Base64', e);
      return null;
    }
  }
  
  /// Crée un widget Image depuis un data URI ou une URL
  static Widget buildImage({
    required String? uri,
    String? fallbackUri,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
    BorderRadius? borderRadius,
  }) {
    if (uri == null || uri.isEmpty) {
      if (fallbackUri != null && fallbackUri.isNotEmpty) {
        return buildImage(
          uri: fallbackUri,
          width: width,
          height: height,
          fit: fit,
          placeholder: placeholder,
          errorWidget: errorWidget,
          borderRadius: borderRadius,
        );
      }
      return errorWidget ?? _buildDefaultPlaceholder(width, height);
    }
    
    Widget imageWidget;
    
    if (isBase64DataUri(uri)) {
      // Image Base64
      final bytes = extractBytesFromDataUri(uri);
      if (bytes == null) {
        if (fallbackUri != null && fallbackUri.isNotEmpty) {
          return buildImage(
            uri: fallbackUri,
            width: width,
            height: height,
            fit: fit,
            placeholder: placeholder,
            errorWidget: errorWidget,
            borderRadius: borderRadius,
          );
        }
        return errorWidget ?? _buildDefaultPlaceholder(width, height);
      }
      imageWidget = Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) {
          if (fallbackUri != null && fallbackUri.isNotEmpty) {
            return buildImage(
              uri: fallbackUri,
              width: width,
              height: height,
              fit: fit,
              placeholder: placeholder,
              errorWidget: errorWidget,
              borderRadius: borderRadius,
            );
          }
          return errorWidget ?? _buildDefaultPlaceholder(width, height);
        },
      );
    } else {
      // URL distante
      imageWidget = Image.network(
        uri,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) {
          if (fallbackUri != null && fallbackUri.isNotEmpty) {
            return buildImage(
              uri: fallbackUri,
              width: width,
              height: height,
              fit: fit,
              placeholder: placeholder,
              errorWidget: errorWidget,
              borderRadius: borderRadius,
            );
          }
          return errorWidget ?? _buildDefaultPlaceholder(width, height);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder ?? _buildDefaultPlaceholder(width, height);
        },
      );
    }
    
    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: imageWidget,
      );
    }
    
    return imageWidget;
  }
  
  static Widget _buildDefaultPlaceholder(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[800],
      child: Icon(
        Icons.store,
        color: Colors.orange[700],
        size: (width != null && height != null) 
            ? (width < height ? width : height) * 0.5 
            : 24,
      ),
    );
  }
}