import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:waflo_app/theme/colors.dart';

/// A single link found inside an agent answer's "Sources:" section.
class StrobiSource {
  final String label;
  final String url;

  const StrobiSource({required this.label, required this.url});
}

/// The result of turning raw agent output into a presentable answer:
/// the cleaned Markdown body (browser-instrumentation noise removed) plus the
/// list of sources parsed out of it.
class CleanedStrobiAnswer {
  final String body;
  final List<StrobiSource> sources;

  const CleanedStrobiAnswer({required this.body, required this.sources});
}

/// Browser-use agents append their raw execution log to the final answer
/// (navigation chatter, "Data written to file", `<url>` blocks, element dumps…).
/// These markers denote the start of that log so it can be trimmed client-side,
/// keeping only the genuine Markdown answer written by the agent.
const _noiseTriggers = <String>[
  r'^🔗',
  r'^Data written to file',
  r'^Searched .* for ',
  r'^Clicked ',
  r'^Sent keys:',
  r'^Waited for ',
  r'^Scrolled',
  r'^Pressed ',
  r'^Typed ',
  r'^Focused ',
  r'^Extracted .* elements',
  r'^Found \d+ elements',
  r'^No elements found',
  r'^<url>',
  r'^</url>',
  r'^<query>',
  r'^</query>',
  r'^<result>',
  r'^</result>',
  r'^Info about current page',
  r'^Took a screenshot',
  r'^Moved the mouse',
  r'^Navigated to ',
  r'^Input: ',
  r'^Current URL:',
  r'^\[',
];

final _noisePattern = RegExp(_noiseTriggers.map((t) => '(?:$t)').join('|'));

final _sourcesMarker = RegExp(
  r'^\s*(?:\*\*)?Sources?(?:\*\*)?\s*:',
  caseSensitive: false,
);
final _urlPattern = RegExp(r'https?://[^\s)\]]+');
final _bulletPattern = RegExp(r'^[-*•]\s+');

/// Cleans a raw agent answer string:
///   1. splits out the "**Sources:**" section into [StrobiSource]s,
///   2. drops the leading browser-execution log,
///   3. trims the remaining Markdown body.
CleanedStrobiAnswer cleanStrobiAnswer(String raw) {
  final lines = _normalizeLines(raw);
  final sources = <StrobiSource>[];
  final bodyLines = <String>[];

  var inSources = false;
  final seenUrls = <String>{};

  for (final line in lines) {
    if (!inSources && _sourcesMarker.hasMatch(line.trim())) {
      inSources = true;
      continue;
    }

    if (inSources) {
      final content = line.trim();
      if (content.isEmpty) {
        inSources = false;
        continue;
      }
      final withoutBullet = content.replaceFirst(_bulletPattern, '');
      final urlMatch = _urlPattern.firstMatch(withoutBullet);
      if (urlMatch != null) {
        final url = urlMatch.group(0)!.replaceAll(RegExp(r'[,.;:]*$'), '');
        if (!seenUrls.contains(url)) {
          seenUrls.add(url);
          sources.add(
            StrobiSource(label: _labelFor(withoutBullet, url), url: url),
          );
          continue;
        }
      }
      inSources = false;
    }

    bodyLines.add(line);
  }

  var cut = bodyLines.length;
  for (var i = 0; i < bodyLines.length; i++) {
    if (_noisePattern.hasMatch(bodyLines[i].trim())) {
      cut = i;
      break;
    }
  }

  final body = bodyLines.take(cut).join('\n').trim();
  return CleanedStrobiAnswer(body: body, sources: sources);
}

List<String> _normalizeLines(String raw) {
  return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
}

String _labelFor(String content, String url) {
  final start = content.indexOf(url);
  var label = content.substring(0, start).trim();
  label = label.replaceFirst(RegExp(r'[—-]\s*$'), '').trim();
  if (label.isEmpty) {
    try {
      final host = Uri.parse(url).host;
      label = host.replaceFirst(RegExp(r'^www\.'), '');
    } catch (_) {
      label = url;
    }
  }
  return label;
}

