import 'dart:async';
import 'package:nfc_manager/nfc_manager.dart';
import 'qr_service.dart';

/// Service NFC pour transfert de bons par tap-to-pay
/// Alternative plus rapide au QR code (200ms vs 5-10s)
/// NOTE: Implémentation simplifiée - nécessite une configuration spécifique par plateforme
class NfcService {
  final QRService _qrService;
  
  bool _isAvailable = false;
  bool _isProcessing = false;
  
  // Callbacks
  Function(String message)? onStatusChange;
  Function(String error)? onError;
  Function(Map<String, dynamic> offerData)? onOfferReceived;
  Function(Map<String, dynamic> ackData)? onAckReceived;

  NfcService({
    required QRService qrService,
  })  : _qrService = qrService;

  /// Vérifier si NFC est disponible
  Future<bool> checkAvailability() async {
    try {
      final isAvailable = await NfcManager.instance.isAvailable();
      _isAvailable = isAvailable;
      return _isAvailable;
    } catch (e) {
      onError?.call('Erreur vérification NFC: $e');
      return false;
    }
  }

  /// Mode Donneur : Émettre une offre via NFC
  Future<void> startOfferSession({
    required String bonId,
    required String p2Encrypted,
    required String nonce,
    required String challenge,
    required int timestamp,
    int ttl = 30,
  }) async {
    if (!_isAvailable) {
      onError?.call('NFC non disponible');
      return;
    }

    if (_isProcessing) {
      onError?.call('Une session NFC est déjà en cours');
      return;
    }

    _isProcessing = true;
    onStatusChange?.call('Approchez les téléphones...');

    try {
      // Encoder l'offre en binaire (même format que QR)
      final offerBytes = _qrService.encodeOffer(
        bonIdHex: bonId,
        p2CipherHex: p2Encrypted,
        nonceHex: nonce,
        challengeHex: challenge,
        timestamp: timestamp,
        ttl: ttl,
      );

      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        onDiscovered: (NfcTag tag) async {
          try {
            // TODO: Implémentation NFC complète requiert configuration plateforme spécifique
            // Pour l'instant, simuler un envoi réussi
            onStatusChange?.call('NFC: Fonctionnalité en développement');
            onError?.call('Veuillez utiliser le QR code pour l\'instant');
            
          } catch (e) {
            onError?.call('Erreur NFC: $e');
          } finally {
            await NfcManager.instance.stopSession();
            _isProcessing = false;
          }
        },
      );
    } catch (e) {
      onError?.call('Erreur session NFC: $e');
      _isProcessing = false;
    }
  }

  /// Mode Receveur : Lire une offre via NFC
  Future<void> startReceiveSession() async {
    if (!_isAvailable) {
      onError?.call('NFC non disponible');
      return;
    }

    if (_isProcessing) {
      onError?.call('Une session NFC est déjà en cours');
      return;
    }

    _isProcessing = true;
    onStatusChange?.call('Approchez votre téléphone...');

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        onDiscovered: (NfcTag tag) async {
          try {
            // TODO: Implémentation NFC complète
            onStatusChange?.call('NFC: Fonctionnalité en développement');
            onError?.call('Veuillez utiliser le QR code pour l\'instant');
            
          } catch (e) {
            onError?.call('Erreur lecture NFC: $e');
          } finally {
            await NfcManager.instance.stopSession();
            _isProcessing = false;
          }
        },
      );
    } catch (e) {
      onError?.call('Erreur session NFC: $e');
      _isProcessing = false;
    }
  }

  /// Envoyer l'ACK au donneur via NFC
  Future<void> sendAck({
    required String bonId,
    required String signature,
    int status = 0x01,
  }) async {
    if (!_isAvailable) {
      onError?.call('NFC non disponible');
      return;
    }

    onStatusChange?.call('Envoi de la confirmation...');

    try {
      // Encoder l'ACK
      final ackBytes = _qrService.encodeAck(
        bonIdHex: bonId,
        signatureHex: signature,
        status: status,
      );

      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        onDiscovered: (NfcTag tag) async {
          try {
            // TODO: Implémentation NFC complète
            onStatusChange?.call('NFC: Fonctionnalité en développement');
            onError?.call('Veuillez utiliser le QR code pour l\'instant');
            
          } catch (e) {
            onError?.call('Erreur envoi ACK: $e');
          } finally {
            await NfcManager.instance.stopSession();
          }
        },
      );
    } catch (e) {
      onError?.call('Erreur ACK NFC: $e');
    }
  }

  /// Attendre l'ACK du receveur
  Future<void> _waitForAck() async {
    final completer = Completer<void>();
    
    await NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (NfcTag tag) async {
        try {
          // TODO: Implémentation NFC complète
          onError?.call('NFC: Fonctionnalité en développement');
          completer.completeError('NFC non implémenté');
        } catch (e) {
          onError?.call('Erreur lecture ACK: $e');
          completer.completeError(e);
        }
      },
    );

    // Timeout après 30 secondes
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        onError?.call('Timeout: Aucun ACK reçu');
        NfcManager.instance.stopSession();
      },
    );
  }

  /// Arrêter la session NFC en cours
  Future<void> stopSession() async {
    await NfcManager.instance.stopSession();
    _isProcessing = false;
    onStatusChange?.call('Session arrêtée');
  }

  bool get isAvailable => _isAvailable;
  bool get isProcessing => _isProcessing;
}
