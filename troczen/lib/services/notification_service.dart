import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'storage_service.dart';
import 'logger_service.dart';

enum NotificationType {
  loop, // Boucle complète
  bootstrap, // Nouveau voisin
  expertise, // Nouvelle attestation
  volume, // Volume inhabituel
}

class MarketNotification {
  final NotificationType type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  MarketNotification({
    required this.type,
    required this.message,
    required this.timestamp,
    this.data,
  });
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _notificationsSubject = BehaviorSubject<List<MarketNotification>>.seeded([]);
  StreamSubscription? _cacheSubscription;
  
  Stream<List<MarketNotification>> get notificationsStream => _notificationsSubject.stream;
  List<MarketNotification> get currentNotifications => _notificationsSubject.value;

  void init(StorageService storageService) {
    _cacheSubscription?.cancel();
    _cacheSubscription = storageService.cacheInsertionsStream.listen((event) {
      _handleCacheInsertion(event, storageService);
    });
  }

  Future<void> _handleCacheInsertion(Map<String, dynamic> event, StorageService storageService) async {
    try {
      final type = event['type'] as String;
      final data = event['data'] as Map<String, dynamic>;

      if (type == 'market_transfer') {
        // Vérifier si c'est une boucle
        final bonId = data['bon_id'] as String;
        final toNpub = data['to_npub'] as String;
        final value = (data['value'] as num).toDouble();

        // Alerte Volume Inhabituel
        if (value >= 500) {
          addNotification(MarketNotification(
            type: NotificationType.volume,
            message: 'Volume inhabituel détecté : $value ẐEN',
            timestamp: DateTime.now(),
            data: data,
          ));
        }

        final bon = await storageService.getMarketBonById(bonId);
        if (bon != null && bon['issuerNpub'] == toNpub) {
          addNotification(MarketNotification(
            type: NotificationType.loop,
            message: 'Boucle complétée ! Un bon est revenu à son émetteur.',
            timestamp: DateTime.now(),
            data: data,
          ));
        }
      } else if (type == 'n2_contact') {
        // Vérifier si c'est un bootstrap
        final npub = data['npub'] as String;
        final bootstrapUsers = await storageService.getBootstrapUsers();
        if (bootstrapUsers.contains(npub)) {
          addNotification(MarketNotification(
            type: NotificationType.bootstrap,
            message: 'Nouveau voisin 🌱 détecté dans le réseau N2.',
            timestamp: DateTime.now(),
            data: data,
          ));
        }
      } else if (type == 'n30502_attestation') {
        final skill = data['skill'] ?? 'Savoir-faire';
        final from = data['attestor_name'] ?? 'Un pair';
        
        addNotification(MarketNotification(
          type: NotificationType.expertise,
          message: '🛡️ Nouvelle attestation : $from a validé la compétence [$skill].',
          timestamp: DateTime.now(),
          data: data,
        ));
      }
    } catch (e) {
      Logger.error('NotificationService', 'Erreur traitement insertion', e);
    }
  }

  void addNotification(MarketNotification notification) {
    final current = List<MarketNotification>.from(_notificationsSubject.value);
    current.insert(0, notification);
    // Garder les 50 dernières notifications
    if (current.length > 50) {
      current.removeLast();
    }
    _notificationsSubject.add(current);
  }

  void clearNotifications() {
    _notificationsSubject.add([]);
  }
  
  void dispose() {
    _cacheSubscription?.cancel();
    _notificationsSubject.close();
  }
}
