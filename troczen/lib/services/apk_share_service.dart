import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'logger_service.dart';

/// Service de partage d'APK pair-à-pair via serveur HTTP local.
/// Permet à l'application TrocZen de s'auto-partager sur le réseau local.
class ApkShareService {
  static const int _defaultPort = 8303;
  static const String _apkFileName = 'troczen.apk';
  static const String _tag = 'ApkShare';
  
  HttpServer? _server;
  String? _apkPath;
  String? _localIpAddress;
  int _port = _defaultPort;
  int _bytesServed = 0;
  int _downloadsCount = 0;
  
  /// Indique si le serveur est en cours d'exécution
  bool get isRunning => _server != null;
  
  /// Adresse IP locale du téléphone
  String? get localIpAddress => _localIpAddress;
  
  /// Port du serveur
  int get port => _port;
  
  /// URL de téléchargement de l'APK
  String? get downloadUrl => _localIpAddress != null 
      ? 'http://$_localIpAddress:$_port/$_apkFileName'
      : null;
  
  /// Nombre de bytes servis
  int get bytesServed => _bytesServed;
  
  /// Nombre de téléchargements complets
  int get downloadsCount => _downloadsCount;
  
  /// Récupère l'adresse IP locale du téléphone
  Future<String?> _getLocalIpAddress() async {
    try {
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          // On cherche une adresse IPv4 qui n'est pas loopback
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      Logger.error(_tag, 'Erreur lors de la récupération de l\'IP locale', e);
    }
    return null;
  }
  
