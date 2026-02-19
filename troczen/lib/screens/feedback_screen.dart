import 'package:flutter/material.dart';
import 'dart:io';
import '../models/user.dart';
import '../config/app_config.dart';
import '../services/feedback_service.dart';

/// Écran d'envoi de feedback/bug report
class FeedbackScreen extends StatefulWidget {
  final User user;

  const FeedbackScreen({super.key, required this.user});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _selectedType = 'bug';
  bool _isSending = false;

  final _feedbackService = FeedbackService();

  final _types = {
    'bug': {'label': '🐛 Bug', 'color': Colors.red},
    'feature': {'label': '✨ Idée', 'color': Colors.blue},
    'question': {'label': '❓ Question', 'color': Colors.orange},
    'praise': {'label': '👍 Compliment', 'color': Colors.green},
  };

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _sendFeedback() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      // Récupérer infos appareil
      final platform = Platform.isAndroid ? 'Android' : 'iOS';

      final result = await _feedbackService.sendFeedback(
        type: _selectedType,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        appVersion: AppConfig.appVersion,
        platform: platform,
      );

      if (!mounted) return;

      // Afficher résultat
      if (result.success) {
        _showSuccess('✅ Feedback envoyé avec succès!\nIssue #${result.issueNumber}');
        Navigator.pop(context);
      } else {
        _showError(result.error ?? 'Échec d\'envoi. Vérifiez votre connexion.');
      }
    } catch (e) {
      _showError('Erreur: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showSuccess(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 12),
            Text('Merci !', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Erreur', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Feedback & Support'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Votre feedback sera publié sur Nostr et créera une issue GitHub publique',
                        style: TextStyle(
                          color: Colors.blue[200],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Type de feedback
              const Text(
                'Type',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              
              Wrap(
                spacing: 8,
                children: _types.entries.map((entry) {
                  final isSelected = _selectedType == entry.key;
                  return ChoiceChip(
                    label: Text(entry.value['label'] as String),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _selectedType = entry.key);
                    },
                    selectedColor: entry.value['color'] as Color,
                    backgroundColor: const Color(0xFF2A2A2A),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[400],
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Titre
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Titre',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  hintText: 'Résumé en une phrase',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFFFB347)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer un titre';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: 'Description détaillée',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  hintText: 'Décrivez le problème ou votre suggestion...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFFFB347)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez décrire votre feedback';
                  }
                  if (value.length < 20) {
                    return 'Merci de donner plus de détails (min 20 caractères)';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Bouton envoyer
              ElevatedButton.icon(
                onPressed: _isSending ? null : _sendFeedback,
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSending ? 'Envoi en cours...' : 'Envoyer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
