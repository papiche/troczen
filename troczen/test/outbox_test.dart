import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/cache_database_service.dart';
import 'test_helper.dart';

void main() {
  setUpAll(() {
    setupTestEnvironment();
  });

  group('Outbox (pending_events) Tests', () {
    late CacheDatabaseService cacheDb;

    setUp(() async {
      cacheDb = CacheDatabaseService();
      await cacheDb.clearAllCache(); // S'assurer que la base est vide
    });

    test('Sauvegarde et récupération d\'un événement en attente', () async {
      final event = {
        'id': 'event_123',
        'kind': 1,
        'content': 'test',
      };

      await cacheDb.savePendingEvent(event);

      final pendingEvents = await cacheDb.getPendingEvents();
      expect(pendingEvents.length, 1);
      expect(pendingEvents.first['id'], 'event_123');
      expect(pendingEvents.first['kind'], 1);
      expect(pendingEvents.first['content'], 'test');

      final count = await cacheDb.getPendingEventsCount();
      expect(count, 1);
    });

    test('Suppression d\'un événement en attente', () async {
      final event = {
        'id': 'event_456',
        'kind': 1,
        'content': 'test',
      };

      await cacheDb.savePendingEvent(event);
      var count = await cacheDb.getPendingEventsCount();
      expect(count, 1);

      await cacheDb.deletePendingEvent('event_456');
      count = await cacheDb.getPendingEventsCount();
      expect(count, 0);
    });

    test('Incrémentation des tentatives', () async {
      final event = {
        'id': 'event_789',
        'kind': 1,
        'content': 'test',
      };

      await cacheDb.savePendingEvent(event);
      
      // On ne peut pas vérifier directement 'attempts' via getPendingEvents car il retourne le JSON,
      // mais on peut vérifier que la méthode ne plante pas.
      await cacheDb.incrementPendingEventAttempts('event_789');
      
      final count = await cacheDb.getPendingEventsCount();
      expect(count, 1);
    });
  });
}
