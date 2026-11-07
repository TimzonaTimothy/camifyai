import '../../widgets/responsive_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/camify_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showPassword = false;
  bool _isRegister = false;
  final _usernameCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();

    bool success;
    if (_isRegister) {
      success = await auth.register(
        _emailCtrl.text.trim(),
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
      );
    } else {
      success = await auth.login(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
    }

    if (success && mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AuthLayout(
        children: [
          // Left panel — branding
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
                  // Decorative glow
                  Positioned(
                    top: -100,
                    left: -100,
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          Color(0x22C9EF9C),
                          Colors.transparent,
                        ]),
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
                        gradient: RadialGradient(colors: [
                          Color(0x15C9EF9C),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo
                        // Logo — matches website / live studio brand
const CamifyLogo(iconSize: 36, fontSize: 20)
    .animate()
    .fadeIn(delay: 100.ms),

                        const Spacer(),

                        // Hero text
                        Text(
                          'A new look.\nEvery time\nyou go live.',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                            height: 1.1,
                          ),
                        ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.05),

                        const SizedBox(height: 20),

                        Text(
                          'Bring your next look to life.\nYour expression. Your movement. Your moment.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ).animate().fadeIn(delay: 300.ms),

                        const SizedBox(height: 48),

                        // Feature chips
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _featureChip(
                                Icons.videocam_rounded, 'Live Video Editing'),
                            _featureChip(Icons.style_rounded, 'Style Transfer'),
                            _featureChip(Icons.face_rounded, 'Avatar Live'),
                            _featureChip(
                                Icons.currency_bitcoin, 'Crypto Payments'),
                          ],
                        ).animate().fadeIn(delay: 400.ms),

                        const Spacer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right panel — form
          Expanded(
            flex: 4,
            child: Container(
              color: AppColors.surface,
              padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width < 700 ? 24 : 56,
                  vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isRegister ? 'Create account' : 'Welcome back',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ).animate().fadeIn(duration: 300.ms),

                        const SizedBox(height: 6),

                        Text(
                          _isRegister
                              ? 'Join the platform and start streaming'
                              : 'Sign in to your account',
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ).animate().fadeIn(delay: 100.ms),

                        const SizedBox(height: 36),

                        // Error message
                        if (auth.error != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.errorDim,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.error.withOpacity(0.3)),
                            ),
                            child: Text(
                              auth.error!,
                              style: const TextStyle(
                                  color: AppColors.error, fontSize: 13),
                            ),
                          ).animate().shake(),

                        // Email
                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.email_outlined, size: 18),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Email required';
                            if (!v.contains('@')) return 'Invalid email';
                            return null;
                          },
                        ).animate().fadeIn(delay: 150.ms),

                        const SizedBox(height: 14),

                        // Username (register only)
                        if (_isRegister) ...[
                          TextFormField(
                            controller: _usernameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline, size: 18),
                            ),
                            validator: (v) {
                              if (_isRegister && (v == null || v.isEmpty)) {
                                return 'Username required';
                              }
                              return null;
                            },
                          ).animate().fadeIn(delay: 200.ms),
                          const SizedBox(height: 14),
                        ],

                        // Password
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon:
                                const Icon(Icons.lock_outline, size: 18),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 18,
                              ),
                              onPressed: () => setState(
                                  () => _showPassword = !_showPassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Password required';
                            if (_isRegister && v.length < 8)
                              return 'Minimum 8 characters';
                            return null;
                          },
                          onFieldSubmitted: (_) => _submit(),
                        ).animate().fadeIn(delay: 200.ms),

                        if (!_isRegister) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.push('/forgot-password'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13),
                              ),
                            ),
                          ).animate().fadeIn(delay: 200.ms),
                          const SizedBox(height: 16),
                        ] else ...[
                          const SizedBox(height: 24),
                        ],

                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: auth.isLoading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      color: AppColors.onAccent,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _isRegister ? 'Create Account' : 'Sign In',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ).animate().fadeIn(delay: 250.ms),

                        const SizedBox(height: 20),

                        // Toggle login/register
                        Center(
                          child: TextButton(
                            onPressed: () => setState(() {
                              _isRegister = !_isRegister;
                            }),
                            child: Text(
                              _isRegister
                                  ? 'Already have an account? Sign in'
                                  : "Don't have an account? Create one",
                              style: const TextStyle(color: AppColors.accent),
                            ),
                          ),
                        ).animate().fadeIn(delay: 300.ms),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
