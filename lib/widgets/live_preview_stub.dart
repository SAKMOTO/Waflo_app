import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:waflo_app/theme/colors.dart';

/// Placeholder used on non-web platforms (macOS/Windows/Linux desktop),
/// where an embedded iframe is not available. The preview still opens via the
/// "Open in browser" action on the preview sheet.
class LivePreview extends StatelessWidget {
  const LivePreview({super.key, required this.url, this.reloadToken = 0});

  final String url;
  final int reloadToken;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.public,
            color: AppColors.textGrey,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            'Live preview is available in the web app.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Open the built website in your browser from this window.',
            style: GoogleFonts.inter(
              color: AppColors.textGrey,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}