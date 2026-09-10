import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// High-level UI/app states that the avatar can be in.
///
/// These are the semantic "what is the app doing" states the rest of the UI
/// reports. The controller maps each one to a concrete animation name (taken
/// from the current character's definition) so a single event can drive any
/// number of characters without the UI knowing about animation internals.
enum AvatarEvent {
  /// Nothing happening — the avatar settles into its default idle loop.
  idle,

  /// The user is typing in the chat/search box.
  typing,

  /// A query has just been submitted and is being sent to the backend.
  sending,

  /// The backend is processing / streaming a response.
  processing,

  /// An agent (e.g. commerce, Strobi/browse) is actively working.
  working,

  /// A response arrived and is being shown.
  response,

  /// The latest action completed successfully.
  success,

  /// Something went wrong.
  error,

  /// The avatar is listening during a conversational turn.
  listening,

  /// The avatar is thinking about what it heard.
  thinking,
}

/// A registered character: a name plus the Flutter asset path of its
/// definition JSON. Additional characters can be dropped in later without
/// touching the UI — just register them here and the runtime resolves them.
class AvatarCharacter {
  final String id;
  final String name;

  /// The agent role this character plays (shown in the character dropdown,
  /// e.g. "Browser Agent", "File Editing & Manipulation").
  final String role;

  final String definitionAsset;

  /// Brand/swatch colour for UI pickers (the character's body colour).
  final Color? color;

  const AvatarCharacter({
    required this.id,
    required this.name,
    required this.role,
    required this.definitionAsset,
    this.color,
  });
}

/// Global singleton that tracks the avatar's current state and exposes it to
/// widgets via [ChangeNotifier]. The [AvatarView] observes this controller and
/// tells the JS runtime which animation to play.
///
/// Mirrors the existing `ChatHistoryController.instance` pattern.
class AvatarController extends ChangeNotifier {
  AvatarController._internal() {
    // Restore the last-selected character (best effort, web only).
    if (kIsWeb) {
      try {
        final savedId = web.window.localStorage.getItem(preferenceStorageKey);
        for (final c in characters) {
          if (c.id == savedId) {
            _current = c;
            break;
          }
        }
      } catch (_) {
        // localStorage unavailable — keep the default character.
      }
    }
  }

  static final AvatarController instance = AvatarController._internal();

  /// Flutter asset path of the bundled avatar runtime (IIFE). Loaded by the
  /// platform view and evaluated so it exposes `window.WafloAvatar`.
  static const String runtimeAsset = 'assets/avatars/wflo_avatar_runtime.js';

  /// Registered characters. Index 0 is the default. The definition asset is
  /// served by Flutter from `assets/` on the web platform view.
  static const List<AvatarCharacter> characters = [
    AvatarCharacter(
      id: 'strobi',
      name: 'Strobi',
      role: 'Browser Agent',
      definitionAsset: 'assets/avatars/strobi/strobi.avatar.json',
      color: Color(0xFF5B7FE5),
    ),
    AvatarCharacter(
      id: 'bubbles',
      name: 'Bubbles',
      role: 'File Editing & Manipulation',
      definitionAsset: 'assets/avatars/bubbles/bubbles.avatar.json',
      color: Color(0xFFE85D9C),
    ),
    AvatarCharacter(
      id: 'cosmo',
      name: 'Cosmo',
      role: 'Research & Analysis',
      definitionAsset: 'assets/avatars/cosmo/cosmo.avatar.json',
      color: Color(0xFF2FD6A8),
    ),
    AvatarCharacter(
      id: 'nixa',
      name: 'Nixa',
      role: 'Code & Development',
      definitionAsset: 'assets/avatars/nixa/nixa.avatar.json',
      color: Color(0xFF8B5CF6),
    ),
    AvatarCharacter(
      id: 'sunny',
      name: 'Sunny',
      role: 'Writing & Communication',
      definitionAsset: 'assets/avatars/sunny/sunny.avatar.json',
      color: Color(0xFFFFB020),
    ),
  ];

