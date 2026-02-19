import 'package:flutter/material.dart';
import '../../models/bon.dart';
import '../../services/panini_card_cache_service.dart';

/// État de la carte Panini
class PaniniCardState {
  final PaniniCacheResult cacheResult;
  final bool isPressed;

  const PaniniCardState({
    this.cacheResult = const PaniniCacheResult(isChecking: true),
    this.isPressed = false,
  });

  PaniniCardState copyWith({
    PaniniCacheResult? cacheResult,
    bool? isPressed,
  }) {
    return PaniniCardState(
      cacheResult: cacheResult ?? this.cacheResult,
      isPressed: isPressed ?? this.isPressed,
    );
  }
}

/// Contrôleur pour la gestion de l'état de PaniniCard.
/// 
/// Ce contrôleur utilise ChangeNotifier pour notifier les widgets
/// lorsque l'état change (cache chargé, pression tactile, etc.).
/// 
/// Exemple d'utilisation:
/// ```dart
/// final controller = PaniniCardController(bon: monBon);
/// 
/// // Dans un widget
/// AnimatedBuilder(
///   animation: controller,
///   builder: (context, child) {
///     return Text(controller.state.cacheResult.localPicturePath ?? 'Chargement...');
///   },
/// )
/// ```
class PaniniCardController extends ChangeNotifier {
  final Bon bon;
  final PaniniCardCacheService? cacheService;
  
  PaniniCardState _state = const PaniniCardState();
  PaniniCardCacheService? _internalCacheService;

  PaniniCardController({
    required this.bon,
    this.cacheService,
  });

  PaniniCardState get state => _state;

  /// Initialise le contrôleur (à appeler dans initState)
  void initialize() {
    _internalCacheService = cacheService ?? PaniniCardCacheService();
    _internalCacheService!.addListener(_onCacheChanged);
    _updateCacheResult();
  }

  void _onCacheChanged() {
    _updateCacheResult();
  }

  void _updateCacheResult() {
    if (_internalCacheService != null) {
      _state = _state.copyWith(
        cacheResult: _internalCacheService!.getCacheResult(bon),
      );
      notifyListeners();
    }
  }

  /// Gestion de la pression tactile (début)
  void onTapDown() {
    _state = _state.copyWith(isPressed: true);
    notifyListeners();
  }

  /// Gestion de la pression tactile (fin)
  void onTapUp() {
    _state = _state.copyWith(isPressed: false);
    notifyListeners();
  }

  /// Gestion de l'annulation de la pression
  void onTapCancel() {
    _state = _state.copyWith(isPressed: false);
    notifyListeners();
  }

  /// Rafraîchit le cache pour ce bon
  void refreshCache() {
    _internalCacheService?.invalidateCache(bon.bonId);
    _updateCacheResult();
  }

  @override
  void dispose() {
    _internalCacheService?.removeListener(_onCacheChanged);
    // Ne pas disposer le cache service s'il a été passé en paramètre
    if (cacheService == null) {
      _internalCacheService?.dispose();
    }
    super.dispose();
  }
}
