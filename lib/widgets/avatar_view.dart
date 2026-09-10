import 'dart:js_interop';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:waflo_app/controllers/avatar_controller.dart';

import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;

/// Bridge into the JS avatar runtime installed by the platform view factory.
/// The runtime exposes `window.__wafloAvatar` with an idempotent `ensure(...)`
/// (create/recreate the avatar in a host by id) and `setState(...)` (apply the
/// current animation / expression to every live controller).
@JS('window.__wafloAvatar.setState')
external void _avatarSetState(String? animation, String? expression);

/// Rebuilds every live avatar host with a different character definition.
/// Called whenever [AvatarController.selectCharacter] changes the active
/// character, so the avatar visually swaps without a page reload.
@JS('window.__wafloAvatar.loadCharacter')
external void _avatarLoadCharacter(String characterId, String definitionWebPath);

/// Exposes the currently active character id for development verification.
@JS('window.__wafloAvatar.getActiveCharacterId')
external String _avatarActiveCharacterId();

/// Reactive, procedural avatar rendered over the DOM (SVG) via an
/// [HtmlElementView] platform view. It mirrors the `HtmlElementView` pattern
/// already proven in [MainPage] (Spline/Lottie DOM embedding).
///
/// The widget observes [AvatarController.instance] and, on any change, pushes
/// the resolved animation / expression into the JS runtime. The runtime loads
/// the bundled `@bible-strong/avatar-web` engine and the character definition
/// from the Flutter web asset server, then renders and loops the animation.
///
/// It is purely visual and non-interactive (translucent hit test + ignored by
/// the pointer system) so it never blocks the chat input below it.
class AvatarView extends StatefulWidget {
  final double width;
  final double height;

