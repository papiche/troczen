import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:hex/hex.dart';
import 'onboarding_flow.dart';

/// Étape 1: Configuration de la Seed de Marché
class OnboardingSeedScreen extends StatefulWidget {
  final VoidCallback onNext;
  
  const OnboardingSeedScreen({
    super.key,
    required this.onNext,
  });

  @override
  State<OnboardingSeedScreen> createState() => _OnboardingSeedScreenState();
}

class _OnboardingSeedScreenState extends State<OnboardingSeedScreen> {
  String? _selectedMode;
  String? _generatedSeed;
  bool _showQrExport = false;
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Titre
          const Text(
            'Configuration du Marché',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFB347),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choisissez comment configurer votre marché local',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 32),
          
          // Options
          Expanded(
            child: _showQrExport && _generatedSeed != null
                ? _buildQrExportView()
                : _buildOptionsView(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOptionsView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Option 1: Scanner
          _buildOptionCard(
            icon: Icons.qr_code_scanner,
            title: 'Scanner un QR Code',
            description: 'Rejoindre un marché existant (idéal pour débuter)',
            mode: 'scan',
            onTap: () => _showScannerDialog(),
          ),
          
          const SizedBox(height: 16),
          
          // Option 2: Générer
          _buildOptionCard(
            icon: Icons.auto_awesome,
            title: 'Créer un nouveau marché',
            description: 'Générer une clé sécurisée pour lancer votre marché',
            mode: 'generate',
            onTap: () => _generateSecureSeed(),
          ),
          
          const SizedBox(height: 16),
          
          // Option 3: Mode 000 (Hackathon)
          _buildOptionCard(
            icon: Icons.warning_amber,
            title: 'Mode Test (000)',
            description: 'Mode développeur - Sécurité faible pour démonstration',
            mode: 'mode000',
            iconColor: Colors.orange,
            onTap: () => _showMode000Confirmation(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String description,
    required String mode,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    final isSelected = _selectedMode == mode;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFB347).withOpacity(0.1)
              : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFB347)
                : Colors.grey[800]!,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (iconColor ?? const Color(0xFFFFB347)).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 32,
                color: iconColor ?? const Color(0xFFFFB347),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFFFFB347),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildQrExportView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.check_circle,
          size: 64,
          color: Colors.green,
        ),
        const SizedBox(height: 16),
        const Text(
          'Clé de votre marché créée !',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Voici le QR code à partager avec vos commerçants',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[400],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        // QR Code avec message pédagogique
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB347).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              QrImageView(
                data: _generatedSeed!,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB347).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '📱 Scanner = Rejoindre',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFB347),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Instruction pédagogique
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFB347).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFFFFB347), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Imprimez ou partagez ce QR pour inviter d\'autres participants à votre marché local',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[300],
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Bouton copier (optionnel pour utilisateurs avancés)
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _generatedSeed!));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Clé copiée (pour utilisateurs avancés)'),
                backgroundColor: Colors.green,
              ),
            );
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copier la clé (avancé)', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey[400],
            side: BorderSide(color: Colors.grey[700]!),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
        
        const Spacer(),
        
        // Bouton Continuer
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              final notifier = context.read<OnboardingNotifier>();
              notifier.setSeedMarket(_generatedSeed!, _selectedMode!);
              widget.onNext();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB347),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continuer',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  void _showScannerDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          height: 400,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Scanner le QR Code',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: MobileScanner(
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final seed = barcodes.first.rawValue;
                        if (seed != null && seed.length == 64) {
                          Navigator.pop(context);
                          _setSeedAndContinue(seed, 'scan');
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _generateSecureSeed() {
    final secureRandom = Random.secure();
    final seedBytes = Uint8List.fromList(
      List.generate(32, (_) => secureRandom.nextInt(256)),
    );
    final seedHex = HEX.encode(seedBytes);
    
    setState(() {
      _selectedMode = 'generate';
      _generatedSeed = seedHex;
      _showQrExport = true;
    });
  }
  
  void _showMode000Confirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'Avertissement',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: const Text(
          'Vous êtes sur le point d\'activer le mode faible sécurité (seed 000…).\n\n'
          'Ce mode est volontairement vulnérable. Tout bon créé peut être cassé.\n\n'
          'Ceci est un défi ouvert aux chercheurs en sécurité.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showMode000TextConfirmation();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text(
              'Continuer',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showMode000TextConfirmation() {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Confirmation requise',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tapez HACKATHON pour confirmer :',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'HACKATHON',
                hintStyle: TextStyle(color: Colors.grey[600]),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.orange),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text == 'HACKATHON') {
                Navigator.pop(context);
                final seed = '0' * 64; // 32 octets de zéros
                _setSeedAndContinue(seed, 'mode000');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Texte incorrect'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text(
              'Confirmer',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
  
  void _setSeedAndContinue(String seed, String mode) {
    setState(() {
      _selectedMode = mode;
      _generatedSeed = seed;
    });
    
    final notifier = context.read<OnboardingNotifier>();
    notifier.setSeedMarket(seed, mode);
    
    // Afficher une confirmation puis continuer
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Seed configurée en mode $mode'),
        backgroundColor: Colors.green,
      ),
    );
    
    // Continuer après un court délai
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        widget.onNext();
      }
    });
  }
}
