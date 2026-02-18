import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/storage_service.dart';
import 'package:troczen/models/user.dart';
import 'package:troczen/models/bon.dart';
import 'package:troczen/models/market.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  late StorageService storageService;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    storageService = StorageService();
  });

  group('StorageService - User Management', () {
    test('saveUser et getUser fonctionnent correctement', () async {
      final user = User(
        npub: 'test_npub_123',
        nsec: 'test_nsec_123',
        displayName: 'Alice',
        createdAt: DateTime.now(),
      );

      await storageService.saveUser(user);
      final retrieved = await storageService.getUser();

      expect(retrieved, isNotNull);
      expect(retrieved!.npub, equals(user.npub));
      expect(retrieved.nsec, equals(user.nsec));
      expect(retrieved.displayName, equals(user.displayName));
    });

    test('getUser retourne null si aucun utilisateur', () async {
      final user = await storageService.getUser();
      expect(user, isNull);
    });

    test('deleteUser supprime l\'utilisateur', () async {
      final user = User(
        npub: 'test_npub',
        nsec: 'test_nsec',
        displayName: 'Bob',
        createdAt: DateTime.now(),
      );

      await storageService.saveUser(user);
      await storageService.deleteUser();
      
      final retrieved = await storageService.getUser();
      expect(retrieved, isNull);
    });
  });

  group('StorageService - Bon Management', () {
    test('saveBon et getBons fonctionnent', () async {
      final bon = Bon(
        bonId: 'bon_123',
        value: 5.0,
        issuerName: 'Miel',
        issuerNpub: 'npub_issuer',
        createdAt: DateTime.now(),
        status: BonStatus.active,
        marketName: 'marche-test',
      );

      await storageService.saveBon(bon);
      final bons = await storageService.getBons();

      expect(bons.length, equals(1));
      expect(bons[0].bonId, equals(bon.bonId));
      expect(bons[0].value, equals(bon.value));
    });

    test('saveBon met à jour un bon existant', () async {
      final bon = Bon(
        bonId: 'bon_456',
        value: 10.0,
        issuerName: 'Test',
        issuerNpub: 'npub',
        createdAt: DateTime.now(),
        status: BonStatus.active,
        marketName: 'marche',
      );

      await storageService.saveBon(bon);
      
      final updatedBon = bon.copyWith(status: BonStatus.spent);
      await storageService.saveBon(updatedBon);

      final bons = await storageService.getBons();
      expect(bons.length, equals(1));
      expect(bons[0].status, equals(BonStatus.spent));
    });

    test('getBonById retourne le bon correct', () async {
      final bon1 = Bon(
        bonId: 'bon_001',
        value: 5.0,
        issuerName: 'Alice',
        issuerNpub: 'npub1',
        createdAt: DateTime.now(),
        status: BonStatus.active,
        marketName: 'marche1',
      );

      final bon2 = Bon(
        bonId: 'bon_002',
        value: 10.0,
        issuerName: 'Bob',
        issuerNpub: 'npub2',
        createdAt: DateTime.now(),
        status: BonStatus.active,
        marketName: 'marche2',
      );

      await storageService.saveBon(bon1);
      await storageService.saveBon(bon2);

      final retrieved = await storageService.getBonById('bon_002');
      expect(retrieved, isNotNull);
      expect(retrieved!.bonId, equals('bon_002'));
      expect(retrieved.issuerName, equals('Bob'));
    });

    test('deleteBon supprime le bon', () async {
      final bon = Bon(
        bonId: 'bon_to_delete',
        value: 5.0,
        issuerName: 'Test',
        issuerNpub: 'npub',
        createdAt: DateTime.now(),
        status: BonStatus.active,
        marketName: 'marche',
      );

      await storageService.saveBon(bon);
      await storageService.deleteBon('bon_to_delete');

      final bons = await storageService.getBons();
      expect(bons.isEmpty, isTrue);
    });

    test('getActiveBons ne retourne que les bons valides', () async {
      final bon1 = Bon(
        bonId: 'bon_active',
        value: 5.0,
        issuerName: 'Alice',
        issuerNpub: 'npub',
        createdAt: DateTime.now(),
        status: BonStatus.active,
        marketName: 'marche',
      );

      final bon2 = Bon(
        bonId: 'bon_spent',
        value: 10.0,
        issuerName: 'Bob',
        issuerNpub: 'npub',
        createdAt: DateTime.now(),
        status: BonStatus.spent,
        marketName: 'marche',
      );

      await storageService.saveBon(bon1);
      await storageService.saveBon(bon2);

      final activeBons = await storageService.getActiveBons();
      expect(activeBons.length, equals(1));
      expect(activeBons[0].bonId, equals('bon_active'));
    });

    test('getBonsByStatus filtre correctement', () async {
      final bons = [
        Bon(
          bonId: 'b1',
          value: 5,
          issuerName: 'A',
          issuerNpub: 'p',
          createdAt: DateTime.now(),
          status: BonStatus.active,
          marketName: 'm',
        ),
        Bon(
          bonId: 'b2',
          value: 5,
          issuerName: 'B',
          issuerNpub: 'p',
          createdAt: DateTime.now(),
          status: BonStatus.pending,
          marketName: 'm',
        ),
        Bon(
          bonId: 'b3',
          value: 5,
          issuerName: 'C',
          issuerNpub: 'p',
          createdAt: DateTime.now(),
          status: BonStatus.active,
          marketName: 'm',
        ),
      ];

      for (final bon in bons) {
        await storageService.saveBon(bon);
      }

      final activeBons = await storageService.getBonsByStatus(BonStatus.active);
      expect(activeBons.length, equals(2));

      final pendingBons = await storageService.getBonsByStatus(BonStatus.pending);
      expect(pendingBons.length, equals(1));
    });
  });

  group('StorageService - Market Management', () {
    test('saveMarket et getMarket fonctionnent', () async {
      final market = Market(
        name: 'marche-toulouse',
        seedMarket: '0' * 64,
        validUntil: DateTime.now().add(const Duration(days: 1)),
        relayUrl: 'wss://relay.test.com',
      );

      await storageService.saveMarket(market);
      final retrieved = await storageService.getMarket();

      expect(retrieved, isNotNull);
      expect(retrieved!.name, equals(market.name));
      expect(retrieved.seedMarket, equals(market.seedMarket));
      expect(retrieved.relayUrl, equals(market.relayUrl));
    });

    test('deleteMarket supprime le marché', () async {
      final market = Market(
        name: 'test',
        seedMarket: '1' * 64,
        validUntil: DateTime.now().add(const Duration(days: 1)),
      );

      await storageService.saveMarket(market);
      await storageService.deleteMarket();

      final retrieved = await storageService.getMarket();
      expect(retrieved, isNull);
    });
  });

  group('StorageService - P3 Cache', () {
    test('saveP3ToCache et getP3FromCache fonctionnent', () async {
      await storageService.saveP3ToCache('bon_123', 'p3_value_abc');
      final retrieved = await storageService.getP3FromCache('bon_123');

      expect(retrieved, equals('p3_value_abc'));
    });

    test('getP3Cache retourne tous les P3', () async {
      await storageService.saveP3ToCache('bon_1', 'p3_1');
      await storageService.saveP3ToCache('bon_2', 'p3_2');
      await storageService.saveP3ToCache('bon_3', 'p3_3');

      final cache = await storageService.getP3Cache();
      expect(cache.length, equals(3));
      expect(cache['bon_1'], equals('p3_1'));
      expect(cache['bon_2'], equals('p3_2'));
      expect(cache['bon_3'], equals('p3_3'));
    });

    test('getP3FromCache retourne null si absent', () async {
      final p3 = await storageService.getP3FromCache('non_existent');
      expect(p3, isNull);
    });
  });

  group('StorageService - Clear All', () {
    test('clearAll supprime toutes les données', () async {
      // Créer des données
      final user = User(
        npub: 'npub',
        nsec: 'nsec',
        displayName: 'Test',
        createdAt: DateTime.now(),
      );

      final bon = Bon(
        bonId: 'bon',
        value: 5,
        issuerName: 'Test',
        issuerNpub: 'npub',
        createdAt: DateTime.now(),
        status: BonStatus.active,
        marketName: 'marche',
      );

      await storageService.saveUser(user);
      await storageService.saveBon(bon);
      await storageService.saveP3ToCache('bon', 'p3');

      // Tout effacer
      await storageService.clearAll();

      // Vérifier
      expect(await storageService.getUser(), isNull);
      expect((await storageService.getBons()).isEmpty, isTrue);
      expect((await storageService.getP3Cache()).isEmpty, isTrue);
    });
  });
}
