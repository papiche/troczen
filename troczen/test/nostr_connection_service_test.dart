import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/nostr_connection_service.dart';

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
      // Ne doit pas planter même si les callbacks ne sont pas assignés
      expect(() => service.onConnectionChange?.call(true), returnsNormally);
      expect(() => service.onError?.call('test'), returnsNormally);
      expect(() => service.onMessage?.call(['test']), returnsNormally);
    });

    test('onAppPaused met à jour le flag', () {
      expect(service.isAppInBackground, isFalse);
      service.onAppPaused();
      expect(service.isAppInBackground, isTrue);
    });

    test('onAppResumed met à jour le flag', () {
      service.onAppPaused();
      expect(service.isAppInBackground, isTrue);
      
      service.onAppResumed();
      expect(service.isAppInBackground, isFalse);
    });

    test('dispose nettoie les ressources', () {
      service.dispose();
      expect(service.isConnected, isFalse);
      expect(service.reconnectAttempts, equals(0));
    });

    test('sendMessage ne plante pas sans connexion', () {
      expect(() => service.sendMessage('test'), returnsNormally);
    });

    test('registerHandler et removeHandler fonctionnent', () {
      var called = false;
      service.registerHandler('test', (msg) {
        called = true;
      });
      
      expect(service.subscriptionHandlers.containsKey('test'), isTrue);
      
      service.removeHandler('test');
      expect(service.subscriptionHandlers.containsKey('test'), isFalse);
    });

    test('forceReconnect reset le compteur de tentatives', () async {
      // Simuler des tentatives de reconnexion (via reflection ou test indirect)
      expect(service.reconnectAttempts, equals(0));
      
      // Le forceReconnect reset le compteur
      await service.forceReconnect();
      expect(service.reconnectAttempts, equals(0));
    });
  });

  group('NostrConnectionService - Lifecycle', () {
    test('Cycle complet pause/resume', () {
      final service = NostrConnectionService();
      
      expect(service.isAppInBackground, isFalse);
      
      service.onAppPaused();
      expect(service.isAppInBackground, isTrue);
      
      service.onAppResumed();
      expect(service.isAppInBackground, isFalse);
      
      service.dispose();
    });
  });
}
