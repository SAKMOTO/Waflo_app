import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:waflo_app/controllers/user_profile_controller.dart';
import 'package:waflo_app/services/user_profile_service.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/widgets/profile_avatar.dart';
import 'package:waflo_app/widgets/side_bar.dart';

/// Modern full-page profile editor: picture management plus display name,
/// username and bio. Email is read-only (managed by Google sign-in).
///
/// Guards against data loss: fields are never cleared on failure, every
/// failure shows a meaningful inline error and the input stays intact.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _email;

  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _error;
  String? _success;

  static final RegExp _usernamePattern = RegExp(r'^[a-zA-Z0-9_]{3,20}$');

  UserProfileController get _controller => UserProfileController.instance;

  @override
  void initState() {
    super.initState();
    final c = _controller;
    _name = TextEditingController(text: c.displayName);
    _username = TextEditingController(text: c.username ?? '');
    _bio = TextEditingController(text: c.bio);
    _email = TextEditingController(text: c.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    _email.dispose();
    super.dispose();
  }

  void _handleNavigation(int index) {
    if (index == 0) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } else if (index == 1) {
      Navigator.of(context).pushNamedAndRemoveUntil('/commerce', (route) => false);
    }
  }

  String? _usernameError(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return null; // username is optional
    final stripped = u.startsWith('@') ? u.substring(1) : u;
    if (!_usernamePattern.hasMatch(stripped)) {
      return 'Username must be 3–20 characters (letters, numbers or _).';
    }
    return null;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() {
        _error = 'Please enter a display name.';
        _success = null;
      });
      return;
    }
    final formatError = _usernameError(_username.text);
    if (formatError != null) {
      setState(() {
        _error = formatError;
        _success = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });

    final raw = _username.text.trim();
    final stripped = (raw.startsWith('@') ? raw.substring(1) : raw).toLowerCase();

    // Username uniqueness (database-backed; skipped transparently when the
    // tables are not yet migrated — the format check above still applies).
    final uid = _controller.userId;
    if (stripped.isNotEmpty && uid != null) {
      final taken = await UserProfileService.usernameExists(
        stripped,
        excludeUserId: uid,
      );
      if (taken == true) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = 'That username is already taken. Try another one.';
        });
        return;
      }
    }

    final error = await _controller.updateProfile(
      displayName: name,
      username: stripped.isEmpty ? null : stripped,
      bio: _bio.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      _success = error == null ? 'Profile saved' : null;
    });
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile saved'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _changePicture() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      if (file == null || file.bytes == null) return;
      setState(() {
        _uploadingAvatar = true;
        _error = null;
      });
      final err = await _controller.uploadAvatarBytes(
        file.bytes!,
        mimeType: _mimeFor(file.extension),
      );
      if (!mounted) return;
      setState(() {
        _uploadingAvatar = false;
        _error = err;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingAvatar = false;
        _error = 'Upload failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          sidebar(
            selectedIndex: 4,
            onNavigate: _handleNavigation,
            onNavigateMain: () => Navigator.of(context)
                .pushNamedAndRemoveUntil('/intro', (route) => false),
            onNavigateBuilder: () => Navigator.of(context).pushNamed('/builder'),
          ),
          Expanded(
            child: Container(
              color: AppColors.background,
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final c = _controller;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(context),
                            const SizedBox(height: 24),
                            Skeletonizer(enabled: c.loading, child: _pictureCard(c)),
                            const SizedBox(height: 20),
                            _fieldsCard(c),
                            const SizedBox(height: 20),
                            _saveBar(c),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          tooltip: 'Back to Settings',
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit Profile',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Customise how you appear across Waflo.',
              style: TextStyle(color: AppColors.textGrey, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pictureCard(UserProfileController c) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ProfileAvatar(
              imageUrl: c.avatarUrl,
              fallbackName: c.greetingName,
              size: 120,
              accent: AppColors.accent,
              uploading: _uploadingAvatar,
            ),
          ),
          const SizedBox(height: 6),
          if (_uploadingAvatar)
            Center(
              child: Text(
                'Uploading your picture…',
                style: TextStyle(color: AppColors.accent, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _uploadingAvatar ? null : _changePicture,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Change'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (c.hasCustomAvatar)
                OutlinedButton.icon(
                  onPressed: _uploadingAvatar
                      ? null
                      : () async {
                          await c.removeAvatar();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Back to your Google photo'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        },
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textGrey,
                    side: BorderSide(color: AppColors.searchBarBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'No custom picture? Your Google photo is shown automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.footerGrey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _fieldsCard(UserProfileController c) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Display name'),
          _field(
            controller: _name,
            hint: 'Your public name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 18),
          _label('Username'),
          _field(
            controller: _username,
            hint: '@handle (3–20 letters, numbers or _)',
            icon: Icons.alternate_email,
          ),
          const SizedBox(height: 14),
          _label('About you'),
          _field(
            controller: _bio,
            hint: 'A short bio — what you build, what you care about.',
            icon: Icons.notes,
            maxLines: 4,
            maxLength: 160,
          ),
          const SizedBox(height: 18),
          _label('Email'),
          TextField(
            controller: _email,
            enabled: false,
            style: TextStyle(color: AppColors.textGrey, fontSize: 15),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.mail_outline, size: 20),
              hintText: c.email ?? 'No email',
              hintStyle: TextStyle(color: AppColors.footerGrey, fontSize: 14),
              filled: true,
              fillColor: AppColors.surface.withValues(alpha: 0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.searchBarBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.searchBarBorder),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Managed by ${c.providerLabel}. Sign in to Google to change it.',
            style: TextStyle(color: AppColors.footerGrey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _saveBar(UserProfileController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_success != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Text(
                  _success!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: (_saving || _uploadingAvatar) ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.searchBarBorder.withValues(alpha: 0.6),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save changes',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.searchBarBorder),
      ),
      child: child,
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textGrey,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.iconGrey, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.iconGrey, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.searchBarBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.searchBarBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }

  static String _mimeFor(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'png':
        return 'image/png';
      default:
        return 'image/png';
    }
  }
}