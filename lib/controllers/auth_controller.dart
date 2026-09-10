import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// Exposes the signed-in profile (Google account) so the app can react to
/// auth changes uniformly — e.g. swap the top-right sign-in button for the
/// user's avatar + name.
class AuthController extends ChangeNotifier {
  AuthController._();

  static final AuthController instance = AuthController._();

  StreamSubscription<AuthState>? _sub;
  static bool _started = false;

  /// Wire the controller to Supabase's auth events. Call once at startup.
  /// Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    _sub = SupabaseService.authStream.listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  User? get user => SupabaseService.currentUser;

  /// True when a real (non-anonymous, Google) account is signed in.
  bool get signedInWithGoogle => SupabaseService.isSignedInWithGoogle;

  /// Profile display name — Google profile `name`/`full_name`, falling back
  /// to the part before "@" of the account email.
  String get displayName {
    final u = user;
    if (u == null) return '';
    final meta = u.userMetadata ?? const <String, dynamic>{};
    final name =
        (meta['name'] ?? meta['full_name'] ?? meta['fullName']) as String?;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final email = u.email;
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'Account';
  }

  /// Google/Gravatar avatar url from the profile metadata.
  String? get avatarUrl {
    final meta = user?.userMetadata ?? const <String, dynamic>{};
    final url = (meta['avatar_url'] ?? meta['picture']) as String?;
    return (url == null || url.isEmpty) ? null : url;
  }

  String? get email => user?.email;

  /// Triggered by the sign-out icon shown with the profile in the header.
  Future<void> signOut() async {
    await SupabaseService.signOut();
    notifyListeners();
  }
}