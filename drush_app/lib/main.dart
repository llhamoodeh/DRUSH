import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/home_screen.dart';

import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'shared/chat_owl_button.dart';
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
  bool _isRestoring = true;
  final AuthService _authService = AuthService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String _currentRouteName = '';
  late final NavigatorObserver _routeObserver = _RouteTrackingObserver(
    onRouteChanged: (routeName) {
      if (!mounted) {
        return;
      }

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _currentRouteName = routeName ?? '';
        });
      });
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    final session = await _authService.restoreSession();
    if (!mounted) {
      return;
    }

    setState(() {
      _session = session;
      _isRestoring = false;
    });
  }

  void _handleLogin(AuthSession session) {
    setState(() {
      _session = session;
    });
    unawaited(_authService.persistSession(session));
  }

  void _handleLogout() {
    unawaited(_authService.clearSession());
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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

        final showOwlButton = _currentRouteName != '/chat';

        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: child,
                ),
              ),
              if (showOwlButton)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: ChatOwlButton(navigatorKey: _navigatorKey),
                ),
            ],
          ),
        );
      },
      navigatorObservers: [_routeObserver],
      routes: {
        '/chat': (context) => ChatScreen(session: _session),
      },
      home: _isRestoring
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _session == null
              ? LoginScreen(onLogin: _handleLogin)
              : HomeScreen(session: _session!, onLogout: _handleLogout),
    );
  }
}

class _RouteTrackingObserver extends NavigatorObserver {
  final ValueChanged<String?> onRouteChanged;

  _RouteTrackingObserver({required this.onRouteChanged});

  void _notify(Route<dynamic>? route) {
    onRouteChanged(route?.settings.name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _notify(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _notify(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _notify(newRoute);
  }
}
