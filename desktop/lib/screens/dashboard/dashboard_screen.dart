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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  int _activityPage = 1;
  int _activityTotalPages = 1;

  String? _dashError;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _dashError = null;
    });
    try {
      final data = await ApiService.instance
          .getDashboard(days: 30, activityPage: _activityPage);
      if (!mounted) return;

      // Check if Django returned an error response (e.g. auth failure, server error)
      final statusCode = data['statusCode'];
      if ((statusCode != null && statusCode != 200) ||
          data.containsKey('error') ||
          data.containsKey('detail')) {
        final errMsg = data['error'] ??
            data['detail'] ??
            'Server returned HTTP $statusCode';
        debugPrint('[Dashboard] API error (HTTP $statusCode): $errMsg');
        setState(() {
          _dashError = errMsg.toString();
          _loading = false;
        });
        return;
      }

      debugPrint(
          '[Dashboard] Loaded: total_used=${data['total_credits_used']}, '
          'daily=${(data['daily_usage'] as List?)?.length ?? 0} days, '
          'activity=${(data['recent_activity'] as List?)?.length ?? 0} items');

      _activityTotalPages = data['activity_total_pages'] ?? 1;
      setState(() {
        _stats = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Dashboard] Exception loading stats: $e');
      if (!mounted) return;
      setState(() {
        _dashError = ErrorHandler.sanitize(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2))
          : AppPage(
              padding: AppLayout.padding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdaptiveRow(
                    breakpoint: 600,
                    children: [
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome back, ${auth.user?.username ?? 'there'}.',
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Your next session starts here.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      )),
                      const SizedBox(width: 16),
                      IconButton(
                        onPressed: _loadStats,
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ).animate().fadeIn(),

                  // ── Error banner ──
                  if (_dashError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.errorDim,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _dashError!,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _loadStats,
                            child: const Text('Retry',
                                style: TextStyle(
                                    color: AppColors.accent, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  LayoutBuilder(builder: (ctx, constraints) {
                    final cols = constraints.maxWidth >= 1100
                        ? 4
                        : constraints.maxWidth >= 560
                            ? 2
                            : 1;
                    return GridView.count(
                      crossAxisCount: cols,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisExtent: 176,
                      children: [
                        _TimeBalanceCard(credits: auth.credits),
                        StatCard(
                          label: 'Time Used (30d)',
                          value: CreditDisplay.toTime(
                              _parseNum(_stats?['total_credits_used'])),
                          icon: Icons.trending_up_rounded,
                          accentColor: AppColors.warning,
                        ),
                        StatCard(
                          label: 'Active Sessions',
                          value: '–',
                          icon: Icons.stream_rounded,
                          accentColor: AppColors.success,
                          subtitle: 'Realtime streams',
                        ),
                        StatCard(
                          label: 'Plan',
                          value: (_stats?['plan'] ?? 'FREE')
                              .toString()
                              .toUpperCase(),
                          icon: Icons.workspace_premium_rounded,
                          accentColor: AppColors.accentLight,
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 32),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(
                          title: 'Usage History',
                          subtitle: 'Last 30 days',
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 200,
                          child: _buildChart(),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 200.ms),

                  const SizedBox(height: 32),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'Recent Activity'),
                        const SizedBox(height: 16),
                        _buildActivityList(),
                      ],
                    ),
                  ).animate().fadeIn(delay: 300.ms),
                ],
              ),
            ),
    );
  }

  double _parseNum(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  Widget _buildChart() {
    final daily = (_stats?['daily_usage'] as List<dynamic>?) ?? [];
    if (daily.isEmpty) {
      return const Center(
        child: Text('No usage data yet',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }
    final spots = daily.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), _parseNum(e.value['credits'] ?? 0));
    }).toList();
    return LineChart(
      LineChartData(
        backgroundColor: Colors.transparent,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (val, _) => Text(
                val.toInt().toString(),
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.accent,
            barWidth: 2.5,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.accent.withOpacity(0.2),
                  AppColors.accent.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityList() {
    final activity = (_stats?['recent_activity'] as List<dynamic>?) ?? [];
    if (activity.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'No activity yet',
        subtitle: 'Start using the playground to see activity here',
      );
    }
    return Column(children: [
      ...activity.take(8).map((item) {
        final endpoint = item['endpoint'] as String? ?? '';
        final creditsRaw = item['credits_used'];
        final credits = creditsRaw == null
            ? 0.0
            : creditsRaw is num
                ? creditsRaw.toDouble()
                : double.tryParse(creditsRaw.toString()) ?? 0.0;
        final model = (item['model_used'] as String? ?? '').replaceAll(
            RegExp(r'xmax|x2[.]1', caseSensitive: false), 'Live studio');

        IconData icon;
        Color color;
        String label;
        switch (endpoint) {
          case 'realtime_token':
            icon = Icons.stream_rounded;
            color = AppColors.accent;
            label = 'Realtime Stream';
            break;
          case 'queue_video':
            icon = Icons.videocam_rounded;
            color = AppColors.success;
            label = 'Video Generation';
            break;
          default:
            icon = Icons.image_rounded;
            color = AppColors.warning;
            label = 'Image Generation';
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AdaptiveRow(
            breakpoint: 540,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    if (model.isNotEmpty)
                      Text(model,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    const Icon(Icons.timer_rounded,
                        size: 12, color: AppColors.accent),
                    const SizedBox(width: 3),
                    Text(CreditDisplay.toTime(credits),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
      if (_activityTotalPages > 1)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _activityPage > 1
                  ? () => setState(() {
                        _activityPage--;
                        _loadStats();
                      })
                  : null,
            ),
            Text('Page $_activityPage of $_activityTotalPages',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _activityPage < _activityTotalPages
                  ? () => setState(() {
                        _activityPage++;
                        _loadStats();
                      })
                  : null,
            ),
          ],
        ),
    ]);
  }
}

// ── Time Balance Card ─────────────────────────────────────────────────────────
class _TimeBalanceCard extends StatelessWidget {
  final double credits;
  const _TimeBalanceCard({required this.credits});

  @override
  Widget build(BuildContext context) {
    final timeStr = CreditDisplay.toTime(credits);
    final isLow = credits < 100;
    final accent = isLow ? AppColors.error : AppColors.accent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLow
                ? [const Color(0xFF1F0A0A), const Color(0xFF2A0F0F)]
                : [const Color(0xFF203021), const Color(0xFF151E17)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(0.3), width: 1.5),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isLow ? Icons.timer_off_rounded : Icons.timer_rounded,
                  color: accent,
                  size: 16,
                ),
              ),
              const SizedBox(height: 10),
              // TIME — big and dominant
              Text(
                timeStr,
                style: TextStyle(
                  color: isLow ? AppColors.error : AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              const Text('streaming time',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 5),
              Container(height: 1, color: AppColors.border),
              const SizedBox(height: 5),
              // Credits display removed - keep LOW indicator
              if (isLow)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.errorDim,
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('LOW',
                      style: TextStyle(
                          color: AppColors.error,
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
