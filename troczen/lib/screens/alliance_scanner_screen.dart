import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/storage_service.dart';

class AllianceScannerScreen extends StatefulWidget {
  const AllianceScannerScreen({super.key});

  @override
  State<AllianceScannerScreen> createState() => _AllianceScannerScreenState();
}

class _AllianceScannerScreenState extends State<AllianceScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null) return;

    setState(() => _isProcessing = true);

    try {
      final data = jsonDecode(rawValue);
      if (data['type'] == 'alliance' && data['seed_market'] != null) {
        final storageService = StorageService();
        final currentMarket = await storageService.getMarket();
        
        if (currentMarket != null) {
          final relays = List<String>.from(data['relays'] ?? []);
          final newRelayUrl = relays.isNotEmpty ? relays.first : currentMarket.relayUrl;
          
          final updatedMarket = currentMarket.copyWith(
            seedMarket: data['seed_market'],
            relayUrl: newRelayUrl,
          );
          
          await storageService.saveMarket(updatedMarket);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Alliance rejointe avec succès !'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context, true);
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('QR Code invalide pour une alliance.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur de lecture du QR Code.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner une Alliance'),
        backgroundColor: const Color(0xFF0A7EA4),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleScan,
          ),
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Placez le QR Code dans le cadre',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
