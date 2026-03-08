import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/market.dart';

class AllianceQrScreen extends StatelessWidget {
  final Market market;

  const AllianceQrScreen({super.key, required this.market});

  @override
  Widget build(BuildContext context) {
    final payload = jsonEncode({
      'type': 'alliance',
      'seed_market': market.seedMarket,
      'relays': [
        market.relayUrl ?? 'ws://10.42.0.1:7777',
        // On pourrait ajouter d'autres relais ici
      ],
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Code d\'Alliance'),
        backgroundColor: const Color(0xFF0A7EA4),
      ),
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Scannez ce QR Code pour rejoindre l\'Alliance',
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 250.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Ce QR Code contient la graine du marché et les relais associés pour unifier les réseaux.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
