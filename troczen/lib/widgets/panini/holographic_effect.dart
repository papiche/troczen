import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Effet holographique animé pour les cartes rares.
/// 
/// Ce widget crée un effet de brillance rotatif qui donne
/// un aspect premium aux cartes légendaires et rares.
/// 
/// Exemple d'utilisation:
/// ```dart
/// HolographicEffect(
///   animation: shimmerController,
/// )
/// ```
class HolographicEffect extends StatelessWidget {
  final Animation<double> animation;

  const HolographicEffect({
    super.key,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Positioned.fill(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Transform.rotate(
              angle: animation.value * 2 * math.pi,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.3),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Effet de brillance statique pour les cartes peu communes
class ShimmerEffect extends StatelessWidget {
  final double opacity;

  const ShimmerEffect({
    super.key,
    this.opacity = 0.1,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: opacity),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Effet de bordure brillante pour les cartes rares
class GlowingBorder extends StatelessWidget {
  final Color color;
  final double borderWidth;
  final double glowRadius;

  const GlowingBorder({
    super.key,
    required this.color,
    this.borderWidth = 3.0,
    this.glowRadius = 30.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: glowRadius,
            spreadRadius: 3,
          ),
        ],
      ),
    );
  }
}