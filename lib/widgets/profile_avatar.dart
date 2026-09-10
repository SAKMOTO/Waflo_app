import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:waflo_app/theme/colors.dart';

/// Circular, premium user avatar used across Settings, Edit Profile, the
/// sidebar and the Home header.
///
/// Renders whichever source is available, in order:
///   1. the custom/uploaded picture (`imageUrl`, https or `data:`),
///   2. the Google profile picture (passed via [imageUrl] by the controller),
///   3. generated initials from [fallbackName].
///
/// Never shows a broken image: any load failure falls straight back to the
/// initials avatar. Supports a soft accent glow, a clean border, a hover
/// camera/edit affordance ([editable]) and a progress ring while an upload is
/// in flight.
class ProfileAvatar extends StatefulWidget {
  final String? imageUrl;

  /// Name used to derive initials when there is no usable image.
  final String fallbackName;

  final double size;

  /// Theme accent for the glow + border (defaults to the app accent).
  final Color? accent;

  /// Show the camera overlay on hover and make the whole avatar tappable.
  final bool editable;

  /// Runs when the avatar is tapped (only wired up when [editable]).
  final VoidCallback? onEdit;

  /// While true, a translucent scrim + progress ring cover the avatar.
  final bool uploading;

  const ProfileAvatar({
    super.key,
    this.imageUrl,
    this.fallbackName = '',
    this.size = 48,
    this.accent,
    this.editable = false,
    this.onEdit,
    this.uploading = false,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  bool _hover = false;

  Color get _accent => widget.accent ?? AppColors.accent;

  String get _initials {
    final name = widget.fallbackName.trim();
    if (name.isEmpty) return '';
    final tokens = name.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length == 1) {
      return tokens.first[0].toUpperCase();
    }
    return '${tokens.first[0]}${tokens.last[0]}'.toUpperCase();
  }

  Widget _initialsView() {
    final initials = _initials;
    return Container(
      color: _accent.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(
              Icons.person_outline,
              color: _accent,
              size: widget.size * 0.5,
            )
          : Text(
              initials,
              style: TextStyle(
                color: _accent,
                fontSize: widget.size * 0.34,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  ImageProvider? _resolveImage() {
    final url = widget.imageUrl;
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    if (trimmed.startsWith('data:image/')) {
      final comma = trimmed.indexOf(',');
      if (comma <= 0) return null;
      final encoded = substringAfterComma(trimmed, comma);
      try {
        return MemoryImage(base64Decode(encoded));
      } catch (_) {
        return null;
      }
    }
    if (kIsWeb) return NetworkImage(trimmed);
    return NetworkImage(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final provider = _resolveImage();

    final content = ClipOval(
      child: SizedBox.square(
        dimension: s,
        child: provider == null
            ? _initialsView()
            : Image(
                image: provider,
                fit: BoxFit.cover,
                width: s,
                height: s,
                errorBuilder: (_, __, ___) => _initialsView(),
                frameBuilder: (context, child, frame, wasSyncLoaded) {
                  if (wasSyncLoaded || frame != null) return child;
                  return _initialsView();
                },
                filterQuality: FilterQuality.medium,
              ),
      ),
    );

    final avatar = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _accent.withValues(alpha: 0.5), width: 1.4),
      ),
      child: content,
    );

    return MouseRegion(
      onEnter: widget.editable ? (_) => setState(() => _hover = true) : null,
      onExit: widget.editable ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.editable ? widget.onEdit : null,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Subtle accent glow behind the avatar.
            Container(
              width: s + s * 0.7,
              height: s + s * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _accent.withValues(alpha: 0.28),
                    _accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            avatar,
            // Upload in progress: scrim + ring.
            if (widget.uploading)
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: s * 0.42,
                  height: s * 0.42,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: _accent,
                  ),
                ),
              )
            else if (widget.editable)
              // Camera affordance on hover.
              AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.photo_camera_outlined, color: Colors.white, size: s * 0.32),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String substringAfterComma(String value, int comma) {
    if (comma + 1 <= value.length) return value.substring(comma + 1);
    return value;
  }
}