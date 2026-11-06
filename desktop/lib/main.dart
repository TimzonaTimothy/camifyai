// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:go_router/go_router.dart';

// import 'theme/app_theme.dart';
// import 'services/auth_provider.dart';
// import 'screens/auth/login_screen.dart';
// import 'screens/auth/forgot_password_screen.dart';
// import 'screens/auth/change_password_screen.dart';
// import 'screens/main_shell.dart';
// import 'screens/dashboard/dashboard_screen.dart';
// import 'screens/playground/playground_screen.dart';
// import 'screens/playground/realtime_stream_screen.dart';
// import 'screens/keys/api_keys_screen.dart';
// import 'screens/billing/billing_screen.dart';
// import 'screens/usage/usage_screen.dart';

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   final authProvider = AuthProvider();
//   await authProvider.init();

//   runApp(
//     ChangeNotifierProvider.value(
//       value: authProvider,
//       child: StreamAIApp(authProvider: authProvider),
//     ),
//   );
// }

// class StreamAIApp extends StatefulWidget {
//   final AuthProvider authProvider;
//   const StreamAIApp({super.key, required this.authProvider});

//   @override
//   State<StreamAIApp> createState() => _StreamAIAppState();
// }

// class _StreamAIAppState extends State<StreamAIApp> {
//   late final GoRouter _router;

//   @override
//   void initState() {
//     super.initState();

//     // ── Create router ONCE — never recreated on rebuild ──────────────────
//     // This prevents the polling-triggered rebuilds from resetting navigation.
//     _router = GoRouter(
//       // Always start on /splash. The redirect below immediately moves the user
//       // to the right screen once initialisation completes.
//       initialLocation: '/splash',
//       refreshListenable: widget.authProvider,
//       redirect: (context, state) {
//         final auth     = widget.authProvider;
//         final loggedIn = auth.isLoggedIn;
//         final loading  = auth.isInitialising;
//         final loc      = state.matchedLocation;

//         // ── Cold-start guard ─────────────────────────────────────────────
//         // While _loadProfile is running (including back-off retries),
//         // keep everyone on /splash so no screen ever renders with _user == null
//         // and no premature redirect to /login happens.
//         if (loading) return loc == '/splash' ? null : '/splash';

//         // ── Stream screen is self-contained — never redirect away from it ─
//         if (loc == '/stream') return null;

//         // ── Post-init routing ────────────────────────────────────────────
//         if (!loggedIn && loc != '/login' && loc != '/forgot-password') return '/login';
//         if (loggedIn  && (loc == '/login' || loc == '/forgot-password' || loc == '/splash')) return '/dashboard';

//         return null;
//       },
//       routes: [
//         // ── Splash / initialising screen ─────────────────────────────────
//         GoRoute(
//           path: '/splash',
//           builder: (_, __) => const _SplashScreen(),
//         ),

//         // ── Auth ─────────────────────────────────────────────────────────
//         GoRoute(
//           path: '/login',
//           builder: (_, __) => const LoginScreen(),
//         ),
//         GoRoute(
//           path: '/forgot-password',
//           builder: (_, __) => const ForgotPasswordScreen(),
//         ),

//         // ── Full-screen stream — outside ShellRoute so no sidebar ─────────
//         GoRoute(
//           path: '/stream',
//           builder: (context, state) {
//             final extra = state.extra as Map<String, dynamic>? ?? {};
//             return RealtimeStreamScreen(
//               model:           extra['model'] as String? ?? 'x2.1',
//               prompt:          extra['prompt'] as String?,
//               faceImageBase64: extra['faceImageBase64'] as String?,
//             );
//           },
//         ),

