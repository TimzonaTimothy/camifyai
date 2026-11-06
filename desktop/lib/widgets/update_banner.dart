import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// A compact banner rendered inside the sidebar whenever an update is available.
/// Mandatory updates cannot be dismissed.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<UpdateService>();
    if (!svc.hasUpdate) return const SizedBox.shrink();

    final info = svc.available!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF263425), Color(0xFF182019)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.accent.withOpacity(0.45)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ─────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.system_update_alt_rounded,
                    size: 15, color: AppColors.accent),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Update available',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!info.isMandatory && !_downloading)
                  GestureDetector(
                    onTap: svc.dismiss,
                    child: const Icon(Icons.close_rounded,
                        size: 14, color: AppColors.textMuted),
                  ),
              ],
            ),

            const SizedBox(height: 4),

            // ── Version line ────────────────────────────────────────────
            Text(
              'v${info.version} is ready',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),

            // ── Release notes ────────────────────────────────────────────
            if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                info.releaseNotes!,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 10),

            // ── Progress bar (while downloading) ────────────────────────
            if (_downloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: AppColors.accentDim,
                  color: AppColors.accent,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _progress > 0
                    ? 'Downloading… ${(_progress * 100).toStringAsFixed(0)}%'
                    : 'Starting download…',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 10),
              ),
              const SizedBox(height: 6),
            ],

            // ── Error message ────────────────────────────────────────────
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 10),
              ),
              const SizedBox(height: 6),
            ],

            // ── Download button ──────────────────────────────────────────
            if (!_downloading)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _startDownload(info.downloadUrl),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: const TextStyle(fontFamily: 'Inter', 
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Download & Install'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Downloads the installer via an authenticated request (Bearer token),
  /// saves it to the user's Downloads folder, then launches it.
  /// The real file URL is resolved server-side — the client never sees it.
  Future<void> _startDownload(String downloadUrl) async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      final token = ApiService.instance.accessToken;
      if (token == null) throw Exception('Not authenticated');

      final request = http.Request('GET', Uri.parse(downloadUrl))
        ..headers['Authorization'] = 'Bearer $token';

      final streamed = await request.send();

      if (streamed.statusCode != 200) {
        throw Exception('Server returned ${streamed.statusCode}');
      }

      // Save to Downloads folder
      final dir = await getDownloadsDirectory() ??
          await getTemporaryDirectory();
      final file = File('${dir.path}/camifyai-Setup.exe');
      final sink = file.openWrite();

      final total = streamed.contentLength ?? 0;
      int received = 0;

      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      }
      await sink.close();

      // Launch the installer
      await launchUrl(Uri.file(file.path));

      // Dismiss the banner once the installer opens
      if (mounted) UpdateService.instance.dismiss();
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = 'Download failed. Please try again.';
        });
      }
    }
  }
}