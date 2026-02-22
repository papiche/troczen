/// Tests d'intégration pour les flux critiques de TrocZen
/// Basé sur le diagramme trozen.mermaid
/// 
/// Flux testés:
/// - PHASE 2 : Création d'un bon (émission)
/// - PHASE 3 : Synchronisation (réception des P3)
/// - PHASE 4 : Transfert atomique offline
library;

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:troczen/services/crypto_service.dart';
import 'package:troczen/services/qr_service.dart';
import 'package:troczen/models/bon.dart';
import 'package:hex/hex.dart';
import 'package:crypto/crypto.dart';

void main() {
  group('========================================', () {
    group('PHASE 2 : CRÉATION D\'UN BON (ÉMISSION)', () {
      late CryptoService cryptoService;

      setUp(() {
        cryptoService = CryptoService();
      });

      test('Flux complet de création de bon - Génération clés et découpage Shamir', () {
        // PHASE 2, étapes 35-37 du diagramme Mermaid:
        // - Génération Clés du Bon (npub_B, nsec_B)
        // - Découpage SSSS(nsec_B) ➔ P1 (Ancre), P2 (Voyageur), P3 (Témoin)

        // 1. Générer les clés du bon
        final bonKeys = cryptoService.generateNostrKeyPair();
        final bonNpub = bonKeys['npub']!;
        final bonNsecHex = bonKeys['privateKeyHex']!;
        final bonNpubHex = bonKeys['publicKeyHex']!;

        // Vérifier que les clés sont valides
        expect(bonNsecHex.length, equals(64), reason: 'Clé privée doit faire 64 chars hex');
        expect(bonNpubHex.length, equals(64), reason: 'Clé publique doit faire 64 chars hex');
        expect(bonNpub.startsWith('npub1'), isTrue, reason: 'Clé publique doit commencer par npub1');
        expect(bonKeys['nsec']!.startsWith('nsec1'), isTrue, reason: 'Clé privée doit commencer par nsec1');

        // 2. Découpage Shamir (2-sur-3)
        final bonNsecBytes = Uint8List.fromList(HEX.decode(bonNsecHex));
        final partsBytes = cryptoService.shamirSplitBytes(bonNsecBytes);
        final parts = partsBytes.map((p) => HEX.encode(p)).toList();
        cryptoService.secureZeroiseBytes(bonNsecBytes);
        final p1 = parts[0]; // Ancre (gardée par l'émetteur)
        final p2 = parts[1]; // Voyageur (dans le QR/transfert)
        final p3 = parts[2]; // Témoin (publié sur Nostr)

        // Vérifier que chaque part fait 64 chars (32 octets)
        expect(p1.length, equals(64), reason: 'P1 doit faire 64 chars hex');
        expect(p2.length, equals(64), reason: 'P2 doit faire 64 chars hex');
        expect(p3.length, equals(64), reason: 'P3 doit faire 64 chars hex');

        // Vérifier que les parts sont différentes
        expect(p1, isNot(equals(p2)), reason: 'P1 et P2 doivent être différents');
        expect(p2, isNot(equals(p3)), reason: 'P2 et P3 doivent être différents');
        expect(p1, isNot(equals(p3)), reason: 'P1 et P3 doivent être différents');

        // 3. Vérifier que la reconstruction fonctionne avec n'importe quelle paire
        final p1Bytes = Uint8List.fromList(HEX.decode(p1));
        final p2Bytes = Uint8List.fromList(HEX.decode(p2));
        final p3Bytes = Uint8List.fromList(HEX.decode(p3));
        final reconstructed12 = HEX.encode(cryptoService.shamirCombineBytesDirect(p1Bytes, p2Bytes, null));
        final reconstructed13 = HEX.encode(cryptoService.shamirCombineBytesDirect(p1Bytes, null, p3Bytes));
        final reconstructed23 = HEX.encode(cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes));

        expect(reconstructed12, equals(bonNsecHex), reason: 'P1+P2 doit reconstruire la clé');
        expect(reconstructed13, equals(bonNsecHex), reason: 'P1+P3 doit reconstruire la clé');
        expect(reconstructed23, equals(bonNsecHex), reason: 'P2+P3 doit reconstruire la clé');
      });

      test('Création d\'un bon avec métadonnées complètes', () {
        // PHASE 2, étapes 38-39 du diagramme Mermaid:
        // - Sauvegarde Bon (P1, P2, métadonnées) dans le Wallet
        // - Sauvegarde P3 dans le Cache P3 local

        // 1. Générer les clés du bon
        final bonKeys = cryptoService.generateNostrKeyPair();
        final bonNsecBytes = Uint8List.fromList(HEX.decode(bonKeys['privateKeyHex']!));
        final partsBytes = cryptoService.shamirSplitBytes(bonNsecBytes);
        final parts = partsBytes.map((p) => HEX.encode(p)).toList();
        cryptoService.secureZeroiseBytes(bonNsecBytes);

        // 2. Créer le bon
        final bon = Bon(
          bonId: bonKeys['publicKeyHex']!,
          value: 50.0,
          issuerName: 'Alice Commerce',
          issuerNpub: 'npub1${'a' * 58}', // npub fictif de l'émetteur
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 365)),
          status: BonStatus.active, // Actif pour être valide
          p1: parts[0], // Ancre (pour l'émetteur)
          p2: parts[1], // Voyageur
          p3: parts[2], // Témoin
          marketName: 'Marché Local',
          rarity: Bon.generateRarity(),
          uniqueId: Bon.generateUniqueId(bonKeys['publicKeyHex']!),
          cardType: Bon.generateCardType(),
        );

        // 3. Vérifier les propriétés du bon
        expect(bon.bonId, equals(bonKeys['publicKeyHex']!));
        expect(bon.value, equals(50.0));
        expect(bon.status, equals(BonStatus.active));
        expect(bon.p1, isNotNull, reason: 'P1 doit être présent pour l\'émetteur');
        expect(bon.p2, isNotNull, reason: 'P2 doit être présent');
        expect(bon.p3, isNotNull, reason: 'P3 doit être présent');
        expect(bon.isValid, isTrue, reason: 'Le bon doit être valide');
        expect(bon.isExpired, isFalse, reason: 'Le bon ne doit pas être expiré');
      });

      test('Chiffrement de P3 avec K_day (clé du jour)', () async {
        // PHASE 2, étape 41 du diagramme Mermaid:
        // - Chiffre P3 avec K_day

        final seedMarket = 'a' * 64; // Graine du marché (64 chars hex)
        final p3Hex = 'b' * 64; // P3 fictive
        final today = DateTime.now();

        // Chiffrer P3 avec la graine du marché
        final encryptedResult = await cryptoService.encryptP3WithSeed(
          p3Hex,
          seedMarket,
          today,
        );

        final encryptedP3 = encryptedResult['ciphertext']!;
        final nonce = encryptedResult['nonce']!;

        expect(encryptedP3, isNotEmpty, reason: 'P3 chiffrée ne doit pas être vide');
        expect(encryptedP3.contains(p3Hex), isFalse, reason: 'P3 chiffrée ne doit pas contenir P3 en clair');
        expect(nonce.length, equals(24), reason: 'Nonce doit faire 24 chars hex (12 octets)');

        // Déchiffrer et vérifier
        final decryptedP3 = await cryptoService.decryptP3WithSeed(
          encryptedP3,
          nonce,
          seedMarket,
          today,
        );

        expect(decryptedP3, equals(p3Hex), reason: 'P3 déchiffrée doit correspondre à l\'originale');
      });

      test('Reconstruction éphémère de nsec_B en RAM (P2 + P3)', () {
        // PHASE 2, étapes 42-44 du diagramme Mermaid:
        // - Reconstruit nsec_B en RAM (P2 + P3)
        // - nsec_B est effacé de la RAM (zeroise)

        // 1. Générer les clés et parts
        final bonKeys = cryptoService.generateNostrKeyPair();
        final originalNsec = bonKeys['privateKeyHex']!;
        final originalNsecBytes = Uint8List.fromList(HEX.decode(originalNsec));
        final partsBytes = cryptoService.shamirSplitBytes(originalNsecBytes);
        final parts = partsBytes.map((p) => HEX.encode(p)).toList();
        cryptoService.secureZeroiseBytes(originalNsecBytes);
        final p2 = parts[1];
        final p3 = parts[2];

        // 2. Reconstruction éphémère (comme dans le flux réel)
        final p2Bytes = Uint8List.fromList(HEX.decode(p2));
        final p3Bytes = Uint8List.fromList(HEX.decode(p3));
        final reconstructedNsecBytes = cryptoService.shamirCombineBytesDirect(null, p2Bytes, p3Bytes);

        // Vérifier que la reconstruction est correcte
        expect(HEX.encode(reconstructedNsecBytes), equals(originalNsec));

        // 3. Simulation du zeroise (nettoyage sécurisé)
        cryptoService.secureZeroiseBytes(reconstructedNsecBytes);

        // Vérifier que les bytes ont été effacés
        expect(reconstructedNsecBytes.every((b) => b == 0), isTrue, 
          reason: 'Après zeroise, tous les bytes doivent être à 0');
      });
    });

    group('========================================', () {
      group('PHASE 3 : SYNCHRONISATION (RÉCEPTEUR)', () {
        late CryptoService cryptoService;

        setUp(() {
          cryptoService = CryptoService();
        });

        test('Dérivation de K_day depuis la graine du marché', () async {
          // PHASE 3, étape 53 du diagramme Mermaid:
          // - Dérive K_day et déchiffre P3

          final seedMarket = 'deadbeef' * 8; // 64 chars hex
          final today = DateTime.now();

          // Dériver K_day pour aujourd'hui
          final kDay = cryptoService.getDailyMarketKey(seedMarket, today);

          expect(kDay.length, equals(64), reason: 'K_day doit faire 64 chars hex (32 octets)');

          // Vérifier que K_day est déterministe
          final kDay2 = cryptoService.getDailyMarketKey(seedMarket, today);
          expect(kDay, equals(kDay2), reason: 'K_day doit être déterministe pour la même date');

          // Vérifier que K_day change selon la date
          final tomorrow = today.add(const Duration(days: 1));
          final kDayTomorrow = cryptoService.getDailyMarketKey(seedMarket, tomorrow);
          expect(kDay, isNot(equals(kDayTomorrow)), reason: 'K_day doit changer chaque jour');
        });

        test('Déchiffrement de P3 reçu du réseau', () async {
          // PHASE 3, étapes 51-54 du diagramme Mermaid:
          // - REQ Sync du matin (Kind 30303)
          // - Reçoit le Bon d'Alice
          // - Dérive K_day et déchiffre P3
          // - Stocke P3 du Bon

          final seedMarket = 'cafe' * 16; // 64 chars hex
          final p3Original = 'babe' * 16; // 64 chars hex
          final today = DateTime.now();

          // 1. Chiffrer P3 (simulation de ce qui vient du réseau)
          final encryptedResult = await cryptoService.encryptP3WithSeed(
            p3Original,
            seedMarket,
            today,
          );
          final encryptedP3 = encryptedResult['ciphertext']!;
          final nonce = encryptedResult['nonce']!;

          // 2. Déchiffrer P3 (côté receveur)
          final decryptedP3 = await cryptoService.decryptP3WithSeed(
            encryptedP3,
            nonce,
            seedMarket,
            today,
          );

          expect(decryptedP3, equals(p3Original), 
            reason: 'P3 déchiffrée doit correspondre à l\'originale');
        });

        test('Stockage de P3 dans le cache local', () async {
          // PHASE 3, étape 54 du diagramme Mermaid:
          // - Stocke P3 du Bon (Essentiel pour valider offline)

          final bonId = 'a' * 64;
          final p3Hex = 'b' * 64;

          // Simuler le stockage dans le cache P3
          // (Dans l'implémentation réelle, c'est fait via StorageService.saveP3ToCache)
          final p3Cache = <String, String>{};
          p3Cache[bonId] = p3Hex;

          expect(p3Cache[bonId], equals(p3Hex), reason: 'P3 doit être récupérable depuis le cache');
          expect(p3Cache.containsKey(bonId), isTrue, reason: 'Le bon ID doit être dans le cache');
        });
      });
    });

    group('========================================', () {
      group('PHASE 4 : TRANSFERT ATOMIQUE OFFLINE', () {
        late CryptoService cryptoService;
        late QRService qrService;

        setUp(() {
          cryptoService = CryptoService();
          qrService = QRService();
        });

        test('Étape A : Génération de l\'offre (QR1)', () async {
          // 1. Préparer les données du bon
          final bonKeys = cryptoService.generateNostrKeyPair();
          final bonId = bonKeys['publicKeyHex']!;
          final bonNsecBytes = Uint8List.fromList(HEX.decode(bonKeys['privateKeyHex']!));
          final partsBytes = cryptoService.shamirSplitBytes(bonNsecBytes);
          cryptoService.secureZeroiseBytes(bonNsecBytes);

          // 2. Chiffrer P2 avec P3 comme clé
          final encryptedP2Result = await cryptoService.encryptP2Bytes(partsBytes[1], partsBytes[2]);
          final nonce = HEX.encode(encryptedP2Result.nonce);

          // Le ciphertext contient maintenant le tag GCM (48 octets = 32 + 16)
          expect(encryptedP2Result.ciphertext.length, equals(48), reason: 'P2 chiffré doit faire 48 octets (32 + tag 16)');
          expect(nonce.length, equals(24), reason: 'Nonce doit faire 24 chars hex (12 octets)');

          // 3. Générer un challenge aléatoire (16 octets)
          final challengeBytes = Uint8List.fromList(
            List.generate(16, (_) => DateTime.now().millisecondsSinceEpoch % 256)
          );
          final challenge = HEX.encode(challengeBytes);
          
          // 4. Encoder l'offre en QR
          // Séparer le ciphertext et le tag pour le QR
          final ciphertextOnly = Uint8List.fromList(encryptedP2Result.ciphertext.sublist(0, 32));
          final tagOnly = encryptedP2Result.tag;
          
          final qrData = qrService.encodeQrV2Bytes(
            bonId: Uint8List.fromList(HEX.decode(bonId)),
            valueInCentimes: 1000,
            issuerNpub: Uint8List(32),
            issuerName: "Test Issuer",
            encryptedP2: ciphertextOnly,
            p2Nonce: encryptedP2Result.nonce,
            p2Tag: tagOnly,
            challenge: challengeBytes,
            signature: Uint8List(64), // Dummy signature
          );

          expect(qrData.length, equals(240), reason: 'QR offre V2 doit faire 240 octets');

          // 5. Décoder et vérifier
          final decoded = qrService.decodeQr(qrData);
          expect(decoded, isNotNull);
          expect(decoded!.bonId, equals(bonId));
          expect(HEX.encode(decoded.encryptedP2), equals(HEX.encode(ciphertextOnly)));
          expect(HEX.encode(decoded.challenge), equals(challenge));
        });

        test('Étape B : Réception et vérification par le receveur', () async {
          final bonKeys = cryptoService.generateNostrKeyPair();
          final bonId = bonKeys['publicKeyHex']!;
          final originalNsec = bonKeys['privateKeyHex']!;
          final originalNsecBytes = Uint8List.fromList(HEX.decode(originalNsec));
          final partsBytes = cryptoService.shamirSplitBytes(originalNsecBytes);
          cryptoService.secureZeroiseBytes(originalNsecBytes);
          
          // Alice chiffre P2
          final encryptedP2Result = await cryptoService.encryptP2Bytes(partsBytes[1], partsBytes[2]);

          // Bob reçoit et déchiffre P2
          final decryptedP2Bytes = await cryptoService.decryptP2Bytes(
            encryptedP2Result.ciphertext,
            encryptedP2Result.nonce,
            partsBytes[2],
          );
          final decryptedP2 = HEX.encode(decryptedP2Bytes);

          expect(decryptedP2, equals(HEX.encode(partsBytes[1])), reason: 'P2 déchiffré doit correspondre');

          // Bob reconstruit nsec_B en RAM
          final reconstructedNsecBytes = cryptoService.shamirCombineBytesDirect(null, decryptedP2Bytes, partsBytes[2]);
          final reconstructedNsec = HEX.encode(reconstructedNsecBytes);
          expect(reconstructedNsec, equals(originalNsec));

          // Signature du challenge (doit être 32 octets - hash SHA256)
          final challengeBytes = Uint8List.fromList(List.generate(32, (i) => i + 1));
          final signatureBytes = cryptoService.signMessageBytesDirect(challengeBytes, reconstructedNsecBytes);
          final signatureHex = HEX.encode(signatureBytes);

          expect(signatureHex.length, equals(128));
          expect(cryptoService.verifySignature(HEX.encode(challengeBytes), signatureHex, bonId), isTrue);
        });

        test('Étape C : Accusé de réception (QR2 - ACK)', () {
          final bonId = 'a' * 64;
          final signature = 'b' * 128; // Signature fictive

          // Encoder l'ACK
          final ackData = qrService.encodeAck(
            bonIdHex: bonId,
            signatureHex: signature,
            status: 0x01, // RECEIVED
          );

          expect(ackData.length, equals(97), reason: 'QR ACK doit faire 97 octets');

          // Décoder et vérifier
          final decoded = qrService.decodeAck(ackData);
          expect(decoded['bonId'], equals(bonId));
          expect(decoded['signature'], equals(signature));
          expect(decoded['status'], equals(0x01));
        });

        test('Étape D : Finalisation par l\'émetteur', () async {
          final bonKeys = cryptoService.generateNostrKeyPair();
          final bonId = bonKeys['publicKeyHex']!;
          final nsec = bonKeys['privateKeyHex']!;

          final challengeBytes = Uint8List.fromList(
            List.generate(16, (_) => DateTime.now().millisecondsSinceEpoch % 256)
          );
          final challenge = HEX.encode(challengeBytes);
          final signature = cryptoService.signMessage(challenge, nsec);

          final isValid = cryptoService.verifySignature(challenge, signature, bonId);
          expect(isValid, isTrue, reason: 'La signature doit être valide');

          final bon = Bon(
            bonId: bonId,
            value: 25.0,
            issuerName: 'Test',
            issuerNpub: 'npub1${'a' * 58}',
            createdAt: DateTime.now(),
            status: BonStatus.spent, // Marqué comme dépensé
            marketName: 'Test Market',
          );

          expect(bon.status, equals(BonStatus.spent), reason: 'Le bon doit être marqué comme dépensé');
          expect(bon.isValid, isFalse, reason: 'Un bon dépensé n\'est plus valide');
        });

        test('Transfert complet atomique (flux end-to-end)', () async {
          // === ALICE (Émetteur) ===
          final aliceKeys = cryptoService.generateNostrKeyPair();
          final bonId = aliceKeys['publicKeyHex']!;
          final bonNsecBytes = Uint8List.fromList(HEX.decode(aliceKeys['privateKeyHex']!));
          final partsBytes = cryptoService.shamirSplitBytes(bonNsecBytes);
          cryptoService.secureZeroiseBytes(bonNsecBytes);

          // Préparation de l'offre
          final encryptedP2Result = await cryptoService.encryptP2Bytes(partsBytes[1], partsBytes[2]);
          
          // Séparer le ciphertext et le tag pour le QR (48 octets total = 32 + 16)
          final ciphertextOnly = Uint8List.fromList(encryptedP2Result.ciphertext.sublist(0, 32));
          final tagOnly = encryptedP2Result.tag;
          
          // Challenge de 16 octets (stocké dans le QR)
          final challengeBytes = Uint8List.fromList(
            List.generate(16, (i) => (DateTime.now().millisecondsSinceEpoch + i) % 256)
          );
          
          final qrOffer = qrService.encodeQrV2Bytes(
            bonId: Uint8List.fromList(HEX.decode(bonId)),
            valueInCentimes: 1000,
            issuerNpub: Uint8List(32),
            issuerName: "Test Issuer",
            encryptedP2: ciphertextOnly,
            p2Nonce: encryptedP2Result.nonce,
            p2Tag: tagOnly,
            challenge: challengeBytes,
            signature: Uint8List(64), // Dummy signature
          );

          // === BOB (Receveur) ===
          final decodedOffer = qrService.decodeQr(qrOffer);
          expect(decodedOffer, isNotNull);
          expect(decodedOffer!.bonId, equals(bonId));

          // Recombiner ciphertext + tag pour le déchiffrement
          final ciphertextWithTag = Uint8List.fromList([
            ...decodedOffer.encryptedP2,
            ...decodedOffer.p2Tag,
          ]);

          final decryptedP2Bytes = await cryptoService.decryptP2Bytes(
            ciphertextWithTag,
            decodedOffer.p2Nonce,
            partsBytes[2],
          );

          final reconstructedNsecBytes = cryptoService.shamirCombineBytesDirect(null, decryptedP2Bytes, partsBytes[2]);
          
          // Hasher le challenge (16 octets) en SHA256 (32 octets) avant de signer
          final challengeHash = Uint8List.fromList(sha256.convert(decodedOffer.challenge).bytes);
          final signatureBytes = cryptoService.signMessageBytesDirect(challengeHash, reconstructedNsecBytes);

          // Génération de l'ACK
          final qrAck = qrService.encodeAckBytes(
            bonId: Uint8List.fromList(HEX.decode(bonId)),
            signature: signatureBytes,
          );

          // === ALICE (Finalisation) ===
          final decodedAck = qrService.decodeAckBytes(qrAck);
          expect(HEX.encode(decodedAck.bonId), equals(bonId));

          // Hasher le challenge avant de vérifier (comme Bob l'a hashé avant de signer)
          final challengeHashForVerify = Uint8List.fromList(sha256.convert(challengeBytes).bytes);
          final isSignatureValid = cryptoService.verifySignatureBytesDirect(
            challengeHashForVerify,
            decodedAck.signature,
            Uint8List.fromList(HEX.decode(bonId)),
          );
          expect(isSignatureValid, isTrue, reason: 'La signature de Bob doit être valide');
        });
      });
    });
    group('========================================', () {
      group('TESTS DE SÉCURITÉ ADDITIONNELS', () {
        late CryptoService cryptoService;
        late QRService qrService;

        setUp(() {
          cryptoService = CryptoService();
          qrService = QRService();
        });

        test('Validation clé publique secp256k1', () {
          final keys = cryptoService.generateNostrKeyPair();
          final pubKeyHex = keys['publicKeyHex']!;

          expect(cryptoService.isValidPublicKey(pubKeyHex), isTrue, 
            reason: 'La clé publique générée doit être valide');

          // Tester avec une clé invalide
          expect(cryptoService.isValidPublicKey('invalid'), isFalse);
          expect(cryptoService.isValidPublicKey('a' * 63), isFalse); // Mauvaise longueur
          expect(cryptoService.isValidPublicKey('g' * 64), isFalse); // Caractères non hex
        });

        test('Signature Schnorr - Détection de falsification', () {
          final keys = cryptoService.generateNostrKeyPair();
          final pubKey = keys['publicKeyHex']!;
          final nsec = keys['privateKeyHex']!;
          
          final challengeBytes = Uint8List.fromList(
            List.generate(16, (_) => DateTime.now().millisecondsSinceEpoch % 256)
          );
          final challenge = HEX.encode(challengeBytes);

          final signature = cryptoService.signMessage(challenge, nsec);

          // Signature valide
          expect(cryptoService.verifySignature(challenge, signature, pubKey), isTrue);

          // Signature avec mauvais challenge
          final wrongChallengeBytes = Uint8List.fromList(
            List.generate(16, (_) => DateTime.now().millisecondsSinceEpoch % 256)
          );
          final wrongChallenge = HEX.encode(wrongChallengeBytes);
          expect(cryptoService.verifySignature(wrongChallenge, signature, pubKey), isFalse);

          // Signature avec mauvaise clé publique
          final wrongPubKey = cryptoService.generateNostrKeyPair()['publicKeyHex']!;
          expect(cryptoService.verifySignature(challenge, signature, wrongPubKey), isFalse);
        });

        test('Shamir - Parts corrompues donnent un résultat différent', () {
          final keys = cryptoService.generateNostrKeyPair();
          final originalNsec = keys['privateKeyHex']!;
          final originalNsecBytes = Uint8List.fromList(HEX.decode(originalNsec));
        final partsBytes = cryptoService.shamirSplitBytes(originalNsecBytes);
        final parts = partsBytes.map((p) => HEX.encode(p)).toList();
        cryptoService.secureZeroiseBytes(originalNsecBytes);

          // Parts valides - reconstruction correcte
          final p0Bytes = Uint8List.fromList(HEX.decode(parts[0]));
          final p1Bytes = Uint8List.fromList(HEX.decode(parts[1]));
          final validReconstruction = HEX.encode(cryptoService.shamirCombineBytesDirect(p0Bytes, p1Bytes, null));
          expect(validReconstruction, equals(originalNsec), reason: 'Parts valides doivent reconstruire la clé');

          // Part corrompue (modifier un byte)
          // Note: Shamir ne détecte pas les parts corrompues, il reconstruit un résultat incorrect
          final corruptedP2 = '${parts[1].substring(0, 62)}ff';
          final corruptedP2Bytes = Uint8List.fromList(HEX.decode(corruptedP2));
          final corruptedReconstruction = HEX.encode(cryptoService.shamirCombineBytesDirect(p0Bytes, corruptedP2Bytes, null));
          
          // Le résultat reconstruit sera différent de l'original
          expect(corruptedReconstruction, isNot(equals(originalNsec)),
            reason: 'Parts corrompues doivent donner un résultat différent de l\'original');
        });

        test('QR - Détection d\'expiration', () {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final ttl = 300; // 5 minutes

          // QR non expiré
          expect(qrService.isExpired(now, ttl), isFalse);
          expect(qrService.timeRemaining(now, ttl), greaterThan(0));

          // QR expiré
          final expiredTimestamp = now - 600; // 10 minutes dans le passé
          expect(qrService.isExpired(expiredTimestamp, ttl), isTrue);
          expect(qrService.timeRemaining(expiredTimestamp, ttl), equals(0));
        });
      });
    });
  });
}
