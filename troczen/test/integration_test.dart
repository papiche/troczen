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
        final parts = cryptoService.shamirSplit(bonNsecHex);
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
        final parts = cryptoService.shamirSplit(bonKeys['privateKeyHex']!);

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
        final parts = cryptoService.shamirSplit(originalNsec);
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
          // PHASE 4, étapes 62-64 du diagramme Mermaid:
          // - Récupère P3 du Bon
          // - Chiffre P2 (Clé AES = SHA256(P3))
          // - Génère Challenge aléatoire
          // - Affiche QR1

          // 1. Préparer les données du bon
          final bonKeys = cryptoService.generateNostrKeyPair();
          final bonId = bonKeys['publicKeyHex']!;
          final parts = cryptoService.shamirSplit(bonKeys['privateKeyHex']!);
          final p2 = parts[1];
          final p3 = parts[2];

          // 2. Chiffrer P2 avec P3 comme clé
          final encryptedP2Result = await cryptoService.encryptP2(p2, p3);
          final encryptedP2 = encryptedP2Result['ciphertext']!;
          final nonce = encryptedP2Result['nonce']!;

          expect(encryptedP2, isNotEmpty, reason: 'P2 chiffré ne doit pas être vide');
          expect(nonce.length, equals(24), reason: 'Nonce doit faire 24 chars hex (12 octets)');

          // 3. Générer un challenge aléatoire (16 octets)
          final challengeBytes = Uint8List.fromList(
            List.generate(16, (_) => DateTime.now().millisecondsSinceEpoch % 256)
          );
          final challenge = HEX.encode(challengeBytes);
          expect(challenge.length, equals(32), reason: 'Challenge doit faire 32 chars hex (16 octets)');

          // 4. Encoder l'offre en QR
          final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final ttl = 300; // 5 minutes

          final qrData = qrService.encodeOffer(
            bonIdHex: bonId,
            p2CipherHex: encryptedP2,
            nonceHex: nonce,
            challengeHex: challenge,
            timestamp: timestamp,
            ttl: ttl,
            signatureHex: '0' * 128, // Dummy signature
          );

          expect(qrData.length, equals(177), reason: 'QR offre doit faire 177 octets');

          // 5. Décoder et vérifier
          final decoded = qrService.decodeOffer(qrData);
          expect(decoded['bonId'], equals(bonId));
          expect(decoded['p2Cipher'], equals(encryptedP2));
          expect(decoded['challenge'], equals(challenge));
        });

        test('Étape B : Réception et vérification par le receveur', () async {
          // PHASE 4, étapes 67-70 du diagramme Mermaid:
          // - Récupère P3 local via npub_B
          // - Déchiffre P2_chiffré grâce à P3
          // - Reconstruit nsec_B = P2 + P3 (en RAM)
          // - Signe le Challenge d'Alice avec nsec_B

          // 1. Préparer les données (simulation de l'offre d'Alice)
          final bonKeys = cryptoService.generateNostrKeyPair();
          final bonId = bonKeys['publicKeyHex']!;
          final originalNsec = bonKeys['privateKeyHex']!;
          final parts = cryptoService.shamirSplit(originalNsec);
          final p2 = parts[1];
          final p3 = parts[2];

          // 2. Alice chiffre P2
          final encryptedP2Result = await cryptoService.encryptP2(p2, p3);
          final encryptedP2 = encryptedP2Result['ciphertext']!;
          final nonce = encryptedP2Result['nonce']!;

          // 3. Bob reçoit et déchiffre P2
          final decryptedP2 = await cryptoService.decryptP2(
            encryptedP2,
            nonce,
            p3,
          );

          expect(decryptedP2, equals(p2), reason: 'P2 déchiffré doit correspondre');

          // 4. Bob reconstruit nsec_B en RAM
          final decryptedP2Bytes = Uint8List.fromList(HEX.decode(decryptedP2));
          final p3Bytes = Uint8List.fromList(HEX.decode(p3));
          final reconstructedNsecBytes = cryptoService.shamirCombineBytesDirect(null, decryptedP2Bytes, p3Bytes);
          final reconstructedNsec = HEX.encode(reconstructedNsecBytes);
          expect(reconstructedNsec, equals(originalNsec),
            reason: 'nsec_B reconstruit doit correspondre à l\'original');

          // 5. Bob signe le challenge
          final challengeBytes = Uint8List.fromList(
            List.generate(16, (_) => DateTime.now().millisecondsSinceEpoch % 256)
          );
          final challenge = HEX.encode(challengeBytes);
          final signature = cryptoService.signMessage(challenge, reconstructedNsec);

          expect(signature, isNotEmpty, reason: 'La signature ne doit pas être vide');
          expect(signature.length, equals(128), reason: 'Signature Schnorr fait 128 chars hex');

          // 6. Vérifier la signature avec la clé publique du bon
          final isValid = cryptoService.verifySignature(challenge, signature, bonId);
          expect(isValid, isTrue, reason: 'La signature doit être valide');
        });

        test('Étape C : Accusé de réception (QR2 - ACK)', () {
          // PHASE 4, étapes 77-78 du diagramme Mermaid:
          // - Affiche QR2 (ACK)

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
          // PHASE 4, étapes 80-82 du diagramme Mermaid:
          // - Vérifie la Signature(Challenge) avec npub_B
          // - Supprime/Invalide P2 du Wallet (Bon = dépensé)

          // 1. Préparer les données
          final bonKeys = cryptoService.generateNostrKeyPair();
          final bonId = bonKeys['publicKeyHex']!;
          final nsec = bonKeys['privateKeyHex']!;

          // 2. Générer et signer un challenge
          final challengeBytes = Uint8List.fromList(
            List.generate(16, (_) => DateTime.now().millisecondsSinceEpoch % 256)
          );
          final challenge = HEX.encode(challengeBytes);
          final signature = cryptoService.signMessage(challenge, nsec);

          // 3. Alice vérifie la signature
          final isValid = cryptoService.verifySignature(challenge, signature, bonId);
          expect(isValid, isTrue, reason: 'La signature doit être valide');

          // 4. Alice marque le bon comme dépensé
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
          // Test complet du flux de transfert atomique
          // Simule les 4 étapes du diagramme Mermaid

          // === ALICE (Émetteur) ===
          // 1. Création du bon
          final aliceKeys = cryptoService.generateNostrKeyPair();
          final bonId = aliceKeys['publicKeyHex']!;
          final bonNsec = aliceKeys['privateKeyHex']!;
          final parts = cryptoService.shamirSplit(bonNsec);
          final p1 = parts[0], p2 = parts[1], p3 = parts[2];

          // 2. Préparation de l'offre
          final encryptedP2Result = await cryptoService.encryptP2(p2, p3);
          final encryptedP2 = encryptedP2Result['ciphertext']!;
          final nonce = encryptedP2Result['nonce']!;
          
          final challengeBytes = Uint8List.fromList(
            List.generate(16, (_) => DateTime.now().millisecondsSinceEpoch % 256)
          );
          final challenge = HEX.encode(challengeBytes);

          final qrOffer = qrService.encodeOffer(
            bonIdHex: bonId,
            p2CipherHex: encryptedP2,
            nonceHex: nonce,
            challengeHex: challenge,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ttl: 300,
            signatureHex: '0' * 128, // Dummy signature
          );

          // === BOB (Receveur) ===
          // 3. Réception et déchiffrement
          final decodedOffer = qrService.decodeOffer(qrOffer);
          expect(decodedOffer['bonId'], equals(bonId));

          // Bob a P3 en cache (simulé)
          final decryptedP2 = await cryptoService.decryptP2(
            decodedOffer['p2Cipher'],
            decodedOffer['nonce'],
            p3,
          );

          // 4. Reconstruction et signature
          final decryptedP2Bytes = Uint8List.fromList(HEX.decode(decryptedP2));
          final p3Bytes = Uint8List.fromList(HEX.decode(p3));
          final reconstructedNsecBytes = cryptoService.shamirCombineBytesDirect(null, decryptedP2Bytes, p3Bytes);
          final reconstructedNsec = HEX.encode(reconstructedNsecBytes);
          final signature = cryptoService.signMessage(decodedOffer['challenge'], reconstructedNsec);

          // 5. Génération de l'ACK
          final qrAck = qrService.encodeAck(
            bonIdHex: bonId,
            signatureHex: signature,
          );

          // === ALICE (Finalisation) ===
          // 6. Vérification de l'ACK
          final decodedAck = qrService.decodeAck(qrAck);
          expect(decodedAck['bonId'], equals(bonId));

          final isSignatureValid = cryptoService.verifySignature(
            challenge,
            decodedAck['signature'],
            bonId,
          );
          expect(isSignatureValid, isTrue, reason: 'La signature de Bob doit être valide');

          // ✅ TRANSFERT TERMINÉ ET SÉCURISÉ
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
          final parts = cryptoService.shamirSplit(originalNsec);

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
