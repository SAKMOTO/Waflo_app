import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:web/web.dart' as web;
import 'package:waflo_app/controllers/user_profile_controller.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/utils/account_flow.dart';
import 'package:waflo_app/widgets/profile_avatar.dart';
import 'package:waflo_app/widgets/side_bar_button.dart';

class sidebar extends StatefulWidget {
  final Function(int)? onNavigate; // Callback for navigation
  final int selectedIndex;         // 0 = Home, 1 = Commerce, 2 = Global

  /// Whether the Chat History panel next to this sidebar is expanded.
  final bool chatHistoryExpanded;

  /// Toggle the Chat History panel. When fired from the sidebar the panel
  /// expands FROM the left (it sits directly beside this navigation rail) and
  /// collapses again when toggled off.
  final VoidCallback? onChatHistoryToggle;

  /// Navigate back to the Main / Intro screen (brand/logo button).
  final VoidCallback? onNavigateMain;

  /// Navigate to the Waflo Builder page (new nav entry, index 3).
  final VoidCallback? onNavigateBuilder;

  const sidebar({
    super.key,
    this.onNavigate,
    this.selectedIndex = 0,
    this.chatHistoryExpanded = false,
    this.onChatHistoryToggle,
    this.onNavigateMain,
    this.onNavigateBuilder,
  });

  @override
  State<sidebar> createState() => _sidebarState();
}

class _sidebarState extends State<sidebar> {
  bool isCollapse = true;
  int _selectedIndex = 0; // 0 = Home, 1 = Commerce, 2 = Global

  /// Osiris global-incident map with the layer set enabled.
  static const String _osirisGlobalUrl =
      'https://osirisai.live/?layers=maritime,cctv,cctv_previews,'
      'live_news,earthquakes,global_incidents,day_night,cables,'
      'sdk_sea,sdk_air,sdk_naval,malware,cyber_attacks';

