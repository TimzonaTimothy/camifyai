import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Official CamifyAI mark: rounded camera icon + "camify" + green "ai".
/// Matches the brand used on the website / live studio.
class CamifyLogo extends StatelessWidget {
  final double iconSize;
  final double fontSize;
  final bool showWordmark;
  final bool compact;

  const CamifyLogo({
    super.key,
    this.iconSize = 32,
    this.fontSize = 20,
    this.showWordmark = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CameraMark(size: iconSize),
        if (showWordmark) ...[
          SizedBox(width: compact ? 8 : 10),
          _Wordmark(fontSize: fontSize),
        ],
      ],
    );
  }
}

class _CameraMark extends StatelessWidget {
  final double size;
  const _CameraMark({required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1A2420),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: AppColors.accent.withOpacity(0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.12),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.55, size * 0.55),
          painter: _CameraIconPainter(color: AppColors.accent),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final double fontSize;
  const _Wordmark({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'camify',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              height: 1,
            ),
          ),
          TextSpan(
            text: 'ai',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple camera body + lens icon (matches the template SVG mark).
class _CameraIconPainter extends CustomPainter {
  final Color color;
  _CameraIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Camera body
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.22, w * 0.84, h * 0.62),
      Radius.circular(w * 0.18),
    );
    canvas.drawRRect(body, stroke);

    // Lens
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.53),
      w * 0.18,
      stroke,
    );

    // Viewfinder bumps (top left / top right)
    canvas.drawLine(
      Offset(w * 0.28, h * 0.12),
      Offset(w * 0.28, h * 0.22),
      stroke,
    );
    canvas.drawLine(
      Offset(w * 0.72, h * 0.12),
      Offset(w * 0.72, h * 0.22),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CameraIconPainter oldDelegate) =>
      oldDelegate.color != color;
}