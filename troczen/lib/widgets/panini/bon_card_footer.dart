import 'package:flutter/material.dart';
import '../../models/bon.dart';
import '../../utils/bon_extensions.dart';

/// Pied de la carte Panini affichant le nom du marché et la date d'émission.
/// 
/// Exemple d'utilisation:
/// ```dart
/// BonCardFooter(bon: bon)
/// ```
class BonCardFooter extends StatelessWidget {
  final Bon bon;

  const BonCardFooter({
    super.key,
    required this.bon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getFooterColor(bon),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bon.marketName.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          _buildDateRow(),
        ],
      ),
    );
  }

  Color _getFooterColor(Bon bon) {
    final color = bon.color != null
        ? Color(bon.color!)
        : BonStatusHelper.getColor(bon.status);
    return color.withValues(alpha: 0.1);
  }

  Widget _buildDateRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Émis le ${bon.createdAt.formatAsDate()}',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 10,
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
        if (bon.isExpired)
          const _ExpiredBadge(),
      ],
    );
  }
}

/// Badge indiquant que le bon est expiré
class _ExpiredBadge extends StatelessWidget {
  const _ExpiredBadge();

  @override
  Widget build(BuildContext context) {
    return Text(
      'EXPIRÉ',
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 10,
        color: Colors.red[700],
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// Pied de carte avec informations étendues
class BonCardFooterExtended extends StatelessWidget {
  final Bon bon;
  final Widget? additionalInfo;

  const BonCardFooterExtended({
    super.key,
    required this.bon,
    this.additionalInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getFooterColor(bon),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bon.marketName.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Émis le ${bon.createdAt.formatAsDate()}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (bon.isExpired)
                Text(
                  'EXPIRÉ',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 10,
                    color: Colors.red[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          if (additionalInfo != null) ...[
            const SizedBox(height: 8),
            additionalInfo!,
          ],
        ],
      ),
    );
  }

  Color _getFooterColor(Bon bon) {
    final color = bon.color != null
        ? Color(bon.color!)
        : BonStatusHelper.getColor(bon.status);
    return color.withValues(alpha: 0.1);
  }
}
