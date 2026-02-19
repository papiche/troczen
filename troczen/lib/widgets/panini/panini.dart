/// Composants pour les cartes Panini.
///
/// Ce dossier contient les widgets refactorisés pour l'affichage
/// des bons au format "carte de collection" style Panini.
///
/// Architecture:
/// - [RarityBadge] : Badge de rareté
/// - [OfflineFirstImage] : Image avec support offline-first
/// - [BonCardHeader] : En-tête de la carte
/// - [BonCardBody] : Corps de la carte
/// - [BonCardFooter] : Pied de la carte
/// - [HolographicEffect] : Effet holographique pour les cartes rares
/// - [PaniniCardController] : Contrôleur ChangeNotifier pour l'état
///
/// Le widget principal [PaniniCard] se trouve dans panini_card.dart
/// à la racine du dossier widgets.
library;

export 'rarity_badge.dart';
export 'offline_first_image.dart';
export 'bon_card_header.dart';
export 'bon_card_body.dart';
export 'bon_card_footer.dart';
export 'holographic_effect.dart';
export 'panini_card_controller.dart';
