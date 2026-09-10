import 'package:flutter/material.dart';
import 'package:waflo_app/controllers/user_profile_controller.dart';
import 'package:waflo_app/theme/colors.dart';

/// Single sign-out flow shared by the Settings page, the sidebar account menu
/// and the Home header. Always asks for confirmation, performs a real
/// Supabase sign-out (clearing the local profile caches) and lands the user
/// back on the Welcome screen — never just hides the UI.
class AccountFlow {
  static Future<void> signOut(BuildContext context) async {
    final confirmed = await _confirmDialog(context);
    if (confirmed != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await UserProfileController.instance.signOut();
    navigator.pushNamedAndRemoveUntil('/intro', (route) => false);
  }

  static Future<bool?> _confirmDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.searchBarBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger.withValues(alpha: 0.14),
                ),
                child: Icon(Icons.logout, color: AppColors.danger, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                'Sign out of Waflo?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You will need to sign in again to access your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}