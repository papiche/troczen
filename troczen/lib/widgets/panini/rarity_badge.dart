import 'package:flutter/material.dart';
import '../../utils/bon_extensions.dart';

/// Badge affichant la rareté d'un bon avec un style visuel adapté.
/// 
/// Exemple d'utilisation:
/// ```dart
/// RarityBadge(rarity: 'legendary')
/// ```
class RarityBadge extends StatelessWidget {
  final String rarity;

  const RarityBadge({
    super.key,
    required this.rarity,
  });

  @override
  Widget build(BuildContext context) {
    final label = RarityHelper.getLabel(rarity);
    final icon = RarityHelper.getIcon(rarity);
    final gradientColors = RarityHelper.getGradientColors(rarity);
    final displayColor = RarityHelper.getColor(rarity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: displayColor.withValues(alpha: 0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
