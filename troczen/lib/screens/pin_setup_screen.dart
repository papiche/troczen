import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user.dart';
import '../services/pin_service.dart';
import 'main_shell.dart';

enum _SetupPhase { enter, confirm }

/// Écran de création du code PIN — appelé en fin d'onboarding.
/// Phase 1 : saisie du PIN à 4 chiffres.
/// Phase 2 : confirmation. Si correspondance → PIN enregistré → MainShell.
class PinSetupScreen extends StatefulWidget {
  final User user;

  const PinSetupScreen({super.key, required this.user});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen>
    with SingleTickerProviderStateMixin {
  final _pinService = PinService();

  _SetupPhase _phase = _SetupPhase.enter;
  String _firstPin = '';
  String _entered = '';
  bool _isSaving = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_isSaving || _entered.length >= PinService.pinLength) return;
    setState(() => _entered += digit);
    if (_entered.length == PinService.pinLength) {
      _handleComplete();
    }
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _handleComplete() async {
    if (_phase == _SetupPhase.enter) {
      setState(() {
        _firstPin = _entered;
        _entered = '';
        _phase = _SetupPhase.confirm;
      });
    } else {
      if (_entered == _firstPin) {
        setState(() => _isSaving = true);
        await _pinService.setPin(_entered);
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => MainShell(user: widget.user)),
          (_) => false,
        );
      } else {
        HapticFeedback.heavyImpact();
        await _shakeController.forward(from: 0);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Les codes ne correspondent pas. Recommencez.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _entered = '';
          _firstPin = '';
          _phase = _SetupPhase.enter;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),

            // Icône et titre
            const Icon(Icons.shield_outlined, size: 52, color: Color(0xFFFFB347)),
            const SizedBox(height: 16),
            Text(
              _phase == _SetupPhase.enter
                  ? 'Créez votre code PIN'
                  : 'Confirmez votre code PIN',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _phase == _SetupPhase.enter
                  ? 'Ce code protège l\'accès à votre compte.\n3 erreurs = données effacées.'
                  : 'Saisissez à nouveau le même code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),

            const SizedBox(height: 48),

            // Indicateurs de progression de saisie
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final shake = _shakeController.isAnimating
                    ? 8 *
                        (_shakeAnimation.value < 0.5
                            ? _shakeAnimation.value
                            : 1 - _shakeAnimation.value)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(shake * 10, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(PinService.pinLength, (i) {
                  final filled = i < _entered.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? const Color(0xFFFFB347)
                          : Colors.grey[800],
                      border: Border.all(
                        color: filled
                            ? const Color(0xFFFFB347)
                            : Colors.grey[600]!,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 12),

            // Indicateur de phase
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _phaseStep(1, _phase == _SetupPhase.enter
                    ? 'active'
                    : 'done'),
                Container(
                  width: 24,
                  height: 2,
                  color: _phase == _SetupPhase.confirm
                      ? const Color(0xFFFFB347)
                      : Colors.grey[800],
                ),
                _phaseStep(2, _phase == _SetupPhase.confirm ? 'active' : 'pending'),
              ],
            ),

            const Spacer(),

            // Pavé numérique
            _buildNumpad(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _phaseStep(int n, String state) {
    final isActive = state == 'active';
    final isDone = state == 'done';
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone
            ? const Color(0xFFFFB347)
            : isActive
                ? const Color(0xFFFFB347).withValues(alpha: 0.2)
                : Colors.grey[800],
        border: Border.all(
          color: isActive || isDone ? const Color(0xFFFFB347) : Colors.grey[700]!,
          width: 2,
        ),
      ),
      child: Center(
        child: isDone
            ? const Icon(Icons.check, size: 14, color: Colors.black)
            : Text(
                '$n',
                style: TextStyle(
                  color: isActive ? const Color(0xFFFFB347) : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          _buildNumRow(['1', '2', '3']),
          const SizedBox(height: 12),
          _buildNumRow(['4', '5', '6']),
          const SizedBox(height: 12),
          _buildNumRow(['7', '8', '9']),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 72, height: 72),
              _numButton('0'),
              _deleteButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map(_numButton).toList(),
    );
  }

  Widget _numButton(String digit) {
    return GestureDetector(
      onTap: () => _onDigit(digit),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E1E1E),
          border: Border.all(color: const Color(0xFF2E2E2E)),
        ),
        child: Center(
          child: Text(
            digit,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      ),
    );
  }

  Widget _deleteButton() {
    return GestureDetector(
      onTap: _onDelete,
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: const Center(
          child: Icon(Icons.backspace_outlined, color: Colors.grey, size: 28),
        ),
      ),
    );
  }
}
