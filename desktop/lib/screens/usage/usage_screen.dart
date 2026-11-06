import '../../widgets/responsive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../utils/credit_display.dart';

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  List<dynamic> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.instance.getUsageHistory();
      setState(() {
        _logs = data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String _endpointLabel(String endpoint) {
    switch (endpoint) {
      case 'realtime_token':
        return 'Realtime Stream';
      case 'queue_video':
        return 'Video Generation';
      case 'queue_image':
        return 'Image Generation';
      default:
        return endpoint;
    }
  }

  IconData _endpointIcon(String endpoint) {
    switch (endpoint) {
      case 'realtime_token':
        return Icons.stream_rounded;
      case 'queue_video':
        return Icons.videocam_rounded;
      default:
        return Icons.image_rounded;
    }
  }

  Color _endpointColor(String endpoint) {
    switch (endpoint) {
      case 'realtime_token':
        return AppColors.accent;
      case 'queue_video':
        return AppColors.success;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AppPage(
        padding: AppLayout.padding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Usage History',
              subtitle: 'A clear view of your sessions and streaming time',
              action: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ).animate().fadeIn(),
            const SizedBox(height: 24),
            _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accent, strokeWidth: 2))
                : _logs.isEmpty
                    ? const EmptyState(
                        icon: Icons.history_rounded,
                        title: 'No usage yet',
                        subtitle:
                            'Your sessions will appear here after you visit the studio',
                      )
                    : ResponsiveTable(
                        child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            // Table header
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              decoration: const BoxDecoration(
                                border: Border(
                                    bottom:
                                        BorderSide(color: AppColors.border)),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                      flex: 3,
                                      child: Text('Type',
                                          style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600))),
                                  Expanded(
                                      flex: 3,
                                      child: Text('Experience',
                                          style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600))),
                                  Expanded(
                                      flex: 2,
                                      child: Text('Time Used',
                                          style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600))),
                                  Expanded(
                                      flex: 3,
                                      child: Text('Date',
                                          style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600))),
                                ],
                              ),
                            ),

                            // Rows
                            ..._logs.asMap().entries.map((e) {
                              final log = e.value as Map<String, dynamic>;
                              final endpoint = log['endpoint'] as String? ?? '';
                              final model =
                                  (log['model_used'] as String? ?? '–')
                                      .replaceAll(
                                          RegExp(r'xmax|x2[.]1',
                                              caseSensitive: false),
                                          'Live studio');
                              final creditsRaw = log['credits_used'];
                              final credits = creditsRaw == null
                                  ? 0.0
                                  : creditsRaw is num
                                      ? creditsRaw.toDouble()
                                      : double.tryParse(
                                              creditsRaw.toString()) ??
                                          0.0;
                              final ts = log['timestamp'] as String? ?? '';

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                decoration: const BoxDecoration(
                                  border: Border(
                                      bottom:
                                          BorderSide(color: AppColors.border)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: _endpointColor(endpoint)
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Icon(_endpointIcon(endpoint),
                                                color: _endpointColor(endpoint),
                                                size: 14),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              child: Text(
                                                  _endpointLabel(endpoint),
                                                  style: const TextStyle(
                                                      color:
                                                          AppColors.textPrimary,
                                                      fontSize: 13))),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(model,
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                              fontFamily: 'JetBrains Mono')),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.timer_rounded,
                                              size: 12,
                                              color: AppColors.accent),
                                          const SizedBox(width: 3),
                                          Text(CreditDisplay.toTime(credits),
                                              style: const TextStyle(
                                                  color: AppColors.textPrimary,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        ts.length > 16
                                            ? ts
                                                .substring(0, 16)
                                                .replaceAll('T', ' ')
                                            : ts,
                                        style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ).animate().fadeIn(
                                  delay: Duration(milliseconds: e.key * 30));
                            }),
                          ],
                        ),
                      )),
          ],
        ),
      ),
    );
  }
}
