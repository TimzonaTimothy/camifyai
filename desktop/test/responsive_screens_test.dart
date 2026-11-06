import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:deepfake_software/models/user.dart';
import 'package:deepfake_software/services/auth_provider.dart';
import 'package:deepfake_software/services/announcement_provider.dart';
import 'package:deepfake_software/theme/app_theme.dart';
import 'package:deepfake_software/screens/main_shell.dart';
import 'package:deepfake_software/screens/dashboard/dashboard_screen.dart';
import 'package:deepfake_software/screens/billing/billing_screen.dart';
import 'package:deepfake_software/screens/usage/usage_screen.dart';
import 'package:deepfake_software/screens/keys/api_keys_screen.dart';
import 'package:deepfake_software/screens/playground/playground_screen.dart';
import 'package:deepfake_software/screens/auth/login_screen.dart';
import 'package:deepfake_software/screens/auth/forgot_password_screen.dart';
import 'package:deepfake_software/screens/auth/change_password_screen.dart';
import 'package:deepfake_software/screens/watermark_fee_screen.dart';

class TestAuth extends AuthProvider {
  @override
  UserModel get user => UserModel.fromJson({
        'username': 'Alexandria Montgomery',
        'email': 'alex@example.com',
        'credits': 123456.0
      });
  @override
  double get credits => user.credits;
}

const activity = {
  'endpoint': 'realtime_token',
  'model_used': 'x2.1',
  'credits_used': 40,
  'timestamp': '2026-11-05T12:30:00Z'
};

Future<http.Response> fixture(http.Request request) async {
  final path = request.url.path;
  dynamic data = <String, dynamic>{};
  if (path.endsWith('/keys/') && request.method == 'POST') {
    data = {'key': 'camify_live_example_key_for_layout_testing_only'};
  } else if (path.contains('/dashboard/')) {
    data = {
      'total_credits_used': 2400,
      'plan': 'creator',
      'daily_usage': [
        {'date': '2026-11-04', 'credits': 120},
        {'date': '2026-11-05', 'credits': 240}
      ],
      'recent_activity': [activity],
      'activity_total_pages': 1
    };
  } else if (path.contains('/usage/')) {
    data = [
      activity,
      {...activity, 'model_used': 'heartbeat'}
    ];
  } else if (path.endsWith('/keys/')) {
    data = [
      {
        'id': 1,
        'name': 'Production streaming application key',
        'prefix': 'camify_live_',
        'created_at': '2026-11-01T12:00:00Z'
      }
    ];
  } else if (path.contains('/packs/')) {
    data = [
      for (var i = 0; i < 4; i++)
        {
          'id': 'pack$i',
          'label': i == 0 ? 'Starter' : 'Creator',
          'credits': 1200 * (i + 1),
          'price_usd': '12.00',
          'popular': i == 1,
          'description': 'Time for your next live session'
        }
    ];
  } else if (path.contains('/currencies/')) {
    data = {
      'crypto': [
        {'id': 'usdttrc20', 'label': 'USDT (TRC20)'}
      ],
      'fiat': []
    };
  } else if (path.endsWith('/payments/')) {
    data = {
      'count': 1,
      'total_pages': 1,
      'results': [
        {
          'id': 1,
          'pack_label': 'Creator streaming time',
          'amount_usd': '12.00',
          'credits_to_add': 1200,
          'currency': 'usdttrc20',
          'gateway': 'crypto',
          'status': 'waiting',
          'created_at': '2026-11-04T12:00:00Z'
        }
      ]
    };
  } else if (path.contains('/watermark-fee/status/')) {
    data = {'paid': false, 'watermark_fee_paid': false, 'fee_usd': '100.00'};
  } else if (path.contains('/watermark-fee/methods/')) {
    data = [
      {
        'id': 1,
        'name': 'USDT (TRC20)',
        'address': 'TAbc123456789012345678901234567890',
        'icon_emoji': '◈'
      }
    ];
  } else if (path.contains('/latest-version/')) {
    data = {'version': '1.0.0', 'download_url': ''};
  }
  return http.Response(jsonEncode(data), 200,
      headers: {'content-type': 'application/json'});
}

