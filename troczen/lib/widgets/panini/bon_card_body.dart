import 'package:flutter/material.dart';
import '../../models/bon.dart';
import '../../utils/bon_extensions.dart';
import 'offline_first_image.dart';

/// Corps de la carte Panini affichant l'image, le nom et les informations de transfert.
///
/// Note: Selon les standards NIP nostr, le champ `picture` est utilisé
/// pour l'image du profil. Il n'y a pas de distinction entre logo et avatar.
///
/// Exemple d'utilisation:
/// ```dart
/// BonCardBody(
///   bon: bon,
///   color: color,
///   localPicturePath: localPicturePath,
///   isCheckingCache: isCheckingCache,
/// )
/// ```
class BonCardBody extends StatelessWidget {
  final Bon bon;
  final Color color;
  /// Chemin local de l'image mise en cache (picture selon NIP nostr)
  final String? localPicturePath;
  final bool isCheckingCache;

  const BonCardBody({
    super.key,
    required this.bon,
    required this.color,
    this.localPicturePath,
    this.isCheckingCache = false,
  });

  @override
  Widget build(BuildContext context) {
    final rarity = bon.rarity ?? 'common';
    final isPending = bon.status == BonStatus.pending;
    // Utiliser picture (NIP nostr) avec fallback sur logoUrl pour compatibilité
    final pictureUrl = bon.picture ?? bon.logoUrl;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Image du profil - OFFLINE-FIRST (picture selon NIP nostr)
            if (pictureUrl != null && pictureUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: OfflineFirstImage(
                  url: pictureUrl,
                  localPath: localPicturePath,
                  width: 60,
                  height: 60,
                  color: color,
                  rarity: rarity,
                  isPending: isPending,
                  fit: BoxFit.cover,
                  isChecking: isCheckingCache,
                ),
              )
            else
              Icon(
                RarityHelper.getDefaultIcon(rarity),
                size: 48,
                color: color.withValues(alpha: isPending ? 0.3 : 1.0),
              ),
            const SizedBox(height: 8),
            
            // Nom de l'émetteur
            Text(
              bon.issuerName,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
            ),

            // Compteur de passages (si disponible)
            if (bon.transferCount != null && bon.transferCount! > 0)
              _buildTransferCount(),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferCount() {
    return const Padding(
      padding: EdgeInsets.only(top: 4),
      child: _TransferCountBadge(),
    );
  }
}

/// Badge affichant le nombre de transferts d'un bon
class _TransferCountBadge extends StatelessWidget {
  const _TransferCountBadge();

  @override
  Widget build(BuildContext context) {
    // Note: Le transferCount est passé via le Bon parent
    // Ce widget est simplifié pour l'affichage statique
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz, size: 12, color: Colors.blue),
          SizedBox(width: 4),
          Text(
            'passages',
            style: TextStyle(
              fontSize: 10,
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Version complète du corps avec le compteur de transferts intégré
class BonCardBodyWithTransfers extends StatelessWidget {
  final Bon bon;
  final Color color;
  /// Chemin local de l'image mise en cache (picture selon NIP nostr)
  final String? localPicturePath;
  final bool isCheckingCache;

  const BonCardBodyWithTransfers({
    super.key,
    required this.bon,
    required this.color,
    this.localPicturePath,
    this.isCheckingCache = false,
  });

  @override
  Widget build(BuildContext context) {
    final rarity = bon.rarity ?? 'common';
    final isPending = bon.status == BonStatus.pending;
    // Utiliser picture (NIP nostr) avec fallback sur logoUrl pour compatibilité
    final pictureUrl = bon.picture ?? bon.logoUrl;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Image du profil - OFFLINE-FIRST (picture selon NIP nostr)
            if (pictureUrl != null && pictureUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: OfflineFirstImage(
                  url: pictureUrl,
                  localPath: localPicturePath,
                  width: 60,
                  height: 60,
                  color: color,
                  rarity: rarity,
                  isPending: isPending,
                  fit: BoxFit.cover,
                  isChecking: isCheckingCache,
                ),
              )
            else
              Icon(
                RarityHelper.getDefaultIcon(rarity),
                size: 48,
                color: color.withValues(alpha: isPending ? 0.3 : 1.0),
              ),
            const SizedBox(height: 8),
            
            // Nom de l'émetteur
            Text(
              bon.issuerName,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
            ),

            // Compteur de passages (si disponible)
            if (bon.transferCount != null && bon.transferCount! > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_horiz, size: 12, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      '${bon.transferCount} passages',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
