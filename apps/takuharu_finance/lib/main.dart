import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/auth_service.dart';
import 'data/household_service.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

/// 通知タップからの画面遷移などで使うグローバル Navigator。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

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
      navigatorKey: appNavigatorKey,
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

  /// 世帯確保＋スプラッシュの最低表示時間（ロゴアニメを少しだけ見せる）。
  Future<void> _ensure() async {
    await Future.wait([
      HouseholdService.instance.ensureHousehold(widget.user),
      Future<void>.delayed(const Duration(milliseconds: 1100)),
    ]);
  }

  @override
  void initState() {
    super.initState();
    _future = _ensure();
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
                        _future = _ensure();
                      }),
                      child: const Text('もう一度'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const MainShell();
      },
    );
  }
}

/// 起動スプラッシュ。淡いピンク背景＋ブランドロゴが「ふわっと呼吸」する
/// 短いアニメ。auth待ち/世帯確保待ちの両方で同じ見た目なので、
/// 連続して表示されても“2回出た”感が出ないようループ脈動にしている。
class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash>
    with SingleTickerProviderStateMixin {
  // 入場のふわっとフェード＋スケールイン（やわらかめ）。
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();
  // ゆっくり控えめな呼吸（ゴツくならないよう振れ幅は小さく）。
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _intro.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final introFade =
        CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    final introScale = Tween<double>(begin: 0.86, end: 1.0)
        .animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
    final breathe = Tween<double>(begin: 0.985, end: 1.025)
        .animate(CurvedAnimation(parent: _breathe, curve: Curves.easeInOut));
    return Scaffold(
      backgroundColor: const Color(0xFFFFF1F4),
      body: Center(
        child: FadeTransition(
          opacity: introFade,
          child: ScaleTransition(
            scale: introScale,
            child: ScaleTransition(
              scale: breathe,
              child: Image.asset(
                'assets/brand/logo.png',
                width: 148,
                errorBuilder: (_, _, _) => const Icon(Icons.favorite_rounded,
                    size: 72, color: AppColors.pink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
