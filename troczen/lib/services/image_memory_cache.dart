import 'dart:io';
import 'package:flutter/material.dart';
import 'package:troczen/services/image_compression_service.dart';

/// Service de cache mémoire pour les images décodées depuis du Base64.
/// Évite de redécoder le Base64 à chaque reconstruction de widget (zéro saccade).
class ImageMemoryCache {
  // On stocke l'ImageProvider déjà créé pour ne pas relancer le décodage
  static final Map<String, ImageProvider> _cache = {};

  /// Récupère une image depuis le cache ou la décode et la met en cache.
  /// [bonId] sert de clé de cache (peut être l'URL ou un ID unique).
  /// [base64String] est la chaîne Base64 à décoder si non présente en cache.
  static ImageProvider? get(String? bonId, String? base64String) {
    if (bonId == null || base64String == null) return null;
    
    // Si déjà décodé, on le rend instantanément
    if (_cache.containsKey(bonId)) return _cache[bonId];

    // Sinon, on décode et on stocke
    try {
      final bytes = ImageCompressionService.extractBytesFromDataUri(base64String);
      if (bytes != null) {
        final provider = MemoryImage(bytes);
        _cache[bonId] = provider;
        return provider;
      }
    } catch (e) {
      debugPrint("Erreur décodage cache: $e");
    }
    return null;
  }

  /// Récupère une image locale depuis le cache ou la charge et la met en cache.
  /// [path] est le chemin local du fichier.
  static ImageProvider? getLocal(String? path) {
    if (path == null) return null;
    
    if (_cache.containsKey(path)) return _cache[path];

    try {
      final provider = FileImage(File(path));
      _cache[path] = provider;
      return provider;
    } catch (e) {
      debugPrint("Erreur chargement image locale cache: $e");
    }
    return null;
  }

  /// Vide le cache mémoire (utile en cas de pression mémoire)
  static void clear() {
    _cache.clear();
  }
}
