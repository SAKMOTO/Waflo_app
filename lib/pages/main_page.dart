import 'dart:js_interop';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:waflo_app/controllers/auth_controller.dart';
import 'package:waflo_app/pages/home_page.dart';
import 'package:waflo_app/services/supabase_service.dart';

import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;

/// Bridge set from the intro's DOM when the "Let's get started" button is
/// clicked; it enters the app.
@JS('window.__wafloEnter')
external set wafloEnterBridge(JSFunction value);

/// Bridge set from the intro's DOM when the SVG entry icon is clicked; the
/// DOM calls `window.__wafloSignIn()` and Flutter starts the Google OAuth flow
/// (or enters Waflo directly when an account is already signed in).
@JS('window.__wafloSignIn')
external set wafloSignInBridge(JSFunction value);

/// Set true the moment the intro starts navigating away so the splash's Spline
/// scene is never booted to a canvas that is about to be removed from the page
/// (a lingering 0-sized WebGL context is what precedes the GPU abort / blank
/// screen + repeated unhandled-exception crash). JS also polls the flag so a
/// boot that was already in flight stops on the very next frame.
@JS('window.__wafloIntroDone')
external set wafloIntroDone(bool value);

/// Tear down the Spline runtime synchronously: discards the WebGL context and
/// detaches the `<canvas>` before Flutter removes the platform view. Without
/// this the running Spline app keeps drawing to a canvas that just became
/// 0-sized, which aborts the GPU process and crashes the whole window.
@JS('window.__wafloDisposeSpline')
external JSFunction? get wafloDisposeSpline;
@JS('window.__wafloDisposeSpline')
external set wafloDisposeSpline(JSFunction value);

