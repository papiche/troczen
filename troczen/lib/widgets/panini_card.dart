/// Widget PaniniCard - Carte de collection pour les bons ẐEN.
/// 
/// Ce fichier sert de point d'entrée principal et maintient la compatibilité
/// avec le code existant. L'implémentation a été refactorisée en composants
/// plus petits dans le dossier `panini/`.
/// 
/// Architecture refactorisée:
/// - `services/panini_card_cache_service.dart` : Logique de cache des images
/// - `widgets/panini/panini_card_controller.dart` : Contrôleur ChangeNotifier
/// - `widgets/panini/bon_card_header.dart` : En-tête de la carte
/// - `widgets/panini/bon_card_body.dart` : Corps de la carte
/// - `widgets/panini/bon_card_footer.dart` : Pied de la carte
/// - `widgets/panini/rarity_badge.dart` : Badge de rareté
/// - `widgets/panini/offline_first_image.dart` : Image avec support offline-first
/// - `widgets/panini/holographic_effect.dart` : Effet holographique
/// - `utils/bon_extensions.dart` : Extensions et helpers
library;

import 'package:flutter/material.dart';
import '../models/bon.dart';
import '../services/panini_card_cache_service.dart';
import '../utils/bon_extensions.dart';
import 'panini/bon_card_header.dart';
import 'panini/bon_card_body.dart';
import 'panini/bon_card_footer.dart';
import 'panini/holographic_effect.dart';
import 'panini/panini_card_controller.dart';

/// Carte Panini pour l'affichage des bons ẐEN.
/// 
/// Cette carte affiche un bon sous forme de carte de collection
/// avec des effets visuels basés sur la rareté.
/// 
/// Utilise [PaniniCardController] pour la gestion de l'état avec ChangeNotifier.
/// 
/// Exemple d'utilisation:
/// ```dart
/// PaniniCard(
///   bon: monBon,
///   onTap: () => Navigator.push(...),
///   onLongPress: () => showDetails(),
///   statusChip: Chip(label: Text('Nouveau')),
/// )
/// ```
class PaniniCard extends StatefulWidget {
  final Bon bon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showActions;
  final Widget? statusChip;
  final PaniniCardCacheService? cacheService;

  const PaniniCard({
    super.key,
    required this.bon,
    this.onTap,
    this.onLongPress,
    this.showActions = true,
    this.statusChip,
    this.cacheService,
  });

  @override
  State<PaniniCard> createState() => PaniniCardState();
}

/// État public de PaniniCard pour permettre l'accès externe si nécessaire
class PaniniCardState extends State<PaniniCard> with TickerProviderStateMixin {
  late AnimationController _shimmerController;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  
  /// Contrôleur pour la gestion de l'état avec ChangeNotifier
  late PaniniCardController _controller;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initController();
  }

  void _initAnimations() {
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
  }

  void _initController() {
    _controller = PaniniCardController(
      bon: widget.bon,
      cacheService: widget.cacheService,
    )..initialize();
  }

  @override
  void didUpdateWidget(PaniniCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bon.bonId != widget.bon.bonId) {
      // Recréer le contrôleur si le bon a changé
      _controller.dispose();
      _initController();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _scaleController.dispose();
    _controller.dispose();
    super.dispose();
  }
  
  /// Gestion du feedback tactile
  void _handleTapDown(TapDownDetails details) {
    _scaleController.forward();
    _controller.onTapDown();
  }
  
  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
    _controller.onTapUp();
    widget.onTap?.call();
  }
  
  void _handleTapCancel() {
    _scaleController.reverse();
    _controller.onTapCancel();
  }

  Color get _cardColor {
    return widget.bon.color != null
        ? Color(widget.bon.color!)
        : BonStatusHelper.getColor(widget.bon.status);
  }

  @override
  Widget build(BuildContext context) {
    final color = _cardColor;
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
            return _buildCardContainer(color, isRare, rarity);
          },
        ),
      ),
    );
  }

  Widget _buildCardContainer(Color color, bool isRare, String rarity) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final state = _controller.state;
        
        return Container(
          height: 220,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: _buildCardDecoration(isRare, rarity),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Fond de carte
                _buildCardBackground(color, rarity),
                
                // Effet holographique pour bons rares
                if (isRare)
                  HolographicEffect(animation: _shimmerController),

                // Contenu principal
                Column(
                  children: [
                    BonCardHeader(bon: widget.bon, color: color),
                    BonCardBodyWithTransfers(
                      bon: widget.bon,
                      color: color,
                      localPicturePath: state.cacheResult.localPicturePath,
                      isCheckingCache: state.cacheResult.isChecking,
                    ),
                    BonCardFooter(bon: widget.bon),
                  ],
                ),

                // Status chip externe (optionnel)
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
    );
  }

  BoxDecoration _buildCardDecoration(bool isRare, String rarity) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: isRare
              ? RarityHelper.getColor(rarity).withValues(alpha: 0.4)
              : Colors.black.withValues(alpha: 0.1),
          blurRadius: isRare ? 30 : 20,
          spreadRadius: isRare ? 3 : 0,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _buildCardBackground(Color color, String rarity) {
    return Container(
      decoration: BoxDecoration(
        gradient: CardGradientHelper.getGradient(color, rarity, widget.bon.isExpired),
        border: Border.all(
          color: widget.bon.isRare 
              ? RarityHelper.getColor(rarity) 
              : Colors.white,
          width: widget.bon.isRare ? 3 : 8,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
