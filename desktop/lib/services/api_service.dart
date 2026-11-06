import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Change this to your real Django server URL ──
// const String kBaseUrl = 'https://camifyai.com/api/v1';
const String kBaseUrl = 'http://10.112.60.138:8000/api/v1';

/// Safely decode a JSON body — returns an empty map if body is null/empty/invalid.
Map<String, dynamic> _safeJsonDecode(String? body) {
  if (body == null || body.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'detail': decoded.toString()};
  } catch (e) {
    return {
      'error':
          'Unexpected server response (${body.substring(0, body.length.clamp(0, 80))}...)'
    };
  }
}

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  String? _accessToken;
  String? _refreshToken;

  // ── Token Management ──────────────────────────────────────────────────────

  Future<void> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
  }

  Future<void> saveTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  bool get isLoggedIn => _accessToken != null;
  String? get accessToken => _accessToken;

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<bool> _tryRefresh() async {
    if (_refreshToken == null) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('$kBaseUrl/auth/refresh/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': _refreshToken}),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        await saveTokens(data['access'], _refreshToken!);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$kBaseUrl$path');
    http.Response resp;

    Future<http.Response> makeRequest() async {
      const timeout = Duration(seconds: 20);
      switch (method) {
        case 'GET':
          return http.get(uri, headers: _authHeaders).timeout(timeout);
        case 'POST':
          return http
              .post(uri,
                  headers: _authHeaders,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(timeout);
        case 'PATCH':
          return http
              .patch(uri,
                  headers: _authHeaders,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(timeout);
        case 'DELETE':
          return http.delete(uri, headers: _authHeaders).timeout(timeout);
        default:
          throw Exception('Unknown method: $method');
      }
    }

    resp = await makeRequest();

    if (resp.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        resp = await makeRequest();
      } else {
        // ✅ FIX: refresh token is expired/invalid — clear tokens so
        // isLoggedIn becomes false and AuthProvider can trigger logout
        await clearTokens();
      }
    }

    return resp;
  }

  // ── AUTH ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String email, String password) async {
    final resp = await http
        .post(
          Uri.parse('$kBaseUrl/auth/login/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));

    final data = _safeJsonDecode(resp.body);
    if (resp.statusCode == 200) {
      await saveTokens(data['access'] as String, data['refresh'] as String);
    } else if (data.isEmpty ||
        (!data.containsKey('error') && !data.containsKey('detail'))) {
      // Server returned non-200 with no parseable body (e.g. bare 401)
      data['error'] =
          'Login failed (server returned ${resp.statusCode}). Please try again.';
    }
    return {'statusCode': resp.statusCode, ...data};
  }

  Future<Map<String, dynamic>> register(
      String email, String username, String password) async {
    final resp = await http
        .post(
          Uri.parse('$kBaseUrl/auth/register/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'username': username,
            'password': password,
            'password2': password,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = _safeJsonDecode(resp.body);
    if (resp.statusCode == 201) {
      await saveTokens(data['access'] as String, data['refresh'] as String);
    } else if (data.isEmpty ||
        (!data.containsKey('error') &&
            !data.containsKey('detail') &&
            !data.containsKey('email') &&
            !data.containsKey('password'))) {
      data['error'] =
          'Registration failed (server returned ${resp.statusCode}). Please try again.';
    }
    return {'statusCode': resp.statusCode, ...data};
  }

  Future<void> logout() async => clearTokens();

  // ── Desktop — Forgot Password ─────────────────────────────────────────────
  // Sends a reset link via streamai51@gmail.com (no auth required).

  Future<Map<String, dynamic>> desktopForgotPassword(String email) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$kBaseUrl/auth/desktop/forgot-password/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return {'ok': true, 'detail': data['detail']};
      }
      return {'ok': false, 'error': data['error'] ?? 'Request failed.'};
    } catch (_) {
      return {'ok': false, 'error': 'Connection error. Check your internet.'};
    }
  }

  // ── Desktop — Verify OTP & Reset Password ─────────────────────────────────
  // Verifies the 6-digit OTP code and sets a new password (no auth required).

  Future<Map<String, dynamic>> desktopVerifyOTP({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$kBaseUrl/auth/desktop/verify-otp/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'code': code,
              'new_password': newPassword,
              'confirm_password': confirmPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return {'ok': true, 'detail': data['detail']};
      }
      return {'ok': false, 'error': data['error'] ?? 'Verification failed.'};
    } catch (_) {
      return {'ok': false, 'error': 'Connection error. Check your internet.'};
    }
  }

  // ── Desktop — Change Password ─────────────────────────────────────────────
  // Requires a valid access token. Confirmation email sent via Gmail.

  Future<Map<String, dynamic>> desktopChangePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      final resp = await _request(
        'POST',
        '/auth/desktop/change-password/',
        body: {
          'current_password': currentPassword,
          'new_password': newPassword,
          'confirm_password': confirmPassword,
        },
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return {'ok': true, 'detail': data['detail']};
      }
      return {
        'ok': false,
        'error': data['error'] ?? 'Failed to change password.'
      };
    } catch (_) {
      return {'ok': false, 'error': 'Connection error.'};
    }
  }

  // ── PROFILE ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMe() async {
    final resp = await _request('GET', '/auth/me/');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDashboard({
    int days = 30,
    int activityPage = 1,
    int activityPageSize = 8,
  }) async {
    final resp = await _request('GET',
        '/auth/dashboard/?days=$days&activity_page=$activityPage&activity_page_size=$activityPageSize');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    data['statusCode'] = resp.statusCode;
    return data;
  }

  Future<Map<String, dynamic>> poll() async {
    final resp = await _request('GET', '/auth/poll/');
    // ✅ FIX: check status before parsing so a 401 doesn't crash the poller
    if (resp.statusCode != 200)
      throw Exception('Poll failed: ${resp.statusCode}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getUsageHistory() async {
    final resp = await _request('GET', '/auth/usage/');
    return jsonDecode(resp.body) as List<dynamic>;
  }

  // ── API KEYS ──────────────────────────────────────────────────────────────

  Future<List<dynamic>> getApiKeys() async {
    final resp = await _request('GET', '/keys/');
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createApiKey(String name) async {
    final resp = await _request('POST', '/keys/', body: {'name': name});
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<bool> revokeApiKey(int keyId) async {
    final resp = await _request('DELETE', '/keys/$keyId/');
    return resp.statusCode == 200;
  }

  Future<bool> renameApiKey(int keyId, String name) async {
    final resp =
        await _request('PATCH', '/keys/$keyId/rename/', body: {'name': name});
    return resp.statusCode == 200;
  }

  // ── STREAMING ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getRealtimeToken(
    String model, {
    String? faceImageBase64,
    String? prompt,
  }) async {
    final body = <String, dynamic>{'model': model};
    if (faceImageBase64 != null) body['face_image'] = faceImageBase64;
    if (prompt != null && prompt.isNotEmpty) body['prompt'] = prompt;
    final resp = await _request('POST', '/play/token/', body: body);
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>
    };
  }

  Future<Map<String, dynamic>> streamHeartbeat() async {
    final resp = await _request('POST', '/play/heartbeat/');
    return {
      ...jsonDecode(resp.body) as Map<String, dynamic>,
      'statusCode': resp.statusCode
    };
  }

  Future<Map<String, dynamic>> refreshRealtimeToken() async {
    final resp = await _request('POST', '/play/token/refresh/');
    return {
      ...jsonDecode(resp.body) as Map<String, dynamic>,
      'statusCode': resp.statusCode
    };
  }

  Future<Map<String, dynamic>> generateVideo({
    required String prompt,
    String model = 'lucy-pro-t2v',
    String resolution = '720p',
  }) async {
    final resp = await _request('POST', '/play/generate/video/', body: {
      'prompt': prompt,
      'model': model,
      'resolution': resolution,
    });
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>
    };
  }

  Future<Map<String, dynamic>> generateImage({
    required String prompt,
    String model = 'lucy-image',
  }) async {
    final resp = await _request('POST', '/play/generate/image/', body: {
      'prompt': prompt,
      'model': model,
    });
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>
    };
  }

  // ── PAYMENTS — SHARED ─────────────────────────────────────────────────────

  Future<List<dynamic>> getCreditPacks() async {
    final resp = await http
        .get(Uri.parse('$kBaseUrl/auth/packs/'))
        .timeout(const Duration(seconds: 20));
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getPaymentHistory(
      {int page = 1, int pageSize = 10}) async {
    final resp =
        await _request('GET', '/payments/?page=$page&page_size=$pageSize');
    final data = jsonDecode(resp.body);
    if (data is Map<String, dynamic>) return data;
    return {
      'results': data,
      'count': (data as List).length,
      'total_pages': 1,
      'page': 1,
      'page_size': pageSize
    };
  }

  Future<Map<String, dynamic>> getPaymentStatus(int paymentId) async {
    final resp = await _request('GET', '/auth/$paymentId/status/');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // ── PAYMENTS — CRYPTO (NOWPayments) ──────────────────────────────────────

  /// Creates a NOWPayments crypto invoice.
  /// [currency]: an enabled USDT network from the backend currency endpoint.
  Future<Map<String, dynamic>> createCryptoPayment({
    required String packId,
    required String currency,
  }) async {
    final resp = await _request('POST', '/auth/payments/create/', body: {
      'pack_id': packId,
      'currency': currency,
    });
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>
    };
  }

  // ── PAYMENTS — FLUTTERWAVE (Card / Bank / Mobile Money) ───────────────────

  /// Creates a Flutterwave payment link.
  /// [currency]: NGN | GHS | KES | ZAR | UGX | TZS | USD | EUR | GBP
  Future<Map<String, dynamic>> createFlutterwavePayment({
    required String packId,
    required String currency,
  }) async {
    final resp =
        await _request('POST', '/auth/payments/flutterwave/initiate/', body: {
      'pack_id': packId,
      'currency': currency,
    });
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>
    };
  }

  /// Verifies a Flutterwave payment after user returns from payment page.
  /// [txRef]: the tx_ref returned by createFlutterwavePayment
  /// [transactionId]: optional — Flutterwave appends this to redirect URL as ?transaction_id=
  Future<Map<String, dynamic>> verifyFlutterwavePayment({
    required String txRef,
    String? transactionId,
  }) async {
    final query = transactionId != null ? '?transaction_id=$transactionId' : '';
    final resp = await _request(
        'GET', '/auth/payments/flutterwave/verify/$txRef/$query');
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>
    };
  }

  // ── LEGACY ALIAS (keeps old billing screen code working) ─────────────────
  Future<Map<String, dynamic>> createPayment({
    required String packId,
    required String currency,
  }) =>
      createCryptoPayment(packId: packId, currency: currency);

  // ── WALLET ADDRESSES ──────────────────────────────────────────────────────
  /// Returns the crypto wallet addresses from the server.
  /// Map key = currency id (e.g. "usdttrc20"), value = { address, label, network }
  Future<Map<String, dynamic>> getWalletAddresses() async {
    final resp = await _request('GET', '/auth/payments/wallets/');
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return {};
  }

  /// Returns {"crypto": [...], "fiat": [...]} — both lists come from the DB.
  Future<Map<String, dynamic>> getCurrencies() async {
    final resp = await _request('GET', '/auth/payments/currencies/');
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return {'crypto': [], 'fiat': []};
  }

  // ── PAYMENT PROOF ─────────────────────────────────────────────────────────
  /// Uploads payment proof (screenshot/receipt) for a pending crypto payment.
  Future<Map<String, dynamic>> submitPaymentProof({
    required int paymentId,
    required File imageFile,
    String? txHash,
    String? notes,
  }) async {
    final uri = Uri.parse('$kBaseUrl/auth/payments/$paymentId/proof/');

    Future<http.Response> doSend() async {
      final req = http.MultipartRequest('POST', uri);
      if (_accessToken != null) {
        req.headers['Authorization'] = 'Bearer $_accessToken';
      }
      req.files.add(
          await http.MultipartFile.fromPath('proof_image', imageFile.path));
      if (txHash != null && txHash.isNotEmpty) req.fields['tx_hash'] = txHash;
      if (notes != null && notes.isNotEmpty) req.fields['notes'] = notes;
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    }

    Map<String, dynamic> safeParseBody(http.Response resp) {
      final body = resp.body.trim();
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'detail': decoded.toString()};
      } catch (_) {
        final hint = body.isNotEmpty
            ? 'Server error (${resp.statusCode}): ${body.substring(0, body.length.clamp(0, 120))}'
            : 'Server returned status ${resp.statusCode} with no body.';
        return {'error': hint};
      }
    }

    try {
      var resp = await doSend();

      // Token expired — refresh and retry once
      if (resp.statusCode == 401 && _refreshToken != null) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          resp = await doSend();
        } else {
          // ✅ FIX: consistent with _request — clear tokens on failed refresh
          await clearTokens();
        }
      }

      return {'statusCode': resp.statusCode, ...safeParseBody(resp)};
    } catch (e) {
      return {'statusCode': 0, 'error': e.toString()};
    }
  }

  // ── ANNOUNCEMENT + APP VERSION GATE ──────────────────────────────────────

  /// GET /api/v1/announcement/
  /// Returns:
  ///   { "active": bool, "text": String, "min_app_version": String }
  Future<Map<String, dynamic>> getAnnouncement() async {
    final resp = await _request('GET', '/auth/announcement/');
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return {'active': false, 'text': '', 'min_app_version': ''};
  }

  // ── WATERMARK FEE ─────────────────────────────────────────────────────────

  /// GET /api/v1/watermark-fee/status/
  /// Returns:
  ///   { "paid": bool, "fee_usd": "100.00",
  ///     "pending_payment": bool, "payment_id": int? }
  Future<Map<String, dynamic>> getWatermarkFeeStatus() async {
    final resp = await _request('GET', '/auth/watermark-fee/status/');
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return {
      'paid': false,
      'fee_usd': '100.00',
      'pending_payment': false,
      'payment_id': null
    };
  }

  /// POST /api/v1/watermark-fee/submit/  (multipart)
  /// Fields: proof_image (required), tx_hash, currency, notes (all optional)
  /// GET /api/v1/watermark-fee/methods/
  Future<List<dynamic>> getWatermarkPaymentMethods() async {
    final resp = await _request('GET', '/auth/watermark-fee/methods/');
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as List<dynamic>;
    }
    return [];
  }

  /// POST /api/v1/watermark-fee/submit/
  Future<Map<String, dynamic>> submitWatermarkFeeProof({
    required File imageFile,
    String? methodId,
    String? txHash,
    String? notes,
  }) async {
    final uri = Uri.parse('$kBaseUrl/auth/watermark-fee/submit/');

    Future<http.Response> doSend() async {
      final req = http.MultipartRequest('POST', uri);
      if (_accessToken != null) {
        req.headers['Authorization'] = 'Bearer $_accessToken';
      }
      req.files.add(
          await http.MultipartFile.fromPath('proof_image', imageFile.path));
      if (methodId != null && methodId.isNotEmpty)
        req.fields['method_id'] = methodId;
      if (txHash != null && txHash.isNotEmpty) req.fields['tx_hash'] = txHash;
      if (notes != null && notes.isNotEmpty) req.fields['notes'] = notes;
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    }

    Map<String, dynamic> parse(http.Response resp) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'detail': decoded.toString()};
      } catch (_) {
        return {'error': 'Server error (${resp.statusCode})'};
      }
    }

    try {
      var resp = await doSend();
      if (resp.statusCode == 401 && _refreshToken != null) {
        if (await _tryRefresh())
          resp = await doSend();
        else
          await clearTokens();
      }
      return {'statusCode': resp.statusCode, ...parse(resp)};
    } catch (e) {
      return {'statusCode': 0, 'error': e.toString()};
    }
  }
}
