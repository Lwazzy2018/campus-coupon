import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/events_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/wallet_screen.dart';
import 'theme.dart';
import 'widgets/cc_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabasePublishableKey);
  runApp(const CampusCouponApp());
}

class CampusCouponApp extends StatelessWidget {
  const CampusCouponApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Campus Coupon',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AuthGate(),
      );
}

/// Navigation rule from SRS "Show Navigation Between Screens":
/// Welcome -> (authenticated session detected) -> Home, otherwise Login.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          currentTab.value = 0;
          return const LoginScreen();
        }
        return const MainShell();
      },
    );
  }
}

/// The four bottom-bar tabs: Home | Coupons | Events | Profile
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: currentTab,
      builder: (context, tab, _) {
        // Built fresh on every tab change so balances/RSVPs are always current.
        switch (tab) {
          case 1:
            return const WalletScreen();
          case 2:
            return const EventsScreen();
          case 3:
            return const ProfileScreen();
          default:
            return const HomeScreen();
        }
      },
    );
  }
}
