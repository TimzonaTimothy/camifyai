import '../../widgets/responsive_layout.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/credit_pack.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_display.dart';
import '../../widgets/shared_widgets.dart';
import '../../utils/error_handler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BILLING SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<CreditPack> _packs = [];
  List<Payment> _history = [];
  int _historyPage = 1;
  int _historyTotalPages = 1;
  int _historyTotal = 0;
  final bool _historyLoading = false;
  bool _loading = true;

  // Currency selection
  String _cryptoCurrency = 'usdtbsc';
  bool _feePaidByUser = true;
  String? _pendingProvider;

  // Pending payment tracking
  int? _pendingPaymentId;
  String? _pendingPaymentUrl;
  String? _pendingTxRef; // Flutterwave tx_ref
  Timer? _paymentPollTimer;

  // Wallet addresses fetched from server
  Map<String, dynamic> _walletAddresses = {};

  // ── Currencies loaded from backend ────────────────────────────────────────
  List<Map<String, String>> _cryptoCurrencies = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _paymentPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.getCreditPacks(),
        ApiService.instance.getPaymentHistory(page: _historyPage),
        ApiService.instance.getWalletAddresses(),
        ApiService.instance.getCurrencies(),
      ]);

      final packs = results[0] as List<dynamic>;
      final historyData = results[1] as Map<String, dynamic>;
      final wallets = results[2] as Map<String, dynamic>;
      final currencies = results[3] as Map<String, dynamic>;

      // Parse crypto currencies from backend
      final rawCrypto = (currencies['crypto'] as List? ?? [])
          .map((c) => {
                'id': (c['id'] as String? ?? ''),
                'label': (c['label'] as String? ?? ''),
              })
          .where((c) => c['id']!.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _packs = packs
            .map((j) => CreditPack.fromJson(j as Map<String, dynamic>))
            .toList();
        _history = (historyData['results'] as List)
            .map((j) => Payment.fromJson(j))
            .toList();
        _historyTotalPages = historyData['total_pages'] ?? 1;
        _historyTotal = historyData['count'] ?? 0;
        _walletAddresses = wallets;
        _cryptoCurrencies = rawCrypto;
        _feePaidByUser = currencies['fee_paid_by_user'] == true;

        // Auto-select first currency if current selection no longer exists
        if (_cryptoCurrencies.isNotEmpty &&
            !_cryptoCurrencies.any((c) => c['id'] == _cryptoCurrency)) {
          _cryptoCurrency = _cryptoCurrencies.first['id']!;
        }

        _loading = false;
      });
      if (_pendingPaymentId == null) {
        final pending =
            _history.where((p) => p.isNowPayments && p.isPending).toList();
        if (pending.isNotEmpty) {
          setState(() {
            _pendingPaymentId = pending.first.id;
            _pendingPaymentUrl = pending.first.paymentUrl;
            _pendingProvider = 'nowpayments';
          });
          _startPaymentPolling(pending.first.id);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Buy a pack ─────────────────────────────────────────────────────────────
  Future<void> _buyPack(CreditPack pack) async {
    Map<String, dynamic> result;

    try {
      result = await ApiService.instance.createCryptoPayment(
        packId: pack.id,
        currency: _cryptoCurrency,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorHandler.sanitize(e)),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }

    final sc = result['statusCode'] as int? ?? 0;
    if (sc != 200 && sc != 201) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['error'] ?? 'Payment failed. Try again.'),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }

    if (!mounted) return;
    final paymentId = result['payment_id'] as int;
    final paymentUrl =
        result['payment_url'] as String?; // null for manual crypto
    final txRef = result['tx_ref'] as String?; // Flutterwave only

    if (!mounted) return;
    setState(() {
      _pendingPaymentId = paymentId;
      _pendingPaymentUrl = paymentUrl;
      _pendingTxRef = txRef;
      _pendingProvider = result['payment_provider'] as String?;
    });

    // Polling is authoritative; opening or returning from checkout never grants credits.
    _startPaymentPolling(paymentId, txRef: txRef);
    if (paymentUrl != null && paymentUrl.isNotEmpty) {
      await _openCheckout(paymentUrl);
    } else if (_pendingProvider != 'nowpayments') {
      await _showPendingInstructionsDialog(result);
    }
  }

  Future<void> _openCheckout(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open checkout');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Could not open checkout. Use Reopen checkout to try again.'),
      ));
    }
  }

  // ── Poll for payment status ────────────────────────────────────────────────
  void _startPaymentPolling(int paymentId, {String? txRef}) {
    _paymentPollTimer?.cancel();
    // Hosted crypto checkout settles automatically; legacy manual records keep their slower interval.
    final interval = _pendingProvider == 'nowpayments'
        ? const Duration(seconds: 10)
        : const Duration(seconds: 30);

    _paymentPollTimer = Timer.periodic(interval, (_) async {
      // Poll the generic status endpoint
      final Map<String, dynamic> status;
      try {
        status = await ApiService.instance.getPaymentStatus(paymentId);
      } catch (_) {
        return;
      }
      if (!mounted || _pendingPaymentId != paymentId) return;
      if (status['status'] == 'failed' || status['status'] == 'expired') {
        _paymentPollTimer?.cancel();
        setState(() {
          _pendingPaymentId = null;
          _pendingPaymentUrl = null;
          _pendingProvider = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('This checkout has ended. You can start a new payment.')));
        _loadData();
        return;
      }
      if (status['status'] == 'confirmed') {
        _handlePaymentConfirmed(
          paymentId: paymentId,
          credits: status['credits'] as int? ?? 0,
          balance: (status['credits_balance'] as num?)?.toDouble() ?? 0,
        );
      }
    });
  }

  void _handlePaymentConfirmed({
    required int paymentId,
    required int credits,
    required double balance,
  }) {
    _paymentPollTimer?.cancel();
    if (!mounted) return;
    context.read<AuthProvider>().updateCredits(balance);
    setState(() {
      _pendingPaymentId = null;
      _pendingPaymentUrl = null;
      _pendingTxRef = null;
      _pendingProvider = null;
    });
    _loadData();
    _showSuccessDialog(credits, balance);
  }

  // Fetch a fresh random wallet address from server, then show the dialog.
  // Shows payment instructions. The server already picked a random wallet
  // for this currency and embedded it in `result`. We also keep the
  // wallets cache refreshed so the address display is always current.
  Future<void> _showPendingInstructionsDialog(
      Map<String, dynamic> result) async {
    final amountUsd =
        result['amount_usd']?.toString() ?? result['amount']?.toString() ?? '';
    final currencyId =
        (result['currency'] as String? ?? 'usdttrc20').toLowerCase();
    final credits = result['credits']?.toString() ?? '';
    final paymentId = result['payment_id']?.toString() ?? '';

    // PRIMARY: wallet info is returned directly by CreatePaymentView
    // so we always get a freshly randomised address without an extra request.
    String walletAddr = result['wallet_address'] as String? ?? '';
    String walletLabel =
        result['wallet_label'] as String? ?? currencyId.toUpperCase();
    String walletNet = result['wallet_network'] as String? ?? currencyId;

    // FALLBACK: if server didn't include wallet info (e.g. older backend),
    // fetch from /payments/wallets/ which also randomises per call.
    if (walletAddr.isEmpty) {
      try {
        final freshWallets = await ApiService.instance.getWalletAddresses();
        if (mounted) setState(() => _walletAddresses = freshWallets);
        final walletInfo =
            freshWallets[currencyId] as Map<String, dynamic>? ?? {};
        walletAddr = walletInfo['address'] as String? ?? '';
        walletLabel = walletInfo['label'] as String? ?? walletLabel;
        walletNet = walletInfo['network'] as String? ?? walletNet;
      } catch (_) {
        // Last resort: use whatever was cached at screen load
        final walletInfo =
            _walletAddresses[currencyId] as Map<String, dynamic>? ?? {};
        walletAddr = walletInfo['address'] as String? ?? '';
        walletLabel = walletInfo['label'] as String? ?? walletLabel;
        walletNet = walletInfo['network'] as String? ?? walletNet;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        scrollable: true,
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.warning.withOpacity(0.5)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.schedule_rounded,
                    color: AppColors.warning, size: 28),
                const SizedBox(width: 10),
                const Text('Payment Pending',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 14),
              const Text(
                'Send the exact amount to the wallet address below. '
                'Once we verify your transfer, your credits will be added and you\'ll receive a confirmation email.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),

              // ── Order summary ────────────────────────────────────────
              _InfoRow(label: 'Amount to send', value: '\$$amountUsd USD'),
              _InfoRow(
                  label: 'Network',
                  value: walletNet.isNotEmpty ? walletNet : walletLabel),
              _InfoRow(label: 'Credits', value: '$credits credits'),
              _InfoRow(label: 'Payment ID', value: '#$paymentId'),
              const SizedBox(height: 16),

              // ── Wallet address box ───────────────────────────────────
              Text(walletLabel,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        walletAddr.isNotEmpty
                            ? walletAddr
                            : 'Address not configured',
                        style: TextStyle(
                          color: walletAddr.isNotEmpty
                              ? AppColors.textPrimary
                              : AppColors.error,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (walletAddr.isNotEmpty) _CopyButton(text: walletAddr),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Warning ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warningDim,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Send ONLY the exact amount on the correct network. Wrong network = lost funds.',
                      style: TextStyle(
                          color: AppColors.warning, fontSize: 12, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: AppColors.accent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Quote your Payment ID in any support message.',
                      style: TextStyle(color: AppColors.accent, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
        actions: [
          Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_rounded, size: 16),
                  label: const Text('Submit Payment Proof'),
                  onPressed: () {
                    final pid = int.tryParse(paymentId) ?? 0;
                    Navigator.of(context, rootNavigator: true).pop();
                    if (pid > 0) _showPaymentProofDialog(pid);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(color: AppColors.warning),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("I'll submit proof later"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Submit payment proof dialog ────────────────────────────────────────────
  void _showPaymentProofDialog(int paymentId) {
    showDialog(
      context: context,
      builder: (_) => _PaymentProofDialog(paymentId: paymentId),
    );
  }

  void _showSuccessDialog(int creditsAdded, double newBalance) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.success),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 56),
            const SizedBox(height: 16),
            const Text('Payment Confirmed!',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('+$creditsAdded credits added',
                style: const TextStyle(color: AppColors.success, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'Balance: ${CreditDisplay.toTime(newBalance)}  ·  '
              '${newBalance.toStringAsFixed(0)} cr',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
              child: const Text('Awesome!'),
            ),
          ),
        ],
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Full-bleed dramatic hero ───────────────────────────
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF0C0F0E), AppColors.bg],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1360),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              AppLayout.padding(context).horizontal / 2,
                              AppLayout.padding(context).vertical,
                              AppLayout.padding(context).horizontal / 2,
                              40),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('BALANCE',
                                  style: TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3)),
                              const SizedBox(height: 12),
                              Text(
                                CreditDisplay.toTime(auth.credits),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 72,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -3,
                                  height: 1,
                                ),
                              ).animate().fadeIn(),
                              const SizedBox(height: 16),
                              const Text(
                                'Add streaming time with USDT.',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1360),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal:
                                AppLayout.padding(context).horizontal / 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                  const SizedBox(height: 8),

                  // ── Pending payment banner ─────────────────────────────
                  if (_pendingPaymentId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      margin: const EdgeInsets.only(bottom: 32),
                      decoration: const BoxDecoration(
                        border: Border(
                            left: BorderSide(
                                color: AppColors.warning, width: 3)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: AppColors.warning, strokeWidth: 2.5),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Payment Pending',
                                    style: TextStyle(
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                  _pendingProvider == 'nowpayments'
                                      ? 'Complete checkout in your browser. Streaming time is added automatically after the payment settles.'
                                      : 'Awaiting manual confirmation. You\'ll receive an email when your credits are added.',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (_pendingPaymentUrl != null &&
                              _pendingPaymentUrl!.isNotEmpty)
                            TextButton(
                              onPressed: () =>
                                  _openCheckout(_pendingPaymentUrl!),
                              child: const Text('Reopen checkout'),
                            ),
                          if (_pendingProvider != 'nowpayments' &&
                              _pendingPaymentId != null)
                            TextButton.icon(
                              icon: const Icon(Icons.upload_rounded, size: 14),
                              label: const Text('Upload Proof'),
                              onPressed: () =>
                                  _showPaymentProofDialog(_pendingPaymentId!),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.accent,
                              ),
                            ),
                        ],
                      ),
                    ).animate().fadeIn(),

                  // ── Network selector (flat, no card chrome) ─────────────
                  const Text('NETWORK',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2)),
                  const SizedBox(height: 14),

                  Builder(builder: (context) {
                    if (_cryptoCurrencies.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Loading currencies…',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                        ]),
                      );
                    }
                    return _CurrencySelector(
                      currencies: _cryptoCurrencies,
                      selected: _cryptoCurrency,
                      onChanged: (c) => setState(() => _cryptoCurrency = c),
                    );
                  }).animate().fadeIn(delay: 50.ms),

                  const SizedBox(height: 12),

                  Text(
                      _feePaidByUser
                          ? 'Fees are added to your total and shown before you pay.'
                          : 'Fees and the final amount are shown before you pay.',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),

                  const SizedBox(height: 44),

                  const Text('CHOOSE A PACK',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2)),
                  const SizedBox(height: 16),

                  // ── Credit packs grid ──────────────────────────────────
                  LayoutBuilder(builder: (ctx, constraints) {
                    final cols = constraints.maxWidth >= 1120
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
                      mainAxisExtent:
                          MediaQuery.textScalerOf(context).scale(210) + 50,
                      children: _packs.asMap().entries.map((e) {
                        return _PackCard(
                          pack: e.value,
                          onBuy: () => _buyPack(e.value),
                        )
                            .animate()
                            .fadeIn(delay: Duration(milliseconds: e.key * 80));
                      }).toList(),
                    );
                  }),

                  const SizedBox(height: 36),

                  // ── Payment history ────────────────────────────────────
                  const Text('PAYMENT HISTORY',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2)),
                  const SizedBox(height: 16),

                  _history.isEmpty
                      ? const EmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: 'No payments yet',
                          subtitle: 'Your payment history will appear here',
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: _history
                                .take(10)
                                .map((p) => _PaymentRow(
                                    payment: p,
                                    onSubmitProof: p.isPending &&
                                            !p.isNowPayments &&
                                            !p.isFlutterwave
                                        ? () => _showPaymentProofDialog(p.id)
                                        : null))
                                .toList(),
                          ),
                        ),

                  if (_historyTotalPages > 1)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: _historyPage > 1
                              ? () => setState(() {
                                    _historyPage--;
                                    _loadData();
                                  })
                              : null,
                        ),
                        Text('Page $_historyPage of $_historyTotalPages',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: _historyPage < _historyTotalPages
                              ? () => setState(() {
                                    _historyPage++;
                                    _loadData();
                                  })
                              : null,
                        ),
                      ],
                    ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CURRENCY SELECTOR
