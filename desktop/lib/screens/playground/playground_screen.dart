import '../../widgets/responsive_layout.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../utils/credit_display.dart';
import '../../utils/error_handler.dart';

class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // _tabController = TabController(length: 3, vsync: this);
    _tabController = TabController(length: 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101313),
      body: Padding(
        padding: AppLayout.padding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Live studio',
              subtitle:
                  'Choose your look. Step in front of the camera. Make it yours.',
            ).animate().fadeIn(),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF191E1D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF303936)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFFC9EF9C),
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: const Color(0xFFC9EF9C),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Create a live look'),
                  // Tab(text: '🎬 Video Generation'),
                  // Tab(text: '🖼️ Image Generation'),
                ],
              ),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 24),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                // children: const [
                //   _RealtimeTab(),
                //   _VideoTab(),
                //   _ImageTab(),
                // ],
                children: const [
                  _RealtimeTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FACE IMAGE UPLOAD WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class FaceImageUploader extends StatelessWidget {
  final File? imageFile;
  final VoidCallback onPickImage;
  final VoidCallback? onRemoveImage;

  const FaceImageUploader({
    super.key,
    required this.imageFile,
    required this.onPickImage,
    this.onRemoveImage,
  });

  @override
  Widget build(BuildContext context) {
    if (imageFile != null) {
      return Stack(
        children: [
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Color(0xFFC9EF9C), width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.file(
                imageFile!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 180,
              ),
            ),
          ),
          // Bottom overlay with change/remove
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(11),
                  bottomRight: Radius.circular(11),
                ),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: onPickImage,
                    icon: const Icon(Icons.swap_horiz_rounded,
                        size: 14, color: Colors.white),
                    label: const Text('Change',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  TextButton.icon(
                    onPressed: onRemoveImage,
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 14, color: AppColors.error),
                    label: const Text('Remove',
                        style: TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
          // Success badge top right
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text('Face ready',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      )
          .animate()
          .fadeIn(duration: 300.ms)
          .scale(begin: const Offset(0.95, 0.95));
    }

    // Empty drop zone
    return GestureDetector(
      onTap: onPickImage,
      child: DottedBorder(
        color: Color(0xFF303936),
        strokeWidth: 1.5,
        dashPattern: const [8, 4],
        borderType: BorderType.RRect,
        radius: const Radius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 210),
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Color(0xFF111613),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFF253421),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.face_rounded,
                    color: Color(0xFFC9EF9C), size: 32),
              ),
              const SizedBox(height: 12),
              const Text(
                'Upload Face Image',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Click to browse  ·  JPG, PNG, WEBP',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: Color(0xFF253421),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFFC9EF9C).withOpacity(0.4)),
                ),
                child: const Text(
                  'Browse Files',
                  style: TextStyle(
                    color: Color(0xFFC9EF9C),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REALTIME TAB
// ─────────────────────────────────────────────────────────────────────────────

class _RealtimeTab extends StatefulWidget {
  const _RealtimeTab();

  @override
  State<_RealtimeTab> createState() => _RealtimeTabState();
}

class _RealtimeTabState extends State<_RealtimeTab> {
  final String _selectedModel = 'x2.1';
  String? _error;

  // Face image state
  File? _faceImage;
  String? _faceImageBase64;
  String? _faceImageName;

  final _promptCtrl = TextEditingController();

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFaceImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final picked = result.files.first;
      if (picked.path == null) {
        throw const FileSystemException(
            'The selected image could not be opened.');
      }

      final file = File(picked.path!);
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _faceImage = file;
        _faceImageBase64 = base64Encode(bytes);
        _faceImageName = picked.name;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Image picker failed: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Could not open the image picker or read the selected image. Please try again.')),
      );
    }
  }

  void _removeFaceImage() {
    setState(() {
      _faceImage = null;
      _faceImageBase64 = null;
      _faceImageName = null;
    });
  }

  Future<void> _getToken() async {
    final auth = context.read<AuthProvider>();

    // Minimum to start = 1 heartbeat (20 credits = 10 seconds at 2cr/sec)
    // Credits work regardless of which plan the user is on —
    // 2000 credits on Starter = 2000 credits of streaming time (1000 seconds)
    // Face image is OPTIONAL for x2.1, only required for live_avatar
    if (auth.credits < 20) {
      setState(() => _error =
          'Not enough credits. You need at least 20 credits to start streaming.');
      return;
    }

    // Navigate to the dedicated /stream route (registered in GoRouter)
    // This avoids ShellRoute interference entirely
    if (!mounted) return;
    context.go('/stream', extra: {
      'model': _selectedModel,
      'prompt':
          _promptCtrl.text.trim().isEmpty ? null : _promptCtrl.text.trim(),
      'faceImageBase64': _faceImageBase64,
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    const ink = Color(0xFFF1F5EE);
    const muted = Color(0xFFA0ACA6);
    const accent = Color(0xFFC9EF9C);
    const surface = Color(0xFF191E1D);
    const border = Color(0xFF303936);

    final configuration = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('01 / YOUR LOOK',
              style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          const Text('A new face.\nStill your expression.',
              style: TextStyle(
                  color: ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  letterSpacing: -0.8)),
          const SizedBox(height: 10),
          const Text(
              'Choose a clear portrait. We’ll apply it to your camera automatically when you enter the studio.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.7)),
          const SizedBox(height: 24),
          FaceImageUploader(
              imageFile: _faceImage,
              onPickImage: _pickFaceImage,
              onRemoveImage: _removeFaceImage),
          if (_faceImageName != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.check_circle_outline_rounded,
                  size: 14, color: accent),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_faceImageName!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 11))),
            ]),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: const Color(0xFF111613),
                borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Icon(Icons.schedule_rounded, color: accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(CreditDisplay.toTime(auth.credits),
                        style: const TextStyle(
                            color: ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w600)),
                    const Text('of streaming time available',
                        style: TextStyle(color: muted, fontSize: 11)),
                  ])),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _faceImage == null ? null : _getToken,
                style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: const Color(0xFF162015),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.arrow_outward_rounded, size: 18),
                label: const Text('Enter live studio',
                    textAlign: TextAlign.center),
              )),
          const SizedBox(height: 12),
          Text(
              _faceImage == null
                  ? 'Add a portrait to get started.'
                  : 'Your browser will ask for camera access.',
              style: const TextStyle(color: muted, fontSize: 11)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ],
      ),
    );

    final preview = Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF253026), Color(0xFF101613)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('02 / MAKE IT LIVE',
            style: TextStyle(
                color: accent,
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 22),
        Container(
          height: MediaQuery.textScalerOf(context).scale(270),
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: const Color(0xFF0D120F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border)),
          child: _faceImage != null
              ? Image.file(_faceImage!, fit: BoxFit.contain)
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                      Icon(Icons.face_retouching_natural_rounded,
                          size: 56, color: accent),
                      SizedBox(height: 20),
                      Text('The next version of you',
                          style: TextStyle(
                              color: ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.5)),
                      SizedBox(height: 8),
                      Text('Your portrait will appear here.',
                          style: TextStyle(color: muted, fontSize: 12)),
                    ]),
        ),
        const SizedBox(height: 26),
        const Text('Made for the moment.',
            style: TextStyle(
                color: ink,
                fontSize: 25,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.6)),
        const SizedBox(height: 10),
        const Text(
            'Your expressions, movement and personality — with a whole new look. The studio handles the transformation while you stay in the moment.',
            style: TextStyle(color: muted, fontSize: 13, height: 1.8)),
        const SizedBox(height: 24),
        const Divider(color: border),
        const SizedBox(height: 18),
        const Wrap(spacing: 22, runSpacing: 12, children: [
          Text('✓ Face applied automatically',
              style: TextStyle(color: accent, fontSize: 11)),
          Text('↗ Separate output for OBS',
              style: TextStyle(color: muted, fontSize: 11)),
        ]),
      ]),
    );

    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
          child: constraints.maxWidth < 820
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      configuration,
                      const SizedBox(height: 20),
                      preview
                    ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 4, child: configuration),
                  const SizedBox(width: 24),
                  Expanded(flex: 6, child: preview),
                ]));
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIDEO TAB
// ─────────────────────────────────────────────────────────────────────────────

