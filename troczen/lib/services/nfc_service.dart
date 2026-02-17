import 'dart:async';
import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'qr_service.dart';
import 'crypto_service.dart';

/// Service NFC pour transfert de bons par tap-to-pay
/// Alternative plus rapide au QR code (200ms vs 5-10s)
class NfcService {
  final QRService _qrService;
  final CryptoService _cryptoService;
  
  bool _isAvailable = false;
  bool _isProcessing = false;
  
  // Callbacks
  Function(String message)? onStatusChange;
  Function(String error)? onError;
  Function(Map<String, dynamic> offerData)? onOfferReceived;
  Function(Map<String, dynamic> ackData)? onAckReceived;

  NfcService({
    required QRService qrService,
    required CryptoService cryptoService,
  })  : _qrService = qrService,
        _cryptoService = cryptoService;

  /// Vérifier si NFC est disponible
  Future<bool> checkAvailability() async {
    try {
      _isAvailable = await NfcManager.instance.isAvailable();
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
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = Ndef.from(tag);
            
            if (ndef == null || !ndef.isWritable) {
              onError?.call('Tag NFC non compatible');
              return;
            }

            // Créer message NDEF
            final ndefMessage = NdefMessage([
              NdefRecord.createMime(
                'application/x-troczen-offer',
                Uint8List.fromList(offerBytes),
              ),
            ]);

            // Écrire sur le tag
            await ndef.write(ndefMessage);
            
            onStatusChange?.call('Offre envoyée ! Attendez l\'ACK...');
            
            // Attendre l'ACK du receveur
            await _waitForAck();
            
          } catch (e) {
            onError?.call('Erreur écriture NFC: $e');
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
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = Ndef.from(tag);
            
            if (ndef == null) {
              onError?.call('Tag NFC non compatible');
              return;
            }

            final ndefMessage = ndef.cachedMessage;
            if (ndefMessage == null || ndefMessage.records.isEmpty) {
              onError?.call('Aucune donnée NFC trouvée');
              return;
            }

            // Lire le premier record
            final record = ndefMessage.records.first;
            
            if (record.typeNameFormat != NdefTypeNameFormat.mime ||
                String.fromCharCodes(record.type) != 'application/x-troczen-offer') {
              onError?.call('Format NFC invalide');
              return;
            }

            // Décoder l'offre
            final offerData = _qrService.decodeOffer(record.payload);
            
            // Vérifier TTL
            if (_qrService.isExpired(offerData['timestamp'], offerData['ttl'])) {
              onError?.call('Offre expirée');
              return;
            }

            onStatusChange?.call('Offre reçue ! Validation...');
            
            // Notifier l'application
            onOfferReceived?.call(offerData);
            
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
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = Ndef.from(tag);
            
            if (ndef == null || !ndef.isWritable) {
              onError?.call('Tag NFC non compatible');
              return;
            }

            final ndefMessage = NdefMessage([
              NdefRecord.createMime(
                'application/x-troczen-ack',
                Uint8List.fromList(ackBytes),
              ),
            ]);

            await ndef.write(ndefMessage);
            
            onStatusChange?.call('Confirmation envoyée !');
            
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
      onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);
          
          if (ndef == null) return;

          final ndefMessage = ndef.cachedMessage;
          if (ndefMessage == null || ndefMessage.records.isEmpty) return;

          final record = ndefMessage.records.first;
          
          if (String.fromCharCodes(record.type) == 'application/x-troczen-ack') {
            final ackData = _qrService.decodeAck(record.payload);
            onAckReceived?.call(ackData);
            completer.complete();
          }
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
