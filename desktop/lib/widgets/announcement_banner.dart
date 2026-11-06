import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/announcement_provider.dart';
import '../theme/app_theme.dart';

class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final ann = context.watch<AnnouncementProvider>();
    if (!ann.active) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A1B0A), Color(0xFF1A1105)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFFE8A020).withOpacity(0.55)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.campaign_rounded,
                    size: 14, color: Color(0xFFE8A020)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Announcement',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: ann.dismiss,
                  child: const Icon(Icons.close_rounded,
                      size: 13, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ann.text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go('/watermark-fee'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8A020),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  textStyle: const TextStyle(fontFamily: 'Inter', 
                      fontSize: 11, fontWeight: FontWeight.w700),
                ),
                child: const Text('Pay Watermark Fee →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}