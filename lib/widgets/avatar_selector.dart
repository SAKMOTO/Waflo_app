import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:waflo_app/controllers/avatar_controller.dart';
import 'package:waflo_app/theme/colors.dart';

/// Compact "AI model" style selector that lives on the right side of the chat
/// input bar. Shows the active character as `[ ● Strobi ▼ ]`; tapping opens a
/// small rounded dropdown attached to the pill.
///
/// The dropdown is rendered through a root [OverlayEntry] so it never pushes
/// or alters the surrounding page layout. It anchors to the pill, flips upward
/// when there is not enough room below, fades + scales in, and closes on
/// outside tap or after selecting a character.
class AvatarSelector extends StatefulWidget {
  const AvatarSelector({super.key});

  @override
  State<AvatarSelector> createState() => _AvatarSelectorState();
}

class _AvatarSelectorState extends State<AvatarSelector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  OverlayEntry? _overlay;

  /// Whether the Arrow 1 hint has been dismissed. The hint shows next to the
  /// character switcher pill while the dropdown has never been opened; the
  /// first click on the dropdown dismisses it for good.
  bool _hintDismissed = false;

  static const double _menuWidth = 220;
  static const double _itemHeight = 50;
  static const double _menuGap = 8;

  AvatarController get _controller => AvatarController.instance;

  bool get _menuOpen => _overlay != null;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      reverseDuration: const Duration(milliseconds: 110),
    );
  }

  @override
  void dispose() {
    _closeOverlay(animate: false);
    _animController.dispose();
    super.dispose();
  }

  /// Pixel rect of this pill in global (overlay) coordinates.
  Rect _anchorRect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      return Rect.zero;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _toggleMenu() {
    // First user click dismisses the pointing arrow hint permanently.
    _hintDismissed = true;
    if (_menuOpen) {
      _closeOverlay(animate: true);
    } else {
      _openOverlay();
    }
  }

  void _openOverlay() {
    if (_menuOpen) return;
    final overlayState = Overlay.maybeOf(context);
    if (overlayState == null) return;

    final anchor = _anchorRect();
    final viewport = overlayState.context.size;
    if (viewport == null || anchor.isEmpty) return;

    final count = AvatarController.characters.length;
    final menuHeight = count * _itemHeight + 8;

    // Place the dropdown below the pill when there is room, otherwise flip it
    // above (the home input bar sits low on the screen).
    final spaceBelow = viewport.height - anchor.bottom;
    final spaceAbove = anchor.top;
    final openAbove =
        spaceBelow < menuHeight + _menuGap && spaceAbove > spaceBelow;

    final menuLeft = (anchor.right - _menuWidth)
        .clamp(8.0, math.max(8.0, viewport.width - _menuWidth - 8))
        .toDouble();
    final double menuTop;
    if (openAbove) {
      menuTop = (anchor.top - menuHeight - _menuGap)
          .clamp(8.0, double.infinity)
          .toDouble();
    } else {
      menuTop = anchor.bottom + _menuGap;
    }

    _animController.value = 0;

    _overlay = OverlayEntry(
      builder: (context) => _buildDropdown(menuLeft, menuTop, openAbove),
    );
    overlayState.insert(_overlay!);
    _animController.forward();
  }

  void _closeOverlay({required bool animate}) {
    final overlay = _overlay;
    if (overlay == null) return;
    void remove() {
      if (_overlay == overlay) {
        _overlay?.remove();
        _overlay = null;
      }
    }

    if (animate) {
      _animController.reverse().whenComplete(remove);
    } else {
      _animController.value = 0;
      remove();
    }
  }

  Widget _buildDropdown(double left, double top, bool openAbove) {
    final anim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final origin = openAbove ? Alignment.bottomRight : Alignment.topRight;

    return Stack(
      children: [
        // Full-screen transparent barrier: any tap outside the menu closes it.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _closeOverlay(animate: true),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: _menuWidth,
          child: ListenableBuilder(
            listenable: _animController,
            builder: (context, _) {
              return FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1).animate(anim),
                  alignment: origin,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: _MenuPanel(
                      menuWidth: _menuWidth,
                      itemHeight: _itemHeight,
                      onSelect: () => _closeOverlay(animate: true),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final character = _controller.currentCharacter;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMenu,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.searchBar,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.searchBarBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: character.color ?? AppColors.submitButton,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      character.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.arrow_drop_down,
                      color: AppColors.iconGrey,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            // Pointing-arrow hint to the right of the switcher pill. Only
            // rendered until the dropdown has been opened; the first tap
            // dismisses it.
            if (!_hintDismissed) ...[
              Positioned(
                right: -52,
                top: -40,
                child: IgnorePointer(
                  child: Lottie.asset(
                    'assets/arrow_1.json',
                    width: 48,
                    height: 70,
                    fit: BoxFit.contain,
                    repeat: true,
                    animate: true,
                  ),
                ),
              ),
              // "Choose the AI Agents" callout in the Welcome-style script
              // font. Rendered to the RIGHT of the arrow (arrow is on the
              // left, text on the right) floating above the pill with it; it
              // disappears on the first tap of the selector — same as the
              // arrow.
              Positioned(
                right: -150,
                top: -58,
                child: IgnorePointer(
                  child: Text(
                    'Choose the\nAI Agent',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.caveat(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The dropdown card listing every registered avatar character.
class _MenuPanel extends StatelessWidget {
  final double menuWidth;
  final double itemHeight;

  /// Called after a character has been selected (closes the dropdown).
  final VoidCallback onSelect;

  const _MenuPanel({
    required this.menuWidth,
    required this.itemHeight,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final controller = AvatarController.instance;
    return SizedBox(
      width: menuWidth,
      child: Material(
        color: AppColors.sideNav,
        elevation: 12,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.searchBarBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final activeId = controller.currentCharacter.id;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final character in AvatarController.characters)
                  InkWell(
                    onTap: () {
                      controller.selectCharacter(character.id);
                      onSelect();
                    },
                    child: SizedBox(
                      height: itemHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: character.color ?? AppColors.submitButton,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  character.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  character.role,
                                  style: TextStyle(
                                    color: AppColors.iconGrey,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            if (character.id == activeId)
                              Icon(
                                Icons.check,
                                color: AppColors.submitButton,
                                size: 16,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}