import 'package:deepfake_software/widgets/camify_logo.dart';

import '../../widgets/responsive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  // 0 = email, 1 = OTP + new password, 2 = success
  int _step = 0;
  bool _isLoading = false;
  String? _error;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Step 1: Request OTP ───────────────────────────────────────────────────

  Future<void> _sendOTP() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ApiService.instance.desktopForgotPassword(
        _emailCtrl.text.trim().toLowerCase(),
      );
      if (!mounted) return;

      if (result['ok'] == true) {
        setState(() {
          _step = 1;
        });
      } else {
        setState(() {
          _error = result['error'] ?? 'Something went wrong.';
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

  // ── Step 2: Verify OTP + reset password ───────────────────────────────────

  Future<void> _verifyOTP() async {
    if (!_otpFormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ApiService.instance.desktopVerifyOTP(
        email: _emailCtrl.text.trim().toLowerCase(),
        code: _codeCtrl.text.trim(),
        newPassword: _newPwCtrl.text,
        confirmPassword: _confirmCtrl.text,
      );
      if (!mounted) return;

      if (result['ok'] == true) {
        setState(() {
          _step = 2;
        });
      } else {
        setState(() {
          _error = result['error'] ?? 'Verification failed.';
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
      body: AuthLayout(
        children: [
          // ── Left branding panel ──────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF101713), Color(0xFF1E291F)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -100,
                    left: -100,
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x22C9EF9C), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -50,
                    right: -50,
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x15C9EF9C), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo
                        // Logo — matches website / live studio brand
                        const CamifyLogo(iconSize: 36, fontSize: 20).animate().fadeIn(delay: 100.ms),

                        const Spacer(),

                        // Icon + heading
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.accentDim,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                          ),
                          child: Icon(
                            _step == 2 ? Icons.check_circle_outline_rounded : Icons.lock_reset_rounded,
                            color: _step == 2 ? AppColors.success : AppColors.accent,
                            size: 36,
                          ),
                        ).animate().fadeIn(delay: 200.ms).scale(begin: const Offset(0.8, 0.8)),

                        const SizedBox(height: 28),

                        Text(
                          _step == 0
                              ? 'Forgot\nyour\npassword?'
                              : _step == 1
                                  ? 'Enter\nyour\nreset code'
                                  : 'Password\nreset\ncomplete!',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                            height: 1.1,
                          ),
                        ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.05),

                        const SizedBox(height: 20),

                        Text(
                          _step == 0
                              ? "No worries. Enter your email and we'll\nsend a 6-digit code to your inbox."
                              : _step == 1
                                  ? 'Check your email for the 6-digit code.\nEnter it below with your new password.'
                                  : 'You can now sign in with\nyour new password.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ).animate().fadeIn(delay: 400.ms),

                        const Spacer(),

                        // Security note
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.shield_outlined, color: AppColors.success, size: 18),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Reset codes are sent from streamai51@gmail.com and expire in 10 minutes.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: 500.ms),

                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Right form panel ──────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: Container(
              color: AppColors.surface,
              padding: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width < 700 ? 24 : 56, vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: _step == 0
                      ? _buildEmailStep()
                      : _step == 1
                          ? _buildOTPStep()
                          : _buildSuccessStep(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 0: Email input ───────────────────────────────────────────────────

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reset password',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 6),

          const Text(
            'Enter the email linked to your account',
            style: TextStyle(color: AppColors.textSecondary),
          ).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 36),

          // Error banner
          if (_error != null) ...[
            _errorBanner(_error!),
          ],

          // Email field
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.email_outlined, size: 18),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Email is required';
              if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
              return null;
            },
            onFieldSubmitted: (_) => _sendOTP(),
          ).animate().fadeIn(delay: 150.ms),

          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendOTP,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(color: AppColors.onAccent, strokeWidth: 2),
                    )
                  : const Text(
                      'Send Reset Code',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 20),

          Center(
            child: TextButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.arrow_back_rounded, size: 14, color: AppColors.accent),
              label: const Text(
                'Back to Sign In',
                style: TextStyle(color: AppColors.accent, fontSize: 13),
              ),
            ),
          ).animate().fadeIn(delay: 250.ms),
        ],
      ),
    );
  }

  // ── Step 1: OTP + New Password ────────────────────────────────────────────

  Widget _buildOTPStep() {
    return Form(
      key: _otpFormKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sent-to indicator
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mark_email_read_outlined, color: AppColors.accent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Code sent to ${_emailCtrl.text.trim()}',
                      style: const TextStyle(color: AppColors.accent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(),

            const Text(
              'Verify & reset',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ).animate().fadeIn(duration: 300.ms),

            const SizedBox(height: 6),

            const Text(
              'Enter the 6-digit code and choose a new password',
              style: TextStyle(color: AppColors.textSecondary),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 28),

            // Error banner
            if (_error != null) ...[
              _errorBanner(_error!),
            ],

            // OTP code field
            _fieldLabel('Reset Code'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                hintText: '000000',
                prefixIcon: Icon(Icons.pin_rounded, size: 18),
              ),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Code is required';
                if (v.length != 6) return 'Enter all 6 digits';
                return null;
              },
            ).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 20),

            // New password
            _fieldLabel('New Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newPwCtrl,
              obscureText: !_showNew,
              decoration: InputDecoration(
                hintText: 'Enter new password',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setState(() => _showNew = !_showNew),
                  color: AppColors.textMuted,
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required';
                if (v.length < 8) return 'Must be at least 8 characters';
                return null;
              },
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 14),

            // Confirm password
            _fieldLabel('Confirm Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: !_showConfirm,
              decoration: InputDecoration(
                hintText: 'Re-enter new password',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setState(() => _showConfirm = !_showConfirm),
                  color: AppColors.textMuted,
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm your password';
                if (v != _newPwCtrl.text) return 'Passwords do not match';
                return null;
              },
              onFieldSubmitted: (_) => _verifyOTP(),
            ).animate().fadeIn(delay: 250.ms),

            const SizedBox(height: 28),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyOTP,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(color: AppColors.onAccent, strokeWidth: 2),
                      )
                    : const Text(
                        'Reset Password',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
              ),
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 16),

            // Resend code
            Center(
              child: TextButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _error = null;
                        });
                        _sendOTP();
                      },
                child: const Text(
                  'Resend code',
                  style: TextStyle(color: AppColors.accent, fontSize: 13),
                ),
              ),
            ).animate().fadeIn(delay: 350.ms),

            const SizedBox(height: 4),

            Center(
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _step = 0;
                  _error = null;
                  _codeCtrl.clear();
                }),
                icon: const Icon(Icons.arrow_back_rounded, size: 14, color: AppColors.textSecondary),
                label: const Text(
                  'Change email',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
            ).animate().fadeIn(delay: 350.ms),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Success ───────────────────────────────────────────────────────

  Widget _buildSuccessStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.successDim,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.success.withOpacity(0.4)),
          ),
          child: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 32),
        ).animate().scale(begin: const Offset(0, 0)).fadeIn(),
        const SizedBox(height: 24),
        const Text(
          'Password reset!',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 10),
        const Text(
          'Your password has been changed successfully.\nYou can now sign in with your new password.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.6,
          ),
        ).animate().fadeIn(delay: 150.ms),
        const SizedBox(height: 36),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => context.go('/login'),
            icon: const Icon(Icons.login_rounded, size: 16),
            label: const Text(
              'Sign In',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ).animate().fadeIn(delay: 250.ms),
      ],
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

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

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.errorDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    ).animate().shake();
  }
}
