import 'dart:async';

import 'package:flutter/material.dart';
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
  final ValueNotifier<_OwlVisibilityState> _owlVisibility =
      ValueNotifier(const _OwlVisibilityState());
  late final NavigatorObserver _routeObserver = _RouteTrackingObserver(
    onRouteChanged: (routeName) {
      final nextName = routeName ?? '';
      final current = _owlVisibility.value;
      if (current.routeName == nextName) {
        return;
      }
      _owlVisibility.value = current.copyWith(routeName: nextName);
    },
    onBottomSheetChanged: (isOpen) {
      final current = _owlVisibility.value;
      if (current.isBottomSheetOpen == isOpen) {
        return;
      }
      _owlVisibility.value = current.copyWith(isBottomSheetOpen: isOpen);
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  @override
  void dispose() {
    _owlVisibility.dispose();
    super.dispose();
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
        return ValueListenableBuilder<_OwlVisibilityState>(
          valueListenable: _owlVisibility,
          child: child,
          builder: (context, state, child) {
            final showOwlButton =
                state.routeName != '/chat' && !state.isBottomSheetOpen;
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
  final ValueChanged<bool>? onBottomSheetChanged;
  int _bottomSheetCount = 0;

  _RouteTrackingObserver({
    required this.onRouteChanged,
    required this.onBottomSheetChanged,
  });

  void _notify(Route<dynamic>? route) {
    onRouteChanged(route?.settings.name);
  }

  void _updateBottomSheetCount({
    required Route<dynamic>? route,
    required int delta,
  }) {
    if (route is ModalBottomSheetRoute) {
      _bottomSheetCount = (_bottomSheetCount + delta).clamp(0, 9999);
      onBottomSheetChanged?.call(_bottomSheetCount > 0);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateBottomSheetCount(route: route, delta: 1);
    _notify(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _updateBottomSheetCount(route: route, delta: -1);
    _notify(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute is ModalBottomSheetRoute && newRoute is! ModalBottomSheetRoute) {
      _updateBottomSheetCount(route: oldRoute, delta: -1);
    } else if (newRoute is ModalBottomSheetRoute && oldRoute is! ModalBottomSheetRoute) {
      _updateBottomSheetCount(route: newRoute, delta: 1);
    }
    _notify(newRoute);
  }
}

class _OwlVisibilityState {
  final String routeName;
  final bool isBottomSheetOpen;

  const _OwlVisibilityState({
    this.routeName = '',
    this.isBottomSheetOpen = false,
  });

  _OwlVisibilityState copyWith({
    String? routeName,
    bool? isBottomSheetOpen,
  }) {
    return _OwlVisibilityState(
      routeName: routeName ?? this.routeName,
      isBottomSheetOpen: isBottomSheetOpen ?? this.isBottomSheetOpen,
    );
  }
}
