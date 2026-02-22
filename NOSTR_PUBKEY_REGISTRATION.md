# 🔑 Enregistrement automatique des Pubkeys Nostr

## Contexte

Pour que le relai Strfry accepte les événements Nostr, la clé publique (pubkey) doit être enregistrée dans le fichier `~/.zen/strfry/amisOfAmis.txt` via la route `/api/nostr/register`.

## ✅ Route API créée

**POST `/api/nostr/register`** dans [`api/api_backend.py`](api/api_backend.py:1040)

**Body** :
```json
{
  "pubkey": "abc123...def"  // 64 caractères hex
}
```

**Réponse** :
```json
{
  "success": true,
  "message": "Pubkey registered successfully",
  "already_registered": false
}
```

## 📝 Implémentation dans NostrService

### 1. Ajouter les imports et variables

Dans [`troczen/lib/services/nostr_service.dart`](troczen/lib/services/nostr_service.dart:1) :

```dart
import 'package:http/http.dart' as http;

class NostrService {
  // ... existing code ...
  
  // ✅ NOUVEAU: Flag pour éviter d'enregistrer plusieurs fois
  bool _pubkeyRegistered = false;
  String? _registeredPubkey;
  
  // ✅ NOUVEAU: URL de l'API (devrait venir de AppConfig)
  String? _apiUrl;
}
```

### 2. Ajouter la méthode d'enregistrement

```dart
/// ✅ Enregistre la pubkey sur le relai Nostr (policy amisOfAmis)
/// Cette méthode DOIT être appelée AVANT toute publication d'événement
/// Retourne true si enregistrement réussi, false sinon
Future<bool> _ensurePubkeyRegistered(String pubkeyHex) async {
  // Vérifier si déjà enregistrée
  if (_pubkeyRegistered && _registeredPubkey == pubkeyHex) {
    return true;
  }
  
  // Si pas d'URL API, essayer de récupérer depuis les paramètres
  _apiUrl ??= await _getApiUrl();
  
  if (_apiUrl == null) {
    Logger.warn('NostrService', 'API URL non configurée - skip pubkey registration');
    return true; // Continuer quand même (fallback)
  }
  
  try {
    final url = Uri.parse('$_apiUrl/api/nostr/register');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'pubkey': pubkeyHex}),
    ).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      _pubkeyRegistered = true;
      _registeredPubkey = pubkeyHex;
      
      if (data['already_registered'] == true) {
        Logger.log('NostrService', 'Pubkey déjà enregistrée sur le relai');
      } else {
        Logger.success('NostrService', 'Pubkey enregistrée avec succès sur le relai');
      }
      
      return true;
    } else {
      Logger.error('NostrService', 'Erreur enregistrement pubkey: ${response.statusCode}');
      return false;
    }
  } catch (e) {
    Logger.error('NostrService', 'Erreur appel /api/nostr/register', e);
    return false; // Retourner false pour bloquer la publication si échec
  }
}

/// Récupère l'URL de l'API depuis la configuration
/// Priorité: Config locale > Variable d'environnement > Marché actif
Future<String?> _getApiUrl() async {
  try {
    // 1. Essayer de récupérer depuis le marché actif
    final market = await _storageService.getMarket();
    if (market?.apiUrl != null && market!.apiUrl!.isNotEmpty) {
      return market.apiUrl;
    }
    
    // 2. Fallback: URL par défaut (localhost pour dev, à configurer en prod)
    return 'http://127.0.0.1:5000';
  } catch (e) {
    Logger.error('NostrService', 'Erreur récupération API URL', e);
    return null;
  }
}
```

### 3. Modifier TOUTES les méthodes de publication

Ajouter l'enregistrement au début de chaque méthode qui publie un événement :

#### publishP3() - Ligne ~420
```dart
Future<bool> publishP3({
  required String bonId,
  required String p3Hex,
  required String issuerNpub,
  required double value,
  // ... autres paramètres
}) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishBonOffer() - Ligne ~510
```dart
Future<bool> publishBonOffer({
  required String bonId,
  // ... paramètres
}) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishBonReception() - Ligne ~640
```dart
Future<bool> publishBonReception({
  required String bonId,
  // ... paramètres
}) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishBonReceptionAck() - Ligne ~690
```dart
Future<bool> publishBonReceptionAck({
  required String bonId,
  // ... paramètres
}) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishCircuitCompleted() - Ligne ~730
```dart
Future<bool> publishCircuitCompleted({
  required List<String> bonIds,
  // ... paramètres
}) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishProfile() - Ligne ~820
```dart
Future<bool> publishProfile({
  required String displayName,
  // ... paramètres
}) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishContacts() - Ligne ~1430
```dart
Future<bool> publishContacts(List<String> friendNpubs) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishDeletionEvent() - Ligne ~1550
```dart
Future<bool> publishDeletionEvent(List<String> eventIds) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishMetadata() - Ligne ~1620
```dart
Future<bool> publishMetadata(Map<String, dynamic> metadata) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishSkillRequest() - Ligne ~1830
```dart
Future<bool> publishSkillRequest(String skill, Market market) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

#### publishSkillAttestation() - Ligne ~1970
```dart
Future<bool> publishSkillAttestation({
  required String requesterNpub,
  // ... paramètres
}) async {
  // ✅ NOUVEAU: Enregistrer la pubkey avant publication
  final user = await _storageService.getUser();
  if (user != null) {
    final registered = await _ensurePubkeyRegistered(user.npubHex);
    if (!registered) {
      Logger.error('NostrService', 'Publication annulée: pubkey non enregistrée');
      return false;
    }
  }
  
  // ... reste du code existant
}
```

## 🎯 Avantages

- ✅ **Automatique** : Enregistrement transparent avant toute publication
- ✅ **Une seule fois** : Flag `_pubkeyRegistered` évite les appels répétés
- ✅ **Sécurisé** : Bloque la publication si enregistrement échoue
- ✅ **Fallback** : Continue si API non disponible (mode dégradé)
- ✅ **Logging** : Traçabilité complète des opérations

## 📦 Dépendance

Ajouter dans `troczen/pubspec.yaml` si pas déjà présent :

```yaml
dependencies:
  http: ^1.1.0
```

## 🧪 Test

1. Créer un nouvel utilisateur dans l'app
2. Publier un profil Nostr
3. Vérifier dans les logs : "Pubkey enregistrée avec succès sur le relai"
4. Vérifier dans `~/.zen/strfry/amisOfAmis.txt` que la pubkey est présente
5. Tenter une nouvelle publication → "Pubkey déjà enregistrée sur le relai"
