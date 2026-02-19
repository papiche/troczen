import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/nostr_service.dart';
import 'package:troczen/services/crypto_service.dart';
import 'package:troczen/services/storage_service.dart';
import 'package:troczen/models/market.dart';

void main() {
  group('NostrService', () {
    late NostrService nostrService;
    late CryptoService cryptoService;
    late StorageService storageService;

    setUp(() {
      cryptoService = CryptoService();
      storageService = StorageService();
      nostrService = NostrService(
        cryptoService: cryptoService,
        storageService: storageService,
      );
    });

    tearDown(() {
      nostrService.disconnect();
    });

    // --- TEST AUTO SYNC ---

    test('enableAutoSync active la sync automatique', () {
      final market = Market(
        name: 'Test Market',
        seedMarket: 'a' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
        relayUrl: 'wss://test.relay',
      );

      expect(nostrService.autoSyncEnabled, isFalse);

      nostrService.enableAutoSync(
        interval: const Duration(minutes: 5),
        initialMarket: market,
      );

      expect(nostrService.autoSyncEnabled, isTrue);
      expect(nostrService.lastSyncedMarket, equals(market));
    });

    test('disableAutoSync désactive la sync automatique', () {
      final market = Market(
        name: 'Test Market',
        seedMarket: 'b' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
      );

      nostrService.enableAutoSync(initialMarket: market);
      expect(nostrService.autoSyncEnabled, isTrue);

      nostrService.disableAutoSync();
      expect(nostrService.autoSyncEnabled, isFalse);
    });

    test('updateAutoSyncMarket met à jour le marché', () {
      final market1 = Market(
        name: 'Market 1',
        seedMarket: 'c' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
      );

      final market2 = Market(
        name: 'Market 2',
        seedMarket: 'd' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
      );

      nostrService.enableAutoSync(initialMarket: market1);
      expect(nostrService.lastSyncedMarket?.name, equals('Market 1'));

      nostrService.updateAutoSyncMarket(market2);
      expect(nostrService.lastSyncedMarket?.name, equals('Market 2'));
    });

    test('enableAutoSync avec interval personnalisé', () {
      final market = Market(
        name: 'Test',
        seedMarket: 'e' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
      );

      nostrService.enableAutoSync(
        interval: const Duration(minutes: 10),
        initialMarket: market,
      );

      // L'interval est enregistré (test indirect)
      expect(nostrService.autoSyncEnabled, isTrue);
    });

    // --- TEST CALLBACKS ---

    test('callbacks sont null-safe', () {
      // Les callbacks ne doivent pas planter même si non assignés
      expect(nostrService.onP3Received, isNull);
      expect(nostrService.onError, isNull);
      expect(nostrService.onConnectionChange, isNull);
    });

    test('callbacks peuvent être assignés', () {
      void onP3(String bonId, String p3) {}
      void onError(String error) {}
      void onConnection(bool connected) {}

      nostrService.onP3Received = onP3;
      nostrService.onError = onError;
      nostrService.onConnectionChange = onConnection;

      expect(nostrService.onP3Received, isNotNull);
      expect(nostrService.onError, isNotNull);
      expect(nostrService.onConnectionChange, isNotNull);
    });
  });
}
