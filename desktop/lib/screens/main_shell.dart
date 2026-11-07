import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/announcement_provider.dart';
import '../services/auth_provider.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/credit_display.dart';
import '../widgets/announcement_banner.dart';
import '../widgets/update_banner.dart';
import '../widgets/camify_logo.dart';

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
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 1000;
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: compact
              ? AppBar(
                  title: const CamifyLogo(iconSize: 28, fontSize: 18),
                  bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(1),
                      child: Container(height: 1, color: AppColors.border)),
                )
              : null,
          drawer: compact
              ? Drawer(
                  width: 280,
                  backgroundColor: AppColors.surface,
                  child: SafeArea(child: _Sidebar(closeOnNavigate: true)))
              : null,
          body: compact
              ? widget.child
              : Row(children: [_Sidebar(), Expanded(child: widget.child)]),
        );
      }),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final bool closeOnNavigate;
  const _Sidebar({this.closeOnNavigate = false});
  static const _navItems = [
    _NavItem(
        icon: Icons.grid_view_rounded, label: 'Dashboard', route: '/dashboard'),
    _NavItem(
        icon: Icons.videocam_rounded,
        label: 'Live studio',
        route: '/playground'),
    _NavItem(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Billing',
        route: '/billing'),
    _NavItem(icon: Icons.history_rounded, label: 'Usage', route: '/usage'),
    _NavItem(
        icon: Icons.lock_outline_rounded,
        label: 'Security',
        route: '/change-password'),
  ];

  void _navigate(BuildContext context, String route) {
    if (closeOnNavigate) Navigator.of(context).pop();
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final location = GoRouterState.of(context).matchedLocation;
    final email = auth.user?.email ?? '';
    return Container(
      width: 248,
      decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(right: BorderSide(color: AppColors.border))),
      child: Column(children: [
        const Padding(
    padding: EdgeInsets.fromLTRB(22, 26, 22, 24),
    child: Align(
      alignment: Alignment.centerLeft,
      child: CamifyLogo(iconSize: 32, fontSize: 20),
    ),
  ),
        const Divider(height: 1),
        Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF263425), Color(0xFF182019)]),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('YOUR STREAMING TIME',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 9,
                            letterSpacing: 1.3)),
                    const SizedBox(height: 10),
                    Text(CreditDisplay.toTime(auth.credits),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.8)),
                    const SizedBox(height: 14),
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                            onPressed: () => _navigate(context, '/billing'),
                            style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 9)),
                            child: const Text('Add time',
                                style: TextStyle(fontSize: 11)))),
                  ])),
          const Padding(
              padding: EdgeInsets.fromLTRB(12, 28, 12, 12),
              child: Text('WORKSPACE',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      letterSpacing: 1.6))),
          for (final item in _navItems)
            _NavButton(
                item: item,
                isActive: location == item.route ||
                    location.startsWith('${item.route}/'),
                onTap: () => _navigate(context, item.route)),
          const SizedBox(height: 24),
          const AnnouncementBanner(),
          const UpdateBanner(),
        ])),
        const Divider(height: 1),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.accentDim,
                  child: Text(email.isEmpty ? 'C' : email[0].toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.accent, fontSize: 12))),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(auth.user?.username ?? 'Your account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    Text(auth.user?.plan.toUpperCase() ?? 'FREE',
                        style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 9,
                            letterSpacing: 0.8)),
                  ])),
              IconButton(
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  tooltip: 'Sign out',
                  onPressed: () async {
                    await context.read<AuthProvider>().logout();
                    if (context.mounted) context.go('/login');
                  }),
            ])),
      ]),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(item.icon,
                  size: 18,
                  color: isActive ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(width: 10),
              Text(
                item.label,
                style: TextStyle(
                  color: isActive ? AppColors.accent : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}
