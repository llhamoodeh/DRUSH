import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const DrushApp());
}

class DrushApp extends StatefulWidget {
  const DrushApp({super.key});

  @override
  State<DrushApp> createState() => _DrushAppState();
}

class _DrushAppState extends State<DrushApp> {
  AuthSession? _session;

  void _handleLogin(AuthSession session) {
    setState(() {
      _session = session;
    });
  }

  void _handleLogout() {
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DRUSH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE53935)),
        useMaterial3: true,
        textTheme: GoogleFonts.manropeTextTheme(),
      ),
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }

        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: child,
            ),
          ),
        );
      },
      home: _session == null
          ? LoginScreen(onLogin: _handleLogin)
          : HomeScreen(session: _session!, onLogout: _handleLogout),
    );
  }
}
