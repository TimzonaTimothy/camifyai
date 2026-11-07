import '../../widgets/responsive_layout.dart';
// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_animate/flutter_animate.dart';
// import '../../services/auth_provider.dart';
// import '../../services/api_service.dart';
// import '../../theme/app_theme.dart';
// import '../../utils/credit_display.dart';
// import '../../widgets/shared_widgets.dart';

// class DashboardScreen extends StatefulWidget {
//   const DashboardScreen({super.key});

//   @override
//   State<DashboardScreen> createState() => _DashboardScreenState();
// }

// class _DashboardScreenState extends State<DashboardScreen> {
//   Map<String, dynamic>? _stats;
//   bool _loading = true;

//   @override
//   void initState() {
//     super.initState();
//     _loadStats();
//   }

//   Future<void> _loadStats() async {
//     setState(() => _loading = true);
//     try {
//       final data = await ApiService.instance.getDashboard(days: 30);
//       setState(() { _stats = data; _loading = false; });
//     } catch (_) {
//       setState(() => _loading = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final auth = context.watch<AuthProvider>();

//     return Scaffold(
//       backgroundColor: AppColors.bg,
//       body: _loading
//           ? const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
//           : SingleChildScrollView(
//               padding: AppLayout.padding(context),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   // Header
//                   Row(
//                     children: [
//                       Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             'Welcome back, ${auth.user?.username ?? 'there'}.',
//                             style: Theme.of(context).textTheme.displayMedium,
//                           ),
//                           const SizedBox(height: 4),
//                           const Text(
//                             'Your next session starts here.',
//                             style: TextStyle(color: AppColors.textSecondary),
//                           ),
//                         ],
//                       ),
//                       const Spacer(),
//                       IconButton(
//                         onPressed: _loadStats,
//                         icon: const Icon(Icons.refresh_rounded),
//                         tooltip: 'Refresh',
//                       ),
//                     ],
//                   ).animate().fadeIn(),

//                   const SizedBox(height: 32),

//                   // Stat cards
//                   LayoutBuilder(builder: (ctx, constraints) {
//                     final cols = constraints.maxWidth >= 1100 ? 4 : constraints.maxWidth >= 560 ? 2 : 1;
//                     return GridView.count(
//                       crossAxisCount: cols,
//                       crossAxisSpacing: 16,
//                       mainAxisSpacing: 16,
//                       shrinkWrap: true,
//                       physics: const NeverScrollableScrollPhysics(),
//                       mainAxisExtent: 176,
//                       children: [
//                         StatCard(
//                           label: 'Credits Remaining',
//                           value: auth.credits.toStringAsFixed(0),
//                           icon: Icons.bolt_rounded,
//                           accentColor: AppColors.accent,
//                           subtitle: '~${CreditDisplay.toTime(auth.credits)} available',
//                         ),
//                         StatCard(
//                           label: 'Credits Used (30d)',
//                           value: _parseNum(_stats?['total_credits_used']).toStringAsFixed(0),
//                           icon: Icons.trending_up_rounded,
//                           accentColor: AppColors.warning,
//                         ),
//                         StatCard(
//                           label: 'Active Sessions',
//                           value: '–',
//                           icon: Icons.stream_rounded,
//                           accentColor: AppColors.success,
//                           subtitle: 'Realtime streams',
//                         ),
//                         StatCard(
//                           label: 'Plan',
//                           value: (auth.user?.plan ?? 'FREE').toUpperCase(),
//                           icon: Icons.workspace_premium_rounded,
//                           accentColor: AppColors.accentLight,
//                         ),
//                       ],
//                     );
//                   }),

//                   const SizedBox(height: 32),

//                   // Usage chart
//                   Container(
//                     padding: const EdgeInsets.all(24),
//                     decoration: BoxDecoration(
//                       color: AppColors.card,
//                       borderRadius: BorderRadius.circular(18),
//                       border: Border.all(color: AppColors.border),
//                     ),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         const SectionHeader(
//                           title: 'Credit Usage',
//                           subtitle: 'Last 30 days',
//                         ),
//                         const SizedBox(height: 24),
//                         SizedBox(
//                           height: 200,
//                           child: _buildChart(),
//                         ),
//                       ],
//                     ),
//                   ).animate().fadeIn(delay: 200.ms),

//                   const SizedBox(height: 32),

//                   // Recent activity
//                   Container(
//                     padding: const EdgeInsets.all(24),
//                     decoration: BoxDecoration(
//                       color: AppColors.card,
//                       borderRadius: BorderRadius.circular(18),
//                       border: Border.all(color: AppColors.border),
//                     ),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         const SectionHeader(title: 'Recent Activity'),
//                         const SizedBox(height: 16),
//                         _buildActivityList(),
//                       ],
//                     ),
//                   ).animate().fadeIn(delay: 300.ms),
//                 ],
//               ),
//             ),
//     );
//   }

//   /// Safely parse any value Django might return as a number.
//   /// Django DecimalField serializes as String e.g. "50.0000"
//   double _parseNum(dynamic val) {
//     if (val == null) return 0.0;
//     if (val is num) return val.toDouble();
//     return double.tryParse(val.toString()) ?? 0.0;
//   }

