import 'package:flutter/material.dart';
import '../models/bon.dart';
import '../models/user.dart';
import '../services/storage_service.dart';
import '../services/nostr_service.dart';
import '../services/crypto_service.dart';
import '../widgets/panini_card.dart';
import '../screens/gallery_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/create_bon_screen.dart';

class WalletScreen extends StatefulWidget {
  final User user;

  const WalletScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  List<Bon> bons = [];

  @override
  void initState() {
    super.initState();
    _loadBons();
  }

  Future<void> _loadBons() async {
    // Charger les bons depuis le stockage
    final storageService = StorageService();
    final loadedBons = await storageService.getBons();
    setState(() {
      bons = loadedBons;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Portefeuille'),
        backgroundColor: const Color(0xFF0A7EA4),
      ),
      body: ListView.builder(
        itemCount: bons.length,
        itemBuilder: (context, index) {
          final bon = bons[index];
          return PaniniCard(bon: bon);
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Bouton scanner
          FloatingActionButton(
            heroTag: 'scan',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ScanScreen(user: widget.user),
                ),
              ).then((_) => _loadBons());
            },
            backgroundColor: const Color(0xFF0A7EA4),
            child: const Icon(Icons.qr_code_scanner),
          ),

          // Bouton créer bon
          FloatingActionButton(
            heroTag: 'create',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateBonScreen(user: widget.user),
                ),
              ).then((_) => _loadBons());
            },
            backgroundColor: const Color(0xFFFFB347),
            child: const Icon(Icons.add),
          ),

          // → NOUVEAU : Bouton collections
          FloatingActionButton(
            heroTag: 'collections',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GalleryScreen(user: widget.user),
                ),
              ).then((_) => _loadBons());
            },
            backgroundColor: const Color(0xFF0A7EA4),
            child: const Icon(Icons.collections),
          ),
        ],
      ),
    );
  }
}
