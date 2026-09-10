import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:waflo_app/controllers/auth_controller.dart';
import 'package:waflo_app/controllers/avatar_controller.dart';
import 'package:waflo_app/controllers/chat_history_controller.dart';
import 'package:waflo_app/controllers/user_profile_controller.dart';
import 'package:waflo_app/pages/main_page.dart';
import 'package:waflo_app/services/chat_web_service.dart';
import 'package:waflo_app/services/supabase_service.dart';
import 'package:waflo_app/utils/account_flow.dart';
import 'package:waflo_app/widgets/avatar_view.dart';
import 'package:waflo_app/widgets/chat_history_sidebar.dart';
import 'package:waflo_app/widgets/chat_input_bar.dart';
import 'package:waflo_app/widgets/profile_avatar.dart';
import 'package:waflo_app/widgets/side_bar.dart';
import 'package:waflo_app/widgets/sgin_button_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String fullResponse = '';
  bool _historyOpen = false;
  StreamSubscription<Map<String, dynamic>>? _avatarStatusSub;

  AvatarController get _avatar => AvatarController.instance;

  @override
  void initState() {
    super.initState();
    ChatWebService().connect();
    unawaited(ChatHistoryController.instance.refreshConversations());
    _avatarStatusSub = ChatWebService().realtimeStream.listen(_onAvatarStatus);
  }

  @override
  void dispose() {
    _avatarStatusSub?.cancel();
    super.dispose();
  }

  /// Maps incoming backend events to the avatar's emotional state.
  void _onAvatarStatus(Map<String, dynamic> data) {
    if (!mounted) return;
    switch (data['type']) {
      case 'search_result':
      case 'browse_started':
      case 'commerce_started':
      case 'agent_status':
        _avatar.setState(AvatarEvent.working);
        break;
      case 'product_found':
        _avatar.setState(AvatarEvent.success);
        break;
      case 'searching':
      case 'thinking':
        _avatar.setState(AvatarEvent.thinking);
        break;
      case 'done':
      case 'final_result':
      case 'growth_result':
      case 'payment_success':
      case 'selection_confirmed':
        _avatar.setState(AvatarEvent.success);
        break;
      case 'error':
      case 'payment_failed':
      case 'commerce_cancelled':
      case 'browse_cancelled':
        _avatar.setState(AvatarEvent.error);
        break;
      default:
        break;
    }
  }

  void _onTypingChanged(bool typing) {
    // Typing = calm, attentive eyes over the idle body. The controller handles
    // state priority and the debounced return to idle; typing never maps to a
    // searching/working/thinking animation.
    _avatar.setTyping(typing);
  }

  void _toggleHistory() {
    setState(() => _historyOpen = !_historyOpen);
    if (_historyOpen) {
      unawaited(ChatHistoryController.instance.refreshConversations());
    }
  }

  void _handleNavigation(int index) {
    if (index == 1) {
      Navigator.pushNamed(context, '/commerce');
    }
  }

  void _handleMainNavigation() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          sidebar(
            onNavigate: _handleNavigation,
            onNavigateMain: _handleMainNavigation,
            onNavigateBuilder: () => Navigator.pushNamed(context, '/builder'),
            chatHistoryExpanded: _historyOpen,
            onChatHistoryToggle: _toggleHistory,
          ),
          ChatHistorySidebar(open: _historyOpen, onToggle: _toggleHistory),
          Expanded(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Align(
                          // Anchor both animations toward the bottom, just above
                          // the text input, instead of dead-centering them.
                          alignment: Alignment.bottomCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // "Welcome" animation, centered above the characters.
                              Lottie.asset(
                                'assets/welcome.json',
                                width: 210,
                                height: 68,
                                fit: BoxFit.contain,
                                repeat: true,
                                animate: true,
                              ),
                              const SizedBox(height: 4),
                              Lottie.asset(
                                'assets/man_woman_hi.json',
                                width: 360,
                                height: 280,
                                fit: BoxFit.contain,
                                repeat: true,
                                animate: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Center(
                        child: ChatInputBar(
                          replacePage: false,
                          showBrowserToggle: true,
                          onTypingChanged: _onTypingChanged,
                          avatar: AvatarView(
                            width: 55,
                            height: 55,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: GestureDetector(
                              onTap: () {
                                // Handle tap event
                              },
                              child: Text(
                                '© 2026 Waflo Inc. All rights reserved.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 22,
                  left: 0,
                  right: 0,
                  // WAFLO brand at the top of Home — same welcome font and
                  // style (white + depth) as the AI agent main screen.
                  child: Column(
                    children: [
                      Text(
                        'WAFLO',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 6,
                          shadows: const [
                            Shadow(
                              color: Color(0xA6000000),
                              blurRadius: 16,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Where knowledge meets AI',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.82),
                          letterSpacing: 2.5,
                          shadows: const [
                            Shadow(
                              color: Color(0xB3000000),
                              blurRadius: 10,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: ListenableBuilder(
                    listenable: AuthController.instance,
                    builder: (context, _) {
                      return AuthController.instance.signedInWithGoogle
                          ? const _SignedInProfile()
                          : _SignInCta(onTap: _signInWithGoogle);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Kick off the Google OAuth flow (same-tab PKCE redirect on web).
  Future<void> _signInWithGoogle() async {
    try {
      await SupabaseService.signInWithGoogle();
    } catch (e, st) {
      // Supabase unreachable / flow cancelled — tell the user, keep chat usable.
      SupabaseService.debugLog('Google sign-in failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in failed: $e')),
      );
    }
  }
}

/// Top-right sign-in block while logged out: the animated sgin SVG icon.
/// Clicking it starts the Google sign-in flow.
class _SignInCta extends StatelessWidget {
  const _SignInCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SginButtonView(width: 130, height: 130, onTap: onTap);
  }
}

/// Top-right account block while signed in with Google: profile picture with
/// the username directly below it (plus a small sign-out control).
class _SignedInProfile extends StatelessWidget {
  const _SignedInProfile();

  @override
  Widget build(BuildContext context) {
    final c = UserProfileController.instance;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ProfileAvatar(
              imageUrl: c.avatarUrl,
              fallbackName: c.greetingName,
              size: 44,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Tooltip(
                message: 'Sign out',
                child: InkWell(
                  onTap: () => AccountFlow.signOut(context),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: Color(0xFF26262B),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black45, blurRadius: 6),
                      ],
                    ),
                    child: const Icon(
                      Icons.logout,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            c.greetingName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (c.email != null) ...[
          const SizedBox(height: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              c.email!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
        ],
      ],
    );
  }
}