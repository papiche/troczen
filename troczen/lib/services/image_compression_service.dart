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

/// ✅ v2.0.1: Service de compression d'images pour Nostr
/// 
/// Compresse les images en JPEG ultra-léger (< 4 Ko) pour les
/// encoder en Base64 directement dans les événements Nostr (Kind 0).
/// 
/// Cela permet un fonctionnement 100% offline sans API Flask.
/// 
/// Spécifications:
/// - Format: JPEG (compression efficace)
/// - Taille max: 50x50 pixels pour avatar/logo
/// - Taille max: 150x50 pixels pour bannière
/// - Poids max: 4 Ko (4096 bytes) encodé Base64
class ImageCompressionService {
  static const int maxAvatarSize = 50;        // 50x50 pixels
  static const int maxBannerWidth = 150;      // 150 pixels de large
  static const int maxBannerHeight = 50;      // 50 pixels de haut
  static const int maxEncodedSize = 4096;     // 4 Ko max en Base64
  
  final ImagePicker _picker = ImagePicker();
  
  /// Sélectionne une image, garde l'original et génère une miniature Base64
  Future<ImageResult?> pickAvatarWithOriginal() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      
      if (image == null) return null;
      
      final originalBytes = await image.readAsBytes();
      final decodedImage = img.decodeImage(originalBytes);
      
      if (decodedImage == null) return null;
      
      final resizedImage = img.copyResize(
        decodedImage,
        width: maxAvatarSize,
        height: maxAvatarSize,
        maintainAspect: true,
      );
      
      final compressedBytes = img.encodeJpg(resizedImage, quality: 70);
      final base64Uri = _encodeAsDataUri(Uint8List.fromList(compressedBytes));
      
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
      );
      
      if (image == null) return null;
      
      final originalBytes = await image.readAsBytes();
      final decodedImage = img.decodeImage(originalBytes);
      
      if (decodedImage == null) return null;
      
      final resizedImage = img.copyResize(
        decodedImage,
        width: maxBannerWidth,
        height: maxBannerHeight,
        maintainAspect: true,
      );
      
      final compressedBytes = img.encodeJpg(resizedImage, quality: 70);
      final base64Uri = _encodeAsDataUri(Uint8List.fromList(compressedBytes));
      
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
        imageQuality: 70,  // Qualité JPEG 70%
      );
      
      if (image == null) return null;
      
      final bytes = await image.readAsBytes();
      
      // Vérifier la taille
      if (bytes.length > maxEncodedSize) {
        // Si encore trop grand, on retourne quand même
        // car image_picker a déjà fait la compression
        Logger.log('ImageCompressionService', 
            'Attention: image avatar > 4 Ko: ${bytes.length} bytes');
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
        maxWidth: maxBannerWidth.toDouble(),
        maxHeight: maxBannerHeight.toDouble(),
        imageQuality: 70,  // Qualité JPEG 70%
      );
      
      if (image == null) return null;
      
      final bytes = await image.readAsBytes();
      
      // Vérifier la taille
      if (bytes.length > maxEncodedSize) {
        Logger.log('ImageCompressionService', 
            'Attention: image bannière > 4 Ko: ${bytes.length} bytes');
      }
      
      return _encodeAsDataUri(bytes);
    } catch (e) {
      Logger.error('ImageCompressionService', 'Erreur sélection bannière', e);
      return null;
    }
  }
  
  /// Encode les bytes en data URI Base64
  String _encodeAsDataUri(Uint8List bytes) {
    final base64 = base64Encode(bytes);
    return 'data:image/jpeg;base64,$base64';
  }
  
  /// Vérifie si une chaîne est un data URI Base64
  static bool isBase64DataUri(String? uri) {
    if (uri == null || uri.isEmpty) return false;
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
