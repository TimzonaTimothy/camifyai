import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Adds the bundled Mozilla root certificates (assets/certs/cacert.pem) to
/// Dart's default TLS trust store.
///
/// Why: on Windows, Dart only trusts root certificates that are ALREADY in
/// the machine's "Trusted Root Certification Authorities" store. Windows
/// ships with a small set and downloads the rest on demand — but only when
/// a Windows component asks, never for a Flutter app. streamaicam.com chains
/// to "SSL.com TLS RSA Root CA 2022", which many PCs don't have yet, so the
/// TLS handshake fails there ("Secure connection failed") while browsers on
/// the same PC work fine.
///
/// Certificates are only ADDED; the Windows store is still used, so
/// corporate/proxy roots installed on a machine keep working.
///
/// Call once in main(), after WidgetsFlutterBinding.ensureInitialized() and
/// before any network request. Every HttpClient created without an explicit
/// SecurityContext (package:http, dio's default adapter) uses this context.
Future<void> installBundledRootCertificates() async {
  try {
    final pem = await rootBundle.loadString('assets/certs/cacert.pem');
    final certs = RegExp(
      r'-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----',
    ).allMatches(pem);

    var added = 0;
    for (final m in certs) {
      // Added one at a time: a root that's already in the machine's store can
      // make the call throw, and that must not stop the rest from loading.
      try {
        SecurityContext.defaultContext
            .setTrustedCertificatesBytes(utf8.encode(m.group(0)!));
        added++;
      } catch (_) {
        // Typically "already trusted on this machine" — nothing to do.
      }
    }
    debugPrint('[TrustedRoots] added $added bundled root certificates');
  } catch (e) {
    // Never block startup over this; the system store still applies.
    debugPrint('[TrustedRoots] could not load bundled roots: $e');
  }
}