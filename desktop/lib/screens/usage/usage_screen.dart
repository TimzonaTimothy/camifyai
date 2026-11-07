import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_display.dart';
import '../../widgets/session_page.dart';

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
      if (!mounted) return;
      setState(() {
        _logs = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _label(String endpoint) {
    switch (endpoint) {
      case 'realtime_token':
        return 'Live session';
      case 'queue_video':
        return 'Video';
      case 'queue_image':
        return 'Image';
      default:
        return endpoint;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionPage(
      title: 'History',
      subtitle: 'Sessions and time used on your account.',
      trailing: IconButton(
        onPressed: _load,
        tooltip: 'Refresh',
        icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
      ),
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2))
          : _logs.isEmpty
              ? const Center(
                  child: Text(
                    'No sessions yet.\nGo live once and they will show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary, height: 1.5),
                  ),
                )
              : ListView.separated(
                  itemCount: _logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final log = _logs[i] as Map<String, dynamic>;
                    final endpoint = log['endpoint'] as String? ?? '';
                    final model = (log['model_used'] as String? ?? '-')
                        .replaceAll(
                            RegExp(r'xmax|x2[.]1', caseSensitive: false),
                            'camifyai');
                    final credits = double.tryParse('${log['credits_used'] ?? 0}') ?? 0;
                    final ts = log['created_at'] as String? ??
                        log['timestamp'] as String? ??
                        '';
                    final when = ts.length > 16
                        ? ts.substring(0, 16).replaceAll('T', ' ')
                        : ts;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.accentDim,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.schedule_rounded,
                                size: 18, color: AppColors.accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _label(endpoint),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  model,
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CreditDisplay.toTime(credits),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                when,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}