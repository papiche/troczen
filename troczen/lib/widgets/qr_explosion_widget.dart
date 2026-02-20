import 'dart:math';
import 'package:flutter/material.dart';
import '../services/feedback_service.dart';
import '../services/logger_service.dart';

/// Type d'explosion pour différencier les cas d'usage
enum QrExplosionType {
  /// Bon en cours d'échange - suppression impossible
  bonTransferInProgress,
  /// Erreur technique générique
  technicalError,
  /// Bon brûlé/encaissé avec succès par l'émetteur
  bonBurned,
}

/// Widget animé montrant une explosion pour signaler une action impossible.
///
/// Cas d'usage métier :
/// - **Bon en cours d'échange** : L'utilisateur tente de supprimer un bon
///   dont il possède P1 (Ancre) mais plus P2 (transféré à un autre porteur).
///   Le bon ne peut pas être supprimé car il appartient maintenant au porteur actuel.
///
/// Le widget envoie automatiquement un rapport à l'API feedback pour traçabilité.
class QrExplosionWidget extends StatefulWidget {
  final double size;
  final VoidCallback onRetry;
  final String? errorMessage;
  final FeedbackService? feedbackService;
  final String? appVersion;
  final String? platform;
  
  /// Type d'explosion pour adapter le message et le comportement
  final QrExplosionType type;
  
  /// ID du bon concerné (pour les rapports)
  final String? bonId;
  
  /// Valeur du bon (pour affichage)
  final double? bonValue;

  const QrExplosionWidget({
    super.key,
    this.size = 280,
    required this.onRetry,
    this.errorMessage,
    this.feedbackService,
    this.appVersion,
    this.platform,
    this.type = QrExplosionType.technicalError,
    this.bonId,
    this.bonValue,
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
  
  /// Envoie un rapport automatique à l'API feedback pour traçabilité
  ///
  /// Pour un bon en cours d'échange, cela permet de suivre les tentatives
  /// de suppression et d'informer l'émetteur de l'état du bon.
  Future<void> _reportQrExplosion() async {
    // Logger l'événement localement
    final typeLabel = widget.type == QrExplosionType.bonTransferInProgress
        ? 'BON_TRANSFER_IN_PROGRESS'
        : 'TECHNICAL_ERROR';
    
    Logger.info(
      'QR_EXPLOSION',
      '[$typeLabel] ${widget.errorMessage ?? "Action impossible"} '
      '${widget.bonId != null ? "Bon: ${widget.bonId!.substring(0, 8)}..." : ""} '
      '${widget.bonValue != null ? "Valeur: ${widget.bonValue} Ẑ" : ""}',
    );
    
    if (widget.feedbackService == null) return;
    
    try {
      // Récupérer les logs récents pour les inclure dans le rapport
      final logsText = Logger.exportLogsText();
      
      // Construire la description selon le type
      String title;
      String description;
      
      if (widget.type == QrExplosionType.bonTransferInProgress) {
        title = '🔒 Bon en cours d\'échange - Suppression impossible';
        description = '''
### Tentative de suppression d'un bon transféré

**Bon ID**: ${widget.bonId ?? 'N/A'}
**Valeur**: ${widget.bonValue != null ? '${widget.bonValue} Ẑ' : 'N/A'}

**Raison**: L'utilisateur (émetteur) a tenté de supprimer un bon dont il possède P1 (l'Ancre) mais plus P2 (transféré).

**Message affiché**:
${widget.errorMessage ?? 'Ce bon a été transféré et ne peut pas être supprimé.'}

---
### Logs récents

```
$logsText
```

---
*Rapport automatique - Traçabilité des transactions*
''';
      } else {
        title = '💥 Erreur technique - Action impossible';
        description = '''
${widget.errorMessage ?? 'Une erreur technique est survenue.'}

---
### Logs récents

```
$logsText
```

---
*Rapport automatique depuis QrExplosionWidget*
''';
      }

      await widget.feedbackService!.reportBug(
        title: title,
        description: description,
        appVersion: widget.appVersion,
        platform: widget.platform,
      );
      Logger.success('QR_EXPLOSION', 'Rapport envoyé à l\'API feedback');
    } catch (e) {
      Logger.warn('QR_EXPLOSION', 'Impossible d\'envoyer le rapport: $e');
    }
  }

  /// Retourne le message par défaut selon le type d'explosion
  String _getDefaultMessage() {
    switch (widget.type) {
      case QrExplosionType.bonTransferInProgress:
        return 'Ce bon a été transféré à un autre porteur.\n\n'
            'Vous conservez P1 (l\'Ancre) en tant qu\'émetteur,\n'
            'mais P2 appartient maintenant au porteur actuel.\n\n'
            'Un bon transféré ne peut pas être supprimé.';
      case QrExplosionType.technicalError:
        return 'Une erreur technique est survenue.\n\n'
            'Veuillez réessayer ou contacter le support si le problème persiste.';
      case QrExplosionType.bonBurned:
        return '🔥 Bon encaissé avec succès !\n\n'
            'La boucle est bouclée.\n'
            'Ce bon a été détruit et ne peut plus être utilisé.';
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
                
                // Icône selon le type
                AnimatedBuilder(
                  animation: _explosionAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _explosionAnimation.value > 0.3 ? 1 : 0,
                      child: Transform.scale(
                        scale: 0.5 + _explosionAnimation.value * 0.5,
                        child: Icon(
                          widget.type == QrExplosionType.bonTransferInProgress
                              ? Icons.lock_outline
                              : Icons.error_outline,
                          size: 60,
                          color: widget.type == QrExplosionType.bonTransferInProgress
                              ? Colors.orange.shade600
                              : Colors.red.shade600,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Message adapté au type d'explosion
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // Titre selon le type
                Text(
                  widget.type == QrExplosionType.bonTransferInProgress
                      ? '🔒 Bon en cours d\'échange'
                      : '� Oups ! Une erreur est survenue',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.type == QrExplosionType.bonTransferInProgress
                        ? Colors.orange.shade700
                        : Colors.red.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Message détaillé
                Text(
                  widget.errorMessage ?? _getDefaultMessage(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                // Info supplémentaire pour bon transféré
                if (widget.type == QrExplosionType.bonTransferInProgress && widget.bonValue != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Text(
                      'Valeur: ${widget.bonValue} Ẑ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Bouton adapté au type
          ElevatedButton.icon(
            onPressed: widget.onRetry,
            icon: Icon(
              widget.type == QrExplosionType.bonTransferInProgress
                  ? Icons.close
                  : Icons.refresh,
            ),
            label: Text(
              widget.type == QrExplosionType.bonTransferInProgress
                  ? 'Fermer'
                  : 'Réessayer',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.type == QrExplosionType.bonTransferInProgress
                  ? Colors.orange.shade600
                  : Colors.blue.shade600,
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
