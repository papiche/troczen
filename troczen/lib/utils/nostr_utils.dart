import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';

class NostrUtils {
  /// Calcule l'ID d'un événement Nostr selon la NIP-01
  static String calculateEventId(Map<String, dynamic> event) {
    final serialized = jsonEncode([
      0,
      event['pubkey'],
      event['created_at'],
      event['kind'],
      event['tags'],
      event['content'],
    ]);

    final hash = sha256.convert(utf8.encode(serialized));
    return HEX.encode(hash.bytes);
  }

  /// Normalise un nom de marché pour l'utiliser comme tag Nostr
  static String normalizeMarketTag(String marketName) {
    final normalized = marketName.runes.map((r) {
      final char = String.fromCharCode(r);
      if (char.codeUnitAt(0) > 127) {
        return removeDiacritics(char);
      }
      return char;
    }).join();
    
    final lower = normalized.toLowerCase();
    final sanitized = lower.replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final cleaned = sanitized.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    
    return 'market_$cleaned';
  }

  /// Supprime les diacritiques d'un caractère
  static String removeDiacritics(String char) {
    const diacriticsMap = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
      'œ': 'oe', 'æ': 'ae',
      'À': 'a', 'Â': 'a', 'Ä': 'a', 'Á': 'a', 'Ã': 'a', 'Å': 'a',
      'È': 'e', 'É': 'e', 'Ê': 'e', 'Ë': 'e',
      'Ì': 'i', 'Í': 'i', 'Î': 'i', 'Ï': 'i',
      'Ò': 'o', 'Ó': 'o', 'Ô': 'o', 'Ö': 'o', 'Õ': 'o',
      'Ù': 'u', 'Ú': 'u', 'Û': 'u', 'Ü': 'u',
      'Ç': 'c', 'Ñ': 'n',
      'Œ': 'oe', 'Æ': 'ae',
    };
    
    return diacriticsMap[char] ?? char.toLowerCase();
  }
}
