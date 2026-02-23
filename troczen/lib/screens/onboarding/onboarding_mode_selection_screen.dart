import 'package:flutter/material.dart';
import '../../models/app_mode.dart';
import '../../services/storage_service.dart';
import '../../services/logger_service.dart';

/// Écran de sélection du mode d'utilisation
/// 
/// ✅ PROGRESSIVE DISCLOSURE : Le Choix du Chapeau
/// Permet à l'utilisateur de choisir son mode au premier lancement
/// Ce choix peut être changé à tout moment dans les paramètres
class OnboardingModeSelectionScreen extends StatefulWidget {
  final VoidCallback onModeSelected;

  const OnboardingModeSelectionScreen({
    super.key,
    required this.onModeSelected,
  });

  @override
  State<OnboardingModeSelectionScreen> createState() => _OnboardingModeSelectionScreenState();
}

class _OnboardingModeSelectionScreenState extends State<OnboardingModeSelectionScreen>
    with SingleTickerProviderStateMixin {
  final _storageService = StorageService();
  AppMode? _selectedMode;
  bool _isSaving = false;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _saveMode() async {
    if (_selectedMode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un mode'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _storageService.setAppMode(_selectedMode!.value);
      Logger.success('OnboardingModeSelection', 'Mode sauvegardé: ${_selectedMode!.label}');
      
      if (mounted) {
        widget.onModeSelected();
      }
    } catch (e) {
      Logger.error('OnboardingModeSelection', 'Erreur sauvegarde mode', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            
            // Titre
            const Text(
              'Comment allez-vous utiliser TrocZen ?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFB347),
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 12),
            
            Text(
              'Choisissez votre "chapeau". Vous pourrez le changer à tout moment dans les paramètres.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 32),
            
            // Cartes de sélection des modes
            Expanded(
              child: ListView(
                children: [
                  _buildModeCard(
                    mode: AppMode.flaneur,
                    icon: Icons.shopping_bag,
                    description: 'Je viens faire mes courses et recevoir des bons locaux',
                    features: [
                      'Interface simplifiée',
                      'Recevoir et dépenser des bons',
                      'Scanner des QR codes',
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildModeCard(
                    mode: AppMode.artisan,
                    icon: Icons.store,
                    description: 'Je tiens un stand ou je propose un service',
                    features: [
                      'Créer mes propres bons',
                      'Gérer ma caisse',
                      'Suivre mes ventes',
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildModeCard(
                    mode: AppMode.alchimiste,
                    icon: Icons.analytics,
                    description: 'Je gère l\'infrastructure du marché',
                    features: [
                      'Tableau de bord économique',
                      'Analyser les circuits',
                      'Gérer la TrocZen Box',
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Bouton de validation
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveMode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB347),
                  disabledBackgroundColor: Colors.grey[800],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Continuer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required AppMode mode,
    required IconData icon,
    required String description,
    required List<String> features,
  }) {
    final isSelected = _selectedMode == mode;
    
    return GestureDetector(
      onTap: () {
        setState(() => _selectedMode = mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFB347) : Colors.grey[800]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFB347).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF3A3A3A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : const Color(0xFFFFB347),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFFFFB347),
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 28,
                  ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? Colors.white.withValues(alpha: 0.9) : Colors.grey[400],
              ),
            ),
            
            const SizedBox(height: 16),
            
            ...features.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check,
                    size: 16,
                    color: isSelected ? Colors.white : const Color(0xFFFFB347),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? Colors.white.withValues(alpha: 0.85) : Colors.grey[500],
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}
