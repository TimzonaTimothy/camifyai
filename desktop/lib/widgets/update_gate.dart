// lib/widgets/update_gate.dart
//
// Wraps any child widget. If the backend's min_app_version is newer than
// the running build, it replaces the child with a "please update" overlay
// instead of letting the user access the playground or stream.
//
// Usage (in playground_screen.dart or main_shell.dart):
//
//   UpdateGate(
//     child: PlaygroundScreen(),
//   )

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/announcement_provider.dart';
import '../theme/app_theme.dart';

class UpdateGate extends StatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  String _runningVersion = '';
  bool _versionLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _runningVersion = info.version; // e.g. "1.0.5"
        _versionLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_versionLoaded) return widget.child;

    final ann = context.watch<AnnouncementProvider>();
    final blocked = ann.isUpdateRequired(_runningVersion);

    if (!blocked) return widget.child;

    // ── Blocking overlay ──────────────────────────────────────────────────
    return Container(
      color: AppColors.bg,
      child: SingleChildScrollView(
          child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update_alt_rounded,
                  size: 40,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Update Required',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),

              // Body
              Text(
                'A new version of the app is required before you can '
                'continue. Please download and install the latest update '
                'to keep using the playground and streaming features.\n\n'
                'Running: v$_runningVersion   '
                '→   Required: v${ann.minAppVersion}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),

              // Download button — navigates to the download screen
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // If you have a dedicated download route, push it here.
                    // Otherwise navigate to the billing/download page.
                    Navigator.of(context).pushNamed('/download');
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download Latest Version'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontFamily: 'Inter', 
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}
