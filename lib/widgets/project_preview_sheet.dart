import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/widgets/live_preview.dart';

/// Live preview of a built project.
///
/// Embeds the generated site (served by the backend over HTTP) inside the app
/// on web, with a toolbar to refresh it or open it in the system browser.
class ProjectPreviewSheet extends StatefulWidget {
  const ProjectPreviewSheet({
    super.key,
    required this.previewUrl,
    required this.title,
  });

  final String previewUrl;
  final String title;

  @override
  State<ProjectPreviewSheet> createState() => _ProjectPreviewSheetState();
}

class _ProjectPreviewSheetState extends State<ProjectPreviewSheet> {
  int _reloadToken = 0;

  Future<void> _openInBrowser() async {
    final ok = await launchUrl(
      Uri.parse(widget.previewUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.previewUrl),
          backgroundColor: AppColors.cardColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.86;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.submitButton.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.visibility_outlined,
                    color: AppColors.submitButton,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview',
                        style: GoogleFonts.ibmPlexMono(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppColors.textGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Reload preview',
                  child: IconButton(
                    onPressed: () =>
                        setState(() => _reloadToken += 1),
                    icon: Icon(
                      Icons.refresh,
                      color: AppColors.textGrey,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Open in browser',
                  child: IconButton(
                    onPressed: _openInBrowser,
                    icon: Icon(
                      Icons.open_in_new,
                      color: AppColors.submitButton,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.searchBarBorder),
              ),
              child: LivePreview(
                key: ValueKey(_reloadToken),
                url: widget.previewUrl,
                reloadToken: _reloadToken,
              ),
            ),
          ),
        ],
      ),
    );
  }
}