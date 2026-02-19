import 'package:flutter/material.dart';
import '../models/bon.dart';

/// Extension pour les helpers de rareté des bons
extension BonRarityExtension on Bon {
  /// Retourne true si le bon est légendaire
  bool get isLegendary => rarity == 'legendary';
  
  /// Retourne true si le bon est rare
  bool get isRareType => rarity == 'rare';
  
  /// Retourne true si le bon est peu commun
  bool get isUncommon => rarity == 'uncommon';
  
  /// Retourne true si le bon est commun
  bool get isCommon => rarity == null || rarity == 'common';
}

/// Helper statique pour les données de rareté
class RarityHelper {
  static const Map<String, _RarityData> _rarityDataMap = {
    'legendary': _RarityData(
      label: 'LÉGENDAIRE',
      icon: Icons.auto_awesome,
      colors: [Colors.amber, Colors.orange],
      displayColor: Colors.amber,
    ),
    'rare': _RarityData(
      label: 'RARE',
      icon: Icons.star,
      colors: [Colors.purple, Colors.blue],
      displayColor: Colors.purple,
    ),
    'uncommon': _RarityData(
      label: 'PEU COMMUN',
      icon: Icons.local_fire_department,
      colors: [Colors.green, Colors.teal],
      displayColor: Colors.green,
    ),
    'common': _RarityData(
      label: 'COMMUN',
      icon: Icons.circle,
      colors: [Colors.grey, Colors.grey],
      displayColor: Colors.grey,
    ),
  };

  static String getLabel(String? rarity) {
    return _rarityDataMap[rarity]?.label ?? _rarityDataMap['common']!.label;
  }

  static IconData getIcon(String? rarity) {
    return _rarityDataMap[rarity]?.icon ?? _rarityDataMap['common']!.icon;
  }

  static List<Color> getGradientColors(String? rarity) {
    return _rarityDataMap[rarity]?.colors ?? _rarityDataMap['common']!.colors;
  }

  static Color getColor(String? rarity) {
    return _rarityDataMap[rarity]?.displayColor ?? Colors.grey;
  }

  static IconData getDefaultIcon(String? rarity) {
    switch (rarity) {
      case 'legendary':
        return Icons.auto_awesome;
      case 'rare':
        return Icons.star_rounded;
      case 'uncommon':
        return Icons.local_fire_department_rounded;
      default:
        return Icons.store_rounded;
    }
  }
}

class _RarityData {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final Color displayColor;

  const _RarityData({
    required this.label,
    required this.icon,
    required this.colors,
    required this.displayColor,
  });
}

/// Helper statique pour les données de statut
class BonStatusHelper {
  static const Map<BonStatus, _StatusData> _statusDataMap = {
    BonStatus.issued: _StatusData(
      label: 'Créé',
      icon: Icons.fiber_new,
      color: Color(0xFFFFB347),
    ),
    BonStatus.pending: _StatusData(
      label: 'En attente',
      icon: Icons.hourglass_empty,
      color: Colors.grey,
    ),
    BonStatus.active: _StatusData(
      label: 'Actif',
      icon: Icons.verified,
      color: Color(0xFFFFB347),
    ),
    BonStatus.spent: _StatusData(
      label: 'Dépensé',
      icon: Icons.check_circle,
      color: Colors.green,
    ),
    BonStatus.expired: _StatusData(
      label: 'Expiré',
      icon: Icons.warning,
      color: Colors.orange,
    ),
    BonStatus.burned: _StatusData(
      label: 'Détruit',
      icon: Icons.delete,
      color: Colors.red,
    ),
  };

  static String getLabel(BonStatus status) {
    return _statusDataMap[status]?.label ?? 'Inconnu';
  }

  static IconData getIcon(BonStatus status) {
    return _statusDataMap[status]?.icon ?? Icons.help_outline;
  }

  static Color getColor(BonStatus status) {
    return _statusDataMap[status]?.color ?? const Color(0xFFFFB347);
  }
}

class _StatusData {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusData({
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// Extension de formatage pour les dates
extension BonDateExtension on DateTime {
  String formatAsDate() {
    return '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';
  }
}

/// Helper pour les gradients de carte selon la rareté
class CardGradientHelper {
  static Gradient getGradient(Color baseColor, String? rarity, bool isExpired) {
    if (isExpired) {
      return LinearGradient(
        colors: [
          Colors.grey.withValues(alpha: 0.1),
          Colors.grey.withValues(alpha: 0.05),
        ],
      );
    }

    switch (rarity) {
      case 'legendary':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.amber[100]!,
            Colors.orange[100]!,
            Colors.amber[100]!,
          ],
        );
      case 'rare':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple[50]!,
            Colors.blue[50]!,
            Colors.purple[50]!,
          ],
        );
      case 'uncommon':
        return LinearGradient(
          colors: [
            Colors.green[50]!,
            Colors.teal[50]!,
          ],
        );
      default:
        return LinearGradient(
          colors: [
            Colors.white,
            baseColor.withValues(alpha: 0.05),
          ],
        );
    }
  }
}
