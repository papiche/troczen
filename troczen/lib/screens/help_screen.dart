import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user.dart';
import '../config/app_config.dart';
import 'feedback_screen.dart';

/// Écran d'aide avec toutes les actions possibles
class HelpScreen extends StatelessWidget {
  final User user;

  const HelpScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Aide & Documentation'),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FeedbackScreen(user: user),
                ),
              );
            },
            tooltip: 'Signaler un problème',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Carte bienvenue
          _buildWelcomeCard(),
          
          const SizedBox(height: 24),
          
          // Actions principales
          _buildSectionTitle('🎯 Actions Principales'),
          _buildActionCard(
            context,
            icon: Icons.add_circle,
            title: 'Créer un bon',
            description: 'Émettez un bon de valeur locale (ẐEN)',
            steps: [
              '1. Tapez sur le bouton + jaune',
              '2. Entrez la valeur et votre nom',
              '3. Le bon apparaît dans votre wallet',
              '✅ Il est automatiquement publié sur Nostr',
            ],
          ),
          
          _buildActionCard(
            context,
            icon: Icons.qr_code_scanner,
            title: 'Scanner un bon',
            description: 'Recevez un bon d\'un autre utilisateur',
            steps: [
              '1. Tapez sur le bouton 📷 bleu',
              '2. Scannez le QR code du donneur',
              '3. Vérification automatique avec P3',
              '4. Montrez votre QR de confirmation',
              '✅ Le bon est dans votre wallet',
            ],
          ),
          
          _buildActionCard(
            context,
            icon: Icons.send,
            title: 'Donner un bon',
            description: 'Transférez un bon à quelqu\'un',
            steps: [
              '1. Sélectionnez un bon dans votre wallet',
              '2. Choisissez "Donner ce bon"',
              '3. Montrez le QR au receveur (30s)',
              '4. Attendez sa confirmation',
              '5. Scannez son QR de confirmation',
              '✅ Le bon est transféré en toute sécurité',
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Configuration
          _buildSectionTitle(' ⚙️ Configuration'),
          
          _buildActionCard(
            context,
            icon: Icons.store,
            title: 'Configurer un marché',
            description: 'Rejoindre un marché local ou global',
            steps: [
              '1. Tapez sur l\'icône ⚙️ en haut',
              '2. Option A: "Marché global TrocZen"',
              '   → Configuration automatique',
              '2. Option B: Marché spécifique',
              '   → Scannez le QR de la borne',
              '   → Ou entrez manuellement la clé',
              '✅ Vous êtes connecté au marché',
            ],
          ),
          
          _buildActionCard(
            context,
            icon: Icons.sync,
            title: 'Synchronisation',
            description: 'Récupérer les bons du réseau',
            steps: [
              '• Sync automatique au démarrage',
              '• Bouton sync manuel (⟳ en haut)',
              '• Récupère les P3 depuis Nostr',
              '✅ Permet de valider les bons reçus',
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Sécurité
          _buildSectionTitle('🔐 Sécurité'),
          
          _buildInfoCard(
            icon: Icons.security,
            title: 'Cryptographie',
            content: '''
• Partage de secret Shamir (2-sur-3)
• Chiffrement AES-256-GCM
• Signatures Schnorr (secp256k1)
• Stockage sécurisé (Keystore/Keychain)
• Clés jamais stockées en clair
            ''',
          ),
          
          _buildInfoCard(
            icon: Icons.lock,
            title: 'Vos identifiants',
            content: '''
⚠️ IMPORTANT:
Votre login et mot de passe génèrent votre identité cryptographique.

• Ne les perdez PAS
• Ne les partagez JAMAIS
• Notez-les en lieu sûr

Si vous les perdez, vos bons sont perdus !
            ''',
          ),
          
          const SizedBox(height: 24),
          
          // Concepts
          _buildSectionTitle('💡 Concepts Clés'),
          
          _buildInfoCard(
            icon: Icons.category,
            title: 'Les 3 Parts (P1, P2, P3)',
            content: '''
Chaque bon est divisé en 3 parts:

• P1 (Ancre) - Reste chez l'émetteur
  → Permet la révocation

• P2 (Voyageur) - Circule de main en main
  → Représente la valeur

• P3 (Témoin) - Publiée sur Nostr
  → Permet la validation

N'importe quelles 2 parts permettent de reconstituer le bon temporairement en RAM.
            ''',
          ),
          
          _buildInfoCard(
            icon: Icons.stars,
            title: 'Rareté des Bons',
            content: '''
Les bons ont des raretés aléatoires:

🟢 Commun (79%) - Standard
🔵 Peu Commun (15%) - Vert/Teal
🟣 Rare (5%) - Animation holographique
🟠 Légendaire (1%) - Effet doré brillant

Les bons rares ont des animations spéciales !
            ''',
          ),
          
          _buildInfoCard(
            icon: Icons.offline_bolt,
            title: 'Offline-First',
            content: '''
TrocZen fonctionne SANS Internet:

✅ Transferts offline complets
✅ Validation avec cache P3 local
✅ Synchronisation quand réseau revient
✅ Comme du cash physique

Internet requis seulement pour:
• Première synchronisation P3
• Publication de nouveaux bons
            ''',
          ),
          
          const SizedBox(height: 24),
          
          // Dépannage
          _buildSectionTitle('🔧 Dépannage'),
          
          _buildTroubleshootCard(
            question: 'Le scan ne fonctionne pas',
            answer: '''
• Vérifiez la permission caméra
• Nettoyez l'objectif
• Bon éclairage requis
• Tenez l'appareil stable
• QR code visible en entier
            ''',
          ),
          
          _buildTroubleshootCard(
            question: 'Erreur "P3 non trouvée"',
            answer: '''
• Synchronisez avec le marché (⟳)
• Vérifiez la connexion réseau
• Configurez le marché d'abord
• Attendez quelques secondes et réessayez
            ''',
          ),
          
          _buildTroubleshootCard(
            question: 'QR code expiré',
            answer: '''
• Les QR expirent après 30 secondes
• Le donneur doit "Régénérer"
• C'une sécurité contre le rejeu
            ''',
          ),
          
          const SizedBox(height: 24),
          
          // Bouton feedback
          _buildFeedbackButton(context),
          
          const SizedBox(height: 16),
          
          // Informations
          _buildAboutCard(),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.help_center, size: 64, color: Colors.white),
          const SizedBox(height: 12),
          const Text(
            'Bienvenue dans TrocZen',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Le troc local, simple et zen 🌻',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFB347),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required List<String> steps,
  }) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(icon, color: const Color(0xFFFFB347)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: steps.map((step) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    step,
                    style: TextStyle(
                      color: Colors.grey[300],
                      height: 1.5,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFFFFB347)),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content.trim(),
              style: TextStyle(
                color: Colors.grey[300],
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTroubleshootCard({
    required String question,
    required String answer,
  }) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: const Icon(Icons.help_outline, color: Colors.orange),
        title: Text(
          question,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              answer.trim(),
              style: TextStyle(
                color: Colors.grey[300],
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FeedbackScreen(user: user),
          ),
        );
      },
      icon: const Icon(Icons.feedback),
      label: const Text('Envoyer un feedback ou signaler un bug'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildAboutCard() {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'À propos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Version: ${AppConfig.appVersion}',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (ctx) => GestureDetector(
                onTap: () {
                  Clipboard.setData(
                    const ClipboardData(text: 'https://github.com/papiche/troczen'),
                  );
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Lien copié !')),
                  );
                },
                child: const Text(
                  'GitHub: github.com/papiche/troczen',
                  style: TextStyle(
                    color: Color(0xFF0A7EA4),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Relay: ${AppConfig.defaultRelayUrl.replaceFirst('wss://', '')}',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            Text(
              'TrocZen est un système de monnaie locale offline-first, '
              'utilisant la cryptographie Nostr et le partage de secret Shamir.',
              style: TextStyle(
                color: Colors.grey[300],
                height: 1.5,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