  /// Opens Osiris full-page (navigates this browser tab to the site). This
  /// bypasses X-Frame-Options:SAMEORIGIN which only blocks iframe embedding.
  static void openGlobalOsiris() {
    web.window.location.assign(_osirisGlobalUrl);
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selectedIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: AnimatedContainer(
        duration : Duration(milliseconds: 150),
        width: isCollapse ? 80 : 160,
        decoration: BoxDecoration(
          color: AppColors.sideNav,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
        crossAxisAlignment: isCollapse ? CrossAxisAlignment.center: CrossAxisAlignment.start,
        children: [
         Row(
          mainAxisAlignment : isCollapse ?  MainAxisAlignment.center: MainAxisAlignment.start,
           children: [
             GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onNavigateMain?.call(),
              child: Container(
                margin : EdgeInsets.symmetric(vertical : 15, horizontal : 15),
                child: Icon(Icons.auto_awesome_mosaic, color: AppColors.textPrimary, size: 34),
              ),
            ),
              isCollapse ? const SizedBox():
              Flexible(
                child: Text('Home',style :TextStyle(color : AppColors.textPrimary,fontWeight : FontWeight.bold,fontSize : 15), overflow: TextOverflow.ellipsis),
              )
           ],
         ),

         // Navigation buttons with selection state
         _buildNavButton(
           icon: Icons.home, 
           text: 'Home', 
           index: 0,
           isSelected: _selectedIndex == 0,
         ),
         
         _buildNavButton(
           icon: Icons.shopping_cart, 
           text: 'Shop', 
           index: 1,
           isSelected: _selectedIndex == 1,
           iconWidget: Lottie.asset(
             'assets/order_complete.json',
             width: 44,
             height: 44,
             fit: BoxFit.contain,
             repeat: true,
             animate: true,
           ),
         ),
         
         // Animated AI icon for the Waflo Builder.
         _buildNavButton(
           icon: Icons.auto_awesome, 
           text: 'Builder', 
           index: 3,
           isSelected: _selectedIndex == 3,
           iconWidget: Lottie.asset(
             'assets/ai_icon.json',
             width: 46,
             height: 46,
             fit: BoxFit.contain,
             repeat: true,
             animate: true,
           ),
         ),
         
         // OSINT (open source intelligence) — rotating Earth globe. Opens the
          // Osiris global-incident map full-page.
          _buildNavButton(
            icon: Icons.public, 
            text: 'OSINT', 
            index: 2,
            isSelected: _selectedIndex == 2,
iconWidget: Lottie.asset(
             'assets/earth_globe.json',
             width: 42,
             height: 42,
             fit: BoxFit.contain,
             repeat: true,
             animate: true,
           ),
          ),
          
          _buildChatHistoryButton(),
          
          SideBarButton(isCollapsed : isCollapse , icon: Icons.add, text: 'Add'),
          
          SideBarButton(isCollapsed : isCollapse , icon: Icons.search, text: 'Search'),
          
          // Settings — opens the Settings page (works from every screen).
            _buildNavButton(
              icon: Icons.settings,
              text: 'Settings',
              index: 4,
              isSelected: _selectedIndex == 4,
              iconWidget: Lottie.asset(
                'assets/gears.json',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                repeat: true,
                animate: true,
              ),
            ),
         
          Spacer(),

          _buildAccountArea(),

          SizedBox(height: 30),
        GestureDetector(
          onTap : (){
            setState(() {
              isCollapse = !isCollapse;
            });


          },
            child: AnimatedContainer(
              duration : Duration(milliseconds: 150),

              margin : EdgeInsets.symmetric(vertical : 15, horizontal : 15),
              child: Icon(
                isCollapse ?Icons.keyboard_arrow_right : Icons.keyboard_arrow_left, color: AppColors.textPrimary, size: 34),
            ),
          )
          
        ],
        ),
      ),
    );
  }

  /// Chat History button. This is the single entry point that slides the
  /// Chat History panel out from the left side of the app. Highlighted while
  /// the panel is expanded; clicking toggles it open/closed.
  Widget _buildChatHistoryButton() {
    final active = widget.chatHistoryExpanded;
    final label = active ? 'Close Chat History' : 'Chat History';
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onChatHistoryToggle?.call(),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: active ? AppColors.accent.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment:
                  isCollapse ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                // Animated chat-bubble icon (TopicTalk), running on a loop.
                Lottie.asset(
                  'assets/topictalk_icon.json',
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                  repeat: true,
                  animate: true,
                ),
                if (!isCollapse) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Chat History',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? AppColors.accent : AppColors.textPrimary,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String text,
    required int index,
    required bool isSelected,
    Widget? iconWidget,
  }) {
    // Tooltip provides the hover label popup for every navigation icon.
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 300),
      child: GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
        // Global opens Osiris full-page (top-level navigation). This works on
        // every page regardless of whether the parent wires onNavigate.
        if (index == 2) {
          openGlobalOsiris();
        }
        // Builder uses its own callback so it works on every page.
        if (index == 3) {
          widget.onNavigateBuilder?.call();
          return;
        }
        // Settings opens the Settings page directly on every page.
        if (index == 4) {
          Navigator.of(context).pushNamed('/settings');
          return;
        }
        // Notify parent widget about navigation
        if (widget.onNavigate != null) {
          widget.onNavigate!(index);
        }
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: isCollapse ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            if (iconWidget != null)
              iconWidget
            else
              Icon(
                icon, 
                color: isSelected ? AppColors.accent : AppColors.textPrimary, 
                size: 34
              ),
            if (!isCollapse) ...[
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? AppColors.accent : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ],
),
      ),
      ),
    );
  }

  /// Bottom account area: the signed-in user (opens the account menu) or a
  /// sign-in shortcut when logged out. Uses the REAL Supabase profile — name,
  /// email and avatar all come from the authenticated Google account.
  Widget _buildAccountArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListenableBuilder(
        listenable: UserProfileController.instance,
        builder: (context, _) {
          final c = UserProfileController.instance;
          if (!c.signedInGoogle) return _signInHint(context);
          return _accountMenu(context, c);
        },
      ),
    );
  }

  Widget _signInHint(BuildContext context) {
    return Tooltip(
      message: 'Sign in with Google',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
              '/intro', (route) => false),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            child: Row(
              mainAxisAlignment:
                  isCollapse ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.searchBar,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.searchBarBorder),
                  ),
                  child: Icon(
                    Icons.person_outline,
                    color: AppColors.iconGrey,
                    size: 18,
                  ),
                ),
                if (!isCollapse) ...[
                  const SizedBox(width: 10),
                  const Text(
                    'Sign in',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountMenu(BuildContext context, UserProfileController c) {
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xFF1E1E24)),
        surfaceTintColor: const WidgetStatePropertyAll(Color(0xFF1E1E24)),
        shadowColor: const WidgetStatePropertyAll(Colors.black54),
        elevation: const WidgetStatePropertyAll(12),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.searchBarBorder),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      builder: (context, controller, child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: child,
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              ProfileAvatar(
                imageUrl: c.avatarUrl,
                fallbackName: c.greetingName,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.greetingName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.email ?? c.handle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textGrey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.person_outline, size: 18),
          onPressed: () => Navigator.of(context).pushNamed('/settings'),
          child: const Text('Profile'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined, size: 18),
          onPressed: () => Navigator.of(context).pushNamed('/settings'),
          child: const Text('Settings'),
        ),
        const PopupMenuDivider(),
        MenuItemButton(
          leadingIcon: Icon(Icons.logout, size: 18, color: AppColors.danger),
          onPressed: () => AccountFlow.signOut(context),
          child: Text(
            'Sign out',
            style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: Row(
          mainAxisAlignment:
              isCollapse ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            ProfileAvatar(
              imageUrl: c.avatarUrl,
              fallbackName: c.greetingName,
              size: 32,
            ),
            if (!isCollapse) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.greetingName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more, color: AppColors.iconGrey, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
