import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/logger_service.dart';

/// Tutoriel interactif pour le premier lancement
/// Contexte : Commerçants d'un village créant des bons de réduction
class TutorialOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback? onComplete;

  const TutorialOverlay({
    super.key,
    required this.child,
    this.onComplete,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  bool _showTutorial = false;
  int _currentStep = 0;
  
  final List<TutorialStep> _steps = [
    TutorialStep(
      title: 'Bienvenue commerçant ! 🏪',
      description: 'TrocZen vous permet de créer des bons de réduction pour dynamiser votre village.\n\nVos clients collectionnent vos bons et les font circuler entre voisins !',
      icon: Icons.store,
      position: TutorialPosition.center,
    ),
    TutorialStep(
      title: 'Partager l\'application 📲',
      description: 'Invitez 5 commerçants voisins à rejoindre votre marché.\n\nAllez dans Paramètres > Partager l\'app pour installer TrocZen d\'un smartphone à l\'autre.\n\nVous avez besoin de 5 personnes pour débloquer la création de ẐEN !',
      icon: Icons.share,
      position: TutorialPosition.center,
    ),
    TutorialStep(
      title: 'Bons 0 ẐEN : Le secret du bootstrap 🎁',
      description: 'Créez des bons à 0 ẐEN et partagez-les !\n\nC\'est la stratégie pour tisser votre toile de confiance sans dépenser.\n\nChaque bon échangé crée un lien de reconnaissance.',
      icon: Icons.card_giftcard,
      position: TutorialPosition.bottomCenter,
      highlightZone: Rect.fromLTWH(0, 0.85, 1, 0.1), // Zone du FAB
    ),
    TutorialStep(
      title: 'Toile de confiance : 5 liens ⏱️',
      description: 'Vous avez 28 jours pour obtenir 5 reconnaissances mutuelles.\n\nAprès ça, vous pourrez créer des ẐEN !\n\nAjoutez vos contacts depuis le Profil.',
      icon: Icons.handshake,
      position: TutorialPosition.topRight,
      highlightZone: Rect.fromLTWH(0.7, 0.05, 0.25, 0.1), // Zone du profil
    ),
    TutorialStep(
      title: 'Scanner pour recevoir 📱',
      description: 'Quand un client vous présente un bon, scannez-le.\n\nLe bon entre dans votre portefeuille et crée un lien de confiance !',
      icon: Icons.qr_code_scanner,
      position: TutorialPosition.center,
    ),
    TutorialStep(
      title: 'Boucler le circuit 🎉',
      description: 'Quand votre propre bon vous revient (après avoir circulé), vous pouvez le "Boucler".\n\nC\'est la preuve que votre commerce dynamise le village !',
      icon: Icons.celebration,
      position: TutorialPosition.center,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenTutorial = prefs.getBool('hasSeenTutorial') ?? false;
      
      if (!hasSeenTutorial) {
        // Attendre que l'interface soit chargée
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          setState(() => _showTutorial = true);
        }
        Logger.log('Tutorial', 'Premier lancement détecté, affichage du tutoriel');
      }
    } catch (e) {
      Logger.error('Tutorial', 'Erreur vérification premier lancement', e);
    }
  }

  Future<void> _completeTutorial() async {
    try {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'hasSeenTutorial', value: 'true');
      
      setState(() => _showTutorial = false);
      
      Logger.log('Tutorial', 'Tutoriel complété');
      widget.onComplete?.call();
      
      // Message de confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Tutoriel terminé ! Vous pouvez le revoir dans Aide > Tutoriel'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      Logger.error('Tutorial', 'Erreur sauvegarde tutoriel', e);
    }
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _completeTutorial();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _skipTutorial() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Passer le tutoriel ?'),
        content: const Text('Vous pourrez le revoir depuis le menu Aide > Tutoriel'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _completeTutorial();
            },
            child: const Text('Passer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Contenu principal
        widget.child,
        
        // Overlay du tutoriel
        if (_showTutorial)
          _buildTutorialOverlay(),
      ],
    );
  }

  Widget _buildTutorialOverlay() {
    final step = _steps[_currentStep];
    final size = MediaQuery.of(context).size;
    
    return Material(
      color: Colors.black.withOpacity(0.8),
      child: Stack(
        children: [
          // Zone highlight (si définie)
          if (step.highlightZone != null)
            Positioned.fill(
              child: CustomPaint(
                painter: HighlightPainter(
                  highlightZone: Rect.fromLTWH(
                    step.highlightZone!.left * size.width,
                    step.highlightZone!.top * size.height,
                    step.highlightZone!.width * size.width,
                    step.highlightZone!.height * size.height,
                  ),
                ),
              ),
            ),
          
          // Carte du tutoriel
          _buildTutorialCard(step),
        ],
      ),
    );
  }

  Widget _buildTutorialCard(TutorialStep step) {
    final size = MediaQuery.of(context).size;
    
    // Position de la carte selon step.position
    Widget card = Container(
      constraints: BoxConstraints(
        maxWidth: size.width * 0.85,
        maxHeight: size.height * 0.6,
      ),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFB347).withOpacity(0.95),
            const Color(0xFFFF8C42).withOpacity(0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB347).withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progression
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _steps.length,
              (index) => Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index == _currentStep
                      ? Colors.white
                      : Colors.white.withOpacity(0.4),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Icône
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(
              step.icon,
              size: 40,
              color: const Color(0xFFFFB347),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Titre
          Text(
            step.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          // Description
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                step.description,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Boutons de navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Bouton Passer
              if (_currentStep == 0)
                TextButton(
                  onPressed: _skipTutorial,
                  child: const Text(
                    'Passer',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              else
                TextButton.icon(
                  onPressed: _previousStep,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  label: const Text(
                    'Retour',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              
              // Bouton Suivant/Terminer
              ElevatedButton.icon(
                onPressed: _nextStep,
                icon: Icon(
                  _currentStep < _steps.length - 1
                      ? Icons.arrow_forward
                      : Icons.check_circle,
                  color: const Color(0xFFFFB347),
                ),
                label: Text(
                  _currentStep < _steps.length - 1 ? 'Suivant' : 'Compris !',
                  style: const TextStyle(
                    color: Color(0xFFFFB347),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    
    // Positionner la carte
    return Positioned.fill(
      child: Align(
        alignment: step.position.alignment,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: card,
        ),
      ),
    );
  }
}

/// Modèle d'étape du tutoriel
class TutorialStep {
  final String title;
  final String description;
  final IconData icon;
  final TutorialPosition position;
  final Rect? highlightZone;  // Zone à mettre en surbrillance (coordonnées relatives 0-1)

  TutorialStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.position,
    this.highlightZone,
  });
}

/// Position du tutoriel à l'écran
enum TutorialPosition {
  center(Alignment.center),
  topCenter(Alignment.topCenter),
  bottomCenter(Alignment.bottomCenter),
  topRight(Alignment.topRight),
  topLeft(Alignment.topLeft),
  bottomRight(Alignment.bottomRight),
  bottomLeft(Alignment.bottomLeft);

  final Alignment alignment;
  const TutorialPosition(this.alignment);
}

/// Peintre pour la zone de surbrillance
class HighlightPainter extends CustomPainter {
  final Rect highlightZone;

  HighlightPainter({required this.highlightZone});

  @override
  void paint(Canvas canvas, Size size) {
    // Fond sombre avec trou transparent
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        highlightZone,
        const Radius.circular(12),
      ))
      ..fillType = PathFillType.evenOdd;
    
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.3);
    
    canvas.drawPath(path, paint);
    
    // Bordure animée autour de la zone
    final borderPaint = Paint()
      ..color = const Color(0xFFFFB347)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        highlightZone,
        const Radius.circular(12),
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant HighlightPainter oldDelegate) {
    return oldDelegate.highlightZone != highlightZone;
  }
}

/// Fonction utilitaire pour afficher manuellement le tutoriel
Future<void> showTutorial(BuildContext context) async {
  // Afficher le tutoriel sans vérifier le flag hasSeenTutorial
  await Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      pageBuilder: (context, _, __) => const _ManualTutorialScreen(),
    ),
  );
}

/// Écran de tutoriel manuel (depuis le menu Aide)
class _ManualTutorialScreen extends StatelessWidget {
  const _ManualTutorialScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TutorialOverlay(
        onComplete: () => Navigator.pop(context),
        child: Container(),
      ),
    );
  }
}
