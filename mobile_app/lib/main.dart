import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/children_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final auth = AuthService(api)..init();
  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthService>.value(value: auth),
      ],
      child: const ChildActivitiesApp(),
    ),
  );
}

class ChildActivitiesApp extends StatefulWidget {
  const ChildActivitiesApp({super.key});

  @override
  State<ChildActivitiesApp> createState() => _ChildActivitiesAppState();
}

class _ChildActivitiesAppState extends State<ChildActivitiesApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AuthService _auth;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthService>()..addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// After sign-out (including an expired session), drop any pushed screens so
  /// the login screen is visible.
  void _onAuthChanged() {
    if (_auth.status == AuthStatus.signedOut) {
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2E7D6B),
            brightness: brightness,
          ),
          useMaterial3: true,
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder()),
        );

    return MaterialApp(
      title: 'Child Activities',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const AuthGate(),
    );
  }
}

/// Shows the login screen or the app depending on the session.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    switch (context.watch<AuthService>().status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedOut:
        return const LoginScreen();
      case AuthStatus.signedIn:
        return const ChildrenScreen();
    }
  }
}
