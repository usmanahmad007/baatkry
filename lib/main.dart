import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';
import 'services/guest_session_service.dart';
import 'services/permission_service.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize cached permissions (ask only once)
  await PermissionService.instance.init();

  // Initialize guest trial session tracker
  await GuestSessionService.instance.init();

  // Initialize Supabase and load or create the user profile
  await SupabaseService.instance.initialize();

  runApp(
    const ProviderScope(
      child: BaatkryApp(),
    ),
  );
}

class BaatkryApp extends StatelessWidget {
  const BaatkryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Baatkry - Live Video Chat',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: const HomeScreen(),
        );
      },
    );
  }
}

// Backward-compatibility alias for test harness
typedef MonkeyOmegleApp = BaatkryApp;
