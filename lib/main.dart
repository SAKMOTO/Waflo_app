import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:waflo_app/controllers/auth_controller.dart';
import 'package:waflo_app/controllers/settings_controller.dart';
import 'package:waflo_app/controllers/user_profile_controller.dart';
import 'package:waflo_app/pages/edit_profile_page.dart';
import 'package:waflo_app/pages/home_page.dart';
import 'package:waflo_app/pages/commerce_page.dart';
import 'package:waflo_app/pages/main_page.dart';
import 'package:waflo_app/pages/builder_page.dart';
import 'package:waflo_app/pages/settings_page.dart';
import 'package:waflo_app/services/supabase_service.dart';
import 'package:waflo_app/theme/app_theme.dart';
import 'package:waflo_app/theme/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort only: chat keeps working even if Supabase is unreachable.
  await SupabaseService.init();
  // Surface signed-in (Google) profile changes to the UI.
  AuthController.instance.start();
  // Track the authenticated account's profile, preferences and sessions.
  UserProfileController.instance.start();
  // Restore persisted theme + account profile from localStorage (web only).
  AppSettingsController.instance;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final palette = AppThemeController.instance.palette;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Waflo',
          theme: ThemeData(
            scaffoldBackgroundColor: AppColors.background,
            colorScheme: ColorScheme.fromSeed(seedColor: palette.accent),
            textTheme: GoogleFonts.interTextTheme(
              ThemeData.dark().textTheme.copyWith(
                    bodyMedium: TextStyle(
                      fontSize: 15,
                      color: AppColors.whiteColor,
                    ),
                  ),
            ),
          ),
          initialRoute: '/intro',
          routes: {
            // Main / Intro screen (Spline background + Lottie enter button).
            '/intro': (context) => const MainPage(),
            // Waflo Home — main AI query entry point.
            '/home': (context) => const HomePage(),
            // Kept for backwards compatibility with any '/' navigation.
            '/': (context) => const HomePage(),
            '/commerce': (context) => const CommercePage(),
            '/builder': (context) => const BuilderPage(),
            // Settings — theme switching + account customization.
            '/settings': (context) => const SettingsPage(),
            // Edit profile — picture, display name, username, bio.
            '/edit-profile': (context) => const EditProfilePage(),
          },
        );
      },
    );
  }
}