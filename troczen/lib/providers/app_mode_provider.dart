import 'package:flutter/foundation.dart';
import '../models/app_mode.dart';
import '../services/storage_service.dart';
import '../services/logger_service.dart';

/// Provider global pour gérer le mode d'utilisation de l'application
/// 
/// Permet de changer dynamiquement l'interface selon le profil utilisateur
/// et de persister le choix dans le stockage sécurisé
class AppModeProvider extends ChangeNotifier {
  final StorageService _storageService;
  AppMode _currentMode = AppMode.flaneur;
  bool _isLoading = true;

  AppModeProvider(this._storageService) {
    _loadMode();
  }

  /// Mode d'utilisation actuel
  AppMode get currentMode => _currentMode;

  /// Indique si le chargement est en cours
  bool get isLoading => _isLoading;

  /// Charge le mode depuis le stockage
  Future<void> _loadMode() async {
    try {
      final modeIndex = await _storageService.getAppMode();
      _currentMode = AppMode.fromIndex(modeIndex);
      _isLoading = false;
      notifyListeners();
      Logger.log('AppModeProvider', 'Mode chargé: ${_currentMode.label}');
    } catch (e) {
      Logger.error('AppModeProvider', 'Erreur chargement mode', e);
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Change le mode d'utilisation
  Future<void> setMode(AppMode mode) async {
    try {
      await _storageService.setAppMode(mode.value);
      _currentMode = mode;
      notifyListeners();
      Logger.success('AppModeProvider', 'Mode changé: ${mode.label}');
    } catch (e) {
      Logger.error('AppModeProvider', 'Erreur changement mode', e);
    }
  }

  /// Passage au mode supérieur (gamification)
  /// Flâneur -> Artisan -> Alchimiste
  Future<void> upgradeMode() async {
    switch (_currentMode) {
      case AppMode.flaneur:
        await setMode(AppMode.artisan);
        break;
      case AppMode.artisan:
        await setMode(AppMode.alchimiste);
        break;
      case AppMode.alchimiste:
        // Déjà au max
        Logger.info('AppModeProvider', 'Mode maximum déjà atteint');
        break;
    }
  }

  /// Suggère une mise à niveau du mode selon les critères
  /// Retourne true si une suggestion est appropriée
  bool shouldSuggestUpgrade({int? contactsCount, int? bonsCreated}) {
    switch (_currentMode) {
      case AppMode.flaneur:
        // Suggérer Artisan si N1 >= 5 (DU activé)
        if (contactsCount != null && contactsCount >= 5) {
          return true;
        }
        break;
      case AppMode.artisan:
        // Suggérer Alchimiste si bons créés >= 10 (acteur établi)
        if (bonsCreated != null && bonsCreated >= 10) {
          return true;
        }
        break;
      case AppMode.alchimiste:
        // Déjà au max
        return false;
    }
    return false;
  }

  /// Message de suggestion pour la mise à niveau
  String getUpgradeSuggestionMessage() {
    switch (_currentMode) {
      case AppMode.flaneur:
        return 'Félicitations ! Vous avez tissé votre toile de confiance (N1 ≥ 5).\n'
            'Voulez-vous activer le mode Artisan pour créer vos propres bons ?';
      case AppMode.artisan:
        return 'Vous êtes un acteur établi du marché !\n'
            'Voulez-vous découvrir l\'Observatoire (mode Alchimiste) pour analyser les circuits économiques ?';
      case AppMode.alchimiste:
        return '';
    }
  }

  /// Mode suivant disponible pour l'upgrade
  AppMode? get nextMode {
    switch (_currentMode) {
      case AppMode.flaneur:
        return AppMode.artisan;
      case AppMode.artisan:
        return AppMode.alchimiste;
      case AppMode.alchimiste:
        return null;
    }
  }
}
