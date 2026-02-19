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
      nostrService.dispose();
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

    // --- TEST CYCLE DE VIE APPLICATION ---

    test('onAppPaused met l\'application en arrière-plan', () {
      final market = Market(
        name: 'Test Market',
        seedMarket: 'f' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
      );

      nostrService.enableAutoSync(initialMarket: market);
      expect(nostrService.isAppInBackground, isFalse);

      nostrService.onAppPaused();
      expect(nostrService.isAppInBackground, isTrue);
    });

    test('onAppResumed remet l\'application au premier plan', () {
      final market = Market(
        name: 'Test Market',
        seedMarket: 'g' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
      );

      nostrService.enableAutoSync(initialMarket: market);
      nostrService.onAppPaused();
      expect(nostrService.isAppInBackground, isTrue);

      nostrService.onAppResumed();
      expect(nostrService.isAppInBackground, isFalse);
    });

    test('dispose nettoie toutes les ressources', () {
      final market = Market(
        name: 'Test Market',
        seedMarket: 'h' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
      );

      nostrService.enableAutoSync(initialMarket: market);
      expect(nostrService.autoSyncEnabled, isTrue);

      nostrService.dispose();
      expect(nostrService.autoSyncEnabled, isFalse);
      expect(nostrService.reconnectAttempts, equals(0));
    });

    // --- TEST RECONNEXION AUTOMATIQUE ---

    test('reconnectAttempts est initialisé à 0', () {
      expect(nostrService.reconnectAttempts, equals(0));
    });

    test('forceReconnect reset le compteur de reconnexion', () async {
      // Simuler des tentatives de reconnexion
      // (normalement fait via _scheduleReconnect qui est privé)
      
      // forceReconnect reset le compteur
      await nostrService.forceReconnect();
      expect(nostrService.reconnectAttempts, equals(0));
    });

    test('isConnected retourne false initialement', () {
      expect(nostrService.isConnected, isFalse);
    });

    test('currentRelay retourne null initialement', () {
      expect(nostrService.currentRelay, isNull);
    });
  });
}
