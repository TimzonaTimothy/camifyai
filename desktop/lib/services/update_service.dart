import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// The current version of this build.
/// Bump this string with every release (matching your backend's version).
const String kCurrentVersion = '1.0.11';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String? releaseNotes;
  final bool isMandatory;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.releaseNotes,
    this.isMandatory = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version:      json['version'] as String,
      downloadUrl:  json['download_url'] as String,
      releaseNotes: json['release_notes'] as String?,
      isMandatory:  (json['mandatory'] as bool?) ?? false,
    );
  }
}

class UpdateService extends ChangeNotifier {
  static final UpdateService instance = UpdateService._();
  UpdateService._();

  UpdateInfo? _available;
  bool _checking = false;
  bool _dismissed = false;

  UpdateInfo? get available     => _dismissed ? null : _available;
  bool        get hasUpdate     => !_dismissed && _available != null;
  bool        get isMandatory   => _available?.isMandatory ?? false;

  /// Call once on app start (and optionally on a timer).
  Future<void> checkForUpdate() async {
    if (_checking) return;
    _checking = true;
    try {
      final resp = await http
          .get(Uri.parse('$kBaseUrl/app/latest-version/'))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final info = UpdateInfo.fromJson(data);
        if (_isNewer(info.version, kCurrentVersion)) {
          _available = info;
          _dismissed = false;
          notifyListeners();
        }
      }
    } catch (_) {
      // silently ignore — no internet / server error
    } finally {
      _checking = false;
    }
  }

  void dismiss() {
    _dismissed = true;
    notifyListeners();
  }

  // ── semver-lite comparison ─────────────────────────────────────────────
  bool _isNewer(String remote, String local) {
    try {
      final r = _parts(remote);
      final l = _parts(local);
      for (int i = 0; i < 3; i++) {
        if (r[i] > l[i]) return true;
        if (r[i] < l[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  List<int> _parts(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    // Pad with zeros to ensure exactly 3 elements (major.minor.patch)
    while (parts.length < 3) parts.add(0);
    return parts;
  }
}