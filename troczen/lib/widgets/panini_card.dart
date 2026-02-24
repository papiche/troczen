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

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/bon.dart';
import '../services/panini_card_cache_service.dart';
import '../utils/bon_extensions.dart';
import 'panini/holographic_effect.dart';
import 'panini/panini_card_controller.dart';
import 'panini/offline_first_image.dart';

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
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  
  bool _isFront = true;
  
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
    
    // Animation de retournement (flip)
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _flipController,
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
    _flipController.dispose();
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
    
    // Retourner la carte au clic
    if (_isFront) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
    _isFront = !_isFront;
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
        animation: Listenable.merge([_scaleAnimation, _flipAnimation, _shimmerController, _controller]),
        builder: (context, child) {
          final state = _controller.state;
          
          // Calcul de la rotation 3D
          final angle = _flipAnimation.value * math.pi;
          final isBackVisible = angle >= math.pi / 2;
          
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001) // Perspective
                ..rotateY(angle),
              alignment: Alignment.center,
              child: Container(
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

                      // Contenu (Recto ou Verso)
                      isBackVisible
                          ? Transform(
                              transform: Matrix4.identity()..rotateY(math.pi),
                              alignment: Alignment.center,
                              child: _buildVerso(color),
                            )
                          : _buildRecto(color, state.cacheResult.localPicturePath, state.cacheResult.isChecking),

                      // Status chip externe (optionnel)
                      if (widget.statusChip != null && !isBackVisible)
                        Positioned(
                          bottom: 12,
                          left: 12,
                          child: widget.statusChip!,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Recto : Ultra épuré (Logo, Nom, Valeur)
  Widget _buildRecto(Color color, String? localPicturePath, bool isCheckingCache) {
    final pictureUrl = widget.bon.picture ?? widget.bon.logoUrl;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Valeur en gros
          Text(
            '${widget.bon.value.toStringAsFixed(0)} ẐEN',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 16),
          // Logo
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: OfflineFirstImage(
                url: pictureUrl,
                localPath: localPicturePath,
                fallbackBase64: widget.bon.picture64,
                width: 80,
                height: 80,
                color: color,
                rarity: widget.bon.rarity,
                isPending: widget.bon.status == BonStatus.pending,
                fit: BoxFit.cover,
                isChecking: isCheckingCache,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Nom du commerçant
          Text(
            widget.bon.issuerName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Verso : Stats de la carte
  Widget _buildVerso(Color color) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.black.withValues(alpha: 0.8), // Fond sombre pour le verso
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'STATISTIQUES',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          const Divider(color: Colors.white30),
          const SizedBox(height: 8),
          _buildStatRow(Icons.swap_horiz, 'Nombre de hops', '${widget.bon.transferCount ?? 0}'),
          _buildStatRow(Icons.fingerprint, 'ID Unique', widget.bon.uniqueId ?? 'N/A'),
          _buildStatRow(Icons.event, 'Expiration', widget.bon.getDurationRemaining()),
          _buildStatRow(Icons.star, 'Rareté', (widget.bon.rarity ?? 'common').toUpperCase()),
          if (widget.bon.wish != null && widget.bon.wish!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Vœu attaché :',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                '"${widget.bon.wish!}"',
                style: const TextStyle(
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            const Spacer(),
          ],
          if (widget.onTap != null)
            Center(
              child: ElevatedButton.icon(
                onPressed: widget.onTap,
                icon: const Icon(Icons.menu_book, size: 16),
                label: const Text('Carnet de voyage', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
