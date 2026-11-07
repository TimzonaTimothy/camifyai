


class CreditDisplay {
  static const double realtimeCreditsPerSecond = 2.0;

  /// Convert backend credits to streaming duration.
  static String toTime(
    double credits, {
    String modelType = 'realtime',
  }) {
    double seconds;

    switch (modelType) {
      case 'v2v':
        seconds = credits * 0.375;
        break;
      case 'lipsync':
        seconds = credits * 1.5;
        break;
      case 'image':
        final images = (credits / 1.333).floor();
        return '$images images';
      case 'realtime':
      default:
        seconds = credits / realtimeCreditsPerSecond;
        break;
    }

    final totalSeconds = seconds.floor().clamp(0, 2147483647);

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final remainingSeconds = totalSeconds % 60;

    if (hours > 0) {
      if (minutes == 0 && remainingSeconds == 0) {
        return '$hours ${hours == 1 ? "hour" : "hours"}';
      }
      return '${hours}h ${minutes}m ${remainingSeconds}s';
    }

    if (minutes > 0) {
      return '${minutes}m ${remainingSeconds}s';
    }

    return '${remainingSeconds}s';
  }

  /// Equivalent value at the new $20/hour package rate.
  /// This is not a refund or cash balance.
  static String toMoney(double credits) {
    final value = credits * 20.0 / 7200.0;
    return '\$${value.toStringAsFixed(2)}';
  }
}
