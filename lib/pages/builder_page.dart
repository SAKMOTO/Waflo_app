import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:waflo_app/controllers/chat_history_controller.dart';
import 'package:waflo_app/pages/main_page.dart';
import 'package:waflo_app/services/builder_web_service.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/widgets/chat_history_sidebar.dart';
import 'package:waflo_app/widgets/project_preview_sheet.dart';
import 'package:waflo_app/widgets/side_bar.dart';

enum _BuilderStage { idle, running, done, error }

/// ✨ Waflo Builder — generate small, self-contained static projects from a
/// prompt (or an analysed website) on the backend, with live progress.
class BuilderPage extends StatefulWidget {
  const BuilderPage({super.key});

  @override
  State<BuilderPage> createState() => _BuilderPageState();
}

class _BuilderPageState extends State<BuilderPage> {
  static const List<String> _steps = [
    'Analyzing',
    'Planning',
    'Generating',
    'Validating',
    'Ready',
  ];

  static const List<String> _examples = [
    'A landing page for a small coffee roastery',
    'A personal portfolio with projects and contact',
    'A fitness tracker dashboard with daily goals',
    'A restaurant menu with categories and prices',
  ];

  final BuilderWebService _service = BuilderWebService();

  _BuilderStage _stage = _BuilderStage.idle;
  String _mode = 'prompt'; // 'prompt' | 'url'
  bool _historyOpen = false;

  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  String _jobId = '';
  String _status = 'queued';
  int _stepIndex = 0;
  int _progress = 0;
  String _message = '';
  String _error = '';

  String _projectId = '';
  String _title = '';
  List<String> _files = const <String>[];

  StreamSubscription<Map<String, dynamic>>? _progressSub;
  Timer? _pollTimer;

  @override
  void dispose() {
    _stopWatching();
    _promptController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Navigation (mirrors Home/Commerce wiring)
  // ---------------------------------------------------------------------------

  void _handleNavigation(int index) {
    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/home');
    } else if (index == 1) {
      Navigator.pushNamed(context, '/commerce');
    }
  }

