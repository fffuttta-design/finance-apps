import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/auth_service.dart';
import 'data/household_service.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await AuthService.instance.init();
  runApp(const TakuharuFinanceApp());
}

class TakuharuFinanceApp extends StatelessWidget {
  const TakuharuFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'たくはるファイナンス',
      debugShowCheckedModeBanner: false,
      theme: buildTakuharuTheme(),
      home: const _AuthGate(),
    );
  }
}

/// ログイン状態で画面を出し分ける。
/// 未ログイン → ログイン画面 / ログイン済 → 世帯を確保してホームへ。
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.userStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return _HouseholdGate(user: user);
      },
    );
  }
}

/// 世帯を確保（無ければ自動作成）してからホームを表示。
class _HouseholdGate extends StatefulWidget {
  final User user;
  const _HouseholdGate({required this.user});

  @override
  State<_HouseholdGate> createState() => _HouseholdGateState();
}

class _HouseholdGateState extends State<_HouseholdGate> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = HouseholdService.instance.ensureHousehold(widget.user);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Splash();
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 48, color: AppColors.pink),
                    const SizedBox(height: 12),
                    const Text('データの読み込みに失敗しました',
                        style: TextStyle(color: AppColors.text)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() {
                        _future = HouseholdService.instance
                            .ensureHousehold(widget.user);
                      }),
                      child: const Text('もう一度'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const HomeScreen();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Icon(Icons.favorite_rounded, size: 64, color: AppColors.pink),
      ),
    );
  }
}
