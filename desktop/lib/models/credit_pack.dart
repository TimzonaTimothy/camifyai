class CreditPack {
  final String id;
  final String label;
  final int credits;
  final String priceUsd;
  final bool popular;
  final String description;
  final int streamingMinutes; // convenience field from backend

  CreditPack({
    required this.id,
    required this.label,
    required this.credits,
    required this.priceUsd,
    required this.popular,
    required this.description,
    this.streamingMinutes = 0,
  });

  factory CreditPack.fromJson(Map<String, dynamic> json) {
    return CreditPack(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      credits: json['credits'] ?? 0,
      priceUsd: json['price_usd']?.toString() ?? '0.00',
      popular: json['popular'] ?? false,
      description: json['description'] ?? '',
      streamingMinutes: json['streaming_minutes'] ?? 0,
    );
  }
}

class Payment {
  final int id;
  final String packLabel;
  final String amountUsd;
  final int creditsToAdd;
  final String currency;
  final String gateway; // "crypto" | "flutterwave"
  final String status;
  final String? paymentUrl;
  final String createdAt;
  final String? confirmedAt;
  final String paymentProvider;

  Payment({
    required this.id,
    required this.packLabel,
    required this.amountUsd,
    required this.creditsToAdd,
    required this.currency,
    required this.gateway,
    required this.status,
    this.paymentUrl,
    required this.createdAt,
    this.confirmedAt,
    this.paymentProvider = 'manual',
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] ?? 0,
      packLabel: json['pack_label'] ?? '',
      amountUsd: json['amount_usd']?.toString() ?? '0.00',
      creditsToAdd: json['credits_to_add'] ?? 0,
      currency: json['currency'] ?? '',
      gateway: json['gateway'] ?? 'crypto',
      status: json['status'] ?? 'waiting',
      paymentUrl: json['payment_url'],
      createdAt: json['created_at'] ?? '',
      confirmedAt: json['confirmed_at'],
      paymentProvider: json['payment_provider'] ?? 'manual',
    );
  }

  bool get isNowPayments => paymentProvider == 'nowpayments';
  bool get isConfirmed => status == 'confirmed';
  bool get isPending => status == 'waiting' || status == 'confirming';
  bool get isCrypto => gateway == 'crypto';
  bool get isFlutterwave => gateway == 'flutterwave';
}
