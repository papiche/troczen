import 'package:flutter/material.dart';
import '../../models/bon.dart';
import '../../utils/bon_extensions.dart';
import 'rarity_badge.dart';

/// En-tête de la carte Panini affichant le statut, la rareté et la valeur.
/// 
/// Exemple d'utilisation:
/// ```dart
/// BonCardHeader(
///   bon: bon,
///   color: color,
/// )
/// ```
class BonCardHeader extends StatelessWidget {
  final Bon bon;
  final Color color;

  const BonCardHeader({
    super.key,
    required this.bon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isRare = bon.isRare;
    final rarity = bon.rarity ?? 'common';

    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                BonStatusHelper.getIcon(bon.status),
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                BonStatusHelper.getLabel(bon.status),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (isRare) ...[
                const SizedBox(width: 8),
                RarityBadge(rarity: rarity),
              ],
            ],
          ),
          Text(
            '${bon.value.toStringAsFixed(0)} ẐEN',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}
