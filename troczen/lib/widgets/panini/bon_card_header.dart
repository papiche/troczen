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

  /// Vérifie si le bon appartient au Marché Libre (seed à zéro)
  /// Dans ce cas, on affiche l'équivalence 1 ẐEN ≈ 0.1 Ğ1
  bool _isGlobalMarket(String marketName) {
    final upperName = marketName.toUpperCase();
    return upperName == 'MARCHÉ LIBRE' ||
           upperName == 'MARCHÉ GLOBAL G1' ||
           upperName == 'HACKATHON';
  }

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${bon.value.toStringAsFixed(0)} ẐEN',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              // Afficher l'équivalence Ğ1 si c'est le Marché Global
              if (_isGlobalMarket(bon.marketName))
                Text(
                  '≈ ${(bon.value * 0.1).toStringAsFixed(2)} Ğ1',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[600],
                  ),
                ),
              if (bon.duAtCreation != null)
                Row(
                  children: [
                    Icon(Icons.trending_down, size: 12, color: Colors.red[400]),
                    const SizedBox(width: 2),
                    Text(
                      '${bon.getRelativeValue(10.0).toStringAsFixed(2)} DU', // 10.0 est le DU actuel simulé
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[400],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