void main() {
  setUpAll(() async {
    // Use SDK-supplied fonts instead of Ahem so overflow checks exercise real glyphs.
    var directory = File(Platform.resolvedExecutable).parent;
    while (!Directory('${directory.path}/bin/cache/artifacts/material_fonts')
        .existsSync()) {
      final parent = directory.parent;
      if (parent.path == directory.path)
        throw StateError('Flutter SDK font directory not found');
      directory = parent;
    }
    final fontDirectory =
        '${directory.path}/bin/cache/artifacts/material_fonts';
    for (final family in ['Inter', 'Roboto', 'JetBrains Mono', 'monospace']) {
      final loader = FontLoader(family);
      loader.addFont(File('$fontDirectory/Roboto-Regular.ttf')
          .readAsBytes()
          .then(ByteData.sublistView));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(File('$fontDirectory/MaterialIcons-Regular.otf')
        .readAsBytes()
        .then(ByteData.sublistView));
    await icons.load();
  });
  final screens = <String, Widget Function()>{
    'dashboard': () => const DashboardScreen(),
    'studio': () => const PlaygroundScreen(),
    'billing': () => const BillingScreen(),
    'usage': () => const UsageScreen(),
    'keys': () => const ApiKeysScreen(),
    'security': () => const ChangePasswordScreen(),
    'watermark': () => const WatermarkFeeScreen(),
    'login': () => const LoginScreen(),
    'reset-password': () => const ForgotPasswordScreen(),
  };
  final sizes = [
    const Size(360, 780),
    const Size(768, 900),
    const Size(1440, 1000),
    const Size(1000, 480),
    const Size(360, 844)
  ];

  for (final entry in screens.entries) {
    for (final size in sizes) {
      testWidgets(
          '${entry.key} fits ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await http.runWithClient(() async {
          final previousErrorHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            debugPrint(details.toString());
            previousErrorHandler?.call(details);
          };
          addTearDown(() => FlutterError.onError = previousErrorHandler);
          final hasShell =
              !['login', 'reset-password', 'watermark'].contains(entry.key);
          final path = entry.key == 'studio' ? '/playground' : '/${entry.key}';
          final router = GoRouter(initialLocation: path, routes: [
            GoRoute(
                path: path,
                builder: (_, __) =>
                    hasShell ? MainShell(child: entry.value()) : entry.value())
          ]);
          final auth = TestAuth();
          final announcements = AnnouncementProvider();
          await tester.pumpWidget(MultiProvider(
              providers: [
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider.value(value: announcements),
              ],
              child: RepaintBoundary(
                  key: const ValueKey('app-preview'),
                  child: MaterialApp.router(
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.dark,
                    routerConfig: router,
                    builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(
                                size.height == 844 ? 1.35 : 1)),
                        child: child!),
                  ))));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull,
              reason: '${entry.key} initial layout');
          if (const bool.fromEnvironment('CAPTURE_UI_PREVIEWS') &&
              size.width == 1440 &&
              ['dashboard', 'billing', 'studio', 'login'].contains(entry.key)) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('app-preview')));
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('/tmp/camify-app-${entry.key}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          if (size.height == 844 || size.height == 480) {
            if (entry.key == 'login') {
              final toggle = find.text("Don't have an account? Create one");
              await tester.ensureVisible(toggle);
              await tester.tap(toggle);
              await tester.pump(const Duration(milliseconds: 500));
              expect(find.byType(TextFormField), findsNWidgets(3));
            } else if (entry.key == 'reset-password') {
              await tester.enterText(
                  find.byType(TextFormField).first, 'alex@example.com');
              final send = find.text('Send Reset Code');
              await tester.ensureVisible(send);
              await tester.tap(send);
              for (var i = 0; i < 8; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(find.text('Verify & reset'), findsOneWidget);
              final fields = find.byType(TextFormField);
              await tester.enterText(fields.at(0), '123456');
              await tester.enterText(fields.at(1), 'NewStrongPassword123!');
              await tester.enterText(fields.at(2), 'NewStrongPassword123!');
              final reset = find.text('Reset Password');
              await tester.ensureVisible(reset);
              await tester.tap(reset);
              for (var i = 0; i < 8; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(find.text('Password reset!'), findsOneWidget);
            } else if (entry.key == 'security') {
              final fields = find.byType(TextFormField);
              await tester.enterText(fields.at(0), 'OldStrongPassword123!');
              await tester.enterText(fields.at(1), 'NewStrongPassword123!');
              await tester.enterText(fields.at(2), 'NewStrongPassword123!');
              final update = find.text('Update Password');
              await tester.ensureVisible(update);
              await tester.tap(update);
              for (var i = 0; i < 8; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(find.text('Password updated!'), findsOneWidget);
            } else if (entry.key == 'keys') {
              final create = find.text('New Key');
              await tester.ensureVisible(create);
              await tester.tap(create);
              await tester.pumpAndSettle();
              expect(find.text('Create API Key'), findsOneWidget);
              await tester.enterText(find.byType(TextField), 'My studio key');
              await tester.tap(find.text('Create'));
              for (var i = 0; i < 8; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(find.text('Key created — copy it now!'), findsOneWidget);
            } else if (entry.key == 'billing') {
              final proof = find.text('Upload proof');
              await tester.ensureVisible(proof);
              await tester.tap(proof);
              await tester.pumpAndSettle();
              expect(find.text('Submit Payment Proof'), findsOneWidget);
              final submit = find.text('Submit Proof');
              await tester.ensureVisible(submit);
              await tester.tap(submit);
              await tester.pump(const Duration(milliseconds: 400));
              expect(tester.takeException(), isNull,
                  reason: 'payment proof dialog');
              Navigator.of(tester.element(find.byType(Dialog))).pop();
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull,
                reason: '${entry.key} secondary state');
          }
          // Exercise content beyond the initial viewport as well as the header.
          final scrollables = find.byType(Scrollable);
          if (scrollables.evaluate().isNotEmpty) {
            await tester.drag(scrollables.first, const Offset(0, -700));
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull,
                reason: '${entry.key} scrolled layout');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
          auth.dispose();
          announcements.dispose();
        }, () => MockClient(fixture));
      });
    }
  }

  testWidgets('compact navigation opens the drawer and navigates to the studio',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      final router = GoRouter(initialLocation: '/dashboard', routes: [
        ShellRoute(
          builder: (_, __, child) => MainShell(child: child),
          routes: [
            GoRoute(
                path: '/dashboard',
                builder: (_, __) => const DashboardScreen()),
            GoRoute(
                path: '/playground',
                builder: (_, __) => const PlaygroundScreen()),
          ],
        )
      ]);
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => TestAuth()),
            ChangeNotifierProvider(create: (_) => AnnouncementProvider()),
          ],
          child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark,
              routerConfig: router)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      final studioNavigation = find.descendant(
          of: find.byType(Drawer), matching: find.text('Live studio'));
      expect(studioNavigation, findsOneWidget);
      await tester.tap(studioNavigation);
      await tester.pumpAndSettle();
      expect(find.text('Enter live studio'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }, () => MockClient(fixture));
  });
  for (final resume in [false, true]) {
    testWidgets(
        'NOWPayments ${resume ? 'resumes a pending invoice' : 'opens checkout and confirms automatically'}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final launches = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'launch')
          launches.add(call.arguments['url'] as String);
        return true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      var created = false;
      const checkout = 'https://nowpayments.io/payment/?iid=9009';
      await http.runWithClient(() async {
        final router = GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const BillingScreen())
        ]);
        await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>(
            create: (_) => TestAuth(),
            child: MaterialApp.router(
                theme: AppTheme.dark,
                routerConfig: router,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(1.35)),
                    child: child!))));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (resume) {
          expect(launches, isEmpty);
        } else {
          final buy = find.widgetWithText(ElevatedButton, r'$12.00').first;
          await tester.ensureVisible(buy);
          await tester.tap(buy);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(created, isTrue);
          expect(launches, [checkout]);
        }
        expect(find.text('Upload Proof'), findsNothing);
        expect(find.text('Submit Payment Proof'), findsNothing);
        final reopen = find.text('Reopen checkout');
        await tester.ensureVisible(reopen);
        await tester.tap(reopen);
        await tester.pump(const Duration(milliseconds: 200));
        expect(launches.last, checkout);
        expect(tester.takeException(), isNull);
        if (!resume) {
          await tester.pump(const Duration(seconds: 11));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('Reopen checkout'), findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      },
          () => MockClient((request) async {
                dynamic data;
                if (request.url.path.endsWith('/currencies/')) {
                  data = {
                    'crypto': [
                      {
                        'id': 'usdtbsc',
                        'label': 'USDT · BNB Smart Chain (BEP20)'
                      }
                    ],
                    'fiat': [],
                    'fee_paid_by_user': true
                  };
                } else if (request.url.path.endsWith('/payments/create/')) {
                  expect(jsonDecode(request.body)['currency'], 'usdtbsc');
                  created = true;
                  data = {
                    'payment_id': 9009,
                    'payment_url': checkout,
                    'payment_provider': 'nowpayments'
                  };
                } else if (request.url.path.endsWith('/payments/')) {
                  data = {
                    'count': resume ? 1 : 0,
                    'total_pages': 1,
                    'results': resume
                        ? [
                            {
                              'id': 9009,
                              'pack_label': 'Creator',
                              'amount_usd': '12.00',
                              'credits_to_add': 1200,
                              'currency': 'usdtbsc',
                              'gateway': 'crypto',
                              'status': 'waiting',
                              'payment_provider': 'nowpayments',
                              'payment_url': checkout,
                              'created_at': '2026-11-05',
                            }
                          ]
                        : []
                  };
                } else if (request.url.path.endsWith('/9009/status/')) {
                  data = {
                    'status': resume ? 'confirming' : 'confirmed',
                    'credits': 1200,
                    'credits_balance': 124656
                  };
                } else {
                  return fixture(request);
                }
                return http.Response(jsonEncode(data), 200,
                    headers: {'content-type': 'application/json'});
              }));
    });
  }
}
