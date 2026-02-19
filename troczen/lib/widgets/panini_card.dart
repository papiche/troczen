import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/bon.dart';
import '../services/image_cache_service.dart';
import '../services/logger_service.dart';

class PaniniCard extends StatefulWidget {
  final Bon bon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showActions;
  final Widget? statusChip;

  const PaniniCard({
    super.key,
    required this.bon,
    this.onTap,
    this.onLongPress,
    this.showActions = true,
    this.statusChip,
  });

  @override
  State<PaniniCard> createState() => _PaniniCardState();
}

class _PaniniCardState extends State<PaniniCard> with TickerProviderStateMixin {
  late AnimationController _shimmerController;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  
  final bool _showDetails = false; // Pour afficher/masquer les détails
  
  // Offline-first: cache local des images
  final ImageCacheService _imageCacheService = ImageCacheService();
  String? _localLogoPath;
  String? _localPicturePath;
  bool _isCheckingCache = true;

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
    
    // Animation de scale pour le feedback tactile
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Vérifier le cache local pour offline-first
    _checkLocalCache();
  }

  /// Vérifie si les images sont disponibles localement (offline-first)
  Future<void> _checkLocalCache() async {
    Logger.log('PaniniCard', 'Vérification cache pour ${widget.bon.issuerName}');
    
    final List<Future<String?>> cacheChecks = [];
    
    // Vérifier le logo du commerçant
    if (widget.bon.logoUrl != null && widget.bon.logoUrl!.isNotEmpty) {
      Logger.log('PaniniCard', 'Logo URL: ${widget.bon.logoUrl}');
      cacheChecks.add(_imageCacheService.getCachedImage(widget.bon.logoUrl!));
    } else {
      cacheChecks.add(Future.value(null));
    }
    
    // Vérifier l'avatar de l'émetteur
    if (widget.bon.picture != null && widget.bon.picture!.isNotEmpty) {
      Logger.log('PaniniCard', 'Picture URL: ${widget.bon.picture}');
      cacheChecks.add(_imageCacheService.getCachedImage(widget.bon.picture!));
    } else {
      cacheChecks.add(Future.value(null));
    }
    
    final results = await Future.wait(cacheChecks);
    
    // Log résultat
    Logger.log('PaniniCard', 'Cache trouvé: Logo=${results[0] != null}, Pic=${results[1] != null}');
    
    if (mounted) {
      setState(() {
        _localLogoPath = results[0];
        _localPicturePath = results[1];
        _isCheckingCache = false;
      });
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _scaleController.dispose();
    super.dispose();
  }
  
  /// Gestion du feedback tactile
  void _handleTapDown(TapDownDetails details) {
    _scaleController.forward();
  }
  
  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
    widget.onTap?.call();
  }
  
  void _handleTapCancel() {
    _scaleController.reverse();
  }
  
  /// Widget d'image offline-first
  /// Priorise le fichier local, puis fallback sur CachedNetworkImage
  Widget _buildOfflineFirstImage({
    required String? url,
    required String? localPath,
    required double width,
    required double height,
    required Color color,
    required String rarity,
    required bool isPending,
    BoxFit fit = BoxFit.cover,
  }) {
    // Si on est encore en train de vérifier le cache, afficher le loader
    if (_isCheckingCache) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey[800],
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: color.withOpacity(0.5),
            ),
          ),
        ),
      );
    }
    
    // OFFLINE-FIRST: Si l'image est disponible localement, l'utiliser directement
    if (localPath != null) {
      final file = File(localPath);
      
      // Vérification supplémentaire que le fichier existe physiquement
      if (file.existsSync()) {
        Logger.log('PaniniCard', 'Utilisation fichier local: $localPath');
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            // En cas d'erreur de lecture locale, fallback sur le réseau
            Logger.error('PaniniCard', 'Erreur lecture fichier local: $localPath', error);
            return _buildNetworkImage(url, width, height, color, rarity, isPending, fit);
          },
        );
      } else {
        Logger.warn('PaniniCard', 'Fichier cache manquant malgré path: $localPath');
      }
    }
    
    // Sinon, utiliser CachedNetworkImage (avec son propre cache)
    Logger.log('PaniniCard', 'Utilisation réseau pour: $url');
    return _buildNetworkImage(url, width, height, color, rarity, isPending, fit);
  }
  
  /// Widget CachedNetworkImage avec fallback
  Widget _buildNetworkImage(
    String? url,
    double width,
    double height,
    Color color,
    String rarity,
    bool isPending,
    BoxFit fit,
  ) {
    if (url == null || url.isEmpty) {
      return Icon(
        _getDefaultIcon(rarity),
        size: width * 0.8,
        color: color.withOpacity(isPending ? 0.3 : 1.0),
      );
    }
    
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheHeight: (height * 2).toInt(),
      memCacheWidth: (width * 2).toInt(),
      maxHeightDiskCache: (height * 4).toInt(),
      maxWidthDiskCache: (width * 4).toInt(),
      placeholder: (context, url) => Container(
        width: width,
        height: height,
        color: Colors.grey[800],
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: color.withOpacity(0.5),
            ),
          ),
        ),
      ),
      errorWidget: (context, url, error) {
        return Icon(
          _getDefaultIcon(rarity),
          size: width * 0.8,
          color: color.withOpacity(isPending ? 0.3 : 1.0),
        );
      },
    );
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
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
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

                    // Effet holographique pour bons rares avec RepaintBoundary
                    if (isRare)
                      RepaintBoundary(
                        child: Positioned.fill(
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
                              // Logo ou image du commerçant - OFFLINE-FIRST
                              if (widget.bon.logoUrl != null && widget.bon.logoUrl!.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _buildOfflineFirstImage(
                                    url: widget.bon.logoUrl,
                                    localPath: _localLogoPath,
                                    width: 60,
                                    height: 60,
                                    color: color,
                                    rarity: rarity,
                                    isPending: isPending,
                                    fit: BoxFit.cover,
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
                  
                  // Status chip externe (optionnel, positionné en bas à gauche)
                  if (widget.statusChip != null)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: widget.statusChip!,
                    ),
                ],
              ),
            ),
          );
        },
      ),
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