// ─────────────────────────────────────────────────────────────────────────────

class _CurrencySelector extends StatelessWidget {
  final List<Map<String, String>> currencies;
  final String selected;
  final ValueChanged<String> onChanged;

  const _CurrencySelector({
    required this.currencies,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: currencies.map((c) {
        final isSelected = selected == c['id'];
        final icon = c['flag'] ?? '';
        return GestureDetector(
          onTap: () => onChanged(c['id']!),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accent : AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(right: 5),
                    child: Icon(Icons.check_circle_rounded,
                        size: 14, color: AppColors.onAccent),
                  )
                else
                  Text(icon, style: const TextStyle(fontSize: 13)),
                Flexible(
                    child: Text(c['label']!,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.onAccent
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ))),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PACK CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PackCard extends StatelessWidget {
  final CreditPack pack;
  final VoidCallback onBuy;

  const _PackCard({
    required this.pack,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = CreditDisplay.toTime(pack.credits.toDouble());

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pack.popular)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('POPULAR',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
            ),

          // Time — the hero number
          Text(
            timeStr,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(pack.description,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),

          const Spacer(),

          Text('\$${pack.priceUsd}',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),

          const SizedBox(height: 14),

          GestureDetector(
            onTap: onBuy,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Buy now',
                    style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded,
                    size: 15, color: AppColors.accent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT HISTORY ROW
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentRow extends StatelessWidget {
  final Payment payment;
  final VoidCallback? onSubmitProof;
  const _PaymentRow({required this.payment, this.onSubmitProof});

  @override
  Widget build(BuildContext context) {
    final isFw = payment.isFlutterwave;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: AdaptiveRow(
        breakpoint: 650,
        children: [
          // Gateway icon
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isFw
                  ? const Color(0xFFF5A623).withOpacity(0.1)
                  : AppColors.accentDim,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              isFw ? Icons.credit_card_rounded : Icons.currency_bitcoin_rounded,
              size: 17,
              color: isFw ? const Color(0xFFF5A623) : AppColors.accent,
            ),
          ),
          const SizedBox(width: 14),

          // Label + currency + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.packLabel,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                Text(
                  '${isFw ? 'Flutterwave' : payment.isNowPayments ? 'NOWPayments' : 'Crypto'} · '
                  '${payment.currency.toUpperCase()} · '
                  '${payment.createdAt.length >= 10 ? payment.createdAt.substring(0, 10) : payment.createdAt}',
                  style:
                      const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),

          // Amount + credits
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${payment.amountUsd}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
              Text(
                '+${CreditDisplay.toTime(payment.creditsToAdd.toDouble())}',
                style: const TextStyle(color: AppColors.success, fontSize: 11),
              ),
            ],
          ),

          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusBadge(status: payment.status),
              if (payment.isPending &&
                  !payment.isFlutterwave &&
                  onSubmitProof != null) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onSubmitProof,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentDim,
                      borderRadius: BorderRadius.circular(5),
                      border:
                          Border.all(color: AppColors.accent.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.upload_rounded,
                            size: 10, color: AppColors.accent),
                        SizedBox(width: 3),
                        Text('Upload proof',
                            style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Info row for the pending instructions dialog
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Copy-to-clipboard button used in wallet address display
// ─────────────────────────────────────────────────────────────────────────────

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _copied
            ? const Icon(Icons.check_rounded,
                key: ValueKey('check'), color: AppColors.success, size: 18)
            : const Icon(Icons.copy_rounded,
                key: ValueKey('copy'),
                color: AppColors.textSecondary,
                size: 18),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT PROOF DIALOG
// Lets the user pick an image and optionally enter a tx hash / notes,
// then uploads everything to the backend as multipart/form-data.
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentProofDialog extends StatefulWidget {
  final int paymentId;
  const _PaymentProofDialog({required this.paymentId});

  @override
  State<_PaymentProofDialog> createState() => _PaymentProofDialogState();
}

class _PaymentProofDialogState extends State<_PaymentProofDialog> {
  final _txHashController = TextEditingController();
  final _notesController = TextEditingController();

  File? _pickedFile;
  bool _submitting = false;
  String? _errorMsg;
  bool _submitted = false;

  @override
  void dispose() {
    _txHashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Pick image from gallery or camera ──────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _pickedFile = File(picked.path);
      _errorMsg = null;
    });
  }

  // ── Submit to backend ──────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_pickedFile == null) {
      setState(
          () => _errorMsg = 'Please attach a screenshot or receipt first.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });

    final result = await ApiService.instance.submitPaymentProof(
      paymentId: widget.paymentId,
      imageFile: _pickedFile!,
      txHash: _txHashController.text.trim(),
      notes: _notesController.text.trim(),
    );

    if (!mounted) return;

    final sc = result['statusCode'] as int? ?? 0;
    if (sc == 200 || sc == 201) {
      setState(() {
        _submitted = true;
        _submitting = false;
      });
    } else {
      setState(() {
        _submitting = false;
        _errorMsg = result['error'] ??
            result['detail'] ??
            'Upload failed. Please try again.';
      });
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.accent.withOpacity(0.4)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _submitted ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  // ── Success state ──────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded,
            color: AppColors.success, size: 52),
        const SizedBox(height: 14),
        const Text(
          'Proof Submitted!',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Our team will review your payment and add your credits shortly. You will receive a confirmation email once approved.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  // ── Form state ─────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(children: [
          const Icon(Icons.upload_file_rounded,
              color: AppColors.accent, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Submit Payment Proof',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                Text('Payment #${widget.paymentId}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textMuted, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Upload a screenshot or photo of your transaction receipt. Accepted: JPG, PNG, WEBP.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 18),

        // ── Image picker area ──────────────────────────────────────────────
        GestureDetector(
          onTap: () => _showPickerSheet(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: _pickedFile == null
                ? MediaQuery.textScalerOf(context).scale(145)
                : 190,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _errorMsg != null && _pickedFile == null
                    ? AppColors.error
                    : AppColors.accent.withOpacity(0.35),
                width: 1.5,
              ),
            ),
            child: _pickedFile == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add_photo_alternate_rounded,
                          color: AppColors.accent, size: 36),
                      SizedBox(height: 8),
                      Text('Tap to attach screenshot / receipt',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                      SizedBox(height: 4),
                      Text('Gallery  ·  Camera',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.file(_pickedFile!, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => setState(() => _pickedFile = null),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _showPickerSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Change',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 11)),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),

        if (_errorMsg != null && _pickedFile == null) ...[
          const SizedBox(height: 6),
          Text(_errorMsg!,
              style: const TextStyle(color: AppColors.error, fontSize: 12)),
        ],

        const SizedBox(height: 16),

        // ── Transaction hash (optional) ────────────────────────────────────
        const Text('Transaction Hash / ID  (optional)',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _txHashController,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'e.g. 0xabc123...',
            hintStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 12),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Notes (optional) ───────────────────────────────────────────────
        const Text('Additional Notes  (optional)',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesController,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Any extra info to help us verify faster…',
            hintStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 12),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
          ),
        ),

        // ── Generic error ──────────────────────────────────────────────────
        if (_errorMsg != null && _pickedFile != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 15),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_errorMsg!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12))),
            ]),
          ),
        ],

        const SizedBox(height: 20),

        // ── Submit button ──────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.upload_rounded, size: 16),
            label: Text(_submitting ? 'Uploading…' : 'Submit Proof'),
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Bottom sheet for gallery / camera choice ───────────────────────────────
  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.accentDim,
                child:
                    Icon(Icons.photo_library_rounded, color: AppColors.accent),
              ),
              title: const Text('Choose from Gallery',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500)),
              subtitle: const Text('Pick a saved screenshot',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.accentDim,
                child: Icon(Icons.camera_alt_rounded, color: AppColors.accent),
              ),
              title: const Text('Take a Photo',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500)),
              subtitle: const Text('Photograph your receipt',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}