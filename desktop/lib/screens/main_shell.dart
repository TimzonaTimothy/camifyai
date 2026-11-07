import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/announcement_provider.dart';
import '../services/auth_provider.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/credit_display.dart';
import '../widgets/announcement_banner.dart';
import '../widgets/camify_logo.dart';
import '../widgets/update_banner.dart';

/// Session-first shell: top navigation only (no left sidebar).
class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.instance.checkForUpdate();
      context.read<AnnouncementProvider>().fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<UpdateService>.value(
      value: UpdateService.instance,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            const _TopBar(),
            const UpdateBanner(),
            const AnnouncementBanner(),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  static const _tabs = [
    _TabItem(label: 'Home', route: '/dashboard'),
    _TabItem(label: 'Go live', route: '/playground'),
    _TabItem(label: 'Time', route: '/billing'),
    _TabItem(label: 'History', route: '/usage'),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final location = GoRouterState.of(context).matchedLocation;
    final email = auth.user?.email ?? '';
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 28 : 16,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const CamifyLogo(iconSize: 30, fontSize: 18),
          if (wide) ...[
            const SizedBox(width: 36),
            for (final tab in _tabs)
              _TopTab(
                label: tab.label,
                active: location == tab.route ||
                    location.startsWith('${tab.route}/'),
                onTap: () => context.go(tab.route),
              ),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  CreditDisplay.toTime(auth.credits),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () => context.go('/playground'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Go live',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Account',
            offset: const Offset(0, 40),
            color: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            onSelected: (value) async {
              if (value == 'security') {
                context.go('/change-password');
              } else if (value == 'logout') {
                await context.read<AuthProvider>().logout();
                if (context.mounted) context.go('/login');
              } else if (value == 'billing') {
                context.go('/billing');
              } else if (value == 'usage') {
                context.go('/usage');
              } else if (value == 'home') {
                context.go('/dashboard');
              }
            },
            itemBuilder: (context) => [
              if (!wide) ...[
                const PopupMenuItem(value: 'home', child: Text('Home')),
                const PopupMenuItem(
                    value: 'billing', child: Text('Time / billing')),
                const PopupMenuItem(value: 'usage', child: Text('History')),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem(value: 'security', child: Text('Security')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.accentDim,
              child: Text(
                email.isEmpty ? 'C' : email[0].toUpperCase(),
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TopTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.accent : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String label;
  final String route;
  const _TabItem({required this.label, required this.route});
}