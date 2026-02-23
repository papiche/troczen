import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/nostr_connection_service.dart';
import 'package:troczen/services/nostr_market_service.dart';
import 'package:troczen/services/nostr_wotx_service.dart';
import 'package:troczen/services/crypto_service.dart';
import 'package:troczen/services/storage_service.dart';
import 'package:troczen/models/market.dart';

/// Tests pour les services Nostr refactorisés
/// 
/// Architecture selon le principe SRP (Single Responsibility Principle):
/// - NostrConnectionService: Connexion WebSocket
/// - NostrMarketService: P3, Circuits, Marchés
/// - NostrWoTxService: Compétences, Attestations
void main() {
  group('NostrConnectionService', () {
    late NostrConnectionService service;

    setUp(() {
      service = NostrConnectionService();
    });

    tearDown(() {
      service.dispose();
    });

    test('État initial correct', () {
      expect(service.isConnected, isFalse);
      expect(service.currentRelay, isNull);
      expect(service.reconnectAttempts, equals(0));
      expect(service.isAppInBackground, isFalse);
    });

    test('Callbacks null-safe', () {
      expect(() => service.onConnectionChange?.call(true), returnsNormally);
      expect(() => service.onError?.call('test'), returnsNormally);
      expect(() => service.onMessage?.call(['test']), returnsNormally);
    });

    test('Cycle de vie application', () {
      expect(service.isAppInBackground, isFalse);
      
      service.onAppPaused();
      expect(service.isAppInBackground, isTrue);
      
      service.onAppResumed();
      expect(service.isAppInBackground, isFalse);
    });

    test('Gestion des handlers', () {
      var called = false;
      service.registerHandler('test', (msg) => called = true);
      
      expect(service.subscriptionHandlers.containsKey('test'), isTrue);
      
      service.removeHandler('test');
      expect(service.subscriptionHandlers.containsKey('test'), isFalse);
    });

    test('dispose nettoie les ressources', () {
      service.dispose();
      expect(service.isConnected, isFalse);
      expect(service.reconnectAttempts, equals(0));
    });
  });

  group('NostrMarketService', () {
    late NostrMarketService service;
    late NostrConnectionService connection;
    late CryptoService cryptoService;
    late StorageService storageService;

    setUp(() {
      connection = NostrConnectionService();
      cryptoService = CryptoService();
      storageService = StorageService();
      
      service = NostrMarketService(
        connection: connection,
        cryptoService: cryptoService,
        storageService: storageService,
      );
    });

    tearDown(() {
      service.dispose();
      connection.dispose();
    });

    test('État initial correct', () {
      expect(service.autoSyncEnabled, isFalse);
      expect(service.lastSyncedMarket, isNull);
    });

    test('enableAutoSync active la sync', () {
      final market = Market(
        name: 'Test Market',
        seedMarket: 'a' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
      );

      service.enableAutoSync(
        interval: const Duration(minutes: 5),
        initialMarket: market,
      );

      expect(service.autoSyncEnabled, isTrue);
      expect(service.lastSyncedMarket, equals(market));
    });

    test('disableAutoSync désactive la sync', () {
      final market = Market(
        name: 'Test Market',
        seedMarket: 'b' * 64,
        validUntil: DateTime.now().add(const Duration(days: 365)),
      );

      service.enableAutoSync(initialMarket: market);
      expect(service.autoSyncEnabled, isTrue);

      service.disableAutoSync();
      expect(service.autoSyncEnabled, isFalse);
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

      service.enableAutoSync(initialMarket: market1);
      expect(service.lastSyncedMarket?.name, equals('Market 1'));

      service.updateAutoSyncMarket(market2);
      expect(service.lastSyncedMarket?.name, equals('Market 2'));
    });

    test('Callbacks null-safe', () {
      expect(() => service.onP3Received?.call('test', 'p3'), returnsNormally);
      expect(() => service.onError?.call('test'), returnsNormally);
    });

    test('Cycle de vie', () {
      service.onAppPaused();
      service.onAppResumed();
      service.dispose();
      
      expect(service.autoSyncEnabled, isFalse);
    });
  });

  group('NostrWoTxService', () {
    late NostrWoTxService service;
    late NostrConnectionService connection;
    late CryptoService cryptoService;

    setUp(() {
      connection = NostrConnectionService();
      cryptoService = CryptoService();
      
      service = NostrWoTxService(
        connection: connection,
        cryptoService: cryptoService,
      );
    });

    tearDown(() {
      connection.dispose();
    });

    test('Callbacks null-safe', () {
      expect(() => service.onError?.call('test'), returnsNormally);
      expect(() => service.onTagsReceived?.call(['tag1', 'tag2']), returnsNormally);
    });
  });

  group('Intégration - Services ensemble', () {
    test('Les services peuvent coexister', () {
      final connection = NostrConnectionService();
      final cryptoService = CryptoService();
      final storageService = StorageService();
      
      final marketService = NostrMarketService(
        connection: connection,
        cryptoService: cryptoService,
        storageService: storageService,
      );
      
      final wotxService = NostrWoTxService(
        connection: connection,
        cryptoService: cryptoService,
      );

      expect(marketService, isNotNull);
      expect(wotxService, isNotNull);
      
      // Nettoyage
      marketService.dispose();
      connection.dispose();
    });
  });
}