  const AvatarView({
    super.key,
    this.width = 96,
    this.height = 96,
  });

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> {
  static int _counter = 0;
  static final Set<String> _registered = {};

  late final String _viewType = 'waflo-avatar-${_counter++}';

  String get _hostId => 'waflo-avatar-host-$_viewType';

  AvatarController get _controller => AvatarController.instance;

  /// Installs the JS bridge (`window.__wafloAvatar`) synchronously during
  /// [initState], before any [AvatarController] notification can reach it.
  bool _bridgeInstalled = false;

  /// Character ids currently loaded by the JS runtime; used to avoid
  /// reloading the same character on every controller notification. Starts as
  /// the default character because the bridge is installed with that config.
  String _loadedCharacterId = AvatarController.characters.first.id;

  @override
  void initState() {
    super.initState();
    debugPrint('[dart] AvatarView created (viewType=$_viewType, host=$_hostId)');
    _installBridge();
    _register(_viewType);
    debugPrint('[dart] Platform view registered: $_viewType');
    _controller.addListener(_syncToRuntime);
    // Seed the JS-side state so the avatar, once created, plays the right
    // animation without waiting for the next controller notification.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncToRuntime());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncToRuntime);
    super.dispose();
  }

  void _installBridge() {
    if (!kIsWeb || _bridgeInstalled) return;
    _bridgeInstalled = true;
    final runtimeUrl = _assetWebPath(AvatarController.runtimeAsset);
    final definitionUrl =
        _assetWebPath(AvatarController.characters.first.definitionAsset);
    final script = web.HTMLScriptElement();
    script.textContent = _bridgeJs(runtimeUrl, definitionUrl);
    web.document.body?.appendChild(script);
    debugPrint('[dart] Avatar JS bridge installed '
        '(runtime=$runtimeUrl, definition=$definitionUrl)');
  }

  void _register(String viewType) {
    if (_registered.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        final host = web.document.createElement('div') as web.HTMLDivElement;
        host
          ..id = _hostId
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.left = '0'
          ..style.width = '${widget.width}px'
          ..style.height = '${widget.height}px'
          ..style.overflow = 'hidden';

        // NOTE: at this point the returned host is NOT yet attached to the
        // document (Flutter's web engine attaches the element returned by the
        // factory AFTER the factory returns). The JS `ensure` therefore waits
        // for the host to appear before creating the avatar.
        final script = web.HTMLScriptElement();
        script.textContent = _hostEnsureJs(_hostId, widget.width.toInt());
        web.document.body?.appendChild(script);
        return host;
      });
    }
  }

  /// Converts a Flutter asset path to a URL on the Flutter web asset server.
  /// Flutter serves assets under `/assets/`, so `assets/foo.json` resolves to
  /// `/assets/assets/foo.json`.
  static String _assetWebPath(String assetPath) => '/assets/$assetPath';

  /// Pushes the latest controller state into the JS runtime (every live view).
  /// When the active character was switched, it first rebuilds the avatar with
  /// the new definition, then applies the current animation / expression. Only
  /// the *character* change recreates the engine — animation/expression changes
  /// reuse the existing controller via [setState].
  void _syncToRuntime() {
    if (!kIsWeb) return;
    final character = _controller.currentCharacter;
    if (character.id != _loadedCharacterId) {
      debugPrint('[dart] avatar character: '
          '$_loadedCharacterId → $character.id ($character.definitionAsset)');
      _loadedCharacterId = character.id;
      _avatarLoadCharacter(character.id, _assetWebPath(character.definitionAsset));
      debugPrint('[dart] js active after switch: '
          '${_avatarActiveCharacterId()} (expected ${character.id})');
    }
    _avatarSetState(
      _controller.currentAnimation,
      _controller.expressionOverride,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return SizedBox.shrink();
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: HtmlElementView(
        viewType: _viewType,
        hitTestBehavior: PlatformViewHitTestBehavior.translucent,
      ),
    );
  }

  /// Installs `window.__wafloAvatar` and its config (runtime + definition URLs)
  /// once. Called during [initState] so the bridge exists before Dart pushes
  /// any state via [AvatarController].
  static String _bridgeJs(String runtimeUrl, String definitionUrl) => '''
(function () {
  'use strict';
  if (window.__wafloAvatar && window.__wafloAvatar.ready) return;
  var CTX = window.__wafloAvatar = window.__wafloAvatar || { controllers: {} };
  CTX.ready = true;
  CTX.config = { runtimeUrl: '$runtimeUrl', definitionUrl: '$definitionUrl', characterId: null };
  console.log('[avatar] bridge installed', JSON.stringify(CTX.config));

  // Per-host bookkeeping so every character remount reuses the exact same CSS
  // box size as the original create (the Flutter ActionHost is fixed), and so
  // the fitted viewBox only ever grows - never shrinks - as animation frames
  // expand the pose beyond the neutral geometry.
  CTX.sizes = {};
  CTX.fits = {};

  // Garbage-collect engines whose host element was removed from the DOM (e.g.
  // a previous AvatarView was disposed on navigation). Without this the stale
  // controllers keep receiving state changes and duplicate animated engines
  // pile up, which manifests as flicker / animation cuts on the page.
  if (typeof MutationObserver !== 'undefined' && window.document.body) {
    var mo = new MutationObserver(function () {
      var ids = Object.keys(CTX.controllers);
      for (var i = 0; i < ids.length; i += 1) {
        var hostId = ids[i];
        if (!window.document.getElementById(hostId) && CTX.controllers[hostId]) {
          try { CTX.controllers[hostId].destroy(); } catch (err) {}
          delete CTX.controllers[hostId];
        }
      }
    });
    mo.observe(window.document.body, { childList: true, subtree: true });
  }

  function loadScript(url) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = url;
      s.onload = resolve;
      s.onerror = function () { reject(new Error('script load failed: ' + url)); };
      document.head.appendChild(s);
    });
  }

  CTX.install = function () {
    if (window.WafloAvatar) {
      console.log('[avatar] runtime global present, createAvatar=',
        typeof (window.WafloAvatar && window.WafloAvatar.createAvatar));
      return Promise.resolve();
    }
    console.log('[avatar] loading runtime script', CTX.config.runtimeUrl);
    return loadScript(CTX.config.runtimeUrl).then(function () {
      if (!window.WafloAvatar) throw new Error('runtime missing window.WafloAvatar');
      console.log('[avatar] runtime loaded, createAvatar=',
        typeof (window.WafloAvatar && window.WafloAvatar.createAvatar));
    });
  };

  function createInHost(hostId, host, size, url) {
    var fetchUrl = url || CTX.config.definitionUrl;
    // Remember the real CSS box size (55px AvatarView) on first creation and
    // always reuse it. Passing `size=null` on a character switch must NOT fall
    // back to a larger default (96px), otherwise the new avatar renders the
    // 96px span inside the fixed 55px host and gets clipped / overflows.
    if (size) CTX.sizes[hostId] = size;
    var hostSize = CTX.sizes[hostId] || CTX.config.size || 96;
    return CTX.install().then(function () {
      return fetch(fetchUrl).then(function (r) {
        if (!r.ok) throw new Error('definition status ' + r.status +
          ' for ' + fetchUrl);
        return r.json();
      });
    }).then(function (def) {
      var anims = def && def.animations ? Object.keys(def.animations) : [];
      var exprs = def && def.expressions ? Object.keys(def.expressions) : [];
      console.log('[avatar] definition loaded: id=', CTX.config.characterId,
        'name=', def && def.name,
        'animations=', anims.join(','), 'expressions=', exprs.join(','));
      // Clean remount. Destroy the previous controller (stops its rAF loop),
      // then clear every child so no stale <span class="bs-avatar">/<svg> and
      // no stale viewBox/scale/transform from the previous character survive.
      // The engine mounts a brand-new <span><svg/></span> with the hardcoded
      // viewBox "-150 -150 300 300"; an old SVG left behind would make
      // host.querySelector('svg') hit the WRONG (stale) element.
      var existing = CTX.controllers[hostId];
      if (existing) {
        try {
          existing.destroy();
          console.log('[avatar] destroyed previous instance', hostId);
        } catch (err) {
          console.error('[avatar] destroy failed', hostId, err);
        }
        delete CTX.controllers[hostId];
      }
      // Forget the previous character's fitted viewBox so the new character is
      // measured and centered from scratch (never unions with / inherits the
      // old geometry, which would leave it too small or offset).
      delete CTX.fits[hostId];
      if (host.hasChildNodes()) host.replaceChildren();
      var ctrl = window.WafloAvatar.createAvatar(host, {
        definition: def,
        // Start on the currently active animation (if any) so switching
        // characters does not flash back to a fresh idle loop.
        defaultAnimation: (CTX.state && CTX.state.animation) || 'idle',
        size: hostSize,
        onError: function (err) { console.error('[avatar] engine error', err); }
      });
      CTX.controllers[hostId] = ctrl;
      console.log('[avatar] avatar created in', hostId,
        'svg elements:', host.querySelectorAll('svg').length);
      CTX.applyState(hostId);
      // Auto-fit every character into the fixed host. The engine paints the
      // first frame synchronously, so measure immediately, then again after
      // the browser has flushed layout (double-rAF) in case getBBox() was
      // stale, then once more after the first animation frames so motion
      // overshoot (arms, particles, head nodes) grows the viewBox instead of
      // being clipped.
      fitViewport(hostId, host);
      requestAnimationFrame(function () {
        requestAnimationFrame(function () { fitViewport(hostId, host); });
      });
      setTimeout(function () { fitViewport(hostId, host); }, 350);
      console.log('[avatar] ' + (CTX.config.characterId || '?') + ' ready in', hostId);
      return true;
    }).catch(function (err) {
      console.error('[avatar] init failed', err);
      return false;
    });
  }

  // Generic auto-fit: every avatar JSON can have different body dimensions /
  // animation extents, but the engine always starts each SVG with the fixed
  // viewBox "-150 -150 300 300". A tall capsule (Bubbles), a Mickey (Cosmo) or
  // a cube with a head node on top (Nixa) therefore gets clipped at the
  // viewport edges.
  //
  // Instead of hardcoding sizes per character, we measure the *actual rendered*
  // bounds via SVG getBBox() (union of every path - body, back/front slices,
  // eyes, decorative nodes) and replace the viewBox with one that contains the
  // character plus a ~10% safe margin. preserveAspectRatio (xMidYMid meet)
  // then scales the whole character into the fixed CSS host box, so nothing is
  // cut and every future JSON avatar fits automatically.
  //
  // Expand-only: once fitted, a re-fit never shrinks the viewBox. If an
  // animation frame extends beyond the neutral pose (arms, particles, head
  // nodes) the later re-fit measurements only grow the box, so motion is never
  // clipped. [AvatarFit] logs per character let us verify the numbers change
  // with each switch.
  function fitViewport(hostId, host) {
    var svg = host.querySelector('svg');
    if (!svg) return;
    // Explicit contain strategy (equivalent to object-fit: contain).
    svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
    try {
      var bb = svg.getBBox();
      if (!bb || !isFinite(bb.x) || !isFinite(bb.y) ||
          !isFinite(bb.width) || !isFinite(bb.height) ||
          bb.width <= 0 || bb.height <= 0) {
        console.log('[avatar] fit skipped (empty bounds), keeping default viewBox');
        return;
      }
      // ~10% safe padding on every side so animation frames (arms, eyes,
      // particles, head nodes) that overshoot the neutral pose stay visible.
      var pad = 0.10;
      var cx = bb.x + bb.width / 2;
      var cy = bb.y + bb.height / 2;
      var w = Math.max(bb.width * (1 + pad * 2), 2);
      var h = Math.max(bb.height * (1 + pad * 2), 2);
      var desired = [cx - w / 2, cy - h / 2, w, h];
      var prev = CTX.fits[hostId];
      if (prev) {
        var d0 = [desired[0], desired[1], desired[0] + desired[2], desired[1] + desired[3]];
        var d1 = [prev[0], prev[1], prev[0] + prev[2], prev[1] + prev[3]];
        var x0 = Math.min(d0[0], d1[0]);
        var y0 = Math.min(d0[1], d1[1]);
        var x1 = Math.max(d0[2], d1[2]);
        var y1 = Math.max(d0[3], d1[3]);
        desired = [x0, y0, x1 - x0, y1 - y0];
      }
      CTX.fits[hostId] = desired;
      svg.setAttribute('viewBox', desired.map(function (v) {
        return Math.round(v * 10) / 10;
      }).join(' '));
      console.log('[AvatarFit]', JSON.stringify({
        character: CTX.config.characterId || '?',
        host: (host.clientWidth || '?') + 'x' + (host.clientHeight || '?'),
        contentBounds: { x: bb.x, y: bb.y, w: bb.width, h: bb.height },
        scale: Math.min(
          (host.clientWidth || bb.width) / bb.width,
          (host.clientHeight || bb.height) / bb.height
        ),
        viewBox: svg.getAttribute('viewBox')
      }));
    } catch (err) {
      console.error('[avatar] fit failed, keeping default viewBox', err);
    }
  }

  CTX.ensure = function (hostId, size) {
    var host = document.getElementById(hostId);
    if (host) {
      console.log('[avatar] host present, creating avatar', hostId);
      return createInHost(hostId, host, size);
    }
    // Flutter attaches the platform-view element only after the factory
    // returns, so retry until it is actually in the document.
    console.log('[avatar] host not attached yet, waiting', hostId);
    return new Promise(function (resolve, reject) {
      var tries = 0;
      var timer = setInterval(function () {
        tries += 1;
        host = document.getElementById(hostId);
        if (host) {
          clearInterval(timer);
          console.log('[avatar] host attached to DOM', hostId);
          createInHost(hostId, host, size).then(resolve)['catch'](reject);
        } else if (tries > 160) {
          clearInterval(timer);
          reject(new Error('[avatar] host never attached: ' + hostId));
        }
      }, 50);
    });
  };

  CTX.applyState = function (hostId) {
    var ctrl = CTX.controllers[hostId];
    if (!ctrl) return;
    var st = CTX.state || {};
    if (st.expression) {
      try { ctrl.setExpression(st.expression); } catch (err) { console.error('[avatar] setExpression', err); }
      return;
    }
    if (st.animation) {
      var r = ctrl.play(st.animation);
      if (r && !r.ok) { ctrl.play('idle'); }
      return;
    }
    ctrl.play('idle');
  };

  CTX.setState = function (animation, expression) {
    var st = CTX.state = { animation: animation || null, expression: expression || null };
    var hosts = Object.keys(CTX.controllers);
    for (var i = 0; i < hosts.length; i += 1) CTX.applyState(hosts[i]);
    return st;
  };

  CTX.loadCharacter = function (characterId, definitionUrl) {
    var prevId = CTX.config.characterId;
    CTX.config.characterId = characterId;
    // Capture the URL now so a second (rapid) switch cannot make an earlier
    // in-flight load fetch the *latest* character for a stale request. Each
    // host rebuilds the engine with this captured URL.
    var url = definitionUrl || CTX.config.definitionUrl;
    CTX.config.definitionUrl = url;
    console.log('[avatar] switching character from', prevId, 'to', characterId, url);
    var hosts = Object.keys(CTX.controllers);
    if (!hosts.length) {
      console.log('[avatar] no live hosts yet for', characterId,
        '(will be picked up when hosts attach)');
      return Promise.resolve();
    }
    var jobs = hosts.map(function (hostId) {
      var host = document.getElementById(hostId);
      if (!host) return Promise.resolve(false);
      return createInHost(hostId, host, null, url);
    });
    return Promise.all(jobs);
  };

  CTX.getActiveCharacterId = function () {
    return CTX.config.characterId || null;
  };

  CTX.getSummary = function () {
    var alive = Object.keys(CTX.controllers)
      .filter(function (id) { return !!document.getElementById(id); });
    return {
      character: CTX.getActiveCharacterId(),
      state: CTX.state || null,
      hosts: alive
    };
  };
})();
''';

  /// Small per-host script run from the platform view factory. The host may not
  /// be attached to the DOM yet at this point, so [CTX.ensure] waits for it.
  static String _hostEnsureJs(String hostId, int size) =>
      '''(function () {
  if (window.__wafloAvatar && window.__wafloAvatar.ensure) {
    console.log('[avatar] host ensure script running for', '$hostId');
    window.__wafloAvatar.ensure('$hostId', $size);
  } else {
    console.error('[avatar] bridge missing while ensuring host', '$hostId');
  }
})();
''';
}