/// Shared dark-theme Markdown style used everywhere agent answers are
/// rendered (agent workspace + the classic chat page) so output looks like a
/// polished ChatGPT response: clean typography, accent links, dark code
/// blocks and bordered tables.
MarkdownStyleSheet strobiMarkdownStyle(BuildContext context, {Color? accent}) {
  final accentColor = accent ?? AppColors.submitButton;
  final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
  const bodyColor = Color(0xFFE6EAEE);
  final headingBase = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  return base.copyWith(
    p: const TextStyle(color: bodyColor, fontSize: 15, height: 1.65),
    a: TextStyle(
      color: accentColor,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
      decorationColor: accentColor.withValues(alpha: 0.4),
    ),
    h1: headingBase.copyWith(fontSize: 22, height: 1.35),
    h2: headingBase.copyWith(fontSize: 19, height: 1.35),
    h3: headingBase.copyWith(fontSize: 16.5, height: 1.35),
    h4: headingBase.copyWith(fontSize: 15),
    h5: headingBase.copyWith(
      fontSize: 14,
      color: AppColors.textGrey,
      letterSpacing: 0.3,
    ),
    h6: headingBase.copyWith(
      fontSize: 13,
      color: AppColors.textGrey,
      letterSpacing: 0.3,
    ),
    strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
    em: const TextStyle(color: Color(0xFFC6CDD2), fontStyle: FontStyle.italic),
    del: TextStyle(
      color: AppColors.textGrey,
      decoration: TextDecoration.lineThrough,
    ),
    blockquote: const TextStyle(
      color: Color(0xFFB9C1C6),
      fontStyle: FontStyle.italic,
      height: 1.55,
    ),
    blockquoteDecoration: BoxDecoration(
      color: const Color(0xFF1E1F20),
      borderRadius: BorderRadius.circular(8),
    ),
    code: GoogleFonts.robotoMono(
      fontSize: 13,
      color: const Color(0xFF8FD8E8),
      backgroundColor: const Color(0xFF161819),
    ),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFF101213),
      borderRadius: BorderRadius.circular(10),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    horizontalRuleDecoration: BoxDecoration(
      color: AppColors.searchBarBorder,
      borderRadius: BorderRadius.circular(1),
    ),
    listBullet: TextStyle(color: accentColor, fontSize: 15),
    tableHead: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 14,
    ),
    tableHeadCellsDecoration: const BoxDecoration(color: Color(0xFF202222)),
    tableBody: const TextStyle(
      color: Color(0xFFC9D0D5),
      fontSize: 14,
      height: 1.5,
    ),
    tableBorder: TableBorder.all(
      color: AppColors.searchBarBorder,
      borderRadius: BorderRadius.circular(6),
    ),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    tableCellsDecoration: const BoxDecoration(color: Colors.transparent),
  );
}

/// Strips raw Markdown syntax from short plain-text labels (event messages,
/// error banners) so nothing like `**bold**` or `- item` is ever shown
/// literally outside the Markdown-rendered assistant bubble.
String stripMarkdownSyntax(String text) {
  if (text.isEmpty) return text;
  final inline = text
      .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!)
      .replaceAllMapped(
        RegExp(r'(^|\s)_([^_\n]+)_(?=\s|$)'),
        (m) => '${m[1]}${m[2]}',
      );
  return inline
      .split('\n')
      .map((line) {
        final heading = RegExp(r'^#{1,6}\s+').firstMatch(line.trimLeft());
        if (heading != null) {
          line = line.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
        }
        final quote = RegExp(r'^(\s*)>\s?').firstMatch(line);
        if (quote != null) {
          line = '${quote.group(1)}${line.substring(quote.end)}';
        }
        final list = RegExp(r'^(\s*)[-*•]\s+').firstMatch(line);
        if (list != null) {
          line = '${list.group(1)}• ${line.substring(list.end)}';
        }
        return line;
      })
      .join('\n')
      .trim();
}

/// A ChatGPT-style assistant message for agent answers. Renders the cleaned
/// Markdown body with [strobiMarkdownStyle], surfaces the parsed sources as
/// tappable link chips and offers a copy action.
class StrobiAssistantMessage extends StatelessWidget {
  final String text;
  final Color accent;
  final String agentName;
  final String role;
  final bool isError;

  const StrobiAssistantMessage({
    super.key,
    required this.text,
    required this.accent,
    this.agentName = 'Agent',
    this.role = 'Agent',
    this.isError = false,
  });

  Future<void> _open(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = isError ? const Color(0xFFE5484D) : accent;
    final cleaned = cleanStrobiAnswer(text);
    final body = cleaned.body.isEmpty ? text.trim() : cleaned.body;

    return Align(
      alignment: Alignment.centerLeft,
      child: SelectionArea(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isError
                  ? const Color(0xFFE5484D).withValues(alpha: 0.5)
                  : accent.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isError ? Icons.error_outline : Icons.travel_explore,
                        size: 14,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isError
                          ? '$agentName · Task failed'
                          : '$agentName · $role',
                      style: GoogleFonts.ibmPlexMono(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    if (cleaned.sources.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${cleaned.sources.length} source'
                          '${cleaned.sources.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Markdown(
                  data: body,
                  shrinkWrap: true,
                  selectable: true,
                  physics: const NeverScrollableScrollPhysics(),
                  styleSheet: strobiMarkdownStyle(context, accent: accentColor),
                  onTapLink: (url, _, _) => _open(url),
                ),
              ),
              if (cleaned.sources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _SourcesPanel(
                    sources: cleaned.sources,
                    accent: accentColor,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: stripMarkdownSyntax(body)),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard!')),
                      );
                    },
                    icon: Icon(
                      Icons.copy,
                      color: AppColors.textGrey,
                      size: 14,
                    ),
                    label: Text(
                      'Copy',
                      style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourcesPanel extends StatelessWidget {
  final List<StrobiSource> sources;
  final Color accent;

  const _SourcesPanel({required this.sources, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF202222),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.searchBarBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SOURCES',
            style: GoogleFonts.ibmPlexMono(
              color: AppColors.textGrey,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final source in sources)
                _SourceChip(source: source, accent: accent),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final StrobiSource source;
  final Color accent;

  const _SourceChip({required this.source, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(Icons.public, size: 14, color: accent),
      label: Text(
        source.label,
        style: const TextStyle(fontSize: 11.5, overflow: TextOverflow.ellipsis),
      ),
      backgroundColor: AppColors.cardColor,
      side: BorderSide(color: accent.withValues(alpha: 0.35)),
      labelStyle: TextStyle(color: Colors.white),
      tooltip: source.url,
      onPressed: () async {
        final uri = Uri.tryParse(source.url);
        if (uri == null) return;
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
    );
  }
}
