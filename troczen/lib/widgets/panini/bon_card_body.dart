import 'package:flutter/material.dart';
import '../../models/bon.dart';
import '../../utils/bon_extensions.dart';
import 'offline_first_image.dart';

/// Corps de la carte Panini affichant l'image, le nom et les informations de transfert.
///
/// Note: Selon les standards NIP nostr, le champ `picture` est utilisé
/// pour l'image du profil (le logo circulaire). La bannière est gérée en fond de carte.
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
        // On rend le fond un peu plus transparent pour laisser voir la bannière en dessous
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[
            // Image du profil (Avatar circulaire bien net) - OFFLINE-FIRST
            if (pictureUrl != null && pictureUrl.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow:[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: OfflineFirstImage(
                    url: pictureUrl,
                    localPath: localPicturePath,
                    fallbackBase64: bon.picture64,
                    width: 64,
                    height: 64,
                    color: color,
                    rarity: rarity,
                    isPending: isPending,
                    fit: BoxFit.cover,
                    isChecking: isCheckingCache,
                  ),
                ),
              )
            else
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.8),
                  border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
                ),
                child: Center(
                  child: Icon(
                    RarityHelper.getDefaultIcon(rarity),
                    size: 36,
                    color: color.withValues(alpha: isPending ? 0.3 : 1.0),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            
            // Nom de l'émetteur
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                bon.issuerName,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[900],
                  // Ombre légère pour garantir la lisibilité sur fond de bannière
                  shadows:[
                    Shadow(
                      color: Colors.white.withValues(alpha: 0.8),
                      blurRadius: 2,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
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
      padding: EdgeInsets.only(top: 8),
      child: _TransferCountBadge(),
    );
  }
}

/// Badge affichant le nombre de transferts d'un bon
class _TransferCountBadge extends StatelessWidget {
  const _TransferCountBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:[
          Icon(Icons.swap_horiz, size: 14, color: Colors.blue.shade700),
          const SizedBox(width: 4),
          Text(
            'passages',
            style: TextStyle(
              fontSize: 11,
              color: Colors.blue.shade700,
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
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[
            // Image du profil (Avatar circulaire bien net) - OFFLINE-FIRST
            if (pictureUrl != null && pictureUrl.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow:[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: OfflineFirstImage(
                    url: pictureUrl,
                    localPath: localPicturePath,
                    fallbackBase64: bon.picture64,
                    width: 64,
                    height: 64,
                    color: color,
                    rarity: rarity,
                    isPending: isPending,
                    fit: BoxFit.cover,
                    isChecking: isCheckingCache,
                  ),
                ),
              )
            else
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.8),
                  border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
                ),
                child: Center(
                  child: Icon(
                    RarityHelper.getDefaultIcon(rarity),
                    size: 36,
                    color: color.withValues(alpha: isPending ? 0.3 : 1.0),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            
            // Nom de l'émetteur
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                bon.issuerName,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[900],
                  shadows:[
                    Shadow(
                      color: Colors.white.withValues(alpha: 0.8),
                      blurRadius: 2,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Compteur de passages (si disponible)
            if (bon.transferCount != null && bon.transferCount! > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children:[
                    Icon(Icons.swap_horiz, size: 14, color: Colors.blue.shade700),
                    const SizedBox(width: 4),
                    Text(
                      '${bon.transferCount} passages',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
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