//   Widget _buildChart() {
//     final daily = (_stats?['daily_usage'] as List<dynamic>?) ?? [];
//     if (daily.isEmpty) {
//       return const Center(
//         child: Text('No usage data yet', style: TextStyle(color: AppColors.textMuted)),
//       );
//     }

//     final spots = daily.asMap().entries.map((e) {
//       return FlSpot(e.key.toDouble(), _parseNum(e.value['credits']));
//     }).toList();

//     return LineChart(
//       LineChartData(
//         backgroundColor: Colors.transparent,
//         gridData: FlGridData(
//           show: true,
//           drawVerticalLine: false,
//           getDrawingHorizontalLine: (_) => FlLine(
//             color: AppColors.border,
//             strokeWidth: 1,
//           ),
//         ),
//         titlesData: FlTitlesData(
//           leftTitles: AxisTitles(
//             sideTitles: SideTitles(
//               showTitles: true,
//               reservedSize: 40,
//               getTitlesWidget: (val, _) => Text(
//                 val.toInt().toString(),
//                 style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
//               ),
//             ),
//           ),
//           bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//           rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//           topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//         ),
//         borderData: FlBorderData(show: false),
//         lineBarsData: [
//           LineChartBarData(
//             spots: spots,
//             isCurved: true,
//             color: AppColors.accent,
//             barWidth: 2.5,
//             dotData: FlDotData(show: false),
//             belowBarData: BarAreaData(
//               show: true,
//               gradient: LinearGradient(
//                 begin: Alignment.topCenter,
//                 end: Alignment.bottomCenter,
//                 colors: [
//                   AppColors.accent.withOpacity(0.2),
//                   AppColors.accent.withOpacity(0.0),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildActivityList() {
//     final activity = (_stats?['recent_activity'] as List<dynamic>?) ?? [];
//     if (activity.isEmpty) {
//       return const EmptyState(
//         icon: Icons.history_rounded,
//         title: 'No activity yet',
//         subtitle: 'Start using the playground to see activity here',
//       );
//     }

//     return Column(
//       children: activity.take(8).map((item) {
//         final endpoint = item['endpoint'] as String? ?? '';
//         // Django DecimalField serializes as String e.g. "50.0000" — parse safely
//         final creditsRaw = item['credits_used'];
//         final credits = creditsRaw == null
//             ? 0.0
//             : creditsRaw is num
//                 ? creditsRaw.toDouble()
//                 : double.tryParse(creditsRaw.toString()) ?? 0.0;
//         final model    = (item['model_used'] as String? ?? '').replaceAll(RegExp(r'xmax|x2[.]1', caseSensitive: false), 'Live studio');

//         IconData icon;
//         Color color;
//         String label;
//         switch (endpoint) {
//           case 'realtime_token':
//             icon = Icons.stream_rounded; color = AppColors.accent; label = 'Realtime Stream';
//             break;
//           case 'queue_video':
//             icon = Icons.videocam_rounded; color = AppColors.success; label = 'Video Generation';
//             break;
//           default:
//             icon = Icons.image_rounded; color = AppColors.warning; label = 'Image Generation';
//         }

//         return Padding(
//           padding: const EdgeInsets.only(bottom: 10),
//           child: Row(
//             children: [
//               Container(
//                 padding: const EdgeInsets.all(8),
//                 decoration: BoxDecoration(
//                   color: color.withOpacity(0.12),
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: Icon(icon, color: color, size: 16),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
//                     if (model.isNotEmpty)
//                       Text(model, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
//                   ],
//                 ),
//               ),
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: AppColors.surface,
//                   borderRadius: BorderRadius.circular(6),
//                 ),
//                 child: Row(
//                   children: [
//                     const Icon(Icons.bolt_rounded, size: 12, color: AppColors.accent),
//                     const SizedBox(width: 3),
//                     Text(
//                       credits.toStringAsFixed(0),
//                       style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         );
//       }).toList(),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_display.dart';
import '../../utils/error_handler.dart';
import '../../widgets/shared_widgets.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_display.dart';

/// Session-first home: one primary action, not a multi-card SaaS dashboard.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final credits = auth.credits;
    final timeLeft = CreditDisplay.toTime(credits);
    final name = auth.user?.username ?? auth.user?.email ?? 'there';

    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hi, $name',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ready when you are.',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.2,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Pick a look, go live, and capture the output in OBS.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1C2820), Color(0xFF141A17)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TIME LEFT',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        timeLeft,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${credits.toStringAsFixed(0)} credits',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => context.go('/playground'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.onAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Go live',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => context.go('/billing'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Add more time'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _LinkRow(
                  title: 'Purchase history',
                  subtitle: 'Past top-ups and usage',
                  onTap: () => context.go('/usage'),
                ),
                _LinkRow(
                  title: 'Security',
                  subtitle: 'Password and account',
                  onTap: () => context.go('/change-password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _LinkRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}