  /// localStorage key used to remember the selected character across sessions.
  static const String preferenceStorageKey = 'waflo.avatar.character';

  AvatarCharacter _current = characters.first;
  AvatarEvent _event = AvatarEvent.idle;

  /// Whether the user is currently composing in the input box. The controller
  /// remembers this so a transient highlight (success/error) settles back to
  /// typing (attentive eyes), not idle, when it expires.
  bool _composing = false;

  /// Pending "settle to idle/typing" timers (typing debounce + transient
  /// expiry). Only one can be outstanding at a time.
  Timer? _settleTimer;

  /// Expression used for "eyes react while typing/attending" without changing
  /// the looping idle animation. Null means "use the animation's own
  /// expression".
  String? _expressionOverride;

  AvatarCharacter get currentCharacter => _current;

  /// The animation name derived from the current event. Used by the platform
  /// view when it (re)creates the avatar.
  String get currentAnimation => animationForEvent(_event);

  AvatarEvent get currentEvent => _event;

  String? get expressionOverride => _expressionOverride;

  /// Map from a UI event to the animation name performed in the avatar.
  ///
  /// This is the single place event→animation translation lives. When a new
  /// character is added, keep this mapping stable (these names are part of the
  /// recommended animation vocabulary) but it can be overridden per character
  /// via [animationForEvent].
  static const Map<AvatarEvent, String> eventAnimation = {
    // Idle settles into a calm loop — never a distracting searching/working.
    AvatarEvent.idle: 'idle',
    // Typing reacts with the eyes (expression, see eventExpression) while the
    // body keeps its calm idle loop. Deliberately NOT a searching/working anim.
    AvatarEvent.typing: 'idle',
    AvatarEvent.sending: 'listening',
    AvatarEvent.processing: 'thinking',
    AvatarEvent.working: 'working',
    AvatarEvent.response: 'listening',
    AvatarEvent.success: 'happy',
    AvatarEvent.error: 'confused',
    AvatarEvent.listening: 'listening',
    AvatarEvent.thinking: 'thinking',
  };

  /// Expression applied for each event (overrides the animation's own eyes).
  /// Typing uses a calm, attentive gaze so the companion "watches" the user
  /// without jumping to a full animation.
  static const Map<AvatarEvent, String> eventExpression = {
    AvatarEvent.typing: 'attentive-left',
    AvatarEvent.sending: 'small-attentive',
    AvatarEvent.response: 'neutral',
  };

  /// Priority of each state. Higher wins when a lower-priority state tries to
  /// downgrade an active higher-priority state (e.g. idle must never displace
  /// working/searching/typing).
  static const Map<AvatarEvent, int> eventPriority = {
    AvatarEvent.error: 8,
    AvatarEvent.success: 7,
    AvatarEvent.working: 6,
    AvatarEvent.thinking: 5,
    AvatarEvent.processing: 5,
    AvatarEvent.sending: 4,
    AvatarEvent.typing: 3,
    AvatarEvent.listening: 2,
    AvatarEvent.response: 2,
    AvatarEvent.idle: 1,
  };

  static int priorityOf(AvatarEvent event) =>
      eventPriority[event] ?? 1;

  /// Fallback used when the character definition is missing an animation
  /// referenced by [eventAnimation].
  static const String fallbackAnimation = 'idle';

  /// Whether [event] uses an expression instead of a full animation change
  /// (typing keeps the idle body and only moves the eyes).
  static bool usesExpression(AvatarEvent event) =>
      eventExpression.containsKey(event);

  /// Resolves the animation for [event], preferring the current character's
  /// own definition when it declares a match, else the shared mapping.
  String animationForEvent(AvatarEvent event) {
    // The shared mapping uses the recommended animation vocabulary that the
    // bundled Strobi definition provides; extend here to support characters
    // with a different set.
    return eventAnimation[event] ?? fallbackAnimation;
  }

