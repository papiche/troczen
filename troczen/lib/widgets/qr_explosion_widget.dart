import 'dart:math';
import 'package:flutter/material.dart';
import '../services/feedback_service.dart';
import '../services/logger_service.dart';

/// Widget animé montrant une explosion quand le QR code ne peut pas être généré
/// à cause de caractères invalides dans les données binaires.
class QrExplosionWidget extends StatefulWidget {
  final double size;
  final VoidCallback onRetry;
  final String? errorMessage;
  final FeedbackService? feedbackService;
  final String? appVersion;
  final String? platform;

  const QrExplosionWidget({
    super.key,
    this.size = 280,
    required this.onRetry,
    this.errorMessage,
    this.feedbackService,
    this.appVersion,
    this.platform,
  });

  @override
  State<QrExplosionWidget> createState() => _QrExplosionWidgetState();
}

class _QrExplosionWidgetState extends State<QrExplosionWidget>
    with TickerProviderStateMixin {
  late AnimationController _explosionController;
  late AnimationController _particleController;
  late Animation<double> _explosionAnimation;
  late List<Particle> _particles;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    
    // Contrôleur pour l'explosion principale
    _explosionController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    // Contrôleur pour les particules
    _particleController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _explosionAnimation = CurvedAnimation(
      parent: _explosionController,
      curve: Curves.easeOutExpo,
    );
    
    // Générer les particules
    _particles = _generateParticles(20);
    
    // Démarrer les animations
    _explosionController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _particleController.forward();
      }
    });
    
    // Envoyer un rapport automatique si le service est disponible
    _reportQrExplosion();
  }
  
  /// Envoie un rapport automatique de l'erreur QR avec les logs
  Future<void> _reportQrExplosion() async {
    // Logger l'erreur localement
    Logger.error(
      'QR_EXPLOSION',
      'QR Code explosion détectée: ${widget.errorMessage ?? "Données binaires invalides"}',
    );
    
    if (widget.feedbackService == null) return;
    
    try {
      // Récupérer les logs récents pour les inclure dans le rapport
      final logsText = Logger.exportLogsText();
      final logsJson = Logger.exportLogsJson();
      
      // Construire la description complète avec les logs
      final fullDescription = '''
${widget.errorMessage ?? 'Le QR code n\'a pas pu être généré à cause de données binaires invalides.'}

---
### Logs récents

```
$logsText
```

---
### Logs JSON
```json
$logsJson
```

---
*Rapport automatique depuis QrExplosionWidget*
''';

      await widget.feedbackService!.reportBug(
        title: '💥 QR Code Explosion - Caractères invalides',
        description: fullDescription,
        appVersion: widget.appVersion,
        platform: widget.platform,
      );
      Logger.success('QR_EXPLOSION', 'Rapport d\'explosion QR envoyé automatiquement avec logs');
    } catch (e) {
      Logger.warn('QR_EXPLOSION', 'Impossible d\'envoyer le rapport d\'explosion: $e');
    }
  }

  List<Particle> _generateParticles(int count) {
    return List.generate(count, (index) {
      return Particle(
        angle: (index / count) * 2 * pi + _random.nextDouble() * 0.5,
        speed: 50 + _random.nextDouble() * 100,
        size: 4 + _random.nextDouble() * 8,
        color: _getRandomColor(),
        rotationSpeed: _random.nextDouble() * 2 - 1,
      );
    });
  }

  Color _getRandomColor() {
    final colors = [
      Colors.red.shade400,
      Colors.orange.shade400,
      Colors.yellow.shade400,
      Colors.red.shade600,
      Colors.deepOrange.shade400,
    ];
    return colors[_random.nextInt(colors.length)];
  }

  @override
  void dispose() {
    _explosionController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size + 120, // Espace supplémentaire pour le message
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Zone d'explosion
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Flash central
                AnimatedBuilder(
                  animation: _explosionAnimation,
                  builder: (context, child) {
                    return Container(
                      width: widget.size * 0.3 * _explosionAnimation.value,
                      height: widget.size * 0.3 * _explosionAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(
                          alpha: 1 - _explosionAnimation.value,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.8),
                            blurRadius: 30 * _explosionAnimation.value,
                            spreadRadius: 10 * _explosionAnimation.value,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                
                // Cercle d'explosion
                AnimatedBuilder(
                  animation: _explosionAnimation,
                  builder: (context, child) {
                    return Container(
                      width: widget.size * 0.8 * _explosionAnimation.value,
                      height: widget.size * 0.8 * _explosionAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.orange.withValues(
                            alpha: 0.8 * (1 - _explosionAnimation.value),
                          ),
                          width: 3,
                        ),
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
                      painter: ParticlePainter(
                        particles: _particles,
                        progress: _particleController.value,
                        center: Offset(widget.size / 2, widget.size / 2),
                      ),
                    );
                  },
                ),
                
                // Icône d'erreur
                AnimatedBuilder(
                  animation: _explosionAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _explosionAnimation.value > 0.3 ? 1 : 0,
                      child: Transform.scale(
                        scale: 0.5 + _explosionAnimation.value * 0.5,
                        child: Icon(
                          Icons.error_outline,
                          size: 60,
                          color: Colors.red.shade600,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Message d'erreur
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Text(
                  '💥 Oups ! Le QR code a explosé',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.errorMessage ??
                      'Les données binaires contiennent des caractères '
                      'incompatibles avec l\'encodage QR.\n\n'
                      'Cela peut arriver lorsque les données cryptées '
                      'génèrent des séquences d\'octets invalides.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Bouton de régénération
          ElevatedButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Générer un nouveau QR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Particule pour l'animation d'explosion
class Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double rotationSpeed;

  Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotationSpeed,
  });
}

/// Peintre personnalisé pour dessiner les particules
class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;
  final Offset center;

  ParticlePainter({
    required this.particles,
    required this.progress,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final distance = particle.speed * progress;
      final x = center.dx + cos(particle.angle) * distance;
      final y = center.dy + sin(particle.angle) * distance;
      
      // Calculer l'opacité (disparition progressive)
      final opacity = 1 - progress;
      
      // Calculer la rotation
      final rotation = particle.rotationSpeed * progress * pi * 2;
      
      final paint = Paint()
        ..color = particle.color.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      
      // Dessiner un carré ou un cercle selon la particule
      if (particles.indexOf(particle) % 2 == 0) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size * (1 - progress * 0.5),
            height: particle.size * (1 - progress * 0.5),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(
          Offset.zero,
          particle.size / 2 * (1 - progress * 0.5),
          paint,
        );
      }
      
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
