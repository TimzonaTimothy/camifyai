import '../../widgets/responsive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _isLoading = false;
  bool _success = false;
  String? _error;

  // Simple strength calculation
  _PasswordStrength get _strength {
    final p = _newCtrl.text;
    if (p.length < 8) return _PasswordStrength.weak;
    int score = 0;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    if (score <= 1) return _PasswordStrength.fair;
    if (score <= 2) return _PasswordStrength.good;
    return _PasswordStrength.strong;
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ApiService.instance.desktopChangePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
        confirmPassword: _confirmCtrl.text,
      );

      if (!mounted) return;

      if (result['ok'] == true) {
        setState(() {
          _success = true;
        });
      } else {
        setState(() {
          _error = result['error'] ?? 'Failed to change password. Try again.';
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Connection error. Check your internet.';
      });
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Change Password',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: _success ? _buildSuccessState() : _buildFormState(),
    );
  }

  // ── Success state ──────────────────────────────────────────────────────────

  Widget _buildSuccessState() {
    return SingleChildScrollView(
        child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.successDim,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withOpacity(0.4)),
                ),
                child: const Icon(Icons.check_circle_outline_rounded,
                    color: AppColors.success, size: 40),
              ).animate().scale(begin: const Offset(0, 0)).fadeIn(),
              const SizedBox(height: 28),
              const Text(
                'Password updated!',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 12),
              const Text(
                'Your password has been changed successfully.\nA confirmation email has been sent to your inbox.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 150.ms),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/dashboard'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Back to Dashboard',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms),
            ],
          ),
        ),
      ),
    ));
  }

  // ── Form state ─────────────────────────────────────────────────────────────

  Widget _buildFormState() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: AppLayout.padding(context),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.accentDim,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.lock_outline_rounded,
                              color: AppColors.accent, size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Update your password',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Choose a strong, unique password',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(),

                  const SizedBox(height: 28),

                  // Error banner
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppColors.errorDim,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: AppColors.error, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ).animate().shake(),
                  ],

                  // ── Current Password ──────────────────────────────────────
                  _fieldLabel('Current Password'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _currentCtrl,
                    obscureText: !_showCurrent,
                    decoration: InputDecoration(
                      hintText: 'Enter your current password',
                      prefixIcon: const Icon(Icons.lock_outline, size: 18),
                      suffixIcon: _visibilityToggle(
                        visible: _showCurrent,
                        onTap: () =>
                            setState(() => _showCurrent = !_showCurrent),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return 'Current password is required';
                      return null;
                    },
                  ).animate().fadeIn(delay: 100.ms),

                  const SizedBox(height: 20),

                  // ── New Password ──────────────────────────────────────────
                  _fieldLabel('New Password'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _newCtrl,
                    obscureText: !_showNew,
                    onChanged: (_) =>
                        setState(() {}), // trigger strength rebuild
                    decoration: InputDecoration(
                      hintText: 'Enter new password',
                      prefixIcon:
                          const Icon(Icons.lock_reset_rounded, size: 18),
                      suffixIcon: _visibilityToggle(
                        visible: _showNew,
                        onTap: () => setState(() => _showNew = !_showNew),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return 'New password is required';
                      if (v.length < 8) return 'Must be at least 8 characters';
                      if (v == _currentCtrl.text)
                        return 'Must differ from current password';
                      return null;
                    },
                  ).animate().fadeIn(delay: 150.ms),

                  // Strength indicator
                  if (_newCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildStrengthIndicator(),
                  ],

                  const SizedBox(height: 20),

                  // ── Confirm Password ──────────────────────────────────────
                  _fieldLabel('Confirm New Password'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: !_showConfirm,
                    decoration: InputDecoration(
                      hintText: 'Re-enter new password',
                      prefixIcon: const Icon(Icons.lock_outline, size: 18),
                      suffixIcon: _visibilityToggle(
                        visible: _showConfirm,
                        onTap: () =>
                            setState(() => _showConfirm = !_showConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return 'Please confirm your new password';
                      if (v != _newCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ).animate().fadeIn(delay: 200.ms),

                  const SizedBox(height: 12),

                  // Tips
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Password tips',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 8),
                        _TipRow(text: 'At least 8 characters'),
                        _TipRow(text: 'Mix uppercase & lowercase letters'),
                        _TipRow(text: 'Include numbers or special characters'),
                      ],
                    ),
                  ).animate().fadeIn(delay: 250.ms),

                  const SizedBox(height: 28),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  color: AppColors.onAccent, strokeWidth: 2),
                            )
                          : const Text(
                              'Update Password',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ).animate().fadeIn(delay: 300.ms),

                  const SizedBox(height: 16),

                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/dashboard'),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ).animate().fadeIn(delay: 350.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _visibilityToggle(
      {required bool visible, required VoidCallback onTap}) {
    return IconButton(
      icon: Icon(visible ? Icons.visibility_off : Icons.visibility, size: 18),
      onPressed: onTap,
      color: AppColors.textMuted,
    );
  }

  Widget _buildStrengthIndicator() {
    final s = _strength;
    final segments = 4;
    final filled = s.index + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(segments, (i) {
            final active = i < filled;
            return Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i < segments - 1 ? 4 : 0),
                decoration: BoxDecoration(
                  color: active ? s.color : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 5),
        Text(
          'Strength: ${s.label}',
          style: TextStyle(
              color: s.color, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

enum _PasswordStrength {
  weak('Weak', Color(0xFFFF4C6E)),
  fair('Fair', Color(0xFFFFAA00)),
  good('Good', Color(0xFF00AAFF)),
  strong('Strong', Color(0xFF00D68F));

  const _PasswordStrength(this.label, this.color);
  final String label;
  final Color color;
}

class _TipRow extends StatelessWidget {
  final String text;
  const _TipRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.check_rounded, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11))),
        ],
      ),
    );
  }
}