class _VideoTab extends StatefulWidget {
  const _VideoTab();

  @override
  State<_VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<_VideoTab> {
  final _promptCtrl = TextEditingController();
  String _selectedModel = 'lucy-pro-t2v';
  String _resolution = '720p';
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_promptCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a prompt.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ApiService.instance.generateVideo(
        prompt: _promptCtrl.text.trim(),
        model: _selectedModel,
        resolution: _resolution,
      );
      if (result['statusCode'] == 200) {
        setState(() => _result = result);
        if (mounted) {
          context
              .read<AuthProvider>()
              .updateCredits((result['credits_remaining'] as num).toDouble());
        }
      } else {
        setState(() => _error = result['error'] ?? 'Generation failed.');
      }
    } catch (e) {
      setState(() => _error = ErrorHandler.sanitize(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Configuration',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
                const SizedBox(height: 20),
                const Text('Prompt',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _promptCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      hintText: 'A cat walking in a lego world...'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Model',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _selectedModel,
                            dropdownColor: AppColors.card,
                            decoration: const InputDecoration(),
                            items: const [
                              DropdownMenuItem(
                                  value: 'lucy-pro-t2v',
                                  child: Text('Lucy (T2V)')),
                              DropdownMenuItem(
                                  value: 'lucy-edit', child: Text('Lucy Edit')),
                              DropdownMenuItem(
                                  value: 'lucy-motion',
                                  child: Text('Lucy Motion')),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedModel = v!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Resolution',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _resolution,
                            dropdownColor: AppColors.card,
                            decoration: const InputDecoration(),
                            items: const [
                              DropdownMenuItem(
                                  value: '720p', child: Text('720p')),
                              DropdownMenuItem(
                                  value: '1080p', child: Text('1080p')),
                            ],
                            onChanged: (v) => setState(() => _resolution = v!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Generate Video  (100 credits)',
                    icon: Icons.videocam_rounded,
                    loading: _loading,
                    onPressed: _generate,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 5,
          child:
              _ResultPanel(loading: _loading, result: _result, error: _error),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE TAB
// ─────────────────────────────────────────────────────────────────────────────

class _ImageTab extends StatefulWidget {
  const _ImageTab();

  @override
  State<_ImageTab> createState() => _ImageTabState();
}

class _ImageTabState extends State<_ImageTab> {
  final _promptCtrl = TextEditingController();
  String _selectedModel = 'lucy-image';
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_promptCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a prompt.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ApiService.instance.generateImage(
        prompt: _promptCtrl.text.trim(),
        model: _selectedModel,
      );
      if (result['statusCode'] == 200) {
        setState(() => _result = result);
        if (mounted) {
          context
              .read<AuthProvider>()
              .updateCredits((result['credits_remaining'] as num).toDouble());
        }
      } else {
        setState(() => _error = result['error'] ?? 'Generation failed.');
      }
    } catch (e) {
      setState(() => _error = ErrorHandler.sanitize(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Configuration',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
                const SizedBox(height: 20),
                const Text('Prompt',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _promptCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      hintText: 'A sunset over the ocean...'),
                ),
                const SizedBox(height: 16),
                const Text('Model',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedModel,
                  dropdownColor: AppColors.card,
                  decoration: const InputDecoration(),
                  items: const [
                    DropdownMenuItem(
                        value: 'lucy-image', child: Text('Lucy Image (T2I)')),
                    DropdownMenuItem(
                        value: 'lucy-image-edit',
                        child: Text('Lucy Image Edit')),
                  ],
                  onChanged: (v) => setState(() => _selectedModel = v!),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Generate Image  (10 credits)',
                    icon: Icons.image_rounded,
                    loading: _loading,
                    onPressed: _generate,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 5,
          child:
              _ResultPanel(loading: _loading, result: _result, error: _error),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESULT PANEL
// ─────────────────────────────────────────────────────────────────────────────

class _ResultPanel extends StatelessWidget {
  final bool loading;
  final Map<String, dynamic>? result;
  final String? error;
  final bool isRealtime;
  final File? faceImageFile;

  const _ResultPanel({
    required this.loading,
    required this.result,
    required this.error,
    this.isRealtime = false,
    this.faceImageFile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Response',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
              const Spacer(),
              // Show face thumbnail in header when uploaded
              if (isRealtime && faceImageFile != null)
                Row(
                  children: [
                    const Text('Face: ',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.file(
                        faceImageFile!,
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 14),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                            color: AppColors.accent, strokeWidth: 2),
                        SizedBox(height: 16),
                        Text('Processing...',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  )
                : error != null
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.errorDim,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.error.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    color: AppColors.error, size: 16),
                                SizedBox(width: 8),
                                Text('Error',
                                    style: TextStyle(
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(error!,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
                          ],
                        ),
                      ).animate().shake()
                    : result == null
                        ? EmptyState(
                            icon: isRealtime
                                ? Icons.stream_rounded
                                : Icons.play_arrow_rounded,
                            title:
                                isRealtime ? 'Ready to stream' : 'Ready to run',
                            subtitle: isRealtime
                                ? 'Upload a face image, pick a model, get your token'
                                : 'Configure your request and press the button',
                          )
                        : _ResultContent(
                            result: result!, isRealtime: isRealtime),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESULT CONTENT
// ─────────────────────────────────────────────────────────────────────────────

class _ResultContent extends StatelessWidget {
  final Map<String, dynamic> result;
  final bool isRealtime;

  const _ResultContent({required this.result, required this.isRealtime});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.successDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isRealtime
                        ? 'Token issued — face swap is ready'
                        : 'Generated successfully',
                    style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '–${result['credits_deducted']} credits',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ).animate().fadeIn(),
          if (isRealtime && result['token'] != null) ...[
            const Text('Temporary API Token',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            CopyField(
                value: result['token'] as String, label: 'Token', secret: true),
            const SizedBox(height: 12),
            if (result['expires_at'] != null)
              Text('Expires: ${result['expires_at']}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.face_rounded,
                          color: AppColors.accent, size: 14),
                      SizedBox(width: 6),
                      Text('Using token for face swap:',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _step('1', 'Use this token as api_key in the streaming SDK'),
                  _step('2', 'Pass your face image in the stream initialState'),
                  _step(
                      '3', 'Call RealtimeClient.connect() to start streaming'),
                  _step('4', 'Your face is swapped live on every frame'),
                ],
              ),
            ),
          ],
          if (!isRealtime &&
              (result['video_url'] != null || result['image_url'] != null)) ...[
            const Text('Output URL',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            CopyField(
              value: (result['video_url'] ?? result['image_url']) as String,
              label: 'URL',
            ),
          ],
          const SizedBox(height: 16),
          const Text('Raw Response',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              _formatJson(result),
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
                color: AppColors.accentDim, shape: BoxShape.circle),
            child: Center(
              child: Text(n,
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _formatJson(Map<String, dynamic> json) {
    final b = StringBuffer('{\n');
    json.forEach((k, v) {
      if (k == 'statusCode') return;
      final val = v is String ? '"$v"' : v.toString();
      b.writeln('  "$k": $val,');
    });
    b.write('}');
    return b.toString();
  }
}
