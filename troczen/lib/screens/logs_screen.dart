import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';
import '../config/app_config.dart';

/// Écran d'accès aux logs pour le mode HACKATHON
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
      appBar: AppBar(
        title: const Text('🐛 Logs HACKATHON'),
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
            color: Colors.orange.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      'Mode HACKATHON - ${Logger.logCount} logs',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'API: ${AppConfig.defaultApiUrl}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Filtres
          Padding(
            padding: const EdgeInsets.all(8),
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
                ? const Center(
                    child: Text(
                      'Aucun log à afficher',
                      style: TextStyle(color: Colors.grey),
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
              color: Colors.grey.shade100,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Soumettre une issue',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _issueController,
                  decoration: const InputDecoration(
                    hintText: 'Décrivez le problème rencontré...',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyLogsToClipboard,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copier JSON'),
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
                            : const Icon(Icons.send),
                        label: Text(_isSubmitting ? 'Envoi...' : 'Soumettre'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
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
      selectedColor: Colors.orange.shade200,
    );
  }

  Widget _buildLogTile(LogEntry log) {
    Color bgColor;
    switch (log.level) {
      case 'error':
        bgColor = Colors.red.shade50;
        break;
      case 'warn':
        bgColor = Colors.orange.shade50;
        break;
      case 'success':
        bgColor = Colors.green.shade50;
        break;
      case 'info':
        bgColor = Colors.blue.shade50;
        break;
      default:
        bgColor = Colors.grey.shade50;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
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
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  log.tag,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            log.message,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
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
