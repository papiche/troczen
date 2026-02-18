import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/onboarding_state.dart';
import 'onboarding_seed_screen.dart';
import 'onboarding_advanced_screen.dart';
import 'onboarding_nostr_sync_screen.dart';
import 'onboarding_profile_screen.dart';
import 'onboarding_complete_screen.dart';

/// Flow d'onboarding avec PageView à 5 étapes
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _seedGenerated = false; // Flag pour empêcher le retour après génération de seed
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  void _nextPage() {
    if (_currentPage < 4) {
      // Après l'étape 3 (index 2), marquer que la seed est générée
      if (_currentPage == 2) {
        setState(() => _seedGenerated = true);
      }
      
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
  
  void _previousPage() {
    // Empêcher le retour après l'étape 3 (seed générée)
    if (_currentPage > 0 && !_seedGenerated) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OnboardingNotifier(),
      child: WillPopScope(
        onWillPop: () async {
          // Empêcher le retour système après la seed générée
          if (_seedGenerated) {
            return false;
          }
          
          if (_currentPage > 0) {
            _previousPage();
            return false;
          }
          return true;
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: SafeArea(
            child: Column(
              children: [
                // Indicateur de progression
                _buildProgressIndicator(),
                
                // Contenu des pages
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(), // Désactiver le swipe
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    children: [
                      OnboardingSeedScreen(onNext: _nextPage),
                      OnboardingAdvancedScreen(
                        onNext: _nextPage,
                        onBack: _previousPage,
                      ),
                      OnboardingNostrSyncScreen(
                        onNext: _nextPage,
                        onBack: _seedGenerated ? null : _previousPage,
                      ),
                      OnboardingProfileScreen(
                        onNext: _nextPage,
                        onBack: null, // Pas de retour après seed générée
                      ),
                      const OnboardingCompleteScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Row(
            children: List.generate(5, (index) {
              final isActive = index == _currentPage;
              final isCompleted = index < _currentPage;
              
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index < 4 ? 8 : 0),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFFFFB347)
                        : isActive
                            ? const Color(0xFFFFB347).withOpacity(0.5)
                            : Colors.grey[800],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Étape ${_currentPage + 1} sur 5',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Notifier pour gérer l'état de l'onboarding
class OnboardingNotifier extends ChangeNotifier {
  OnboardingState _state = OnboardingState();
  
  OnboardingState get state => _state;
  
  void updateState(OnboardingState newState) {
    _state = newState;
    notifyListeners();
  }
  
  void setSeedMarket(String seed, String mode) {
    _state = _state.copyWith(seedMarket: seed, seedMode: mode);
    notifyListeners();
  }
  
  void setAdvancedConfig({
    String? relayUrl,
    String? apiUrl,
    String? ipfsGateway,
  }) {
    _state = _state.copyWith(
      relayUrl: relayUrl,
      apiUrl: apiUrl,
      ipfsGateway: ipfsGateway,
    );
    notifyListeners();
  }
  
  void setSyncCompleted(int p3Count) {
    _state = _state.copyWith(
      p3Count: p3Count,
      syncCompleted: true,
    );
    notifyListeners();
  }
  
  void setProfile({
    required String displayName,
    String? about,
    String? pictureUrl,
    List<String>? activityTags,
    String? g1PublicKey,
  }) {
    _state = _state.copyWith(
      displayName: displayName,
      about: about,
      pictureUrl: pictureUrl,
      activityTags: activityTags,
      g1PublicKey: g1PublicKey,
    );
    notifyListeners();
  }
}
