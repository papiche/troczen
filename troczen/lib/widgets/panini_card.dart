import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/bon.dart';

class PaniniCard extends StatefulWidget {
  final Bon bon;
  final VoidCallback? onTap;
  final bool showActions;

  const PaniniCard({
    Key? key,
    required this.bon,
    this.onTap,
    this.showActions = true,
  }) : super(key: key);

  @override
  State<PaniniCard> createState() => _PaniniCardState();
}

class _PaniniCardState extends State<PaniniCard> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  bool _showDetails = false; // Pour afficher/masquer les détails

  @override
  void initState() {
    super.initState();
    // Animation shimmer pour les bons rares
    if (widget.bon.isRare) {
      _shimmerController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 3),
      )..repeat();
    } else {
      _shimmerController = AnimationController(vsync: this);
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.bon.color != null
        ? Color(widget.bon.color!)
        : _getColorByStatus(widget.bon.status);
    
    final isActive = widget.bon.status == BonStatus.active && !widget.bon.isExpired;
    final hasP2 = widget.bon.p2 != null && widget.bon.p2!.isNotEmpty;
    final hasP1 = widget.bon.p1 != null && widget.bon.p1!.isNotEmpty;
    final isPending = widget.bon.status == BonStatus.pending;
    final isRare = widget.bon.isRare;
    final rarity = widget.bon.rarity ?? 'common';

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          return Container(
            height: 220,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: isRare 
                      ? _getRarityColor(rarity).withOpacity(0.4)
                      : Colors.black.withOpacity(0.1),
                  blurRadius: isRare ? 30 : 20,
                  spreadRadius: isRare ? 3 : 0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  // Fond de carte
                  Container(
                    decoration: BoxDecoration(
                      gradient: _getCardGradient(color, rarity),
                      border: Border.all(
                        color: isRare ? _getRarityColor(rarity) : Colors.white,
                        width: isRare ? 3 : 8,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  // Effet holographique pour bons rares
                  if (isRare)
                    Positioned.fill(
                      child: Transform.rotate(
                        angle: _shimmerController.value * 2 * math.pi,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withOpacity(0.0),
                                Colors.white.withOpacity(0.3),
                                Colors.white.withOpacity(0.0),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Contenu principal
                  Column(
                    children: [
                      // En-tête avec badge rareté
                      Container(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _getIconByStatus(widget.bon.status),
                                  color: color,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getStatusText(widget.bon.status),
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (isRare) ...[
                                  const SizedBox(width: 8),
                                  _buildRarityBadge(rarity),
                                ],
                              ],
                            ),
                            Text(
                              '${widget.bon.value.toStringAsFixed(0)} ẐEN',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Corps de la carte
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: color.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Logo ou image du commerçant
                              if (widget.bon.logoUrl != null && widget.bon.logoUrl!.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    widget.bon.logoUrl!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        _getDefaultIcon(rarity),
                                        size: 48,
                                        color: color.withOpacity(isPending ? 0.3 : 1.0),
                                      );
                                    },
                                  ),
                                )
                              else
                                Icon(
                                  _getDefaultIcon(rarity),
                                  size: 48,
                                  color: color.withOpacity(isPending ? 0.3 : 1.0),
                                ),
                              const SizedBox(height: 8),
                              
                              // Nom de l'émetteur
                              Text(
                                widget.bon.issuerName,
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                                textAlign: TextAlign.center,
                              ),

                              // Compteur de passages (si disponible)
                              if (widget.bon.transferCount != null && widget.bon.transferCount! > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.swap_horiz, size: 12, color: Colors.blue),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${widget.bon.transferCount} passages',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Pied de carte
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.bon.marketName.toUpperCase(),
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
                                  'Émis le ${_formatDate(widget.bon.createdAt)}',
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                if (widget.bon.isExpired)
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Badge de rareté
  Widget _buildRarityBadge(String rarity) {
    final rarityData = _getRarityData(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: rarityData['colors'],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _getRarityColor(rarity).withOpacity(0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(rarityData['icon'], size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            rarityData['label'],
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

  // Gradient selon rareté
  Gradient _getCardGradient(Color baseColor, String rarity) {
    if (widget.bon.isExpired) {
      return LinearGradient(
        colors: [
          Colors.grey.withOpacity(0.1),
          Colors.grey.withOpacity(0.05),
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
            baseColor.withOpacity(0.05),
          ],
        );
    }
  }

  Map<String, dynamic> _getRarityData(String rarity) {
    switch (rarity) {
      case 'legendary':
        return {
          'label': 'LÉGENDAIRE',
          'icon': Icons.auto_awesome,
          'colors': [Colors.amber, Colors.orange],
        };
      case 'rare':
        return {
          'label': 'RARE',
          'icon': Icons.star,
          'colors': [Colors.purple, Colors.blue],
        };
      case 'uncommon':
        return {
          'label': 'PEU COMMUN',
          'icon': Icons.local_fire_department,
          'colors': [Colors.green, Colors.teal],
        };
      default:
        return {
          'label': 'COMMUN',
          'icon': Icons.circle,
          'colors': [Colors.grey, Colors.grey],
        };
    }
  }

  Color _getRarityColor(String rarity) {
    switch (rarity) {
      case 'legendary':
        return Colors.amber;
      case 'rare':
        return Colors.purple;
      case 'uncommon':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getDefaultIcon(String rarity) {
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

  Color _getColorByStatus(BonStatus status) {
    switch (status) {
      case BonStatus.active:
        return const Color(0xFFFFB347); // Jaune miel
      case BonStatus.pending:
        return Colors.grey;
      case BonStatus.spent:
        return Colors.green;
      case BonStatus.expired:
        return Colors.orange;
      case BonStatus.burned:
        return Colors.red;
      default:
        return const Color(0xFFFFB347);
    }
  }

  IconData _getIconByStatus(BonStatus status) {
    switch (status) {
      case BonStatus.active:
        return Icons.verified;
      case BonStatus.pending:
        return Icons.hourglass_empty;
      case BonStatus.spent:
        return Icons.check_circle;
      case BonStatus.expired:
        return Icons.warning;
      case BonStatus.burned:
        return Icons.delete;
      default:
        return Icons.verified;
    }
  }

  String _getStatusText(BonStatus status) {
    switch (status) {
      case BonStatus.issued:
        return 'Créé';
      case BonStatus.pending:
        return 'En attente';
      case BonStatus.active:
        return 'Actif';
      case BonStatus.spent:
        return 'Dépensé';
      case BonStatus.expired:
        return 'Expiré';
      case BonStatus.burned:
        return 'Détruit';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildStat(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        Text(value, style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        )),
        Text(label, style: const TextStyle(
          color: Colors.grey,
          fontSize: 10,
        )),
      ],
    );
  }
}