/// Main / Intro screen.
///
/// The intro is rendered as one interactive HTML overlay (a Flutter platform
/// view) instead of stacked Flutter widgets:
///   * a Spline scene rendered directly with the Spline runtime (pinned,
///     self-hosted) — this keeps Spline's own pointer events live so the
///     robot reacts to the mouse, and shows NO Spline watermark/player UI;
///   * the WAFLO title, subtitle and the Lottie "click" animation as a DOM
///     button that fades/scales into the Home screen.
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  static int _counter = 0;
  static final Set<String> _registered = {};

  late final String _viewType = 'waflo-intro-${_counter++}';

  /// Spline scene (raw `.splinecode`) loaded with Self-hosted runtime.
  static const String _splineSceneUrl =
      'https://prod.spline.design/c7ZtUctGeaXpGquy/scene.splinecode';

  /// Pinned runtime that still ships the Application export.
  static const String _splineRuntimeUrl =
      'https://unpkg.com/@splinetool/runtime@1.0.29/build/runtime.js';

  @override
  void initState() {
    super.initState();
    _register(_viewType);
    AuthController.instance.addListener(_onAuthChanged);
    // Returning from a Google OAuth redirect restarts the app with a restored
    // session — skip past the intro for signed-in users.
    if (AuthController.instance.signedInWithGoogle) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _enterWafloOnce());
    }
  }

  bool _entered = false;

  void _onAuthChanged() {
    if (!mounted) return;
    if (AuthController.instance.signedInWithGoogle) _enterWafloOnce();
  }

  /// Google OAuth entry point behind the intro's SVG button + "Let's get
  /// started" Lottie. Already signed in -> straight to Waflo.
  Future<void> _handleSginAction() async {
    if (AuthController.instance.signedInWithGoogle) {
      _enterWafloOnce();
      return;
    }
    try {
      await SupabaseService.signInWithGoogle();
      // PKCE navigates to Google and back to the app origin; on return
      // init() restores the session and _onAuthChanged enters Waflo.
    } catch (e, st) {
      if (kDebugMode) debugPrint('waflo sign-in error: $e\n$st');
      web.console.log(('[waflo] sign-in error: $e\n$st').toJS);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in failed: $e')),
      );
    }
  }

  void _enterWaflo() {
    _entered = true;
    wafloIntroDone = true;
    wafloDisposeSpline?.callAsFunction();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, _, _) => const HomePage(),
        transitionsBuilder: (_, animation, _, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.04, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _enterWafloOnce() {
    if (_entered) return;
    _enterWaflo();
  }

  @override
  void dispose() {
    AuthController.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _register(String viewType) {
    if (_registered.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        final host =
            web.document.createElement('div') as web.HTMLDivElement;
        _paintIntro(host, _enterWafloOnce, _handleSginAction);
        return host;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: HtmlElementView(
          viewType: _viewType,
          hitTestBehavior: PlatformViewHitTestBehavior.translucent,
        ),
      ),
    );
  }

  static void _paintIntro(web.HTMLDivElement host, VoidCallback onEnter,
      VoidCallback onSginAction) {
    // Bridges so the DOM entry button / sgin icon can act from inside Flutter
    // (which owns the Supabase session and navigation).
    wafloEnterBridge = onEnter.toJS;
    wafloSignInBridge = onSginAction.toJS;

    host
      ..style.position = 'absolute'
      ..style.top = '0'
      ..style.left = '0'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.overflow = 'hidden';
    host.innerHTML = _splashHtml.toJS;

    // Fonts + libraries for the splash.
    final fontLink = web.HTMLLinkElement();
    fontLink.rel = 'stylesheet';
    fontLink.href =
        'https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;700&display=swap';
    web.document.head?.appendChild(fontLink);

    final splineScript = web.HTMLScriptElement()..type = 'module';
    splineScript.textContent = _bootstrapJs(_splineSceneUrl, _splineRuntimeUrl);
    web.document.body?.appendChild(splineScript);
  }

  static const String _splashHtml = '''
<style>
  #waflo-spline{position:absolute;top:0;left:0;width:100%;height:100%;display:block;background:transparent;}
  #waflo-veil{position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;
    background:linear-gradient(180deg, rgba(12,12,34,0.12) 0%, rgba(4,4,16,0.45) 100%);}
  #waflo-ui{position:absolute;top:0;left:0;width:100%;height:100%;display:flex;flex-direction:column;
    align-items:center;justify-content:center;pointer-events:none;}
  #waflo-title{font-family:'IBM Plex Mono',monospace;color:#fff;font-size:46px;font-weight:700;
    letter-spacing:6px;text-shadow:0 2px 16px rgba(0,0,0,0.65);}
  #waflo-sub{font-family:'IBM Plex Mono',monospace;color:rgba(255,255,255,0.82);font-size:14px;
    letter-spacing:2px;margin-top:10px;text-shadow:0 1px 10px rgba(0,0,0,0.7);}
  #waflo-enter{width:205px;height:205px;margin-top:20px;pointer-events:auto;cursor:pointer;
    filter:drop-shadow(0 10px 30px rgba(0,0,0,0.5));}
  #waflo-lgs{margin-top:18px;pointer-events:auto;cursor:pointer;
    font-family:'IBM Plex Mono',monospace;font-size:17px;font-weight:700;color:#fff;
    letter-spacing:2px;padding:13px 36px;border-radius:999px;
    background:linear-gradient(180deg,rgba(255,255,255,0.16),rgba(255,255,255,0.05));
    border:1px solid rgba(255,255,255,0.30);
    box-shadow:0 12px 32px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.28);
    text-shadow:0 2px 10px rgba(0,0,0,0.65);
    transition:transform .18s ease,background .18s ease,box-shadow .18s ease;}
  #waflo-lgs:hover{transform:translateY(-2px) scale(1.04);
    background:linear-gradient(180deg,rgba(255,255,255,0.24),rgba(255,255,255,0.09));
    box-shadow:0 16px 40px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.35);}
</style>
<canvas id="waflo-spline"></canvas>
<div id="waflo-veil"></div>
<div id="waflo-ui">
  <div id="waflo-title">WAFLO</div>
  <div id="waflo-sub">Where knowledge meets AI</div>
  <div id="waflo-enter"></div>
  <div id="waflo-lgs">Let's get started</div>
</div>
''';

  static String _bootstrapJs(String sceneUrl, String runtimeUrl) => '''
import { Application } from '$runtimeUrl';
(function () {
  'use strict';
  // Only boot the Spline scene once its canvas is really in the DOM AND has a
  // non-zero size. Creating a WebGL context on a 0×0 canvas produces
  // "Framebuffer is incomplete: Attachment has zero size" and can take down
  // the whole GPU pipeline (every other canvas on the page goes blank + the
  // app throws unhandled "Aborted()" exceptions on the next draw).
  var booted = false;
  var app = null;
  var canvas = null;
  var disposed = false;

  function tearDown() {
    if (disposed) return;
    disposed = true;
    booted = true;
    // Dispose the Spline runtime FIRST: it owns the WebGL context. Leaving it
    // running on a canvas that Flutter is about to remove (or that already got
    // a 0 size) is what aborts the GPU process / blanks every canvas.
    try {
      if (app && typeof app.dispose === 'function') { app.dispose(); }
    } catch (err) { console.error('waflo spline dispose error', err); }
    app = null;
    // Idempotent; only tears down the canvas this script created.
    if (canvas && canvas.parentNode) { canvas.parentNode.removeChild(canvas); }
    canvas = null;
  }

  function scheduleSpline() {
    if (disposed) return;
    if (window.__wafloIntroDone) { tearDown(); return; }
    canvas = document.getElementById('waflo-spline');
    if (canvas === null) { tearDown(); return; }   // intro replaced — stop
    if (booted) return;
    if (!(canvas.clientWidth > 0 && canvas.clientHeight > 0)) {
      setTimeout(scheduleSpline, 200);        // wait for real layout size
      return;
    }
    booted = true;
    try {
      app = new Application(canvas);
      app.load("$sceneUrl").catch(function (err) {
        console.error('waflo spline load error', err);
        tearDown();
      });
    } catch (err) {
      console.error('waflo spline init error', err);
      booted = false;
      setTimeout(scheduleSpline, 500);
    }
  }
  // Give the intro a moment to figure out whether the user is already signed
  // in (in which case the page navigates away and Spline never boots).
  setTimeout(scheduleSpline, 400);

  // Safety watchdog: the intro may be dismissed while Spline is ALREADY
  // running (the common case — user watches the robot, then clicks through).
  // Poll the intro-done flag + whether our canvas is still attached, and tear
  // the WebGL context down before Flutter disposes the platform view.
  var watchdog = setInterval(function () {
    var canvasEl = document.getElementById('waflo-spline');
    if (window.__wafloIntroDone || canvasEl === null || !document.body.contains(canvasEl)) {
      clearInterval(watchdog);
      tearDown();
    }
  }, 300);

  // Expose the dispose bridge so Flutter can tear the WebGL context down
  // synchronously the instant the intro navigates away (before the platform
  // view is removed — calling it here beats waiting on the 300ms watchdog).
  window.__wafloDisposeSpline = tearDown;

  function bootSvg() {
    fetch('/assets/assets/sgin.svg')
      .then(function (r) { if (!r.ok) { throw new Error('svg status ' + r.status); } return r.text(); })
      .then(function (svg) {
        var box = document.getElementById('waflo-enter');
        if (box) { box.innerHTML = svg; }
      })
      .catch(function (err) { console.error('waflo sgin svg error', err); });
  }
  bootSvg();

  var enter = document.getElementById('waflo-enter');
  if (enter) {
    enter.addEventListener('click', function (ev) {
      ev.stopPropagation();
      try { if (window.__wafloSignIn) { window.__wafloSignIn(); } } catch (err) {}
    });
  }

  var lgs = document.getElementById('waflo-lgs');
  if (lgs) {
    lgs.addEventListener('click', function (ev) {
      ev.stopPropagation();
      try { if (window.__wafloEnter) { window.__wafloEnter(); } } catch (err) {}
    });
  }
})();
''';
}