  void _goMain() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainPage()),
    );
  }

  void _toggleHistory() {
    setState(() => _historyOpen = !_historyOpen);
    if (_historyOpen) {
      unawaited(ChatHistoryController.instance.refreshConversations());
    }
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (_mode == 'prompt') {
      if (prompt.length < 8) {
        _toast('Tell me a bit more — describe your app idea (min 8 characters).');
        return;
      }
    } else {
      final url = _urlController.text.trim();
      final parsed = Uri.tryParse(url);
      if (parsed == null ||
          !(parsed.scheme == 'http' || parsed.scheme == 'https')) {
        _toast('Enter a valid http:// or https:// website URL.');
        return;
      }
    }

    setState(() {
      _stage = _BuilderStage.running;
      _jobId = '';
      _status = 'queued';
      _stepIndex = 0;
      _progress = 5;
      _message = 'Queued…';
      _error = '';
    });

    try {
      final created = await _service.createGeneration(
        prompt: prompt,
        url: _mode == 'url' ? _urlController.text.trim() : null,
        mode: _mode,
      );
      if (!mounted) return;
      _jobId = created['job_id'] as String;
      _startWatching();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _BuilderStage.error;
        _error = 'Could not reach the Waflo Builder backend.\n'
            'Start the backend (server/main.py on port 8000) and try again. '
            '($e)';
      });
    }
  }

  /// Live progress over the WebSocket plus a polling safety-net so the UI
  /// stays in sync even if the socket drops (e.g. backend restart).
  void _startWatching() {
    _stopWatching();
    _progressSub = _service
        .progressStream(_jobId)
        .listen(_applyProgress, onError: (_) {});

    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      unawaited(_poll());
    });
  }

  void _stopWatching() {
    _progressSub?.cancel();
    _progressSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    try {
      final job = await _service.fetchJob(_jobId);
      if (!mounted) return;
      if (_stage != _BuilderStage.running) return;
      _applyProgress(job);
    } catch (_) {
      // Backend temporarily unreachable — the WebSocket will resync when it
      // comes back.
    }
  }

  void _applyProgress(Map<String, dynamic> data) {
    final status = (data['status'] as String?) ?? _status;
    final stepIndex = (data['step_index'] as int?) ?? _stepIndex;
    final progress = (data['progress'] as int?) ?? _progress;
    final message = ((data['message'] as String?) ?? _message).trim();

    setState(() {
      _status = status;
      _stepIndex = stepIndex;
      _progress = progress;
      _message = message.isEmpty ? _message : message;
    });

    if (status == 'completed') {
      _stopWatching();
      unawaited(_finish());
    } else if (status == 'failed') {
      _stopWatching();
      setState(() {
        _stage = _BuilderStage.error;
        _error = (data['error'] as String?) ??
            'Builder couldn\'t complete this generation.';
      });
    } else if (status == 'cancelled') {
      _stopWatching();
      _toast('Generation cancelled.');
      setState(() {
        _stage = _BuilderStage.idle;
        _jobId = '';
        _progress = 0;
        _stepIndex = 0;
        _message = '';
      });
    }
  }

  Future<void> _finish() async {
    try {
      final job = await _service.fetchJob(_jobId);
      if (!mounted) return;
      final project = job['project'] as Map<String, dynamic>?;
      final title = project?['title'] as String? ?? 'Your project';
      final files = (project?['files'] as List?)?.cast<String>() ??
          const <String>[];
      setState(() {
        _stage = _BuilderStage.done;
        _projectId = project?['project_id'] as String? ?? _jobId;
        _title = title;
        _files = files;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _BuilderStage.done;
        _projectId = _jobId;
        _title = 'Your project';
        _files = const <String>[];
      });
    }
  }

  Future<void> _cancel() async {
    if (_jobId.isEmpty) return;
    setState(() => _message = 'Cancelling…');
    final ok = await _service.cancelJob(_jobId);
    if (!mounted) return;
    if (!ok) _toast('Job already finished.');
  }

  void _reset() {
    _stopWatching();
    setState(() {
      _stage = _BuilderStage.idle;
      _jobId = '';
      _status = 'queued';
      _stepIndex = 0;
      _progress = 0;
      _message = '';
      _error = '';
      _projectId = '';
      _title = '';
      _files = const <String>[];
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.cardColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          sidebar(
            onNavigate: _handleNavigation,
            onNavigateMain: _goMain,
            selectedIndex: 3,
            chatHistoryExpanded: _historyOpen,
            onChatHistoryToggle: _toggleHistory,
          ),
          ChatHistorySidebar(open: _historyOpen, onToggle: _toggleHistory),
          Expanded(
            child: Container(
              color: AppColors.background,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(),
                        const SizedBox(height: 24),
                        switch (_stage) {
                          _BuilderStage.idle => _buildIdle(),
                          _BuilderStage.running => _buildRunning(),
                          _BuilderStage.done => _buildDone(),
                          _BuilderStage.error => _buildError(),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.submitButton.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.auto_awesome,
            color: AppColors.submitButton,
            size: 28,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Waflo Builder',
                style: GoogleFonts.ibmPlexMono(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Describe an app — or drop a website URL — and Waflo will plan '
                'and build a self-contained project for you.',
                style: GoogleFonts.inter(
                  color: AppColors.textGrey,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------- Idle -------

  Widget _buildIdle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Working-from-home hero animation on the Builder main screen.
        Center(
          child: Lottie.asset(
            'assets/builder_home.json',
            width: 320,
            height: 320,
            fit: BoxFit.contain,
            repeat: true,
            animate: true,
          ),
        ),
        const SizedBox(height: 8),
        _modeSwitcher(),
        const SizedBox(height: 20),
        if (_mode == 'url') ...[
          _urlField(),
          const SizedBox(height: 16),
        ],
        _promptField(),
        const SizedBox(height: 18),
        if (_mode == 'prompt') _exampleChips(),
        const SizedBox(height: 24),
        _primaryButton(
          'Generate project',
          icon: Icons.rocket_launch,
          onPressed: _generate,
        ),
        const SizedBox(height: 12),
        Text(
          'Generated projects are saved to generated_projects/ in the backend '
          'folder — they never run inside Waflo. No API keys are shared.',
          style: GoogleFonts.inter(color: AppColors.footerGrey, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _modeSwitcher() {
    return Row(
      children: [
        _modeChip('prompt', 'From an idea', Icons.lightbulb_outline),
        const SizedBox(width: 12),
        _modeChip('url', 'From a website', Icons.link),
      ],
    );
  }

  Widget _modeChip(String value, String label, IconData icon) {
    final selected = _mode == value;
    return GestureDetector(
      onTap: () => setState(() => _mode = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.submitButton.withOpacity(0.18)
              : AppColors.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.submitButton : AppColors.searchBarBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? AppColors.submitButton : AppColors.textGrey, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? Colors.white : AppColors.textGrey,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _urlField() {
    return TextField(
      controller: _urlController,
      keyboardType: TextInputType.url,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: _inputDecoration(
        'Website URL',
        hint: 'https://example.com',
        icon: Icons.public,
      ),
    );
  }

  Widget _promptField() {
    return TextField(
      controller: _promptController,
      minLines: 4,
      maxLines: 6,
      maxLength: 1000,
      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
      decoration: _inputDecoration(
        _mode == 'url'
            ? 'What should the rebuilt app do?'
            : 'Describe your app or idea…',
        hint: _mode == 'url'
            ? 'e.g. Reimagine this page as a clean dark landing with the '
                'same sections but a fresh layout'
            : 'e.g. A landing page for a coffee roastery with a hero, '
                'menu, and contact section',
        icon: Icons.edit_outlined,
      ).copyWith(
        counterStyle: TextStyle(color: AppColors.footerGrey, fontSize: 11),
      ),
    );
  }

  Widget _exampleChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final example in _examples)
          GestureDetector(
            onTap: () => _promptController.text = example,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                example.length > 42 ? '${example.substring(0, 42)}…' : example,
                style: GoogleFonts.inter(
                  color: AppColors.textGrey,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ------- Running -------

  Widget _buildRunning() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.submitButton,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _message.isEmpty ? 'Working on it…' : _message,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _steps.length; i++) _stepRow(i),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (_progress / 100).clamp(0.02, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.searchBarBorder,
              color: AppColors.submitButton,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_progress%',
            style: GoogleFonts.inter(
              color: AppColors.textGrey,
              fontSize: 12,
            ),
            textAlign: TextAlign.end,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepRow(int index) {
    final current = index == _stepIndex;
    final done = index < _stepIndex ||
        (_stepIndex >= 4 && index == 4 && _progress >= 100);
    final active = current || done;

    final IconData icon;
    final Color color;
    if (done) {
      icon = Icons.check_circle;
      color = Colors.greenAccent;
    } else if (current) {
      icon = Icons.radio_button_checked;
      color = AppColors.submitButton;
    } else {
      icon = Icons.radio_button_unchecked;
      color = AppColors.footerGrey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Text(
            _steps[index],
            style: GoogleFonts.inter(
              color: active ? Colors.white : AppColors.footerGrey,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ------- Done -------

  Widget _buildDone() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.greenAccent,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            _title,
            style: GoogleFonts.ibmPlexMono(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _projectId.isEmpty ? 'Project ready' : 'Project $_projectId',
            style: GoogleFonts.inter(
              color: AppColors.textGrey,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          if (_files.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final f in _files)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.submitButton.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      f,
                      style: GoogleFonts.robotoMono(
                        color: AppColors.submitButton,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _files.isEmpty ? null : _openCodeViewer,
                style: _raisedStyle(),
                icon: const Icon(Icons.code),
                label: const Text('View Code'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _openPreview,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: AppColors.searchBarBorder),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Open Preview'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _reset,
                child: Text(
                  'Build Another',
                  style: TextStyle(color: AppColors.textGrey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------- Error -------

  Widget _buildError() {
    final friendly = _error.isEmpty
        ? 'Builder couldn\'t complete this generation.'
        : _error;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 44),
          const SizedBox(height: 12),
          Text(
            'Builder couldn\'t complete this generation.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 17,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          SelectableText(
            friendly,
            style: GoogleFonts.inter(color: AppColors.textGrey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _reset,
                style: _raisedStyle(),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/home'),
                child: Text(
                  'Back',
                  style: TextStyle(color: AppColors.textGrey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _openCodeViewer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CodeViewerSheet(
        projectId: _projectId,
        files: _files,
      ),
    );
  }

  void _openPreview() {
    if (_projectId.isEmpty) {
      _toast('No built project to preview yet.');
      return;
    }
    final url =
        '${BuilderWebService.baseUrl}/api/builder/projects/$_projectId/preview/';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProjectPreviewSheet(previewUrl: url, title: _title),
    );
  }

  // ---------------------------------------------------------------------------
  // Widget helpers
  // ---------------------------------------------------------------------------

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.searchBarBorder),
      ),
      child: child,
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(color: AppColors.textGrey, fontSize: 14),
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: AppColors.footerGrey, fontSize: 13),
      filled: true,
      fillColor: AppColors.background,
      prefixIcon: Icon(icon, color: AppColors.textGrey, size: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.searchBarBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.submitButton, width: 1.5),
      ),
    );
  }

  Widget _primaryButton(String label, {required IconData icon, required VoidCallback onPressed}) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: _raisedStyle(),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  ButtonStyle _raisedStyle() {
    return FilledButton.styleFrom(
      backgroundColor: AppColors.submitButton,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

/// Minimal in-app code viewer for a generated project. Fetches file contents
/// on demand from the backend (files live in `generated_projects/<id>/source/`).
class _CodeViewerSheet extends StatefulWidget {
  const _CodeViewerSheet({required this.projectId, required this.files});

  final String projectId;
  final List<String> files;

  @override
  State<_CodeViewerSheet> createState() => _CodeViewerSheetState();
}

class _CodeViewerSheetState extends State<_CodeViewerSheet> {
  String? _selected;
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.files.isNotEmpty) {
      _selected = widget.files.first;
      _load(_selected!);
    } else {
      _loading = false;
    }
  }

  Future<void> _load(String path) async {
    setState(() {
      _selected = path;
      _loading = true;
    });
    final file =
        await BuilderWebService().fetchProjectFile(widget.projectId, path);
    if (!mounted) return;
    setState(() {
      _content = file?['content'] as String? ?? '// Could not load file.';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.72;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Text(
                  'Generated files',
                  style: GoogleFonts.ibmPlexMono(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          if (widget.files.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in widget.files)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f),
                        selected: _selected == f,
                        onSelected: (_) => _load(f),
                        selectedColor: AppColors.submitButton.withOpacity(0.25),
                        backgroundColor: AppColors.background,
                        labelStyle: GoogleFonts.robotoMono(
                          color: _selected == f
                              ? AppColors.submitButton
                              : AppColors.textGrey,
                          fontSize: 12,
                        ),
                        side: BorderSide(
                          color: _selected == f
                              ? AppColors.submitButton
                              : AppColors.searchBarBorder,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.submitButton,
                      ),
                    )
                  : SingleChildScrollView(
                      child: SelectableText(
                        _content,
                        style: GoogleFonts.robotoMono(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}