// lib/services/announcement_provider.dart
//
// Fetches the announcement banner and minimum app version from the backend
// on login and whenever the app resumes. All screens read from this provider.

import 'package:flutter/material.dart';
import 'api_service.dart';

class AnnouncementProvider extends ChangeNotifier {
  bool   _active          = false;
  String _text            = '';
  String _minAppVersion   = '';
  bool   _dismissed       = false;  // user tapped ✕ on the banner this session
  bool   _loaded          = false;

  bool   get active        => _active && !_dismissed && _text.isNotEmpty;
  String get text          => _text;
  String get minAppVersion => _minAppVersion;
  bool   get loaded        => _loaded;

  /// Fetch from GET /api/v1/announcement/.
  /// Safe to call multiple times — will just refresh state.
  Future<void> fetch() async {
    try {
      final data = await ApiService.instance.getAnnouncement();
      _active        = data['active']          == true;
      _text          = (data['text']           as String?) ?? '';
      _minAppVersion = (data['min_app_version'] as String?) ?? '';
      _dismissed     = false;   // reset dismissal on each fresh fetch
      _loaded        = true;
      notifyListeners();
    } catch (_) {
      // Network failure — keep previous state silently.
    }
  }

  /// The user tapped the ✕ button on the banner — hide for this session.
  void dismiss() {
    _dismissed = true;
    notifyListeners();
  }

  /// True if the running build is older than [minAppVersion].
  /// Comparison is semver-style: "1.0.5" < "1.0.6".
  bool isUpdateRequired(String runningVersion) {
    if (_minAppVersion.isEmpty) return false;
    return _compareSemver(runningVersion, _minAppVersion) < 0;
  }

  /// Returns -1, 0, or 1 for a < b, a == b, a > b.
  int _compareSemver(String a, String b) {
    final partsA = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final partsB = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final len = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (int i = 0; i < len; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va < vb) return -1;
      if (va > vb) return  1;
    }
    return 0;
  }
}
