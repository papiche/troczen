import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/apk_share_service.dart';
import '../services/logger_service.dart';

/// Écran de partage d'APK pair-à-pair.
/// Affiche un QR Code que d'autres appareils peuvent scanner pour télécharger l'APK.
class ApkShareScreen extends StatefulWidget {
  const ApkShareScreen({super.key});

  @override
  State<ApkShareScreen> createState() => _ApkShareScreenState();
}

class _ApkShareScreenState extends State<ApkShareScreen> {
  final _apkShareService = ApkShareService();
  bool _isStarting = false;
  bool _isServerRunning = false;
  String? _downloadUrl;
  String? _errorMessage;
  int _downloadsCount = 0;
  
  @override
  void initState() {
    super.initState();
    _startServer();
  }
  
  Future<void> _startServer() async {
    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });
    
    try {
      final success = await _apkShareService.startServer();
      
      if (success) {
        setState(() {
          _isServerRunning = true;
          _downloadUrl = _apkShareService.downloadUrl;
        });
        
        // Surveiller les téléchargements
        _monitorDownloads();
      } else {
        setState(() {
          _errorMessage = 'Impossible de démarrer le serveur. Vérifiez que l\'APK est disponible.';
        });
      }
    } catch (e) {
      Logger.error('ApkShareScreen', 'Erreur lors du démarrage du serveur', e);
      setState(() {
        _errorMessage = 'Erreur: $e';
      });
    } finally {
      setState(() {
        _isStarting = false;
      });
    }
  }
  
  void _monitorDownloads() {
    // Mettre à jour périodiquement le compteur de téléchargements
    Future.delayed(const Duration(seconds: 2), () {
      if (_isServerRunning && mounted) {
        setState(() {
          _downloadsCount = _apkShareService.downloadsCount;
        });
        _monitorDownloads();
      }
    });
  }
  
  Future<void> _stopServer() async {
    await _apkShareService.stopServer();
    setState(() {
      _isServerRunning = false;
      _downloadUrl = null;
      _downloadsCount = 0;
    });
  }
  
  @override
  void dispose() {
    _apkShareService.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partager l\'application'),
        backgroundColor: const Color(0xFF0A7EA4),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête explicatif
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Column(
                children: [
                  Icon(Icons.share, size: 48, color: Color(0xFF0A7EA4)),
                  SizedBox(height: 12),
                  Text(
                    'Partage TrocZen',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0A7EA4),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Scannez le QR Code ci-dessous avec l\'appareil photo de votre téléphone pour télécharger et installer TrocZen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // État du serveur
            if (_isStarting) ...[
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Démarrage du serveur...'),
                  ],
                ),
              ),
            ] else if (_errorMessage != null) ...[
              _buildErrorCard(),
            ] else if (_isServerRunning && _downloadUrl != null) ...[
              _buildQrCodeCard(),
              const SizedBox(height: 16),
              _buildServerInfoCard(),
              const SizedBox(height: 16),
              _buildStopButton(),
            ],
            
            const SizedBox(height: 24),
            
            // Instructions
            _buildInstructionsCard(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          const Text(
            'Erreur',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Une erreur est survenue',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _startServer,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A7EA4),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQrCodeCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // QR Code
          QrImageView(
            data: _downloadUrl!,
            version: QrVersions.auto,
            size: 250,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF0A7EA4),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
            embeddedImage: const AssetImage('assets/images/.gitkeep'),
            embeddedImageStyle: const QrEmbeddedImageStyle(
              size: Size(50, 50),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // URL
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _downloadUrl!,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: Color(0xFF0A7EA4),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildServerInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Serveur actif',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem(
                icon: Icons.devices,
                label: 'IP Locale',
                value: _apkShareService.localIpAddress ?? '-',
              ),
              _buildInfoItem(
                icon: Icons.dns,
                label: 'Port',
                value: '${_apkShareService.port}',
              ),
              _buildInfoItem(
                icon: Icons.download_done,
                label: 'Téléchargements',
                value: '$_downloadsCount',
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF0A7EA4), size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStopButton() {
    return ElevatedButton.icon(
      onPressed: _stopServer,
      icon: const Icon(Icons.stop),
      label: const Text('Arrêter le serveur'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
  
  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                'Instructions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Pour le destinataire:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildInstructionStep('1', 'Ouvrez l\'appareil photo du téléphone'),
          _buildInstructionStep('2', 'Pointez vers le QR Code'),
          _buildInstructionStep('3', 'Appuyez sur la notification pour ouvrir'),
          _buildInstructionStep('4', 'Téléchargez et installez l\'APK'),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            '⚠️ Note importante:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Les deux appareils doivent être connectés au même réseau WiFi. '
            'L\'installation depuis des sources inconnues doit être autorisée sur l\'appareil destinataire.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF0A7EA4),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
