import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user.dart';
import '../services/pin_service.dart';
import '../services/storage_service.dart';
import 'main_shell.dart';

/// Écran de verrouillage par code PIN.
/// Affiché à chaque lancement si un PIN est configuré.
/// Après [PinService.maxAttempts] échecs : toutes les données sont effacées.
class PinScreen extends StatefulWidget {
  final User user;

  const PinScreen({super.key, required this.user});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen>
    with SingleTickerProviderStateMixin {
  final _pinService = PinService();
  final _storageService = StorageService();

  String _entered = '';
  int _failures = 0;
  bool _isChecking = false;

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
    _loadFailures();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadFailures() async {
    final f = await _pinService.getFailureCount();
    if (mounted) setState(() => _failures = f);
  }

  void _onDigit(String digit) {
    if (_isChecking || _entered.length >= PinService.pinLength) return;
    setState(() => _entered += digit);
    if (_entered.length == PinService.pinLength) {
      _checkPin();
    }
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _checkPin() async {
    setState(() => _isChecking = true);
    final ok = await _pinService.verifyPin(_entered);

    if (ok) {
      await _pinService.resetFailures();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainShell(user: widget.user)),
      );
    } else {
      final failures = await _pinService.recordFailure();
      HapticFeedback.heavyImpact();
      await _shakeController.forward(from: 0);

      if (failures >= PinService.maxAttempts) {
        await _triggerAutoDestruct();
      } else {
        if (mounted) {
          setState(() {
            _failures = failures;
            _entered = '';
            _isChecking = false;
          });
        }
      }
    }
  }

  Future<void> _triggerAutoDestruct() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.red[900],
        title: const Text(
          'Accès refusé',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '3 tentatives incorrectes.\nToutes les données de l\'application ont été effacées.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    await _storageService.clearAllData();

    if (!mounted) return;
    // Relancer l'app depuis zéro (LoginScreen rédirigera vers l'onboarding)
    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = PinService.maxAttempts - _failures;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),

            // Logo
            const Icon(Icons.lock, size: 48, color: Color(0xFFFFB347)),
            const SizedBox(height: 12),
            const Text(
              'Code PIN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.user.displayName,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),

            const SizedBox(height: 48),

            // 4 points d'indication
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final shake = (_shakeController.isAnimating)
                    ? 8 * (_shakeAnimation.value < 0.5
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
                  final isError = _failures > 0 && _entered.isEmpty && !_isChecking;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? const Color(0xFFFFB347)
                          : isError
                              ? Colors.red[700]
                              : Colors.grey[800],
                      border: Border.all(
                        color: filled
                            ? const Color(0xFFFFB347)
                            : isError
                                ? Colors.red
                                : Colors.grey[600]!,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 16),

            // Message d'erreur / tentatives restantes
            AnimatedOpacity(
              opacity: _failures > 0 ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Text(
                remaining > 0
                    ? '$remaining tentative${remaining > 1 ? 's' : ''} restante${remaining > 1 ? 's' : ''}'
                    : 'Données effacées',
                style: TextStyle(
                  color: remaining <= 1 ? Colors.red : Colors.orange,
                  fontSize: 13,
                ),
              ),
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
              const SizedBox(width: 72, height: 72), // vide à gauche
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
