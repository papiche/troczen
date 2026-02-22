import 'dart:math';
import 'package:flutter/material.dart';
import '../services/logger_service.dart';

/// Widget animé pour la Révélation du Circuit d'un bon.
///
/// Quand un bon termine son parcours, il ne se "burn" pas mais se "révèle".
/// Le Carnet de Voyage devient une preuve économique (Kind 30304).
///
/// Couleurs: Vertes/Violettes (intelligence et succès)
/// Icône: Réseau/boucle (Icons.all_inclusive ou Icons.hub)
class CircuitRevelationWidget extends StatefulWidget {
  final double size;
  final VoidCallback onClose;
  
  /// ID du bon révélé
  final String? bonId;
  
  /// Valeur du bon en ẐEN
  final double? valueZen;
  
  /// Nombre de transferts (hops)
  final int? hopCount;
  
  /// Âge du bon en jours
  final int? ageDays;
  
  /// Compétence associée au parcours
  final String? skillAnnotation;
  
  /// Rareté du bon
  final String? rarity;

  const CircuitRevelationWidget({
    super.key,
    this.size = 280,
    required this.onClose,
    this.bonId,
    this.valueZen,
    this.hopCount,
    this.ageDays,
    this.skillAnnotation,
    this.rarity,
  });

  @override
  State<CircuitRevelationWidget> createState() => _CircuitRevelationWidgetState();
}

class _CircuitRevelationWidgetState extends State<CircuitRevelationWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _particleController;
  late AnimationController _ringController;
  late Animation<double> _pulseAnimation;
  late List<CircuitParticle> _particles;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    
    // Contrôleur pour le pulse central
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    // Contrôleur pour les particules
    _particleController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    
    // Contrôleur pour les anneaux
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.elasticOut,
    );
    
    // Générer les particules
    _particles = _generateParticles(25);
    
    // Démarrer les animations en séquence
    _pulseController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _particleController.forward();
        _ringController.forward();
      }
    });
    
    // Logger l'événement
    Logger.log(
      'CircuitRevelation',
      '🎉 Circuit révélé: ${widget.bonId?.substring(0, 8) ?? "N/A"}... | '
      '${widget.valueZen ?? 0}ẐEN | ${widget.hopCount ?? 0} hops | ${widget.ageDays ?? 0} jours',
    );
  }

  List<CircuitParticle> _generateParticles(int count) {
    final particles = <CircuitParticle>[];
    
    // Couleurs: Vert -> Violet (gradient de succès/intelligence)
    final colors = [
      Colors.green.shade400,
      Colors.green.shade600,
      Colors.teal.shade400,
      Colors.purple.shade300,
      Colors.purple.shade500,
      Colors.deepPurple.shade400,
      Colors.indigo.shade400,
    ];
    
    for (int i = 0; i < count; i++) {
      particles.add(CircuitParticle(
        angle: _random.nextDouble() * 2 * pi,
        speed: 50 + _random.nextDouble() * 100,
        size: 4 + _random.nextDouble() * 8,
        color: colors[_random.nextInt(colors.length)],
        rotationSpeed: _random.nextDouble() * 2 - 1,
        type: _random.nextDouble() > 0.7 ? ParticleType.star : ParticleType.circle,
      ));
    }
    
    return particles;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _particleController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: widget.size + 80),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green.shade50,
              Colors.purple.shade50,
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.purple.shade200,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animation centrale
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Anneaux concentriques animés
                  AnimatedBuilder(
                    animation: _ringController,
                    builder: (context, child) {
                      return CustomPaint(
                        size: Size(widget.size, widget.size),
                        painter: RingPainter(
                          progress: _ringController.value,
                          center: Offset(widget.size / 2, widget.size / 2),
                        ),
                      );
                    },
                  ),
                  
                  // Particules
                  AnimatedBuilder(
                    animation: _particleController,
                    builder: (context, child) {
                      return CustomPaint(
                        size: Size(widget.size, widget.size),
                        painter: CircuitParticlePainter(
                          particles: _particles,
                          progress: _particleController.value,
                          center: Offset(widget.size / 2, widget.size / 2),
                        ),
                      );
                    },
                  ),
                  
                  // Icône centrale avec animation de pulse
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _pulseAnimation.value > 0.2 ? 1 : 0,
                        child: Transform.scale(
                          scale: 0.3 + _pulseAnimation.value * 0.7,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                colors: [
                                  Colors.green.shade300,
                                  Colors.purple.shade400,
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purple.withValues(alpha: 0.5),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.all_inclusive,  // Symbole infini - boucle
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Titre
            Text(
              '🔄 Circuit Révélé',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                foreground: Paint()
                  ..shader = LinearGradient(
                    colors: [Colors.green.shade600, Colors.purple.shade600],
                  ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 8),
            
            // Sous-titre
            Text(
              'Le Carnet de Voyage devient une preuve économique',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 16),
            
            // Stats du circuit
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.shade100),
              ),
              child: Column(
                children: [
                  // Valeur
                  if (widget.valueZen != null)
                    _buildStatRow(
                      icon: Icons.monetization_on,
                      label: 'Valeur',
                      value: '${widget.valueZen!.toStringAsFixed(0)} ẐEN',
                      color: Colors.green.shade600,
                    ),
                  
                  const SizedBox(height: 8),
                  
                  // Hops (transferts)
                  if (widget.hopCount != null)
                    _buildStatRow(
                      icon: Icons.swap_horiz,
                      label: 'Transferts',
                      value: '${widget.hopCount} hop${widget.hopCount! > 1 ? 's' : ''}',
                      color: Colors.teal.shade600,
                    ),
                  
                  const SizedBox(height: 8),
                  
                  // Âge
                  if (widget.ageDays != null)
                    _buildStatRow(
                      icon: Icons.schedule,
                      label: 'Durée de vie',
                      value: '${widget.ageDays} jour${widget.ageDays! > 1 ? 's' : ''}',
                      color: Colors.purple.shade600,
                    ),
                  
                  // Compétence (bonus)
                  if (widget.skillAnnotation != null && widget.skillAnnotation!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade100, Colors.purple.shade100],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 16, color: Colors.purple.shade600),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.skillAnnotation!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.purple.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Bouton de fermeture
            ElevatedButton.icon(
              onPressed: widget.onClose,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Excellent !'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 4,
                shadowColor: Colors.green.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Particule pour l'animation de révélation
class CircuitParticle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double rotationSpeed;
  final ParticleType type;

  CircuitParticle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotationSpeed,
    required this.type,
  });
}

