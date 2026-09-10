import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Live embedded preview for the web build: an `<iframe>` pointing at the
/// backend-served generated project, hosted inside a Flutter platform view.
/// Give it a new [key] (or bump [reloadToken]) to force a fresh reload.
class LivePreview extends StatefulWidget {
  const LivePreview({
    super.key,
    required this.url,
    this.reloadToken = 0,
  });

  final String url;
  final int reloadToken;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> {
  late String _viewType;

  static String _factoryId(String url, int token) {
    final hash = url.hashCode & 0x7fffffff;
    return 'waflo_live_preview_${hash}_$token';
  }

  @override
  void initState() {
    super.initState();
    _viewType = _factoryId(widget.url, widget.reloadToken);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = widget.url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..style.backgroundColor = '#ffffff'
        ..allowFullscreen = true;
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}