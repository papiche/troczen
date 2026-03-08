import 'dart:typed_data';
import 'package:hex/hex.dart';
import 'crypto_service.dart';
import 'nostr_service.dart';
import 'storage_service.dart';
import 'logger_service.dart';
import '../models/bon.dart';
import '../models/nostr_profile.dart';
import '../config/app_config.dart';

/// ✅ Service de Révélation/Circuit de bons
///
/// Le terme "Burn" (brûler/détruire) vient de la crypto classique.
/// Dans TrocZen, fermer une boucle ne détruit pas la valeur, cela crée de l'information.
/// Le Carnet de Voyage devient une preuve économique (Kind 30304).
///
/// Ce service combine:
/// - Kind 5: Burn classique (révocation technique)
/// - Kind 30304: Révélation du Circuit (preuve économique)
class BurnService {
  final CryptoService _cryptoService;
  final StorageService _storageService;

  BurnService({
    required CryptoService cryptoService,
    required StorageService storageService,
  })  : _cryptoService = cryptoService,
        _storageService = storageService;

  /// Révéler/Clore le circuit d'un bon (émetteur uniquement)
  /// Nécessite P1 (ancre) + P3 (témoin)
  ///
  /// En plus du Kind 5 (Burn), publie un Kind 30304 (Circuit/Révélation)
  /// qui transforme le parcours du bon en preuve économique.
  Future<bool> burnBon({
    required Bon bon,
    required String p1,
    required String reason,
    String? skillAnnotation,  // ✅ Bonus: Compétence associée au parcours
  }) async {
    Uint8List? p3Bytes;
    Uint8List? p1Bytes;
    Uint8List? nsecBonBytes;
    try {
      // 1. ✅ SÉCURITÉ: Récupérer P3 du cache en Uint8List directement
      p3Bytes = await _storageService.getP3FromCacheBytes(bon.bonId);
      if (p3Bytes == null) {
        throw Exception('P3 non trouvée pour ce bon');
      }

      // 2. Convertir P1 en Uint8List
      try {
        p1Bytes = Uint8List.fromList(HEX.decode(p1));
      } catch (e) {
        throw Exception('P1 invalide (non hexadécimal)');
      }

      // 3. ✅ SÉCURITÉ: Reconstruire sk_B temporairement en Uint8List (P1 + P3)
      nsecBonBytes = _cryptoService.shamirCombineBytesDirect(p1Bytes, null, p3Bytes);

      // 4. Extraire les données du parcours pour la Révélation
      final hopCount = bon.transferCount ?? 0;
      final ageDays = DateTime.now().difference(bon.createdAt).inDays;
      
      Logger.log('BurnService',
          'Révélation circuit: ${bon.bonId} | ${bon.value}ẐEN | $hopCount hops | $ageDays jours');

      // 5. Publier les events sur Nostr
      final nostrService = NostrService(cryptoService: _cryptoService, storageService: _storageService);

      final market = await _storageService.getMarket();
      final relayUrl = market?.relayUrl ?? AppConfig.defaultRelayUrl;
      
      final connected = await nostrService.connect(relayUrl);
      if (!connected) {
        throw Exception('Impossible de se connecter au relais');
      }

      // 6. ✅ NOUVEAU: Publier la Révélation du Circuit (Kind 30304)
      // Le Carnet de Voyage devient une preuve économique
      // ✅ SÉCURITÉ: Le contenu est chiffré avec la Seed du Marché
      final circuitPublished = await nostrService.market.publishBonCircuit(
        bonId: bon.bonId,
        valueZen: bon.value,
        hopCount: hopCount,
        ageDays: ageDays,
        marketName: market?.name ?? NostrConstants.globalMarketName,
        issuerNpub: bon.issuerNpub,
        nsecBonBytes: nsecBonBytes,
        seedMarket: market?.seedMarket ?? '',  // ✅ SÉCURITÉ: Seed pour chiffrement
        skillAnnotation: skillAnnotation,  // Bonus: compétence associée
      );
      
      if (circuitPublished) {
        Logger.log('BurnService', '✅ Circuit révélé (Kind 30304)');
      } else {
        Logger.warn('BurnService', '⚠️ Échec publication Circuit (Kind 30304)');
      }

      // 7. ✅ SÉCURITÉ: Utiliser la version Uint8List de publishBurn
      final burned = await nostrService.publishBurnBytes(
        bonId: bon.bonId,
        nsecBonBytes: nsecBonBytes,
        reason: reason,
        marketName: market?.name ?? NostrConstants.globalMarketName,
      );

      await nostrService.disconnect();

      if (!burned) {
        throw Exception('Échec publication burn');
      }

      // 8. Marquer le bon comme révélé/clos localement
      final burnedBon = bon.copyWith(
        status: BonStatus.burned,
        p1: null,  // Supprime P1 après burn
      );
      await _storageService.saveBon(burnedBon);

      Logger.log('BurnService',
          '🎉 Bon révélé: ${bon.bonId} | Circuit: $hopCount hops, $ageDays jours');
      
      return true;
    } catch (e) {
      Logger.error('BurnService', 'Erreur burn/révélation', e);
      return false;
    } finally {
      if (nsecBonBytes != null) _cryptoService.secureZeroiseBytes(nsecBonBytes);
      if (p1Bytes != null) _cryptoService.secureZeroiseBytes(p1Bytes);
      if (p3Bytes != null) _cryptoService.secureZeroiseBytes(p3Bytes);
    }
  }

  /// Vérifier si un bon a été brûlé/révélé via Nostr
  Future<bool> isBonBurned(String bonId) async {
    // TODO: Vérifier via Nostr si event kind 5 existe pour ce bon
    // Pour l'instant, vérifier localement
    final bon = await _storageService.getBonById(bonId);
    return bon?.status == BonStatus.burned;
  }
  
  /// ✅ NOUVEAU: Récupérer les statistiques de circuit d'un bon
  /// Utile pour afficher le résumé avant révélation
  Map<String, dynamic> getCircuitStats(Bon bon) {
    final hopCount = bon.transferCount ?? 0;
    final ageDays = DateTime.now().difference(bon.createdAt).inDays;
    
    return {
      'bon_id': bon.bonId,
      'value_zen': bon.value,
      'hop_count': hopCount,
      'age_days': ageDays,
      'market': bon.marketName,
      'created_at': bon.createdAt.toIso8601String(),
    };
  }
}
