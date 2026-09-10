import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

/// Centralises the Supabase connection used only for persisting chat history.
///
/// Values can be overridden at build time with:
///   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
///
/// Never expose a service-role key or the database password in the client.
class SupabaseService {
  SupabaseService._();

  static const String _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xzjpevmvereokrhalsmy.supabase.co',
  );

  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_kBtOla3xM5W8lMdyctLZ3w_Nsl3DGlr',
  );

  static bool initialized = false;
  static bool signedIn = false;

  /// Initialise Supabase once and try to sign in anonymously so [ready] can be
  /// relied on by the history features. Chat itself must keep working even if
  /// this fails, which is why failures are swallowed and surfaced via
  /// [ready] (plus a debug print).
  static Future<void> init() async {
    if (initialized) return;
    try {
      await Supabase.initialize(
        url: _url,
        publishableKey: _publishableKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      initialized = true;
    } catch (e) {
      debugPrint('SupabaseService: init failed -> $e');
      initialized = false;
    }

    if (initialized) {
      try {
        // Reuse an existing session (browser/localStorage keyed by origin) so
        // the SAME anonymous user comes back on relaunch. Otherwise every
        // relaunch would mint a fresh anonymous user whose RLS-permitted rows
        // are empty (all prior history is owned by other anonymous users).
        if (Supabase.instance.client.auth.currentSession == null) {
          await Supabase.instance.client.auth.signInAnonymously();
        }
        signedIn = true;
      } catch (e) {
        debugPrint('SupabaseService: anonymous sign-in failed -> $e');
        signedIn = false;
      }
    }
  }

  /// True when the database is reachable and we have an authenticated user.
  /// History features degrade gracefully (and silently) when this is false.
  static bool get ready => initialized && signedIn;

  /// Supabase's current signed-in user (anonymous bootstrap OR Google user).
  static User? get currentUser =>
      initialized ? Supabase.instance.client.auth.currentUser : null;

  /// Stream of auth events (SIGNED_IN, SIGNED_OUT, TOKEN_REFRESHED, ...).
  static Stream<AuthState> get authStream =>
      initialized
          ? Supabase.instance.client.auth.onAuthStateChange
          : const Stream.empty();

  /// True once a real (non-anonymous) account is signed in — i.e. the chat
  /// history bootstrap anonymous session does not count.
  static bool get isSignedInWithGoogle {
    final user = currentUser;
    return user != null && !user.isAnonymous;
  }

  /// Start the "Sign in with Google" flow. On web this PKCE flow navigates
  /// the current tab to Google, then back to [redirectTo] (which defaults to
  /// the app origin — so the Supabase project's Auth → URL Configuration must
  /// allow that origin for Google providers).
  static Future<bool> signInWithGoogle({String? redirectTo}) async {
    final auth = Supabase.instance.client.auth;
    // With the PKCE flow the return URL gets "?code=..." appended, so the
    // redirect target must be a clean origin WITHOUT a hash fragment (a
    // fragment would swallow the code for Flutter's hash router). Default to
    // the app's root origin.
    redirectTo ??= '${Uri.base.origin}/';
    _log('signInWithGoogle: calling signInWithOAuth(google, redirectTo='
        '$redirectTo)');
    // The Google OAuth redirect replaces any anonymous/bootstrap session when
    // it returns, so there is no need to sign out first. (Doing so on web
    // issues a blocking /logout network call that can stall the navigation.)
    final result = await auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
    );
    _log('signInWithGoogle: signInWithOAuth returned');
    return result;
  }

  /// Console-log on web (survives release builds), no-op elsewhere.
  static void debugLog(String message) => _log(message);

  /// Console-log on web (survives release builds), no-op elsewhere.
  static void _log(String message) {
    if (kIsWeb) {
      web.console.log(('[waflo] $message').toJS);
    } else if (kDebugMode) {
      debugPrint('[waflo] $message');
    }
  }

  /// Sign the current account out (clears the local session).
  static Future<void> signOut() async {
    if (initialized) {
      await Supabase.instance.client.auth.signOut();
    }
  }
}