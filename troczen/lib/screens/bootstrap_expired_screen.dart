import 'package:flutter/material.dart';
import '../widgets/qr_explosion_widget.dart';
import '../services/storage_service.dart';
import '../services/logger_service.dart';

/// Écran affiché lorsque le bootstrap a expiré (DU non activé dans les 28 jours)
/// 
/// L'utilisateur n'a pas réussi à établir N1 ≥ 5 liens réciproques dans le délai
/// imparti. L'application doit être réinitialisée.
class BootstrapExpiredScreen extends StatelessWidget {
  const BootstrapExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              QrExplosionWidget(
                type: QrExplosionType.bootstrapExpired,
                size: 280,
                onRetry: () => _showResetConfirmation(context),
                errorMessage: 'Le délai de 28 jours pour activer le DU(ẐEN) est expiré.\n\n'
                    'Vous n\'avez pas établi assez de liens de confiance réciproques (N1 < 5).\n\n'
                    'L\'application doit être réinitialisée pour recommencer le processus.',
              ),
              const SizedBox(height: 24),
              // Explication supplémentaire
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade700),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.purple.shade300),
                        const SizedBox(width: 8),
                        Text(
                          'Comment activer le DU(ẐEN) ?',
                          style: TextStyle(
                            color: Colors.purple.shade200,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Le Dividende Universel (DU) nécessite une toile de confiance.\n\n'
                      '• Établissez 5 relations réciproques (N1 ≥ 5)\n'
                      '• Chaque relation doit être mutuelle (follow Nostr)\n'
                      '• Le DU sera alors calculé et crédité quotidiennement\n\n'
                      'Réinstallez l\'application et tissez votre réseau !',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Text(
              'Réinitialiser l\'application ?',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: const Text(
          'Cette action va supprimer toutes vos données locales :\n\n'
          '• Votre profil utilisateur\n'
          '• Vos bons ẐEN\n'
          '• Vos contacts\n'
          '• Votre marché\n\n'
          'Vous devrez recommencer l\'onboarding.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _resetApp(context),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Réinitialiser'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resetApp(BuildContext context) async {
    Navigator.pop(context); // Fermer le dialogue
    
    try {
      final storageService = StorageService();
      await storageService.clearAllData();
      
      Logger.info('BootstrapExpired', 'Application réinitialisée après expiration du bootstrap');
      
      if (context.mounted) {
        // Redémarrer l'application
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/',
          (route) => false,
        );
      }
    } catch (e) {
      Logger.error('BootstrapExpired', 'Erreur lors de la réinitialisation', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la réinitialisation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}