//         // ── Main app with sidebar ─────────────────────────────────────────
//         ShellRoute(
//           builder: (context, state, child) => MainShell(child: child),
//           routes: [
//             GoRoute(
//               path: '/dashboard',
//               builder: (_, __) => const DashboardScreen(),
//             ),
//             GoRoute(
//               path: '/playground',
//               builder: (_, __) => const PlaygroundScreen(),
//             ),
//             GoRoute(
//               path: '/keys',
//               builder: (_, __) => const ApiKeysScreen(),
//             ),
//             GoRoute(
//               path: '/billing',
//               builder: (_, __) => const BillingScreen(),
//             ),
//             GoRoute(
//               path: '/usage',
//               builder: (_, __) => const UsageScreen(),
//             ),
//             GoRoute(
//               path: '/change-password',
//               builder: (_, __) => const ChangePasswordScreen(),
//             ),
//           ],
//         ),
//       ],
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp.router(
//       title: 'camifyai',
//       debugShowCheckedModeBanner: false,
//       theme: AppTheme.dark,
//       routerConfig: _router,
//     );
//   }
// }

// // ── Splash screen shown during cold-start profile fetch ──────────────────────
// // Displayed whenever isInitialising == true.
// // Shows a retry counter so the user knows the app is working, not frozen.
// class _SplashScreen extends StatelessWidget {
//   const _SplashScreen();

//   @override
//   Widget build(BuildContext context) {
//     final auth = context.watch<AuthProvider>();
//     // Show retry hint only after the first attempt has failed.
//     final retrying = auth.isInitialising;

//     return Scaffold(
//       backgroundColor: AppColors.bg,
//       body: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             // Logo mark
//             Container(
//               width: 56,
//               height: 56,
//               decoration: BoxDecoration(
//                 color: AppColors.accent,
//                 borderRadius: BorderRadius.circular(16),
//               ),
//               child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 32),
//             ),
//             const SizedBox(height: 24),
//             const Text(
//               'camifyai',
//               style: TextStyle(
//                 color: AppColors.textPrimary,
//                 fontSize: 24,
//                 fontWeight: FontWeight.w800,
//                 letterSpacing: -0.5,
//               ),
//             ),
//             const SizedBox(height: 32),
//             const SizedBox(
//               width: 24,
//               height: 24,
//               child: CircularProgressIndicator(
//                 color: AppColors.accent,
//                 strokeWidth: 2.5,
//               ),
//             ),
//             const SizedBox(height: 16),
//             Text(
//               retrying ? 'Connecting to server…' : 'Starting up…',
//               style: const TextStyle(
//                 color: AppColors.textSecondary,
//                 fontSize: 13,
//               ),
//             ),
//             const SizedBox(height: 6),
//             const Text(
//               'Please wait',
//               style: TextStyle(
//                 color: AppColors.textMuted,
//                 fontSize: 11,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }



import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'theme/app_theme.dart';
import 'services/auth_provider.dart';
import 'services/announcement_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/change_password_screen.dart';
import 'screens/main_shell.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/playground/playground_screen.dart';
import 'screens/playground/realtime_stream_screen.dart';
import 'screens/keys/api_keys_screen.dart';
import 'screens/billing/billing_screen.dart';
import 'screens/usage/usage_screen.dart';
import 'screens/watermark_fee_screen.dart';
import 'utils/trusted_roots.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

   // Must run before any HTTPS request — see utils/trusted_roots.dart.
  await installBundledRootCertificates();

  final authProvider         = AuthProvider();
  final announcementProvider = AnnouncementProvider();

  await authProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: announcementProvider),
      ],
      child: StreamAIApp(
        authProvider:         authProvider,
        announcementProvider: announcementProvider,
      ),
    ),
  );
}

class StreamAIApp extends StatefulWidget {
  final AuthProvider         authProvider;
  final AnnouncementProvider announcementProvider;
  const StreamAIApp({
    super.key,
    required this.authProvider,
    required this.announcementProvider,
  });

  @override
  State<StreamAIApp> createState() => _StreamAIAppState();
}

class _StreamAIAppState extends State<StreamAIApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    _router = GoRouter(
      initialLocation: '/splash',
      refreshListenable: widget.authProvider,
      redirect: (context, state) {
        final auth     = widget.authProvider;
        final loggedIn = auth.isLoggedIn;
        final loading  = auth.isInitialising;
        final loc      = state.matchedLocation;

        if (loading) return loc == '/splash' ? null : '/splash';
        if (loc == '/stream') return null;

        if (!loggedIn && loc != '/login' && loc != '/forgot-password') return '/login';
        if (loggedIn && (loc == '/login' || loc == '/forgot-password' || loc == '/splash')) {
          widget.announcementProvider.fetch();
          return '/dashboard';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          builder: (_, __) => const _SplashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/stream',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return RealtimeStreamScreen(
              model:           extra['model']           as String? ?? 'x2.1',
              prompt:          extra['prompt']          as String?,
              faceImageBase64: extra['faceImageBase64'] as String?,
            );
          },
        ),
        GoRoute(
          path: '/watermark-fee',
          builder: (_, __) => const WatermarkFeeScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, __) => const DashboardScreen(),
            ),
            GoRoute(
              path: '/playground',
              builder: (_, __) => const PlaygroundScreen(),
            ),
            GoRoute(
              path: '/keys',
              builder: (_, __) => const ApiKeysScreen(),
            ),
            GoRoute(
              path: '/billing',
              builder: (_, __) => const BillingScreen(),
            ),
            GoRoute(
              path: '/usage',
              builder: (_, __) => const UsageScreen(),
            ),
            GoRoute(
              path: '/change-password',
              builder: (_, __) => const ChangePasswordScreen(),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'camifyai',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}

// ── Splash screen ─────────────────────────────────────────────────────────────
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'camifyai',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'AI Streaming Platform',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: AppColors.accent,
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  auth.isInitialising
                      ? 'Connecting to server…'
                      : 'Starting up…',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (_appVersion.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'v$_appVersion',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}