  /// Switch the active character. Returns true if the character was found.
  /// The selection is persisted locally so it survives a reload. The event
  /// state is intentionally left untouched — the new character picks up
  /// whatever animation/expression is currently active (no reset to idle).
  bool selectCharacter(String id) {
    for (final c in characters) {
      if (c.id == id) {
        if (_current.id != id) {
          _current = c;
          if (kIsWeb) {
            try {
              web.window.localStorage.setItem(preferenceStorageKey, id);
            } catch (_) {
              // Non-fatal: selection just won't persist.
            }
          }
          notifyListeners();
        }
        return true;
      }
    }
    return false;
  }

  /// Apply a transient/high-level state (working, thinking, success, error…).
  ///
  /// Enforces [eventPriority]: a lower-priority state (e.g. idle/typing) cannot
  /// downgrade an active higher-priority state (error/success/working/searching),
  /// so ambient or typing callbacks never override real work.
  ///
  /// Success/error are transient highlights: they auto-settle back to typing
  /// (if the user is composing) or idle after [transientDuration]. Long-lived
  /// states (working/searching/thinking) stay until the backend reports done.
  void setState(AvatarEvent event, {bool force = false}) {
    final incoming = priorityOf(event);
    final current = priorityOf(_event);
    if (!force && incoming < current) {
      // A lower-priority state tried to override a higher-priority one. Ignore
      // the bump unless we are merely refreshing the same event.
      if (event != _event) return;
    }
    if (event == _event && !force) return;
    _settleTimer?.cancel();
    _event = event;
    // Typing keeps the idle body and moves only the eyes.
    _expressionOverride =
        usesExpression(event) ? eventExpression[event] : null;
    if (event == AvatarEvent.success || event == AvatarEvent.error) {
      // Fade the highlight back to composing/idle shortly.
      _settleTimer = Timer(transientDuration, settle);
    }
    notifyListeners();
  }

  /// Update the "user is typing" flag.
  ///
  /// Typing is an ambient, low-priority state: it shows attentive eyes over the
  /// idle body and is never shown as searching/working. While a higher-priority
  /// state is active it waits quietly; when that settles, the avatar returns to
  /// typing (not idle). Stopping typing settles to idle after a short debounce.
  void setTyping(bool typing) {
    _composing = typing;
    if (typing) {
      // Typing is only visible over low-priority (ambient) states. If a
      // transient highlight is active it keeps priority and settles later.
      if (priorityOf(_event) <= priorityOf(AvatarEvent.typing)) {
        _settleTimer?.cancel();
        _event = AvatarEvent.typing;
        _expressionOverride = eventExpression[AvatarEvent.typing];
      }
    } else {
      // Leaving the box: settle to idle after a debounce. A pending transient
      // expiry is left running so success/error still fade normally.
      if (_event == AvatarEvent.typing) {
        _settleTimer?.cancel();
        _settleTimer = Timer(typingIdleDelay, settle);
      }
    }
    notifyListeners();
  }

  /// How long [AvatarEvent.success] / [AvatarEvent.error] hold before settling.
  static const Duration transientDuration = Duration(milliseconds: 2600);

  /// Debounce between the last keystroke and returning to idle.
  static const Duration typingIdleDelay = Duration(milliseconds: 700);

  /// Return to the ambient state: typing (if composing) else idle. Bypasses
  /// the priority guard — this is the sanctioned way to fall back to idle.
  void settle() {
    _settleTimer?.cancel();
    _event = _composing ? AvatarEvent.typing : AvatarEvent.idle;
    _expressionOverride =
        usesExpression(_event) ? eventExpression[_event] : null;
    notifyListeners();
  }

  /// Set just a facial expression without changing the looping animation
  /// (e.g. the avatar's eyes tracking while the user types). Pass null to
  /// clear the override.
  void setExpression(String? expression) {
    if (expression == _expressionOverride) return;
    _expressionOverride = expression;
    notifyListeners();
  }

  /// Resets to the default idle state (ignoring any composing flag).
  void clear() {
    _composing = false;
    settle();
  }
}
