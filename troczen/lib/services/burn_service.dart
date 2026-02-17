import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'crypto_service.dart';
import 'nostr_service.dart';
import 'storage_service.dart';
import '../models/bon.dart';
import '../models/nostr_profile.dart';

/// ✅ Service de révocation/burn de bons (kind 5)
/// Permet à l'émetteur de détruire un bon avec P1+P3
class BurnService {
  final CryptoService _cryptoService;
  final StorageService _storageService;

  BurnService({
    required CryptoService cryptoService,
    required StorageService storageService,
  })  : _cryptoService = cryptoService,
        _storageService = storageService;

  /// Brûler/révoquer un bon (émetteur uniquement)
  /// Nécessite P1 (ancre) + P3 (témoin)
  Future<bool> burnBon({
    required Bon bon,
    required String p1,
    required String reason,
  }) async {
    try {
      // 1. Récupérer P3 du cache
      final p3 = await _storageService.getP3FromCache(bon.bonId);
      if (p3 == null) {
        throw Exception('P3 non trouvée pour ce bon');
      }

      // 2. Reconstruire sk_B temporairement (P1 + P3)
      final nsecBon = _cryptoService.shamirCombine(p1, null, p3);

      // 3. Publier event kind 5 sur Nostr
      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );

      final market = await _storageService.getMarket();
      final relayUrl = market?.relayUrl ?? NostrConstants.defaultRelay;
      
      final connected = await nostrService.connect(relayUrl);
      if (!connected) {
        throw Exception('Impossible de se connecter au relais');
      }

      final burned = await nostrService.publishBurn(
        bonId: bon.bonId,
        nsecBon: nsecBon,
        reason: reason,
        marketName: market?.name ?? NostrConstants.globalMarketName,
      );

      await nostrService.disconnect();

      if (!burned) {
        throw Exception('Échec publication burn');
      }

      // ✅ SÉCURITÉ 100%: Nettoyage RAM après usage
      _cryptoService.secureZeroise(nsecBon);

      // 4. Marquer le bon comme brûlé localement
      final burnedBon = bon.copyWith(
        status: BonStatus.burned,
        p1: null,  // Supprime P1 après burn
      );
      await _storageService.saveBon(burnedBon);

      return true;
    } catch (e) {
      print('Erreur burn: $e');
      return false;
    }
  }

  /// Vérifier si un bon a été brûlé via Nostr
  Future<bool> isBonBurned(String bonId) async {
    // TODO: Vérifier via Nostr si event kind 5 existe pour ce bon
    // Pour l'instant, vérifier localement
    final bon = await _storageService.getBonById(bonId);
    return bon?.status == BonStatus.burned;
  }
}
