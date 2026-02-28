import 'package:flutter/material.dart';
import '../../models/bon.dart';

/// État de la carte Panini
class PaniniCardState {
  final bool isPressed;

  const PaniniCardState({
    this.isPressed = false,
  });

  PaniniCardState copyWith({
    bool? isPressed,
  }) {
    return PaniniCardState(
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
  
  PaniniCardState _state = const PaniniCardState();

  PaniniCardController({
    required this.bon,
  });

  PaniniCardState get state => _state;

  /// Initialise le contrôleur (à appeler dans initState)
  void initialize() {
    // Plus besoin de cache service
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
    // Plus besoin de cache service
  }

  @override
  void dispose() {
    super.dispose();
  }
}
