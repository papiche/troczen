import "dart:typed_data";
import 'dart:async';
import 'dart:convert';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import '../models/nostr_profile.dart';
import '../utils/nostr_utils.dart';
import 'crypto_service.dart';
import 'logger_service.dart';
import 'nostr_connection_service.dart';

/// Service de gestion WoTx (Web of Trust extended) - Kinds 30500-30503
/// Responsabilité unique: Gestion des compétences, permis et attestations
class NostrWoTxService {
  final NostrConnectionService _connection;
  final CryptoService _cryptoService;
  
  // Enregistrement des pubkeys
  bool _pubkeyRegistered = false;
  String? _registeredPubkey;
  String? _apiUrl;
  
  // Callbacks
  Function(String error)? onError;
  Function(List<String> tags)? onTagsReceived;
  
  NostrWoTxService({
    required NostrConnectionService connection,
    required CryptoService cryptoService,
  })  : _connection = connection,
        _cryptoService = cryptoService;
  
  // ============================================================
  // ENREGISTREMENT PUBKEY
  // ============================================================
  
  /// Enregistre la pubkey sur le relai
  Future<bool> ensurePubkeyRegistered(String pubkeyHex) async {
    if (_pubkeyRegistered && _registeredPubkey == pubkeyHex) {
      return true;
    }
    
    _apiUrl ??= await _getApiUrl();
    
    if (_apiUrl == null) {
      Logger.warn('NostrWoTx', 'API URL non configurée - skip pubkey registration');
      return true;
    }
    
    try {
      final url = Uri.parse('$_apiUrl/api/nostr/register');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pubkey': pubkeyHex}),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        _pubkeyRegistered = true;
        _registeredPubkey = pubkeyHex;
        Logger.success('NostrWoTx', 'Pubkey enregistrée');
        return true;
      } else {
        Logger.error('NostrWoTx', 'Erreur enregistrement pubkey: ${response.statusCode}');
        return true; // 🔥 MODIFICATION CRITIQUE : Toujours retourner true pour tenter la publication Nostr quand même !
      }
    } catch (e) {
      Logger.error('NostrWoTx', 'Erreur appel /api/nostr/register', e);
      return true; // 🔥 MODIFICATION CRITIQUE : Toujours retourner true pour tenter la publication Nostr quand même !
    }
  }
  
  Future<String?> _getApiUrl() async {
    // Utiliser l'URL de l'API configurée ou détecter automatiquement
    // Pour simplifier, on retourne null ici et le service parent doit gérer
    return null;
  }
  
  // ============================================================
  // SKILL PERMIT (Kind 30500)
  // ============================================================
  
  /// Publie une déclaration de compétence/permis (kind 30500)
  Future<bool> publishSkillPermit({
    required String npub,
    required String nsec,
    required String skillTag,
    required String seedMarket,
  }) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return false;
    }

    final registered = await ensurePubkeyRegistered(npub);
    if (!registered) {
      Logger.warn('NostrWoTx', 'Pubkey non enregistrée sur l\'API, mais on tente la publication Nostr quand même');
    }

    try {
      final normalizedTag = NostrUtils.normalizeSkillTag(skillTag);
      final dTag = 'PERMIT_${normalizedTag.toUpperCase()}_X1';
      
      final plaintextContent = jsonEncode({
        'level': 1,
        'type': 'self_declaration',
        'skill': normalizedTag,
        'timestamp': DateTime.now().toIso8601String(),
      });

      final encrypted = _cryptoService.encryptWoTxContent(plaintextContent, seedMarket);
      
      final tags = <List<String>>[
        ['d', dTag],
        ['t', normalizedTag],
      ];
      
      if (encrypted['nonce']!.isNotEmpty) {
        tags.add(['encryption', 'aes-gcm', encrypted['nonce']!]);
      }

      final event = {
        'kind': 30500,
        'pubkey': npub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': tags,
        'content': encrypted['ciphertext']!,
      };

      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      Uint8List nsecBytes;
      try {
        nsecBytes = Uint8List.fromList(HEX.decode(nsec));
      } catch (e) {
        throw Exception('Clé privée invalide (non hexadécimale)');
      }
      final signature = _cryptoService.signMessageBytes(eventId, nsecBytes);
      event['sig'] = signature;

      final message = jsonEncode(['EVENT', event]);
      _connection.sendMessage(message);

      Logger.log('NostrWoTx', 'Skill Permit publié: $normalizedTag');
      return true;
    } catch (e) {
      onError?.call('Erreur publication Skill Permit: $e');
      return false;
    }
  }
  
  /// Récupère les définitions de savoir-faire (Kind 30500)
  Future<List<String>> fetchSkillDefinitions() async {
    if (!_connection.isConnected) return [];
    
    try {
      final completer = Completer<List<String>>();
      final Set<String> skills = {};
      final subId = 'skills_${DateTime.now().millisecondsSinceEpoch}';
      
      _connection.registerHandler(subId, (message) {
        if (message[0] == 'EVENT') {
          final event = message[2] as Map<String, dynamic>;
          final tags = event['tags'] as List;
          for (final tag in tags) {
            if (tag is List && tag.isNotEmpty && tag[0] == 't' && tag.length > 1) {
              skills.add(tag[1].toString());
            }
          }
        } else if (message[0] == 'EOSE') {
          _connection.sendMessage(jsonEncode(['CLOSE', subId]));
          _connection.removeHandler(subId);
          if (!completer.isCompleted) completer.complete(skills.toList()..sort());
        }
      });

      _connection.sendMessage(jsonEncode(['REQ', subId, {'kinds': [NostrConstants.kindSkillPermit]}]));
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        _connection.removeHandler(subId);
        if (!completer.isCompleted) completer.complete(skills.toList()..sort());
      });
      
      final result = await completer.future;
      fallbackTimer.cancel();
      return result;
    } catch (e) {
      Logger.error('NostrWoTx', 'Erreur fetchSkillDefinitions', e);
      return [];
    }
  }
  
  // ============================================================
  // SKILL REQUEST (Kind 30501)
  // ============================================================
  
  /// Publie une demande d'attestation (kind 30501)
  Future<bool> publishSkillRequest({
    required String npub,
    required String nsec,
    required String skill,
    required String seedMarket,
    String motivation = "Déclaration initiale lors de l'inscription",
  }) async {
    if (!_connection.isConnected) return false;
    
    final registered = await ensurePubkeyRegistered(npub);
    if (!registered) {
      Logger.warn('NostrWoTx', 'Pubkey non enregistrée sur l\'API, mais on tente la publication Nostr quand même');
    }
    
    try {
      final normalizedSkill = NostrUtils.normalizeSkillTag(skill);
      final permitId = 'PERMIT_${normalizedSkill.toUpperCase()}_X1';
      
      final plaintextContent = jsonEncode({
        'motivation': motivation,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      final encrypted = _cryptoService.encryptWoTxContent(plaintextContent, seedMarket);
      
      final tags = <List<String>>[
        ['permit_id', permitId],
        ['t', normalizedSkill],
      ];
      
      if (encrypted['nonce']!.isNotEmpty) {
        tags.add(['encryption', 'aes-gcm', encrypted['nonce']!]);
      }
      
      final event = {
        'kind': NostrConstants.kindSkillRequest,
        'pubkey': npub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': tags,
        'content': encrypted['ciphertext']!,
      };

      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      Uint8List nsecBytes;
      try {
        nsecBytes = Uint8List.fromList(HEX.decode(nsec));
      } catch (e) {
        throw Exception('Clé privée invalide (non hexadécimale)');
      }
      event['sig'] = _cryptoService.signMessageBytes(eventId, nsecBytes);

      final success = await _connection.sendEventAndWait(eventId, jsonEncode(['EVENT', event]));
      if (success) {
        Logger.success('NostrWoTx', 'Skill request publiée: $skill');
      }
      return success;
    } catch (e) {
      Logger.error('NostrWoTx', 'Erreur publishSkillRequest', e);
      return false;
    }
  }
  
  /// Récupère les demandes de certification en attente
  Future<List<Map<String, dynamic>>> fetchPendingSkillRequests({
    required List<String> mySkills,
    required String myNpub,
  }) async {
    if (!_connection.isConnected || mySkills.isEmpty) return [];
    
    try {
      final completer = Completer<List<Map<String, dynamic>>>();
      final List<Map<String, dynamic>> requests = [];
      final subId = 'skill_req_${DateTime.now().millisecondsSinceEpoch}';
      
      _connection.registerHandler(subId, (message) {
        if (message[0] == 'EVENT') {
          final event = message[2] as Map<String, dynamic>;
          final pubkey = event['pubkey'] as String;
          
          if (pubkey == myNpub) return;
          
          final tags = event['tags'] as List;
          String? skill;
          String? permitId;
          
          for (final tag in tags) {
            if (tag is List && tag.isNotEmpty) {
              if (tag[0] == 't' && tag.length > 1) {
                skill = tag[1].toString();
              } else if (tag[0] == 'permit_id' && tag.length > 1) {
                permitId = tag[1].toString();
              }
            }
          }
          
          if (skill != null && mySkills.any((s) => NostrUtils.normalizeSkillTag(s) == NostrUtils.normalizeSkillTag(skill!))) {
            requests.add({
              'id': event['id'],
              'pubkey': pubkey,
              'created_at': event['created_at'],
              'skill': skill,
              'permit_id': permitId,
              'content': event['content'],
            });
          }
        } else if (message[0] == 'EOSE') {
          _connection.sendMessage(jsonEncode(['CLOSE', subId]));
          _connection.removeHandler(subId);
          if (!completer.isCompleted) completer.complete(requests);
        }
      });

      final skillTags = mySkills.map((s) => NostrUtils.normalizeSkillTag(s)).toList();
      _connection.sendMessage(jsonEncode([
        'REQ', subId,
        {
          'kinds': [NostrConstants.kindSkillRequest],
          '#t': skillTags,
          'limit': 50,
        }
      ]));
      
      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        _connection.removeHandler(subId);
        if (!completer.isCompleted) completer.complete(requests);
      });
      
      final result = await completer.future;
      fallbackTimer.cancel();
      return result;
    } catch (e) {
      Logger.error('NostrWoTx', 'Erreur fetchPendingSkillRequests', e);
      return [];
    }
  }
  
  // ============================================================
  // SKILL ATTESTATION (Kind 30502)
  // ============================================================
  
  /// Publie une attestation (kind 30502) pour valider un pair
  Future<bool> publishSkillAttestation({
    required String myNpub,
    required String myNsec,
    required String requestId,
    required String requesterNpub,
    required String permitId,
    required String seedMarket,
    String? motivation,
  }) async {
    if (!_connection.isConnected) return false;
    
    final registered = await ensurePubkeyRegistered(myNpub);
    if (!registered) {
      Logger.warn('NostrWoTx', 'Pubkey non enregistrée sur l\'API, mais on tente la publication Nostr quand même');
    }
    
    try {
      final plaintextContent = jsonEncode({
        'type': 'skill_attestation',
        'motivation': motivation ?? 'Attestation de compétence',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      final encrypted = _cryptoService.encryptWoTxContent(plaintextContent, seedMarket);
      
      final rawSkill = permitId.replaceFirst('PERMIT_', '').replaceAll(RegExp(r'_X\d+$'), '');
      final normalizedSkill = NostrUtils.normalizeSkillTag(rawSkill);
      
      final tags = <List<String>>[
        ['e', requestId],
        ['p', requesterNpub],
        ['permit_id', permitId],
        ['t', normalizedSkill],
      ];
      
      if (encrypted['nonce']!.isNotEmpty) {
        tags.add(['encryption', 'aes-gcm', encrypted['nonce']!]);
      }
      
      final event = {
        'kind': NostrConstants.kindSkillAttest,
        'pubkey': myNpub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': tags,
        'content': encrypted['ciphertext']!,
      };

      final eventId = NostrUtils.calculateEventId(event);
      event['id'] = eventId;
      Uint8List myNsecBytes;
      try {
        myNsecBytes = Uint8List.fromList(HEX.decode(myNsec));
      } catch (e) {
        throw Exception('Clé privée invalide (non hexadécimale)');
      }
      event['sig'] = _cryptoService.signMessageBytes(eventId, myNsecBytes);

      final success = await _connection.sendEventAndWait(eventId, jsonEncode(['EVENT', event]));
      if (success) {
        Logger.success('NostrWoTx', 'Attestation publiée pour $requesterNpub');
      }
      return success;
    } catch (e) {
      Logger.error('NostrWoTx', 'Erreur publishSkillAttestation', e);
      return false;
    }
  }
  
  /// Récupère les attestations reçues par l'utilisateur
  Future<List<Map<String, dynamic>>> fetchMyAttestations(String myNpub) async {
    if (!_connection.isConnected) return [];
    
    try {
      final completer = Completer<List<Map<String, dynamic>>>();
      final List<Map<String, dynamic>> attestations = [];
      final subId = 'my_attest_${DateTime.now().millisecondsSinceEpoch}';
      
      _connection.registerHandler(subId, (message) {
        if (message[0] == 'EVENT') {
          final event = message[2] as Map<String, dynamic>;
          final tags = event['tags'] as List;
          
          String? permitId;
          String? requestId;
          
          for (final tag in tags) {
            if (tag is List && tag.length > 1) {
              if (tag[0] == 'permit_id') permitId = tag[1].toString();
              if (tag[0] == 'e') requestId = tag[1].toString();
            }
          }
          
          attestations.add({
            'id': event['id'],
            'attestor': event['pubkey'],
            'permit_id': permitId,
            'request_id': requestId,
            'created_at': event['created_at'],
            'content': event['content'],
          });
        } else if (message[0] == 'EOSE') {
          _connection.sendMessage(jsonEncode(['CLOSE', subId]));
          _connection.removeHandler(subId);
          if (!completer.isCompleted) completer.complete(attestations);
        }
      });

      _connection.sendMessage(jsonEncode([
        'REQ', subId,
        {
          'kinds': [NostrConstants.kindSkillAttest],
          '#p': [myNpub],
          'limit': 100,
        }
      ]));

      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        _connection.removeHandler(subId);
        if (!completer.isCompleted) completer.complete(attestations);
      });

      final result = await completer.future;
      fallbackTimer.cancel();
      return result;
    } catch (e) {
      Logger.error('NostrWoTx', 'Erreur fetchMyAttestations', e);
      return [];
    }
  }
  
  // ============================================================
  // SKILL REACTION (Kind 7)
  // ============================================================
  
  /// Publie un avis client (👍 / 👎) sur une compétence (kind 7)
  Future<bool> publishSkillReview({
    required String myNpub,
    required String myNsec,
    required String targetNpub,
    required String permitEventId,
    required bool isPositive,
  }) async {
    if (!_connection.isConnected) return false;
    
    try {
      final tags = <List<String>>[
        ['e', permitEventId],
        ['p', targetNpub],
        ['t', 'wotx-review'],
        ['k', '30500'],
      ];
      
      final event = {
        'kind': 7,
        'pubkey': myNpub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': tags,
        'content': isPositive ? '+' : '-',
      };

      final id = NostrUtils.calculateEventId(event);
      event['id'] = id;
      Uint8List myNsecBytes;
      try {
        myNsecBytes = Uint8List.fromList(HEX.decode(myNsec));
      } catch (e) {
        throw Exception('Clé privée invalide (non hexadécimale)');
      }
      event['sig'] = _cryptoService.signMessageBytes(id, myNsecBytes);

      final success = await _connection.sendEventAndWait(id, jsonEncode(['EVENT', event]));
      if (success) {
        Logger.success('NostrWoTx', 'Avis publié pour $targetNpub');
      }
      return success;
    } catch (e) {
      Logger.error('NostrWoTx', 'Erreur publishSkillReview', e);
      return false;
    }
  }

  /// Publie une réaction (👍 / 👎) à une compétence (kind 7)
  Future<bool> publishSkillReaction({
    required String myNpub,
    required String myNsec,
    required String artisanNpub,
    required String eventId,
    required bool isPositive,
  }) async {
    if (!_connection.isConnected) return false;
    
    try {
      final tags = <List<String>>[
        ['e', eventId],
        ['p', artisanNpub],
        ['t', 'wotx-review'],
        ['k', '30500'],
      ];
      
      final event = {
        'kind': 7,
        'pubkey': myNpub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': tags,
        'content': isPositive ? '+' : '-',
      };

      final id = NostrUtils.calculateEventId(event);
      event['id'] = id;
      Uint8List myNsecBytes;
      try {
        myNsecBytes = Uint8List.fromList(HEX.decode(myNsec));
      } catch (e) {
        throw Exception('Clé privée invalide (non hexadécimale)');
      }
      event['sig'] = _cryptoService.signMessageBytes(id, myNsecBytes);

      final success = await _connection.sendEventAndWait(id, jsonEncode(['EVENT', event]));
      if (success) {
        Logger.success('NostrWoTx', 'Réaction publiée pour $artisanNpub');
      }
      return success;
    } catch (e) {
      Logger.error('NostrWoTx', 'Erreur publishSkillReaction', e);
      return false;
    }
  }

  // ============================================================
  // EXTRACTION DES TAGS D'ACTIVITÉ
  // ============================================================
  
  /// Récupère les tags d'activité depuis les profils Nostr (kind 0)
  Future<List<String>> fetchActivityTagsFromProfiles({int limit = 100}) async {
    if (!_connection.isConnected) {
      onError?.call('Non connecté au relais');
      return [];
    }

    try {
      final completer = Completer<List<String>>();
      final Set<String> extractedTags = {};
      final subscriptionId = 'zen-tags-${DateTime.now().millisecondsSinceEpoch}';
      
      _connection.registerHandler(subscriptionId, (message) {
        try {
          if (message[0] == 'EVENT' && message.length >= 3) {
            final event = message[2] as Map<String, dynamic>?;
            if (event != null) {
              final content = event['content'] as String?;
              if (content != null) {
                final contentJson = jsonDecode(content);
                
                // 1. Tags explicites
                final tags = contentJson['tags'] as List?;
                if (tags != null) {
                  for (final tag in tags) {
                    if (tag is List && tag.isNotEmpty && tag[0] == 't') {
                      final tagValue = tag.length > 1 ? tag[1]?.toString() : null;
                      if (tagValue != null && tagValue.isNotEmpty) {
                        extractedTags.add(tagValue);
                      }
                    }
                  }
                }
                
                // 2. Champs activity et profession
                final activity = contentJson['activity'] as String?;
                if (activity != null && activity.isNotEmpty) {
                  extractedTags.add(activity);
                }
                
                final profession = contentJson['profession'] as String?;
                if (profession != null && profession.isNotEmpty) {
                  extractedTags.add(profession);
                }
                
                // 3. Hashtags dans about
                final about = contentJson['about'] as String?;
                if (about != null) {
                  final hashtagRegex = RegExp(r'#(\w+)');
                  final matches = hashtagRegex.allMatches(about);
                  for (final match in matches) {
                    final hashtag = match.group(1);
                    if (hashtag != null && hashtag.isNotEmpty) {
                      extractedTags.add(hashtag);
                    }
                  }
                }
              }
            }
          } else if (message[0] == 'EOSE') {
            _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
            _connection.removeHandler(subscriptionId);
            if (!completer.isCompleted) {
              completer.complete(extractedTags.toList()..sort());
            }
          }
        } catch (e) {
          Logger.error('NostrWoTx', 'Erreur parsing tags response', e);
        }
      });

      final request = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'kinds': [0],
          'limit': limit,
        },
      ]);
      
      _connection.sendMessage(request);
      
      Timer(const Duration(seconds: 5), () {
        _connection.removeHandler(subscriptionId);
        if (!completer.isCompleted) {
          _connection.sendMessage(jsonEncode(['CLOSE', subscriptionId]));
          completer.complete(extractedTags.toList()..sort());
        }
      });
      
      final result = await completer.future;
      
      Logger.log('NostrWoTx', 'Tags extraits: ${result.length} tags uniques');
      onTagsReceived?.call(result);
      
      return result;
    } catch (e) {
      onError?.call('Erreur récupération tags: $e');
      Logger.error('NostrWoTx', 'Erreur fetchActivityTagsFromProfiles', e);
      return [];
    }
  }
}