enum ParticleType { circle, star }

/// Peintre pour les particules du circuit
class CircuitParticlePainter extends CustomPainter {
  final List<CircuitParticle> particles;
  final double progress;
  final Offset center;

  CircuitParticlePainter({
    required this.particles,
    required this.progress,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Mouvement en spirale vers l'extérieur
      final spiralAngle = particle.angle + progress * particle.rotationSpeed;
      final distance = particle.speed * progress;
      final x = center.dx + cos(spiralAngle) * distance;
      final y = center.dy + sin(spiralAngle) * distance;
      
      // Opacité qui pulse puis disparaît
      final opacity = (1 - progress) * (0.5 + 0.5 * cos(progress * pi * 3));
      
      final paint = Paint()
        ..color = particle.color.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      
      if (particle.type == ParticleType.star) {
        _drawStar(canvas, Offset(x, y), particle.size * (1 - progress * 0.5), paint);
      } else {
        canvas.drawCircle(Offset(x, y), particle.size * (1 - progress * 0.3), paint);
      }
    }
  }
  
  void _drawStar(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    const points = 5;
    const innerRadius = 0.4;
    
    for (int i = 0; i < points * 2; i++) {
      final radius = i.isEven ? size : size * innerRadius;
      final angle = (i * pi / points) - pi / 2;
      final x = center.dx + cos(angle) * radius;
      final y = center.dy + sin(angle) * radius;
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CircuitParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Peintre pour les anneaux concentriques
class RingPainter extends CustomPainter {
  final double progress;
  final Offset center;

  RingPainter({
    required this.progress,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dessiner 3 anneaux concentriques qui s'étendent
    for (int i = 0; i < 3; i++) {
      final ringProgress = ((progress - i * 0.15) / 0.7).clamp(0.0, 1.0);
      if (ringProgress <= 0 || ringProgress > 1) continue;
      
      final radius = 30 + ringProgress * 100;
      final opacity = (1 - ringProgress) * 0.6;
      
      final paint = Paint()
        ..color = (i.isEven ? Colors.green : Colors.purple).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 - i * 0.5;
      
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
