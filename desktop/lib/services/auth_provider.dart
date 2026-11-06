import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/user.dart';
import 'api_service.dart';

class AuthProvider extends ChangeNotifier with WidgetsBindingObserver {
  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  // Exposed so the app shell can show a "retrying…" indicator on startup.
  bool _isInitialising = false;

  Timer? _pollTimer;
  Timer? _retryTimer;

  // How many times we've retried _loadProfile on this cold-start.
  int _profileRetryCount = 0;
  static const int _maxProfileRetries = 4;
  // Back-off delays in seconds: 2s → 4s → 8s → 16s
  static const List<int> _retryDelays = [2, 4, 8, 16];

  UserModel? get user           => _user;
  bool get isLoading            => _isLoading;
  bool get isLoggedIn           => _user != null;
  bool get isInitialising       => _isInitialising;
  String? get error             => _error;
  double get credits            => _user?.credits ?? 0.0;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    await ApiService.instance.loadTokens();

    if (ApiService.instance.isLoggedIn) {
      _isInitialising = true;
      notifyListeners();
      await _loadProfile();
      // _loadProfile sets _isInitialising = false once it either
      // succeeds, exhausts retries, or detects invalid tokens.
    }
  }

  // ── Lifecycle — stop polling when app minimised ───────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // If we came back online after a failed cold-start, try again once.
      if (!isLoggedIn && ApiService.instance.isLoggedIn) {
        _profileRetryCount = 0;
        _isInitialising = true;
        notifyListeners();
        _loadProfile();
      } else if (isLoggedIn) {
        _startPolling();
      }
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.hidden) {
      _stopPolling();
      _retryTimer?.cancel();
    }
  }

  // ── Auth Actions ──────────────────────────────────────────────────────────

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.instance.login(email, password);
      if (data['statusCode'] == 200) {
        _user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
        _profileRetryCount = 0;
        _startPolling();
        return true;
      } else {
        _error = data['error'] as String? ?? 'Login failed.';
        return false;
      }
    } on SocketException catch (e) {
      debugPrint('[AuthProvider] login SocketException: $e');
      _error = 'No internet connection. Please check your network.';
      return false;
    } on HandshakeException catch (e) {
      debugPrint('[AuthProvider] login HandshakeException: $e');
      _error = 'Secure connection failed. Try again or contact support.';
      return false;
    } on TimeoutException catch (e) {
      debugPrint('[AuthProvider] login TimeoutException: $e');
      _error = 'Request timed out. Server may be slow — try again.';
      return false;
    } catch (e) {
      debugPrint('[AuthProvider] login error (${e.runtimeType}): $e');
      _error = 'Connection error: ${e.toString().replaceAll('Exception: ', '')}';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register(String email, String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.instance.register(email, username, password);
      if (data['statusCode'] == 201) {
        _user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
        _profileRetryCount = 0;
        _startPolling();
        return true;
      } else {
        if (data['email'] != null) {
          _error = (data['email'] as List).first.toString();
        } else if (data['password'] != null) {
          _error = (data['password'] as List).first.toString();
        } else {
          _error = data['error'] as String? ?? 'Registration failed.';
        }
        return false;
      }
    } on SocketException catch (e) {
      debugPrint('[AuthProvider] register SocketException: $e');
      _error = 'No internet connection. Please check your network.';
      return false;
    } on HandshakeException catch (e) {
      debugPrint('[AuthProvider] register HandshakeException: $e');
      _error = 'Secure connection failed. Try again or contact support.';
      return false;
    } on TimeoutException catch (e) {
      debugPrint('[AuthProvider] register TimeoutException: $e');
      _error = 'Request timed out. Server may be slow — try again.';
      return false;
    } catch (e) {
      debugPrint('[AuthProvider] register error (${e.runtimeType}): $e');
      _error = 'Connection error: ${e.toString().replaceAll('Exception: ', '')}';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _stopPolling();
    _retryTimer?.cancel();
    _profileRetryCount = 0;
    _isInitialising = false;
    await ApiService.instance.logout();
    _user = null;
    notifyListeners();
  }

  // ── Profile loading with retry + graceful fallback ────────────────────────
  //
  // Three distinct outcomes are handled:
  //
  //  A. SUCCESS — getMe() returns 200 with valid JSON.
  //     → Parse user, start polling, done.
  //
  //  B. AUTH FAILURE — tokens are invalid/expired AND refresh also failed.
  //     ApiService.clearTokens() was already called inside _request(), so
  //     ApiService.isLoggedIn is now false.
  //     → Log out cleanly; GoRouter sends user to /login with no blank screen.
  //
  //  C. NETWORK / SERVER ERROR — SocketException, timeout, 500, bad JSON, etc.
  //     The tokens themselves are still valid; this is a temporary failure.
  //     → Retry up to _maxProfileRetries times with exponential back-off.
  //     → After all retries exhausted, log out and send to /login so the user
  //        can try again manually rather than staring at a blank screen.

  Future<void> _loadProfile() async {
    // Guard: if tokens were invalidated before we even try, go straight to logout.
    if (!ApiService.instance.isLoggedIn) {
      await _handleUnauthenticated();
      return;
    }

    try {
      final data = await ApiService.instance.getMe();

      // getMe() returns the raw decoded body regardless of status code.
      // A failed refresh would have already called clearTokens() inside
      // _request(), so ApiService.isLoggedIn will be false in that case.
      if (!ApiService.instance.isLoggedIn) {
        // Tokens were cleared mid-request (refresh token had expired).
        await _handleUnauthenticated();
        return;
      }

      // Happy path — parse and store the user.
      _user = UserModel.fromJson(data);
      _profileRetryCount = 0;
      _isInitialising = false;
      _error = null;
      notifyListeners();
      _startPolling();

    } on SocketException {
      // Pure network failure — server unreachable, no wifi, DNS failure, etc.
      await _scheduleProfileRetry(reason: 'network');

    } on HandshakeException {
      // TLS/SSL error — treated the same as network failure.
      await _scheduleProfileRetry(reason: 'network');

    } on TimeoutException {
      await _scheduleProfileRetry(reason: 'timeout');

    } catch (e) {
      // Could be a FormatException from jsonDecode, a cast error in fromJson,
      // an unexpected server response, or anything else.
      //
      // Distinguish: if tokens are gone it's an auth failure;
      // otherwise it's a transient/parse error and we retry.
      if (!ApiService.instance.isLoggedIn) {
        await _handleUnauthenticated();
      } else {
        await _scheduleProfileRetry(reason: 'parse/server');
      }
    }
  }

  // Called when we know the session is dead. Clears state and redirects.
  Future<void> _handleUnauthenticated() async {
    _isInitialising = false;
    await logout(); // clears tokens, sets _user = null, notifyListeners()
    // GoRouter's redirect will fire because isLoggedIn is now false and
    // ApiService tokens are also gone → sends to /login automatically.
  }

  // Schedules the next retry attempt with exponential back-off.
  // If we've exhausted all retries, falls back to logout so the user
  // always lands on /login instead of a blank screen.
  Future<void> _scheduleProfileRetry({required String reason}) async {
    if (_profileRetryCount >= _maxProfileRetries) {
      // We've tried enough. The server or network may be down.
      // Log out cleanly — user will see /login and can try again.
      debugPrint('[AuthProvider] _loadProfile failed ($reason) after '
          '$_maxProfileRetries retries — clearing session.');
      _isInitialising = false;
      await logout();
      return;
    }

    final delay = _retryDelays[_profileRetryCount.clamp(0, _retryDelays.length - 1)];
    _profileRetryCount++;

    debugPrint('[AuthProvider] _loadProfile failed ($reason) — '
        'retry $_profileRetryCount/$_maxProfileRetries in ${delay}s');

    // Keep _isInitialising = true so the UI stays on the loading screen
    // (not a blank screen or a premature redirect to /login).
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delay), _loadProfile);
  }

  // ── Polling (every 15s) ───────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!isLoggedIn) return;
      try {
        final data = await ApiService.instance.poll();
        final newCredits = (data['credits'] ?? 0).toDouble();
        if (_user != null && newCredits != _user!.credits) {
          _user = _user!.copyWith(credits: newCredits);
          notifyListeners();
        }
      } catch (_) {
        // If ApiService cleared tokens because the refresh token expired,
        // log out cleanly so GoRouter redirects to /login.
        if (!ApiService.instance.isLoggedIn) {
          await logout();
        }
        // Otherwise it's a transient network blip — polling will retry in 15s.
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void updateCredits(double newCredits) {
    if (_user != null) {
      _user = _user!.copyWith(credits: newCredits);
      notifyListeners();
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _retryTimer?.cancel();
    super.dispose();
  }
}