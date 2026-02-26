import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';
import '../config/app_config.dart';

/// Écran d'accès aux logs pour le Marché Libre (transparence publique)
/// Permet de visualiser, exporter et soumettre les logs à l'API
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<LogEntry> _logs = [];
  String _selectedLevel = 'all';
  bool _isSubmitting = false;
  final TextEditingController _issueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() {
    setState(() {
      if (_selectedLevel == 'all') {
        _logs = Logger.getLogs();
      } else {
        _logs = Logger.getLogsByLevel(_selectedLevel);
      }
    });
  }

  Future<void> _copyLogsToClipboard() async {
    final logsText = Logger.exportLogsText();
    await Clipboard.setData(ClipboardData(text: logsText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 Logs copiés dans le presse-papier'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _submitLogsToApi() async {
    if (_issueController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Veuillez décrire l\'issue'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final success = await Logger.submitLogsToApi(
        issueDescription: _issueController.text,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Logs soumis avec succès à l\'API'),
              backgroundColor: Colors.green,
            ),
          );
          _issueController.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Erreur lors de la soumission des logs'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Effacer les logs'),
        content: const Text('Voulez-vous vraiment effacer tous les logs ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Logger.clearLogs();
              _loadLogs();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🗑️ Logs effacés'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
            child: const Text('Effacer', style: TextStyle(color: Colors.red)),
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
        title: const Text('🐛 Logs'),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copier les logs',
            onPressed: _copyLogsToClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Effacer les logs',
            onPressed: _clearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // En-tête info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              border: Border(
                bottom: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFFFB347)),
                    const SizedBox(width: 8),
                    Text(
                      'Logs de l\'application - ${Logger.logCount} entrées',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFB347),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'API: ${AppConfig.defaultApiUrl}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade300,
                  ),
                ),
              ],
            ),
          ),

          // Filtres
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF1E1E1E),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'Tous'),
                  const SizedBox(width: 8),
                  _buildFilterChip('error', '❌ Erreurs'),
                  const SizedBox(width: 8),
                  _buildFilterChip('warn', '⚠️ Warnings'),
                  const SizedBox(width: 8),
                  _buildFilterChip('success', '✅ Succès'),
                  const SizedBox(width: 8),
                  _buildFilterChip('info', 'ℹ️ Info'),
                  const SizedBox(width: 8),
                  _buildFilterChip('debug', '🔍 Debug'),
                ],
              ),
            ),
          ),

          // Liste des logs
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.article_outlined, size: 64, color: Colors.grey[700]),
                        const SizedBox(height: 16),
                        Text(
                          'Aucun log à afficher',
                          style: TextStyle(color: Colors.grey[500], fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[_logs.length - 1 - index]; // Inverser l'ordre
                      return _buildLogTile(log);
                    },
                  ),
          ),

          // Zone de soumission
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(
                top: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Soumettre une issue',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _issueController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Décrivez le problème rencontré...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[700]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFFB347)),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyLogsToClipboard,
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copier JSON'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[300],
                          side: BorderSide(color: Colors.grey[600]!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submitLogsToApi,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send, size: 18),
                        label: Text(_isSubmitting ? 'Envoi...' : 'Soumettre'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB347),
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String level, String label) {
    final isSelected = _selectedLevel == level;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedLevel = level;
          _loadLogs();
        });
      },
      selectedColor: const Color(0xFFFFB347),
      backgroundColor: const Color(0xFF2A2A2A),
      labelStyle: TextStyle(
        color: isSelected ? Colors.black : Colors.grey[300],
      ),
      checkmarkColor: Colors.black,
    );
  }

  Widget _buildLogTile(LogEntry log) {
    Color bgColor;
    Color borderColor;
    Color textColor;
    switch (log.level) {
      case 'error':
        bgColor = Colors.red.withValues(alpha: 0.15);
        borderColor = Colors.red.withValues(alpha: 0.4);
        textColor = Colors.red.shade300;
        break;
      case 'warn':
        bgColor = Colors.orange.withValues(alpha: 0.15);
        borderColor = Colors.orange.withValues(alpha: 0.4);
        textColor = Colors.orange.shade300;
        break;
      case 'success':
        bgColor = Colors.green.withValues(alpha: 0.15);
        borderColor = Colors.green.withValues(alpha: 0.4);
        textColor = Colors.green.shade300;
        break;
      case 'info':
        bgColor = Colors.blue.withValues(alpha: 0.15);
        borderColor = Colors.blue.withValues(alpha: 0.4);
        textColor = Colors.blue.shade300;
        break;
      default:
        bgColor = Colors.grey.withValues(alpha: 0.15);
        borderColor = Colors.grey.withValues(alpha: 0.4);
        textColor = Colors.grey.shade300;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                log.timestamp.toIso8601String().split('T').last,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log.tag,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            log.message,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _issueController.dispose();
    super.dispose();
  }
}
