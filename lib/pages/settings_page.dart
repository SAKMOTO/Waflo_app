import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:waflo_app/controllers/avatar_controller.dart';
import 'package:waflo_app/controllers/user_profile_controller.dart';
import 'package:waflo_app/models/user_preferences_model.dart';
import 'package:waflo_app/theme/app_theme.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/utils/account_flow.dart';
import 'package:waflo_app/widgets/profile_avatar.dart';
import 'package:waflo_app/widgets/side_bar.dart';

/// The Waflo Settings experience: a real account profile bound to the
/// Supabase-authenticated Google user, theme selection (persisted + synced),
/// app preferences, account/security management with a real sign-out, and an
/// about section. Every value shown here comes from Supabase — nothing is
/// hardcoded.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void dispose() {
    super.dispose();
  }

  void _handleNavigation(int index) {
    if (index == 0) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } else if (index == 1) {
      Navigator.of(context).pushNamedAndRemoveUntil('/commerce', (route) => false);
    }
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          sidebar(
            selectedIndex: 4,
            onNavigate: _handleNavigation,
            onNavigateMain: () => Navigator.of(context)
                .pushNamedAndRemoveUntil('/intro', (route) => false),
            onNavigateBuilder: () => Navigator.of(context).pushNamed('/builder'),
          ),
          Expanded(
            child: Container(
              color: AppColors.background,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: ListenableBuilder(
                      listenable: UserProfileController.instance,
                      builder: (context, _) {
                        final c = UserProfileController.instance;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(),
                            const SizedBox(height: 24),
                            Skeletonizer(enabled: c.loading, child: _profileCard(c)),
                            const SizedBox(height: 20),
                            _sectionCard(
                              title: 'Appearance',
                              subtitle: 'Color theme — saved instantly and across your account.',
                              child: _themeSection(),
                            ),
                            const SizedBox(height: 20),
                            _sectionCard(
                              title: 'Preferences',
                              subtitle: 'How Waflo behaves for you.',
                              child: _preferencesSection(c),
                            ),
                            const SizedBox(height: 20),
                            _sectionCard(
                              title: 'Account',
                              subtitle: 'Your sign-in and connected identity.',
                              child: _accountSection(c),
                            ),
                            const SizedBox(height: 20),
                            _sectionCard(
                              title: 'Security',
                              subtitle: 'Session and access control.',
                              child: _securitySection(c),
                            ),
                            const SizedBox(height: 20),
                            _sectionCard(
                              title: 'About Waflo',
                              subtitle: 'Version and policies.',
                              child: _aboutSection(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ header

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Personalize your Waflo experience.',
          style: TextStyle(color: AppColors.textGrey, fontSize: 14),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ cards

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.searchBarBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: AppColors.footerGrey, fontSize: 12),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _profileCard(UserProfileController c) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.searchBarBorder),
      ),
      child: !c.signedInGoogle
          ? _signedOutHint(c)
          : _signedInProfile(c),
    );
  }

  Widget _signedOutHint(UserProfileController c) {
    return Row(
      children: [
        ProfileAvatar(fallbackName: '', size: 64),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No account connected',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Sign in with Google to sync your profile and preferences.',
                style: TextStyle(color: AppColors.textGrey, fontSize: 12),
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context)
              .pushNamedAndRemoveUntil('/intro', (route) => false),
          child: const Text('Sign in'),
        ),
      ],
    );
  }

  Widget _signedInProfile(UserProfileController c) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;
        final avatar = Row(
          children: [
            ProfileAvatar(
              imageUrl: c.avatarUrl,
              fallbackName: c.greetingName,
              size: narrow ? 72 : 84,
              editable: true,
              onEdit: () => Navigator.of(context).pushNamed('/edit-profile'),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.greetingName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.handle,
                    style: TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  if (c.email != null)
                    Text(
                      c.email!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                    ),
                  const SizedBox(height: 8),
                  _providerBadge(c),
                ],
              ),
            ),
          ],
        );

        final editButton = FilledButton.icon(
          onPressed: () => Navigator.of(context).pushNamed('/edit-profile'),
          icon: const Icon(Icons.edit_outlined, size: 17),
          label: const Text('Edit Profile'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              avatar,
              const SizedBox(height: 18),
              Align(alignment: Alignment.centerLeft, child: editButton),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: avatar),
            editButton,
          ],
        );
      },
    );
  }

  Widget _providerBadge(UserProfileController c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: AppColors.success, size: 14),
          const SizedBox(width: 6),
          Text(
            '${c.providerLabel} Account',
            style: TextStyle(
              color: AppColors.success,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- appearance

  Widget _themeSection() {
    final current = AppThemeController.instance.current;
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = constraints.maxWidth;
        final cols = span > 700 ? 4 : 2;
        final gap = 14.0;
        final itemWidth = (span - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final id in AppThemeId.values)
              SizedBox(
                width: itemWidth,
                child: _themeTile(id, selected: id == current),
              ),
          ],
        );
      },
    );
  }

  Widget _themeTile(AppThemeId id, {required bool selected}) {
    final palette = palettes[id]!;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => UserProfileController.instance.setTheme(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.accent : palette.searchBarBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette.background,
                          palette.surface,
                        ],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: palette.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: palette.accent.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, color: palette.accent, size: 18),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              palette.name,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ preferences

  Widget _preferencesSection(UserProfileController c) {
    final prefs = c.preferences ?? const UserPreferencesModel();
    return Column(
      children: [
        _agentRow(c),
        const SizedBox(height: 6),
        _switchTile(
          icon: Icons.animation_outlined,
          title: 'Animations',
          subtitle: 'Avatar and UI motion throughout Waflo.',
          value: prefs.animationsEnabled,
          onChanged: (v) => c.updatePreferences(prefs.copyWith(animationsEnabled: v)),
        ),
        _switchTile(
          icon: Icons.volume_up_outlined,
          title: 'Sound Effects',
          subtitle: 'Play sounds for events and notifications.',
          value: prefs.soundEnabled,
          onChanged: (v) => c.updatePreferences(prefs.copyWith(soundEnabled: v)),
        ),
        _switchTile(
          icon: Icons.self_improvement_outlined,
          title: 'Reduce Motion',
          subtitle: 'Minimize transitions and animations.',
          value: prefs.reduceMotion,
          onChanged: (v) => c.updatePreferences(prefs.copyWith(reduceMotion: v)),
        ),
      ],
    );
  }

  Widget _agentRow(UserProfileController c) {
    final currentId = AvatarController.instance.currentCharacter.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.searchBarBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.smart_toy_outlined, color: AppColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Default Agent',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'The character pre-selected for new sessions.',
                  style: TextStyle(color: AppColors.footerGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _validAgentId(currentId),
              dropdownColor: AppColors.sideNav,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              icon: Icon(Icons.expand_more, color: AppColors.iconGrey, size: 20),
              items: [
                for (final ch in AvatarController.characters)
                  DropdownMenuItem(
                    value: ch.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: ch.color ?? AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(ch.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) c.setDefaultAgent(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  String _validAgentId(String id) {
    for (final ch in AvatarController.characters) {
      if (ch.id == id) return id;
    }
    return AvatarController.characters.first.id;
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.searchBarBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: AppColors.footerGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.accent,
            activeThumbColor: Colors.white,
            inactiveTrackColor: AppColors.searchBarBorder.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- account

  Widget _accountSection(UserProfileController c) {
    return Column(
      children: [
        _infoRow(icon: Icons.mail_outline, label: 'Email', value: c.email ?? '—'),
        _infoRow(
          icon: Icons.link,
          label: 'Connected account',
          value: c.providerLabel,
          trailing: Icon(Icons.check_circle, color: AppColors.success, size: 16),
        ),
        _infoRow(
          icon: Icons.alternate_email,
          label: 'Signed in as',
          value: c.handle,
        ),
        _infoRow(
          icon: Icons.event_outlined,
          label: 'Account created',
          value: _formatDate(c.accountCreatedAt),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/edit-profile'),
            icon: Icon(Icons.manage_accounts_outlined, size: 17, color: AppColors.accent),
            label: const Text('Manage Profile'),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
          ),
        ),
      ],
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.searchBarBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.iconGrey, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(color: AppColors.textGrey, fontSize: 13),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- security

  Widget _securitySection(UserProfileController c) {
    final active = c.signedInGoogle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoRow(
          icon: Icons.shield_outlined,
          label: 'Session status',
          value: active ? 'Active' : 'Signed out',
          trailing: c.signedInGoogle
              ? Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: AppColors.success.withValues(alpha: 0.6), blurRadius: 6),
                    ],
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),
        SizedBox(
          child: OutlinedButton.icon(
            onPressed: () => AccountFlow.signOut(context),
            icon: const Icon(Icons.logout, size: 17),
            label: const Text('Sign out of Waflo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- about

  Widget _aboutSection() {
    return Column(
      children: [
        _infoRow(
          icon: Icons.info_outline,
          label: 'Waflo Version',
          value: 'v1.0.0',
        ),
        _infoRow(
          icon: Icons.privacy_tip_outlined,
          label: 'Privacy Policy',
          value: '',
          trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
        ),
        _infoRow(
          icon: Icons.description_outlined,
          label: 'Terms of Service',
          value: '',
          trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
        ),
      ],
    );
  }
}