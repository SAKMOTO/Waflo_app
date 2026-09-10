import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

/// Renders the animated `sgin.svg` (SMIL) inside a Flutter Web platform view.
///
/// Flutter's SVG renderers cannot animate SMIL `<animate>` elements, so the
/// SVG is injected inline into a DOM host element, exactly like the intro
/// screen does — animations play natively in the browser.
///
/// Clicks are handled on the DOM host itself and bridged back to [onTap]:
/// Flutter's gesture recognizers do not receive pointer events through a
/// HtmlElementView platform view on web.
class SginButtonView extends StatefulWidget {
  const SginButtonView({super.key, this.width, this.height, this.onTap});

  final double? width;
  final double? height;
  final VoidCallback? onTap;

  @override
  State<SginButtonView> createState() => _SginButtonViewState();
}

class _SginButtonViewState extends State<SginButtonView> {
  static int _counter = 0;
  static final Set<String> _registered = {};

  late final String _viewType = 'waflo-sgin-svg-${_counter++}';

  @override
  void initState() {
    super.initState();
    if (_registered.add(_viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final host = web.document.createElement('div') as web.HTMLDivElement;
        host
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.display = 'flex'
          ..style.alignItems = 'center'
          ..style.justifyContent = 'center'
          ..style.overflow = 'hidden'
          ..style.cursor = 'pointer';
        _loadSvg(host);
        // DOM-level click -> Flutter callback. Needed because the platform
        // view's DOM subtree swallows pointer events before Flutter's gesture
        // arena can claim the tap.
        host.addEventListener('click', ((web.Event event) {
          widget.onTap?.call();
        }).toJS);
        return host;
      });
    }
  }

  static void _loadSvg(web.HTMLDivElement host) {
    rootBundle
        .loadString('assets/sgin.svg')
        .then((String svg) {
      host.innerHTML = svg.toJS;
    }).catchError((Object error) {
      if (kDebugMode) debugPrint('sgin svg load error: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: HtmlElementView(
        viewType: _viewType,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
    );
  }
}