  /// Extrait l'APK depuis les assets de l'application
  Future<String?> _extractApkFromAssets() async {
    try {
      // Le fichier APK doit être placé dans assets/apk/troczen.apk
      const assetPath = 'assets/apk/$_apkFileName';
      
      // Charger les bytes depuis les assets
      final ByteData byteData;
      try {
        byteData = await rootBundle.load(assetPath);
      } catch (e) {
        Logger.error(_tag, 'APK non trouvé dans les assets', e);
        return null;
      }
      
      // Créer le répertoire de destination
      final appDir = await getApplicationDocumentsDirectory();
      final apkDir = Directory('${appDir.path}/apk_share');
      
      if (!await apkDir.exists()) {
        await apkDir.create(recursive: true);
      }
      
      final destPath = '${apkDir.path}/$_apkFileName';
      final destFile = File(destPath);
      
      // Écrire les bytes dans le fichier
      final buffer = byteData.buffer;
      await destFile.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );
      
      Logger.log(_tag, 'APK extrait depuis les assets: $destPath');
      return destPath;
    } catch (e) {
      Logger.error(_tag, 'Erreur lors de l\'extraction de l\'APK depuis les assets', e);
      return null;
    }
  }
  
  static const platform = MethodChannel('com.example.troczen/apk_path');

  /// Récupère le chemin de l'APK installé via MethodChannel
  Future<String?> _getInstalledApkPath() async {
    try {
      if (Platform.isAndroid) {
        final String? apkPath = await platform.invokeMethod('getApkPath');
        if (apkPath != null && File(apkPath).existsSync()) {
          Logger.log(_tag, 'APK installé trouvé: $apkPath');
          return apkPath;
        }
      }
      return null;
    } catch (e) {
      Logger.error(_tag, 'Erreur lors de la récupération du chemin de l\'APK installé', e);
      return null;
    }
  }
  
  /// Prépare l'APK pour le partage
  Future<bool> prepareApk() async {
    try {
      // Méthode 1: Utiliser l'APK installé (optimisation de taille)
      final installedPath = await _getInstalledApkPath();
      if (installedPath != null) {
        _apkPath = installedPath;
        Logger.log(_tag, 'APK préparé depuis l\'installation (optimisé)');
        return true;
      }

      // Méthode 2: Extraire l'APK depuis les assets (fallback)
      final assetPath = await _extractApkFromAssets();
      if (assetPath != null) {
        _apkPath = assetPath;
        Logger.log(_tag, 'APK préparé depuis les assets (fallback)');
        return true;
      }
      
      Logger.error(_tag, 'Impossible de préparer l\'APK pour le partage');
      return false;
    } catch (e) {
      Logger.error(_tag, 'Erreur lors de la préparation de l\'APK', e);
      return false;
    }
  }
  
  /// Démarre le serveur HTTP de partage
  Future<bool> startServer({int port = _defaultPort}) async {
    if (_server != null) {
      Logger.log(_tag, 'Le serveur est déjà en cours d\'exécution');
      return true;
    }
    
    try {
      // Récupérer l'adresse IP locale
      _localIpAddress = await _getLocalIpAddress();
      if (_localIpAddress == null) {
        Logger.error(_tag, 'Impossible de récupérer l\'adresse IP locale');
        return false;
      }
      
      // Préparer l'APK
      final apkReady = await prepareApk();
      if (!apkReady) {
        Logger.error(_tag, 'Impossible de préparer l\'APK');
        return false;
      }
      
      _port = port;
      
      // Lancer le serveur HTTP
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      
      Logger.log(_tag, 'Serveur APK démarré sur http://$_localIpAddress:$_port');
      
      // Gérer les requêtes entrantes
      _server!.listen(_handleRequest);
      
      return true;
    } catch (e) {
      Logger.error(_tag, 'Erreur lors du démarrage du serveur', e);
      _server = null;
      return false;
    }
  }
  
  /// Gère une requête HTTP entrante
  Future<void> _handleRequest(HttpRequest request) async {
    Logger.log(_tag, 'Requête reçue: ${request.method} ${request.uri.path}');
    
    // Headers CORS pour permettre l'accès depuis n'importe quel client
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
    
    // Gérer les requêtes OPTIONS (preflight CORS)
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }
    
    // Seules les requêtes GET sont autorisées
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }
    
    // Servir l'APK
    if (request.uri.path == '/$_apkFileName') {
      await _serveApk(request);
    } else if (request.uri.path == '/') {
      // Page d'accueil avec instructions
      await _serveWelcomePage(request);
    } else {
      // 404 pour les autres chemins
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Non trouvé');
      await request.response.close();
    }
  }
  
  /// Sert le fichier APK
  Future<void> _serveApk(HttpRequest request) async {
    try {
      if (_apkPath == null) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('APK non disponible');
        await request.response.close();
        return;
      }
      
      final apkFile = File(_apkPath!);
      if (!await apkFile.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('APK non trouvé');
        await request.response.close();
        return;
      }
      
      final fileLength = await apkFile.length();
      
      // Headers pour le téléchargement
      request.response.headers.set('Content-Type', 'application/vnd.android.package-archive');
      request.response.headers.set('Content-Length', fileLength);
      request.response.headers.set('Content-Disposition', 'attachment; filename="$_apkFileName"');
      
      // Stream le fichier vers la réponse
      final stream = apkFile.openRead();
      int bytesSent = 0;
      
      await for (final chunk in stream) {
        request.response.add(chunk);
        bytesSent += chunk.length;
      }
      
      await request.response.close();
      
      _bytesServed += bytesSent;
      _downloadsCount++;
      
      Logger.log(_tag, 'APK servi: $bytesSent bytes envoyés à ${request.connectionInfo?.remoteAddress.address}');
    } catch (e) {
      Logger.error(_tag, 'Erreur lors du service de l\'APK', e);
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }
  
  /// Sert une page d'accueil avec instructions
  Future<void> _serveWelcomePage(HttpRequest request) async {
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TrocZen - Partage APK</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      max-width: 600px;
      margin: 50px auto;
      padding: 20px;
      background: linear-gradient(135deg, #0A7EA4, #FFB347);
      min-height: 100vh;
      color: white;
    }
    .container {
      background: rgba(255,255,255,0.95);
      border-radius: 20px;
      padding: 30px;
      color: #333;
      box-shadow: 0 10px 40px rgba(0,0,0,0.3);
    }
    h1 { color: #0A7EA4; margin-bottom: 10px; }
    .download-btn {
      display: inline-block;
      background: linear-gradient(135deg, #0A7EA4, #0891b2);
      color: white;
      padding: 15px 40px;
      border-radius: 30px;
      text-decoration: none;
      font-size: 18px;
      font-weight: bold;
      margin: 20px 0;
      box-shadow: 0 4px 15px rgba(10, 126, 164, 0.4);
    }
    .info { color: #666; font-size: 14px; margin-top: 20px; }
    .qr-hint {
      background: #FFF3CD;
      border: 1px solid #FFB347;
      border-radius: 10px;
      padding: 15px;
      margin: 20px 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🪙 TrocZen</h1>
    <p>Système de bons ẐEN pour marchés locaux</p>
    
    <div class="qr-hint">
      <strong>📱 Vous avez scanné le QR Code !</strong><br>
      Cliquez ci-dessous pour télécharger l'application.
    </div>
    
    <a href="/$_apkFileName" class="download-btn">⬇️ Télécharger l'APK</a>
    
    <div class="info">
      <p><strong>Instructions:</strong></p>
      <ol>
        <li>Téléchargez l'APK</li>
        <li>Ouvrez le fichier téléchargé</li>
        <li>Autorisez l'installation depuis des sources inconnues si demandé</li>
        <li>Installez et profitez !</li>
      </ol>
    </div>
  </div>
</body>
</html>
''';
    
    request.response.headers.set('Content-Type', 'text/html; charset=utf-8');
    request.response.write(html);
    await request.response.close();
  }
  
  /// Arrête le serveur HTTP
  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close();
      _server = null;
      Logger.log(_tag, 'Serveur APK arrêté');
    }
  }
  
  /// Nettoie les ressources
  Future<void> dispose() async {
    await stopServer();
    _apkPath = null;
    _localIpAddress = null;
    _bytesServed = 0;
    _downloadsCount = 0;
  }
}
