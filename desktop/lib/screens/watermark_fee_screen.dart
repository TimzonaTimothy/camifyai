import '../widgets/responsive_layout.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

class WatermarkFeeScreen extends StatefulWidget {
  const WatermarkFeeScreen({super.key});

  @override
  State<WatermarkFeeScreen> createState() => _WatermarkFeeScreenState();
}

class _WatermarkFeeScreenState extends State<WatermarkFeeScreen> {
  bool _loading = true;
  bool _paid = false;
  bool _hasPending = false;

  String? _feeUsd;

  List<Map<String, dynamic>> _methods = [];
  Map<String, dynamic>? _selectedMethod;

  File? _proofImage;
  final _txHashCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  String? _submitError;
  bool _submitSuccess = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _txHashCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.getWatermarkFeeStatus(),
        ApiService.instance.getWatermarkPaymentMethods(),
      ]);
      final statusData = results[0] as Map<String, dynamic>;
      final methodsList = results[1] as List<dynamic>;
      setState(() {
        _paid = statusData['paid'] == true;
        _hasPending = statusData['pending_payment'] == true;
        _feeUsd = statusData['fee_usd']?.toString();
        _methods = methodsList
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _selectedMethod = _methods.isNotEmpty ? _methods.first : null;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _proofImage = File(picked.path));
  }

  Future<void> _submit() async {
    if (_proofImage == null) {
      setState(() => _submitError = 'Please attach a payment screenshot.');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final result = await ApiService.instance.submitWatermarkFeeProof(
      imageFile: _proofImage!,
      methodId: _selectedMethod?['id']?.toString(),
      txHash: _txHashCtrl.text.trim().isEmpty ? null : _txHashCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    setState(() {
      _submitting = false;
      if (result['statusCode'] == 201) {
        _submitSuccess = true;
        _hasPending = true;
      } else {
        _submitError = result['error'] as String? ??
            result['detail'] as String? ??
            'Submission failed. Please try again.';
      }
    });
  }

  void _copyAddress() {
    final addr = _selectedMethod?['address'] as String? ?? '';
    if (addr.isEmpty) return;
    Clipboard.setData(ClipboardData(text: addr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Address copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String get _feeLabel => _feeUsd != null ? '\$$_feeUsd USD' : '...';
  String get _feeShort => _feeUsd != null ? '\$$_feeUsd' : '...';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => context.go('/dashboard'),
        ),
        title: const Text(
          'Watermark Removal Fee',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : _paid
              ? _buildPaid()
              : _buildFlow(),
    );
  }

  Widget _buildPaid() {
    return SingleChildScrollView(
        child: Center(
      child: Padding(
        padding: AppLayout.padding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded,
                size: 72, color: AppColors.success),
            const SizedBox(height: 20),
            const Text(
              'Watermark Fee Paid ✓',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your account is using the clean API key.\n'
              'Your outputs no longer have a watermark.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            TextButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildFlow() {
    return AppPage(
      padding: AppLayout.padding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _noticeCard(),
          const SizedBox(height: 24),
          if (!_submitSuccess) ...[
            _label('Fee Amount'),
            _infoTile(Icons.attach_money_rounded,
                'One-time watermark removal fee', _feeLabel, true),
            const SizedBox(height: 24),
            _label('1. Choose Payment Method'),
            const SizedBox(height: 8),
            _methods.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      'No payment methods configured yet. '
                      'Please contact support.',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _methods.map((m) {
                      final sel = _selectedMethod?['id'] == m['id'];
                      return GestureDetector(
                        onTap: () => setState(() => _selectedMethod = m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.accent.withOpacity(0.12)
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: sel ? AppColors.accent : AppColors.border,
                              width: sel ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m['icon_emoji'] ?? '💵',
                                  style: const TextStyle(fontSize: 15)),
                              const SizedBox(width: 7),
                              Text(
                                m['name'] ?? '',
                                style: TextStyle(
                                  color: sel
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight:
                                      sel ? FontWeight.w700 : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 20),
            if (_selectedMethod != null) ...[
              _label('2. Send exactly $_feeShort to this address'),
              const SizedBox(height: 8),
              _addressCard(),
              const SizedBox(height: 24),
            ],
            _label('3. Upload Payment Screenshot'),
            const SizedBox(height: 4),
            const Text(
              'Choose your receipt or transaction screenshot from gallery.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            _imagePicker(),
            const SizedBox(height: 20),
            _label('Transaction Hash (optional)'),
            const SizedBox(height: 6),
            _textField(_txHashCtrl, 'Paste your TX hash / ID'),
            const SizedBox(height: 14),
            _label('Notes (optional)'),
            const SizedBox(height: 6),
            _textField(_notesCtrl, 'Any extra info for the admin…',
                maxLines: 3),
            const SizedBox(height: 24),
            if (_submitError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorDim,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withOpacity(0.4)),
                ),
                child: Text(_submitError!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 13)),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                  disabledBackgroundColor: AppColors.accent.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontFamily: 'Inter', 
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onAccent),
                      )
                    : Text('Submit Proof — $_feeShort Fee'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Widget _noticeCard() {
    if (_submitSuccess) {
      return _card(
          AppColors.success,
          AppColors.successDim,
          Icons.check_circle_rounded,
          'Proof submitted!',
          'An admin will review your payment and activate your account '
              'within 24 hours.');
    }
    if (_hasPending) {
      return _card(
          AppColors.warning,
          AppColors.warningDim,
          Icons.hourglass_top_rounded,
          'Proof under review',
          'Your payment proof is waiting for admin confirmation. '
              'Once confirmed your watermark will be removed.');
    }
    return _card(
        const Color(0xFFE8A020),
        const Color(0x22E8A020),
        Icons.info_outline_rounded,
        'One-time $_feeShort fee',
        'Starting 1st July, accounts that have not paid the watermark '
            'removal fee will have a watermark on their outputs. '
            'Pay once to remove it permanently.');
  }

  Widget _card(Color c, Color dim, IconData icon, String title, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dim,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: c, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      );

  Widget _infoTile(IconData icon, String label, String value, bool highlight) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight ? AppColors.accent.withOpacity(0.08) : AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              highlight ? AppColors.accent.withOpacity(0.3) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: highlight ? AppColors.accent : AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13))),
          Text(value,
              style: TextStyle(
                  color: highlight ? AppColors.accent : AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _addressCard() {
    final addr = _selectedMethod?['address'] as String? ?? '';
    final extraInfo = _selectedMethod?['extra_info'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_selectedMethod?['icon_emoji'] ?? ''} '
            '${_selectedMethod?['name'] ?? ''}',
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  addr,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _copyAddress,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.copy_rounded,
                      size: 14, color: AppColors.accent),
                ),
              ),
            ],
          ),
          if (extraInfo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                extraInfo,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _imagePicker() {
    if (_proofImage != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(_proofImage!,
                width: double.infinity, height: 180, fit: BoxFit.cover),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Change',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 130),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined,
                color: AppColors.accent, size: 28),
            SizedBox(height: 8),
            Text(
              'Tap to choose screenshot from gallery',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            SizedBox(height: 2),
            Text(
              'JPG or PNG',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String hint,
      {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}
