import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

/// Renders a Spline 3D scene on Flutter Web by embedding Spline's official
/// player page (`my.spline.design/...`) in an <iframe>.
///
/// Using the official player page is the reliable route: Spline serves its own
/// runtime there, so this works even though `@splinetool/runtime@latest` is now
/// an ES module (it no longer exposes `window.Application`, which broke the old
/// self-hosted runtime bootstrap).
///
/// Pointer events are ignored so surrounding controls stay interactive.
/// Only supported on the web platform; elsewhere it renders nothing.
///
/// Note: the embed page renders the camera baked into the PUBLISHED spline file.
/// If a republished scene still encodes a stale play-camera, render it with
/// [SelfHostedSplineScene] instead, which can force position/rotation after load.
class SplineScene extends StatelessWidget {
  final String sceneUrl;
  final double? width;
  final double? height;

  const SplineScene({
    super.key,
    required this.sceneUrl,
    this.width,
    this.height,
  });

  static int _counter = 0;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const SizedBox.shrink();
    }
    final viewType = 'spline-scene-${_counter++}';
    _registerFactory(viewType, sceneUrl);
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: HtmlElementView(
        viewType: viewType,
        hitTestBehavior: PlatformViewHitTestBehavior.translucent,
      ),
    );
  }

  static final Set<String> _registered = {};

  static void _registerFactory(String viewType, String sceneUrl) {
    if (_registered.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        return _buildHost(viewType, sceneUrl);
      });
    }
  }

  static web.HTMLIFrameElement _buildHost(String viewType, String sceneUrl) {
    final frame = web.document.createElement('iframe') as web.HTMLIFrameElement
      ..id = 'spline-frame-$viewType'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.pointerEvents = 'none'
      ..setAttribute('allow', 'autoplay')
      ..setAttribute('title', 'Waflo background scene');
    // A query param on Spline's player page is ignored for content but changes
    // the resource URL, so the embedded iframes never show a stale cached scene
    // after a republish. It also doubles as a reload token: each build gets a
    // fresh value, forcing a re-fetch instead of Chromium's cached copy.
    final separator = sceneUrl.contains('?') ? '&' : '?';
    frame.setAttribute(
      'src',
      '$sceneUrl${separator}v=${DateTime.now().millisecondsSinceEpoch}',
    );
    return frame;
  }
}

/// Renders a Spline scene from a raw `.splinecode` URL using Spline's
/// self-hosted runtime, with the camera FORCED to a fixed position/rotation
/// after load.
///
/// The embed player page (`my.spline.design/...`) renders whatever play-camera
/// is baked into the published file. If a republish does not actually change
/// that baked camera (e.g. it still encodes an old top view), the embed cannot
/// fix it. This widget sidesteps the publish entirely: it loads the scene with
/// the same pinned runtime [MainPage] uses and repositions the camera on top
/// of the loaded scene, so the subject always appears as the intended view.
///
/// Values are baked into the generated JS at build/first-use time, so a given
/// instance is fixed once its [sceneUrl]/camera args are provided.
///
/// Pointer events on the canvas are ignored so surrounding controls stay
/// interactive. Web only.
class SelfHostedSplineScene extends StatelessWidget {
  final String sceneUrl;
  final double? width;
  final double? height;

  /// Forced camera world position `[x, y, z]` after the scene loads.
  final List<double> cameraPosition;

  /// Forced camera world rotation (euler, radians) `[x, y, z]`.
  /// Defaults to `[0, 0, 0]`.
  final List<double> cameraRotation;

  const SelfHostedSplineScene({
    super.key,
    required this.sceneUrl,
    this.cameraPosition = const [0, -78, 420],
    this.cameraRotation = const [0, 0, 0],
    this.width,
    this.height,
  });

  static int _counter = 0;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const SizedBox.shrink();
    }
    final viewType = 'spline-self-${_counter++}';
    final sceneUrl = this.sceneUrl;
    final camPos = cameraPosition;
    final camRot = cameraRotation;
    _registerFactory(viewType, ()
        => _buildHost(viewType, sceneUrl, camPos, camRot),
    );
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: HtmlElementView(
        viewType: viewType,
        hitTestBehavior: PlatformViewHitTestBehavior.translucent,
      ),
    );
  }

  static final Set<String> _registered = {};

  static void _registerFactory(String viewType, web.HTMLDivElement Function() build) {
    if (_registered.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        return build();
      });
    }
  }

  static web.HTMLDivElement _buildHost(String viewType, String sceneUrl,
      List<double> camPos, List<double> camRot) {
    final host = web.document.createElement('div') as web.HTMLDivElement
      ..id = 'spline-self-$viewType'
      ..style.position = 'absolute'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.overflow = 'hidden';

    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..id = 'waflo-spline-$viewType'
      ..style.position = 'absolute'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..style.pointerEvents = 'none';
    host.appendChild(canvas);

    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..type = 'module';
    script.textContent = _bootstrapJs(
      viewType,
      sceneUrl,
      camPos.map(_fmt).join(', '),
      camRot.map(_fmt).join(', '),
    );
    host.appendChild(script);
    return host;
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(4);
  }

  static String _bootstrapJs(String viewType, String sceneUrl,
      String camPosJs, String camRotJs) =>
      '''
import { Application } from 'https://unpkg.com/@splinetool/runtime@1.0.29/build/runtime.js';
(function () {
  'use strict';
  const canvas = document.getElementById('waflo-spline-$viewType');
  function boot() {
    try {
      const app = new Application(canvas);
      app.load("$sceneUrl").then(function () {
        try {
          const cam = app.camera;
          if (cam) {
            cam.position.set($camPosJs);
            cam.rotation.set($camRotJs);
          } else {
            console.warn('self-hosted scene has no app.camera');
          }
        } catch (err) {
          console.error('camera override failed', err);
        }
      }).catch(function (err) {
        console.error('spline self-hosted load error', err);
      });
    } catch (err) {
      console.error('spline self-hosted init error', err);
      setTimeout(boot, 500);
    }
  }
  boot();
})();
''';
}